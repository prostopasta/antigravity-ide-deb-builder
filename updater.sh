#!/usr/bin/env bash
#
# check-antigravity-ide-update
# Checks Google's official CDN for new Antigravity IDE releases and stages them
# in the local APT repository. Meant to be run from a systemd timer, never from
# an APT hook: staging a release means downloading ~190 MB, which must not block
# "apt update".
#

set -euo pipefail

QUIET=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        -q|--quiet) QUIET=true ;;
        -f|--force) FORCE=true ;;
        -h|--help)
            echo "Usage: ${0##*/} [-q|--quiet] [-f|--force]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

REPO_DIR="${REPO_DIR:-/var/local/antigravity-ide-repo}"
PKG_NAME="antigravity-ide"
# Releases to keep in the repository. The newest one is what apt installs; the
# previous one stays around so a broken release can be rolled back by hand.
KEEP_RELEASES="${KEEP_RELEASES:-2}"

log() {
    if [ "$QUIET" = false ]; then
        echo "[antigravity-ide-updater] $*"
    fi
}

warn() {
    echo "[antigravity-ide-updater] $*" >&2
}

mkdir -p "$REPO_DIR"

# Rebuilds every index file apt reads. Doing only Packages.gz leaves apt on the
# stale plain Packages, so a staged release is never offered for installation
# and the next run downloads it all over again.
reindex_repo() {
    local tmp_release
    tmp_release="$(mktemp -t antigravity-release-XXXXXX)"
    (
        cd "$REPO_DIR"
        dpkg-scanpackages . /dev/null > Packages 2>/dev/null
        gzip -9cf Packages > Packages.gz
        # apt-ftparchive is pointed at the directory only after Release is gone,
        # otherwise it checksums the empty file the redirect would create.
        rm -f Release
        apt-ftparchive release . > "$tmp_release"
        install -m 0644 "$tmp_release" Release
    )
    rm -f "$tmp_release"
}

# Drops .deb files beyond KEEP_RELEASES, but never the version that is currently
# installed: apt needs it on disk to reinstall or to verify the package.
prune_old_debs() {
    local installed
    installed="$(dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null || echo "")"

    local -a debs
    mapfile -t debs < <(find "$REPO_DIR" -maxdepth 1 -name "${PKG_NAME}_*.deb" -printf '%f\n' \
        | sed -E "s/^${PKG_NAME}_(.*)_[^_]+\.deb$/\1/" \
        | sort -V -r)

    local idx=0 ver
    for ver in "${debs[@]}"; do
        idx=$((idx + 1))
        [ "$idx" -le "$KEEP_RELEASES" ] && continue
        [ "$ver" = "$installed" ] && continue
        log "Removing superseded package $ver"
        rm -f "$REPO_DIR/${PKG_NAME}_${ver}_"*.deb
    done
}

# Check network connectivity quickly
if ! curl -fsSL --head --connect-timeout 4 "https://antigravity.google" >/dev/null 2>&1; then
    log "Notice: Network unavailable or antigravity.google not reachable. Skipping update check."
    exit 0
fi

# Detect architecture
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    amd64) PLATFORM="linux-x64" ;;
    arm64) PLATFORM="linux-arm" ;;
    *) log "Unsupported architecture: $ARCH"; exit 0 ;;
esac

# Scrape latest URL from download page
HTML="$(curl -fsSL --compressed "https://antigravity.google/download" 2>/dev/null || true)"
MATCHED_URL="$(echo "$HTML" | grep -o -E "https://edgedl\.me\.gvt1\.com/edgedl/release2/[^\"' ]+/${PLATFORM}/Antigravity%20IDE\.tar\.gz" | head -n 1 || true)"

if [ -z "$MATCHED_URL" ]; then
    log "Could not resolve latest release URL from official page."
    exit 0
fi

LATEST_VERSION="$(echo "$MATCHED_URL" | sed -E 's|.*/stable/([0-9.]+)-.*|\1|')"
# A download page whose URL layout changed leaves the whole URL in the variable;
# dpkg --compare-versions would then treat it as "newer" and re-download forever.
if ! [[ "$LATEST_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    warn "Could not parse a version out of $MATCHED_URL — skipping."
    exit 0
fi

# Compare against what is already staged in the repository, not against the
# installed version: a release that was built but not installed yet is still
# staged, and downloading it again would be pure waste.
DEB_OUT="$REPO_DIR/${PKG_NAME}_${LATEST_VERSION}_${ARCH}.deb"
INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null || echo "none")"
log "Installed version: $INSTALLED_VERSION | Latest available: $LATEST_VERSION"

if [ "$FORCE" = false ] && [ -s "$DEB_OUT" ]; then
    log "Antigravity IDE $LATEST_VERSION is already staged in $REPO_DIR."
    # Still reindex: the package may have been staged by a run that failed
    # before writing the indexes.
    prune_old_debs
    reindex_repo
    exit 0
fi

log "New version ($LATEST_VERSION) detected! Staging package..."

TMP_BUILD="$(mktemp -d -t agy-update-XXXXXX)"
cleanup() {
    rm -rf "$TMP_BUILD"
}
trap cleanup EXIT

# Download & package
TARBALL="$TMP_BUILD/payload.tar.gz"
if [ "$QUIET" = true ]; then
    curl -fSL --no-progress-meter -o "$TARBALL" "$MATCHED_URL"
else
    curl -fL --progress-bar -o "$TARBALL" "$MATCHED_URL"
fi

EXTRACT="$TMP_BUILD/extracted"
mkdir -p "$EXTRACT"
tar -xzf "$TARBALL" -C "$EXTRACT"

APP_DIR="$(find "$EXTRACT" -maxdepth 2 -type d -name "Antigravity IDE" | head -n 1)"
if [ -z "$APP_DIR" ]; then
    warn "Could not locate 'Antigravity IDE' directory inside the archive."
    exit 1
fi

BUILD_ROOT="$TMP_BUILD/pkg"
mkdir -p "$BUILD_ROOT/DEBIAN"
mkdir -p "$BUILD_ROOT/usr/bin"
mkdir -p "$BUILD_ROOT/usr/share/antigravity-ide"
mkdir -p "$BUILD_ROOT/usr/share/applications"
mkdir -p "$BUILD_ROOT/usr/share/pixmaps"
mkdir -p "$BUILD_ROOT/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$BUILD_ROOT/usr/share/bash-completion/completions"
mkdir -p "$BUILD_ROOT/usr/share/zsh/vendor-completions"

cp -a "$APP_DIR/." "$BUILD_ROOT/usr/share/antigravity-ide/"
ln -s "/usr/share/antigravity-ide/bin/antigravity-ide" "$BUILD_ROOT/usr/bin/antigravity-ide"

cat << 'DESKTOP' > "$BUILD_ROOT/usr/share/applications/antigravity-ide.desktop"
[Desktop Entry]
Name=Antigravity IDE
Comment=AI-First Integrated Development Environment
GenericName=Text Editor
Exec=/usr/bin/antigravity-ide %F
Icon=antigravity-ide
Type=Application
StartupNotify=true
StartupWMClass=antigravity-ide
Categories=Utility;TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-antigravity-workspace;
Actions=new-empty-window;
Keywords=vscode;antigravity;ide;ai;developer;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/usr/bin/antigravity-ide --new-window %F
Icon=antigravity-ide
DESKTOP
chmod 644 "$BUILD_ROOT/usr/share/applications/antigravity-ide.desktop"

ICON_SRC="$BUILD_ROOT/usr/share/antigravity-ide/resources/app/resources/linux/code.png"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$BUILD_ROOT/usr/share/pixmaps/antigravity-ide.png"
    cp "$ICON_SRC" "$BUILD_ROOT/usr/share/icons/hicolor/512x512/apps/antigravity-ide.png"
    chmod 644 "$BUILD_ROOT/usr/share/pixmaps/antigravity-ide.png" "$BUILD_ROOT/usr/share/icons/hicolor/512x512/apps/antigravity-ide.png"
fi

BASH_COMP="$BUILD_ROOT/usr/share/antigravity-ide/resources/completions/bash/antigravity-ide"
if [ -f "$BASH_COMP" ]; then
    cp "$BASH_COMP" "$BUILD_ROOT/usr/share/bash-completion/completions/antigravity-ide"
    chmod 644 "$BUILD_ROOT/usr/share/bash-completion/completions/antigravity-ide"
fi

ZSH_COMP="$BUILD_ROOT/usr/share/antigravity-ide/resources/completions/zsh/_antigravity-ide"
if [ -f "$ZSH_COMP" ]; then
    cp "$ZSH_COMP" "$BUILD_ROOT/usr/share/zsh/vendor-completions/_antigravity-ide"
    chmod 644 "$BUILD_ROOT/usr/share/zsh/vendor-completions/_antigravity-ide"
fi

chmod 4755 "$BUILD_ROOT/usr/share/antigravity-ide/chrome-sandbox"

INSTALLED_SIZE="$(du -sk "$BUILD_ROOT/usr" | cut -f1)"
cat << CONTROL > "$BUILD_ROOT/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${LATEST_VERSION}
Section: devel
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Google, LLC <antigravity-support@google.com>
Depends: ca-certificates, libasound2t64 | libasound2, libatk-bridge2.0-0, libatk1.0-0, libatspi2.0-0, libc6 (>= 2.28), libcairo2, libcups2, libcurl4 | libcurl3-gnutls, libdbus-1-3, libexpat1, libgbm1, libglib2.0-0, libgtk-3-0, libnspr4, libnss3, libpango-1.0-0, libstdc++6, libudev1, libx11-6, libxcb1, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxkbcommon0, libxkbfile1, libxrandr2, xdg-utils
Recommends: libvulkan1
Description: Antigravity IDE (Standalone) - AI-First IDE
 Antigravity IDE is a dedicated desktop application with native windowing,
 integrated agent panels, and full execution workspace built for
 agent-first software engineering.
Homepage: https://antigravity.google
CONTROL

cat << 'POSTINST' > "$BUILD_ROOT/DEBIAN/postinst"
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    update-alternatives --install /usr/bin/editor editor /usr/bin/antigravity-ide 0
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if command -v update-mime-database >/dev/null 2>&1; then
        update-mime-database /usr/share/mime || true
    fi
    if [ -f /usr/share/antigravity-ide/chrome-sandbox ]; then
        chown root:root /usr/share/antigravity-ide/chrome-sandbox || true
        chmod 4755 /usr/share/antigravity-ide/chrome-sandbox || true
    fi
fi
exit 0
POSTINST
chmod 755 "$BUILD_ROOT/DEBIAN/postinst"

cat << 'POSTRM' > "$BUILD_ROOT/DEBIAN/postrm"
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    update-alternatives --remove editor /usr/bin/antigravity-ide || true
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if command -v update-mime-database >/dev/null 2>&1; then
        update-mime-database /usr/share/mime || true
    fi
fi
exit 0
POSTRM
chmod 755 "$BUILD_ROOT/DEBIAN/postrm"

# Built under a temporary name so an interrupted run never leaves a half-written
# .deb that the next run would mistake for a complete staged release.
fakeroot dpkg-deb -Zxz --build --root-owner-group "$BUILD_ROOT" "$DEB_OUT.partial"
mv -f "$DEB_OUT.partial" "$DEB_OUT"

# Prune first: the indexes must describe the files that are left on disk.
prune_old_debs
reindex_repo

log "Successfully updated local repo to Antigravity IDE $LATEST_VERSION"
