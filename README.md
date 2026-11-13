# Antigravity IDE `.deb` Package Builder

Automated, clean-room Debian/Ubuntu (`.deb`) packaging and repository automation for **Google Antigravity IDE (Standalone)**.

## Contents

- [Why this exists](#why-this-exists)
- [Quick installation](#quick-installation): one-line installer, local build, cross-building.
- [Automatic updates via APT](#automatic-updates-via-apt): short summary.
- [Documentation](#documentation)
  - [Local APT repository and automatic updates](docs/APT_REPOSITORY.md): how it works, files, updater options, rollback, reading `apt update` output, troubleshooting.
  - [Signing the local APT repository](docs/REPOSITORY_SIGNING.md): what is signed, the signing key and why it needs no backup, migrating from `trusted=yes`.
- [Legal and licensing notice](#legal--licensing-notice)

---

## Why this exists

Google distributes the **Antigravity IDE (Standalone)** v2.x on Linux primarily via `.tar.gz` tarballs rather than native APT packages. This project provides an open-source, automated recipe that:
1. Downloads the official release directly from Google's edge delivery network (`edgedl.me.gvt1.com`).
2. Configures standard Linux desktop integration (Desktop launcher, system icons, bash/zsh completions, SUID sandbox).
3. Packages it into a native `.deb` file compatible with Ubuntu and Debian.
4. Integrates with `apt` for clean lifecycle management and automated updates.

---

## Quick Installation

### Option 1: One-Line Installer
```bash
curl -fsSL https://raw.githubusercontent.com/prostopasta/antigravity-ide-deb-builder/main/install.sh | bash
```

### Option 2: Build & Install Locally
```bash
# Clone repository
git clone https://github.com/prostopasta/antigravity-ide-deb-builder.git
cd antigravity-ide-deb-builder

# Build .deb package (detects system architecture automatically)
./build.sh

# Install with apt
sudo apt install ./antigravity-ide_*_amd64.deb
```

### Option 3: Cross-building Architecture
```bash
./build.sh amd64   # For Intel/AMD 64-bit
./build.sh arm64   # For ARM 64-bit (Raspberry Pi, Asahi, Graviton, etc.)
```

---

## Automatic Updates via APT

New releases are staged into a local APT repository by a daily systemd timer, so
`sudo apt upgrade` picks them up like any other package. `install.sh` sets all of
this up. The repository lives in `/var/local/antigravity-ide-repo` and is signed
with a key created on the machine, so its source entry uses `signed-by=` rather
than `trusted=yes`.

Stage a release right now, without waiting for the timer:

```bash
sudo /usr/local/bin/check-antigravity-ide-update
```

Setting it up by hand, updater options, rollback and troubleshooting are in
[docs/APT_REPOSITORY.md](docs/APT_REPOSITORY.md). The signing key, and moving an
older install off `trusted=yes`, are in
[docs/REPOSITORY_SIGNING.md](docs/REPOSITORY_SIGNING.md).

> **Do not** run the updater from an `APT::Update::Pre-Invoke` hook. Staging a
> release downloads ~190 MB from Google's CDN, and an APT hook makes every
> `apt update` block on that download.

---

## Documentation

| Document | What it covers |
|----------|----------------|
| [docs/APT_REPOSITORY.md](docs/APT_REPOSITORY.md) | How the local repository and the daily timer work, files and paths, setting it up by hand, updater options and environment variables, rolling back, reading `apt update` output, troubleshooting |
| [docs/REPOSITORY_SIGNING.md](docs/REPOSITORY_SIGNING.md) | Why the repository is signed, what exactly is signed, where the key lives and why it has no passphrase and no backup, migrating from `trusted=yes`, checking and replacing the key |

---

## Legal & Licensing Notice

- **Google Antigravity** and **Antigravity IDE** are proprietary products created by Google LLC and are subject to the [Google Terms of Service](https://policies.google.com/terms).
- This repository contains **no proprietary binaries, trademarks, or copyrighted application code**. It is an open-source build tool / packaging recipe (similar to Arch Linux AUR PKGBUILDs and Homebrew Casks) that pulls official distribution assets directly onto the user's system.
- The packaging scripts in this repository are released under the [MIT License](LICENSE).
