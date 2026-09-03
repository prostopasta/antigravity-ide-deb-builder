#!/usr/bin/env bash
#
# Antigravity IDE .deb Package Builder
# Builds a native Debian/Ubuntu (.deb) package from Google's official standalone tarball.
#

set -euo pipefail

# Configuration
PKG_NAME="antigravity-ide"
TMP_DIR="$(mktemp -d -t antigravity-deb-XXXXXX)"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
COMPRESSION="${COMPRESSION:-xz}" # xz, zstd, or gzip

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Architecture detection & normalization
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64|amd64)
        ARCH="amd64"
        PLATFORM="linux-x64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        PLATFORM="linux-arm"
        ;;
    *)
        echo "Error: Unsupported CPU architecture: $ARCH_RAW" >&2
        exit 1
        ;;
esac

# Allow overriding arch via CLI argument
if [ "${1:-}" != "" ] && [ "$1" != "auto" ]; then
    ARCH="$1"
    case "$ARCH" in
        amd64) PLATFORM="linux-x64" ;;
        arm64) PLATFORM="linux-arm" ;;
        *) echo "Error: Argument must be 'amd64' or 'arm64'" >&2; exit 1 ;;
    esac
fi

echo "==> Detecting latest Antigravity IDE release from official CDN..."
DOWNLOAD_PAGE_HTML="$(curl -fsSL --compressed "https://antigravity.google/download" || true)"
MATCHED_URL="$(echo "$DOWNLOAD_PAGE_HTML" | grep -o -E "https://edgedl\.me\.gvt1\.com/edgedl/release2/[^\"' ]+/${PLATFORM}/Antigravity%20IDE\.tar\.gz" | head -n 1 || true)"

if [ -z "$MATCHED_URL" ]; then
    # Fallback default known stable
    MATCHED_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/${PLATFORM}/Antigravity%20IDE.tar.gz"
fi

VERSION="$(echo "$MATCHED_URL" | sed -E 's|.*/stable/([0-9.]+)-.*|\1|')"
echo "==> Target Version: ${VERSION} (${ARCH})"
echo "==> Download URL: ${MATCHED_URL}"

TARBALL="${TMP_DIR}/Antigravity_IDE_${VERSION}_${ARCH}.tar.gz"
echo "==> Downloading release tarball..."
curl -fL --progress-bar -o "$TARBALL" "$MATCHED_URL"

echo "==> Unpacking tarball..."
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$TARBALL" -C "$EXTRACT_DIR"

APP_DIR="$(find "$EXTRACT_DIR" -maxdepth 2 -type d -name "Antigravity IDE" | head -n 1)"
if [ -z "$APP_DIR" ] || [ ! -d "$APP_DIR" ]; then
    echo "Error: Could not locate 'Antigravity IDE' directory inside archive." >&2
    exit 1
fi

BUILD_ROOT="${TMP_DIR}/package_root"
mkdir -p "$BUILD_ROOT/DEBIAN"
mkdir -p "$BUILD_ROOT/usr/bin"
mkdir -p "$BUILD_ROOT/usr/share/antigravity-ide"
mkdir -p "$BUILD_ROOT/usr/share/applications"
mkdir -p "$BUILD_ROOT/usr/share/pixmaps"
mkdir -p "$BUILD_ROOT/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$BUILD_ROOT/usr/share/bash-completion/completions"
mkdir -p "$BUILD_ROOT/usr/share/zsh/vendor-completions"

echo "==> Staging payload..."
cp -a "$APP_DIR/." "$BUILD_ROOT/usr/share/antigravity-ide/"

# Symlink CLI binary
ln -s "/usr/share/antigravity-ide/bin/antigravity-ide" "$BUILD_ROOT/usr/bin/antigravity-ide"

# Desktop integration
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
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-antigravity-workspace;
Actions=new-empty-window;
Keywords=vscode;antigravity;ide;ai;developer;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/usr/bin/antigravity-ide --new-window %F
Icon=antigravity-ide
DESKTOP
chmod 644 "$BUILD_ROOT/usr/share/applications/antigravity-ide.desktop"

# Icons
ICON_SRC="$BUILD_ROOT/usr/share/antigravity-ide/resources/app/resources/linux/code.png"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$BUILD_ROOT/usr/share/pixmaps/antigravity-ide.png"
    cp "$ICON_SRC" "$BUILD_ROOT/usr/share/icons/hicolor/512x512/apps/antigravity-ide.png"
    chmod 644 "$BUILD_ROOT/usr/share/pixmaps/antigravity-ide.png" "$BUILD_ROOT/usr/share/icons/hicolor/512x512/apps/antigravity-ide.png"
fi

# Shell completions
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

# Permissions
chmod 4755 "$BUILD_ROOT/usr/share/antigravity-ide/chrome-sandbox"

# Control metadata
INSTALLED_SIZE="$(du -sk "$BUILD_ROOT/usr" | cut -f1)"
cat << CONTROL > "$BUILD_ROOT/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Community Packaging <https://github.com/prostopasta/antigravity-ide-deb-builder>
Depends: ca-certificates, libasound2t64 | libasound2, libatk-bridge2.0-0, libatk1.0-0, libatspi2.0-0, libc6 (>= 2.28), libcairo2, libcups2, libcurl4 | libcurl3-gnutls, libdbus-1-3, libexpat1, libgbm1, libglib2.0-0, libgtk-3-0, libnspr4, libnss3, libpango-1.0-0, libstdc++6, libudev1, libx11-6, libxcb1, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxkbcommon0, libxkbfile1, libxrandr2, xdg-utils
Recommends: libvulkan1
Description: Antigravity IDE (Standalone) - AI-First IDE
 Antigravity IDE is a dedicated desktop application with native windowing,
 integrated agent panels, and full execution workspace built for
 agent-first software engineering.
Homepage: https://antigravity.google
CONTROL

# postinst hook
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

# postrm hook
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

# Build package
DEB_OUTPUT="${OUTPUT_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "==> Building ${DEB_OUTPUT} (using -Z${COMPRESSION})..."
mkdir -p "$OUTPUT_DIR"
fakeroot dpkg-deb -Z"$COMPRESSION" --build --root-owner-group "$BUILD_ROOT" "$DEB_OUTPUT"

echo "==> Successfully created Debian package: ${DEB_OUTPUT}"
ls -lh "$DEB_OUTPUT"
