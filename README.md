# Antigravity IDE `.deb` Package Builder

Automated, clean-room Debian/Ubuntu (`.deb`) packaging and repository automation for **Google Antigravity IDE (Standalone)**.

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
this up; to do it by hand:

1. Keep a local repository in `/var/local/antigravity-ide-repo`:
   ```bash
   sudo mkdir -p /var/local/antigravity-ide-repo
   echo "deb [trusted=yes] file:/var/local/antigravity-ide-repo ./" | sudo tee /etc/apt/sources.list.d/antigravity-ide-local.list
   ```

2. Install the updater and its timer:
   ```bash
   sudo install -m 0755 updater.sh /usr/local/bin/check-antigravity-ide-update
   sudo install -m 0644 systemd/antigravity-ide-update.* /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now antigravity-ide-update.timer
   ```

Stage a release right now, without waiting for the timer:

```bash
sudo /usr/local/bin/check-antigravity-ide-update
```

> **Do not** run the updater from an `APT::Update::Pre-Invoke` hook. Staging a
> release downloads ~190 MB from Google's CDN, and an APT hook makes every
> `apt update` block on that download.

---

## Legal & Licensing Notice

- **Google Antigravity** and **Antigravity IDE** are proprietary products created by Google LLC and are subject to the [Google Terms of Service](https://policies.google.com/terms).
- This repository contains **no proprietary binaries, trademarks, or copyrighted application code**. It is an open-source build tool / packaging recipe (similar to Arch Linux AUR PKGBUILDs and Homebrew Casks) that pulls official distribution assets directly onto the user's system.
- The packaging scripts in this repository are released under the [MIT License](LICENSE).
