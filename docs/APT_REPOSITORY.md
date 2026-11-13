# Local APT repository and automatic updates

New Antigravity IDE releases reach `apt upgrade` through a small APT repository
that lives on the machine itself. This page explains how it is put together,
how to run it by hand and how to read what `apt update` prints for it.
Signing is covered separately in [REPOSITORY_SIGNING.md](REPOSITORY_SIGNING.md).

## Contents

- [How it works](#how-it-works)
- [Files and paths](#files-and-paths)
- [Setting it up by hand](#setting-it-up-by-hand)
- [The updater](#the-updater)
  - [Options](#options)
  - [Environment variables](#environment-variables)
  - [What one run does](#what-one-run-does)
- [Everyday commands](#everyday-commands)
- [Rolling back to the previous release](#rolling-back-to-the-previous-release)
- [Reading `apt update` output](#reading-apt-update-output)
- [Troubleshooting](#troubleshooting)
- [Refreshing only this source](#refreshing-only-this-source)
- [Why the updater is not an APT hook](#why-the-updater-is-not-an-apt-hook)

## How it works

```
antigravity-ide-update.timer        daily, with up to 2 h random delay
        │
        ▼
check-antigravity-ide-update        updater.sh installed into /usr/local/bin
        │  downloads the tarball from Google's CDN, builds a .deb,
        │  rebuilds Packages / Release and signs InRelease
        ▼
/var/local/antigravity-ide-repo     the repository: .deb files + indexes
        │
        ▼
apt update / apt upgrade            reads it through the file: source entry
```

The timer only stages a release. Nothing is installed until you run
`apt upgrade` yourself, the same as for any other package.

## Files and paths

| Path | What it is |
|------|------------|
| `/usr/local/bin/check-antigravity-ide-update` | The updater (`updater.sh` from this repository) |
| `/etc/systemd/system/antigravity-ide-update.service` | Runs the updater once, quietly, at low CPU and I/O priority |
| `/etc/systemd/system/antigravity-ide-update.timer` | Starts the service daily; catches up after the machine was off |
| `/var/local/antigravity-ide-repo/` | The repository: `antigravity-ide_<version>_<arch>.deb`, `Packages`, `Packages.gz`, `Release`, `InRelease` |
| `/etc/apt/sources.list.d/antigravity-ide-local.list` | The source entry: `deb [signed-by=…] file:/var/local/antigravity-ide-repo ./` |
| `/var/lib/antigravity-ide-repo/gnupg/` | Signing key, root only (see [REPOSITORY_SIGNING.md](REPOSITORY_SIGNING.md)) |
| `/etc/apt/keyrings/antigravity-ide-local.gpg` | Public key apt verifies `InRelease` with |

## Setting it up by hand

`install.sh` does all of this. To do it yourself from a clone of this
repository:

1. Install the updater and its timer:
   ```bash
   sudo install -m 0755 updater.sh /usr/local/bin/check-antigravity-ide-update
   sudo install -m 0644 systemd/antigravity-ide-update.* /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now antigravity-ide-update.timer
   ```

2. Create the repository, sign it and register it with apt:
   ```bash
   sudo mkdir -p /var/local/antigravity-ide-repo
   sudo /usr/local/bin/check-antigravity-ide-update --reindex
   echo "deb [signed-by=/etc/apt/keyrings/antigravity-ide-local.gpg] file:/var/local/antigravity-ide-repo ./" | sudo tee /etc/apt/sources.list.d/antigravity-ide-local.list
   ```

3. Stage the current release and install it:
   ```bash
   sudo /usr/local/bin/check-antigravity-ide-update
   sudo apt update
   sudo apt install antigravity-ide
   ```

Prerequisites: `curl`, `dpkg-dev`, `fakeroot`, `apt-utils` and `gnupg`.

## The updater

### Options

| Option | What it does |
|--------|--------------|
| *(none)* | Checks Google's download page; if a newer release exists, downloads it, builds the `.deb`, prunes old ones and rebuilds and signs the indexes |
| `-q`, `--quiet` | Prints warnings only. The systemd service uses it |
| `-f`, `--force` | Rebuilds the `.deb` even if this version is already staged |
| `-r`, `--reindex` | Rebuilds and signs the indexes for the `.deb` files already in the repository. No network access |
| `-h`, `--help` | Prints usage |

### Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `REPO_DIR` | `/var/local/antigravity-ide-repo` | Repository directory |
| `KEEP_RELEASES` | `2` | How many `.deb` files to keep. The installed version is never removed |
| `SIGNING_HOME` | `/var/lib/antigravity-ide-repo/gnupg` | GnuPG home holding the signing key |
| `SIGNING_KEYRING` | `/etc/apt/keyrings/antigravity-ide-local.gpg` | Where the public key is exported |

### What one run does

1. Quits quietly if `antigravity.google` is unreachable.
2. Finds the newest tarball URL for this architecture on the download page and
   takes the version from it. A URL it cannot parse stops the run instead of
   being treated as a "newer" version.
3. If that version is already staged, it only prunes and reindexes (a previous
   run may have stopped before writing the indexes) and exits.
4. Otherwise it downloads the tarball, lays out the package (launcher, icons,
   bash and zsh completions, SUID sandbox, `editor` alternative) and builds the
   `.deb` under a temporary name, renaming it only when the build is complete.
5. Removes `.deb` files beyond `KEEP_RELEASES`, except the installed version.
6. Rebuilds `Packages`, `Packages.gz` and `Release`, then signs `Release` into
   `InRelease`.

## Everyday commands

Stage a release now, without waiting for the timer:

```bash
sudo /usr/local/bin/check-antigravity-ide-update
```

When the timer last ran and when it runs next:

```bash
systemctl list-timers antigravity-ide-update.timer
```

What the last runs printed:

```bash
journalctl -u antigravity-ide-update.service -n 50
```

Which versions apt sees:

```bash
apt-cache policy antigravity-ide
```

## Rolling back to the previous release

The repository keeps the previous release (`KEEP_RELEASES=2`), so a broken
update can be undone with apt alone:

```bash
apt-cache policy antigravity-ide
sudo apt install antigravity-ide=<previous version>
sudo apt-mark hold antigravity-ide
```

Release the hold once a fixed version is staged:

```bash
sudo apt-mark unhold antigravity-ide
```

## Reading `apt update` output

With a signed repository the local source prints a single kind of line:

```
Get:1 file:/var/local/antigravity-ide-repo ./ InRelease [1,109 B]
Get:1 file:/var/local/antigravity-ide-repo ./ InRelease [1,109 B]
```

The `file:` method prints `Get` twice for the same file. It is read once; this
is only how that method reports progress.

An unsigned repository (an older install with `trusted=yes`) prints this
instead:

```
Get:1 file:/var/local/antigravity-ide-repo ./ InRelease
Ign:1 file:/var/local/antigravity-ide-repo ./ InRelease
Get:2 file:/var/local/antigravity-ide-repo ./ Release [832 B]
Get:3 file:/var/local/antigravity-ide-repo ./ Release.gpg
Ign:3 file:/var/local/antigravity-ide-repo ./ Release.gpg
```

apt first asks for `InRelease` (the signed `Release`). It is missing, and
`Ign` means apt skipped it without treating that as an error. apt then falls
back to `Release` plus its detached signature `Release.gpg`; the signature is
missing too, so it gets `Ign` as well. Lines with the same number are one
file: `Get` is the attempt, `Ign` is "not there, moving on". See
[REPOSITORY_SIGNING.md](REPOSITORY_SIGNING.md#migrating-from-trustedyes) to
switch such an install to the signed layout.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Get`/`Ign` lines for `InRelease` and `Release.gpg` | Repository is not signed (installed before signing existed) | [Migrate from `trusted=yes`](REPOSITORY_SIGNING.md#migrating-from-trustedyes) |
| `The repository … is not signed` | `InRelease` is missing: signing failed, or the indexes were written by something other than the updater | `sudo check-antigravity-ide-update --reindex` and read its output |
| `NO_PUBKEY` or a signature error | `/etc/apt/keyrings/antigravity-ide-local.gpg` is missing or belongs to another key | `sudo check-antigravity-ide-update --reindex` exports the current key again |
| `Hash Sum mismatch` | Files changed in the repository after `InRelease` was written | `sudo check-antigravity-ide-update --reindex` |
| A new release never shows up in `apt upgrade` | The timer has not run, or the download page changed | Check `systemctl list-timers` and `journalctl -u antigravity-ide-update.service` |
| The same release is downloaded every day | The run failed before writing the indexes | Run the updater by hand and read the error |
| `apt upgrade` suddenly finds nothing, kernel and all; `apt-cache policy <pkg>` lists only `/var/lib/dpkg/status` | An `apt-get update` limited to one source deleted the lists of all the others (see below) | `sudo apt update` |

## Refreshing only this source

To update the local source alone, without fetching every repository, limit the
source list **and** turn off list cleanup:

```bash
sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/antigravity-ide-local.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
```

After an update apt removes from `/var/lib/apt/lists` every file that does not
belong to the sources it was given. With only the local source given, that is
every other repository, Ubuntu's archive included. Nothing breaks visibly:
`apt upgrade` simply reports `0 upgraded`, and a new kernel that `apt upgrade`
normally keeps back looks as if it were held. A full `sudo apt update` brings
the lists back. `install.sh` passes `List-Cleanup=0` for this reason.

A quick check that the lists are gone: `ls /var/lib/apt/lists | wc -l` shows a
handful of files instead of a hundred or more.

## Why the updater is not an APT hook

Earlier versions ran the check from `APT::Update::Pre-Invoke`. Staging a release
downloads about 190 MB from Google's CDN and rebuilds an xz-compressed package,
and a hook makes every `apt update` wait for that. `install.sh` removes the old
hook (`/etc/apt/apt.conf.d/99antigravity-ide`) and installs the timer instead.
Do not put the updater back into an APT hook.
