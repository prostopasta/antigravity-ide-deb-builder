# Signing the local APT repository

The local repository (see [APT_REPOSITORY.md](APT_REPOSITORY.md)) is signed
with a key that the updater creates on the machine itself. apt verifies the
signature through `signed-by=`, so the source entry does not need
`trusted=yes`.

## Contents

- [Background](#background)
- [What signing the repository means](#what-signing-the-repository-means)
- [The signing key](#the-signing-key)
  - [Where it lives](#where-it-lives)
  - [Why it has no passphrase](#why-it-has-no-passphrase)
  - [Why it needs no backup](#why-it-needs-no-backup)
- [What the updater does on every run](#what-the-updater-does-on-every-run)
- [What this protects against](#what-this-protects-against)
- [Migrating from `trusted=yes`](#migrating-from-trustedyes)
- [Checking the signature by hand](#checking-the-signature-by-hand)
- [Replacing the key](#replacing-the-key)

## Background

Up to [#3](https://github.com/prostopasta/antigravity-ide-deb-builder/pull/3)
the repository had a `Release` file but no signature, and the source entry
was registered with `trusted=yes`. Every `apt update` therefore asked for
`InRelease` and `Release.gpg`, found neither and printed `Get`/`Ign` pairs
for them (the lines are explained in
[APT_REPOSITORY.md](APT_REPOSITORY.md#reading-apt-update-output)).
`trusted=yes` also told apt to accept anything in the directory without
checking it.

Since #3 the updater signs the repository, `install.sh` registers it with
`signed-by=`, and `apt update` reads a single `InRelease` file.

## What signing the repository means

Not every `.deb` gets a signature. Only one file is signed, and the checksums
carry the trust down to the packages:

```
InRelease  (signed)   ── lists the checksums of ──▶  Packages, Packages.gz
Packages              ── lists the checksum of  ──▶  every .deb
```

`InRelease` is `Release` with an inline (clearsigned) OpenPGP signature. apt
checks that signature against the public key named in `signed-by=`, then checks
`Packages` against the checksums in `InRelease`, then each `.deb` against
`Packages`. A good signature on `InRelease` therefore vouches for the whole
repository.

APT can also use the older layout of `Release` plus a detached `Release.gpg`.
The updater writes only `InRelease`: apt asks for it first, and once it is
there apt does not ask for the other two.

## The signing key

A dedicated ed25519 key whose user ID is `Antigravity IDE local APT repository`.
It is not your personal GnuPG key and has nothing to do with Google's key for
their own repository (`/etc/apt/keyrings/antigravity-repo-key.gpg`).

### Where it lives

| What | Path | Permissions |
|------|------|-------------|
| Private key (GnuPG home) | `/var/lib/antigravity-ide-repo/gnupg/` | `0700`, root |
| Public key for apt | `/etc/apt/keyrings/antigravity-ide-local.gpg` | `0644`, root |

The private key stays outside `/var/local/antigravity-ide-repo`, because the
repository directory is readable by everyone. Both paths can be changed with
the `SIGNING_HOME` and `SIGNING_KEYRING` environment variables.

### Why it has no passphrase

The updater runs from a systemd timer with nobody at the keyboard. A passphrase
would either have to be stored next to the key, which protects nothing, or
would stop every unattended run.

### Why it needs no backup

The key only proves "these indexes were written by this machine's updater".
Nothing outside the machine trusts it, and the repository is rebuilt locally
from Google's CDN. If the key is lost, the next run of the updater creates a
new one and exports the new public key over the old one. Do not copy it into a
password manager or vault.

## What the updater does on every run

`reindex_repo` in `updater.sh`:

1. `ensure_signing_key` creates the key if `SIGNING_HOME` has none, and exports
   the public key to `SIGNING_KEYRING`. The export runs every time, so a deleted
   or outdated keyring is repaired by the next run.
2. Removes the old `InRelease` first. If signing fails later, apt reports an
   unsigned repository instead of a misleading `Hash Sum mismatch`.
3. Rebuilds `Packages`, `Packages.gz` and `Release`.
4. Clearsigns `Release` into `InRelease`.
5. Stops the `gpg-agent` that signing started, so nothing is left running as
   root after the timer finishes.

`check-antigravity-ide-update --reindex` runs only these steps, without
network access. `install.sh` uses it to create the repository.

## What this protects against

- apt no longer accepts whatever is in the directory. A `.deb` or index changed
  after signing fails verification instead of being installed.
- The source entry is an ordinary signed one, the same as Google's, Docker's or
  Kubernetes' repositories on the same machine.

What it does not change: the repository, the updater and the key all belong to
root. Someone who already has root can re-sign anything, as they could before.
In practice the main gain is a clean `apt update` and dropping `trusted=yes`.

## Migrating from `trusted=yes`

An install made before #3 has `trusted=yes` in its source entry and no
`InRelease`. From a clone of this repository at the current `main`:

```bash
sudo install -m 0755 updater.sh /usr/local/bin/check-antigravity-ide-update
```

```bash
sudo /usr/local/bin/check-antigravity-ide-update --reindex
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/antigravity-ide-local.gpg] file:/var/local/antigravity-ide-repo ./" | sudo tee /etc/apt/sources.list.d/antigravity-ide-local.list
```

```bash
sudo apt update
```

The first command installs the signing updater, the second creates the key and
`InRelease`, the third switches the source entry to `signed-by=`, and the last
should show only `InRelease` for this source. Running `install.sh` again does
the same.

## Checking the signature by hand

```bash
gpgv --keyring /etc/apt/keyrings/antigravity-ide-local.gpg /var/local/antigravity-ide-repo/InRelease
```

`Good signature from "Antigravity IDE local APT repository"` means apt will
accept the repository.

The key's fingerprint:

```bash
sudo gpg --homedir /var/lib/antigravity-ide-repo/gnupg --list-secret-keys --keyid-format long
```

## Replacing the key

To start over with a new key, for example after copying the disk to another
machine:

```bash
sudo rm -rf /var/lib/antigravity-ide-repo/gnupg
```

```bash
sudo /usr/local/bin/check-antigravity-ide-update --reindex
```

```bash
sudo apt update
```

The updater creates a new key, overwrites the public key in
`/etc/apt/keyrings/antigravity-ide-local.gpg` and signs the indexes with it.
