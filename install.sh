#!/usr/bin/env bash
#
# Antigravity IDE One-Line Installer & APT Repository Setup
#

set -euo pipefail

echo "=========================================================="
echo "    Google Antigravity IDE (Standalone) Installer        "
echo "=========================================================="

# Check root/sudo
SUDO=""
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: This installer requires root privileges or sudo." >&2
        exit 1
    fi
fi

# 1. Install prerequisites
echo "==> Ensuring prerequisites are installed..."
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq curl dpkg-dev fakeroot apt-utils gnupg >/dev/null

# 2. Build or download deb
WORKDIR="$(mktemp -d -t antigravity-install-XXXXXX)"
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/build.sh" ]; then
    echo "==> Running local build.sh..."
    (cd "$WORKDIR" && "$SCRIPT_DIR/build.sh")
else
    echo "==> Downloading build.sh from repository..."
    curl -fsSL https://raw.githubusercontent.com/prostopasta/antigravity-ide-deb-builder/main/build.sh -o "$WORKDIR/build.sh"
    chmod +x "$WORKDIR/build.sh"
    (cd "$WORKDIR" && "$WORKDIR/build.sh")
fi

DEB_FILE="$(find "$WORKDIR" -name "antigravity-ide_*.deb" | head -n 1)"
if [ -z "$DEB_FILE" ]; then
    echo "Error: Package build failed." >&2
    exit 1
fi

# 3. Install the updater and its timer
# The updater must not live in an APT hook: staging a release is a ~190 MB
# download, and a hook would make every "apt update" wait for it.
RAW_URL="https://raw.githubusercontent.com/prostopasta/antigravity-ide-deb-builder/main"
UPDATER="/usr/local/bin/check-antigravity-ide-update"
echo "==> Installing update checker and daily timer..."
if [ -f "$SCRIPT_DIR/updater.sh" ]; then
    $SUDO install -m 0755 "$SCRIPT_DIR/updater.sh" "$UPDATER"
else
    curl -fsSL "$RAW_URL/updater.sh" -o "$WORKDIR/updater.sh"
    $SUDO install -m 0755 "$WORKDIR/updater.sh" "$UPDATER"
fi

for unit in antigravity-ide-update.service antigravity-ide-update.timer; do
    if [ -f "$SCRIPT_DIR/systemd/$unit" ]; then
        $SUDO install -m 0644 "$SCRIPT_DIR/systemd/$unit" "/etc/systemd/system/$unit"
    else
        curl -fsSL "$RAW_URL/systemd/$unit" -o "$WORKDIR/$unit"
        $SUDO install -m 0644 "$WORKDIR/$unit" "/etc/systemd/system/$unit"
    fi
done

# 4. Setup local APT repository
# The updater writes the indexes (Packages, Packages.gz, Release) and signs
# them into InRelease, creating the repository's signing key on first use, so
# the installer and the timer always produce the same repository.
REPO_DIR="/var/local/antigravity-ide-repo"
KEYRING="/etc/apt/keyrings/antigravity-ide-local.gpg"
echo "==> Setting up local APT repository at $REPO_DIR..."
$SUDO mkdir -p "$REPO_DIR"
$SUDO cp "$DEB_FILE" "$REPO_DIR/"
$SUDO "$UPDATER" --reindex

# 5. Register APT source
# signed-by instead of trusted=yes: apt checks InRelease against the local key
# rather than accepting whatever is in the directory.
SOURCES_LIST="/etc/apt/sources.list.d/antigravity-ide-local.list"
echo "==> Registering APT source: $SOURCES_LIST..."
echo "deb [signed-by=$KEYRING] file:$REPO_DIR ./" | $SUDO tee "$SOURCES_LIST" > /dev/null

# Earlier versions of this installer wired the check into an APT hook
$SUDO rm -f /etc/apt/apt.conf.d/99antigravity-ide

$SUDO systemctl daemon-reload
$SUDO systemctl enable --now antigravity-ide-update.timer

# 6. Install via APT
echo "==> Installing antigravity-ide via apt..."
# Only the local source is refreshed, to keep the install fast. List-Cleanup=0
# is required: without it apt deletes the package lists of every source it was
# not shown here, Ubuntu's archive included, and "apt upgrade" then finds
# nothing to upgrade until the next full "apt update".
$SUDO apt-get update \
    -o Dir::Etc::sourcelist="sources.list.d/antigravity-ide-local.list" \
    -o Dir::Etc::sourceparts="-" \
    -o APT::Get::List-Cleanup="0"
$SUDO apt-get install -y --reinstall antigravity-ide

echo "=========================================================="
echo "✓ Antigravity IDE has been successfully installed!"
echo "✓ Run 'antigravity-ide' from terminal or open from launcher."
echo "=========================================================="
