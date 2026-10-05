# PhotoPrism on FreeBSD 13.3 (TrueNAS CORE jails)

This branch (`freebsd13`) runs the current PhotoPrism `develop` code natively on
FreeBSD 13.3/13.4, for example in an iocage jail on TrueNAS CORE 13.3, without
TensorFlow. It is an unofficial build: PhotoPrism does not support FreeBSD.

Tested on: TrueNAS CORE 13.3 host (kernel 13.3-RELEASE-p4), jail userland
13.4-RELEASE-p2, amd64, SQLite database.

## What is different from upstream

| Change | Why |
|---|---|
| `notensorflow` build tag (commit "AI: Add notensorflow build tag") | libtensorflow does not exist for FreeBSD. On `develop`, TensorFlow is only used for the old FaceNet model; classification, NSFW and face detection/recognition (SFace) run on ONNX Runtime. Builds without the tag are unchanged. |
| `plus` submodule pinned to a matching commit | Keeps the private [photoprism/plus](https://github.com/photoprism/plus) extension in sync with this branch. Only needed for Plus builds, and only cloneable with access to that repository. |
| `freebsd/` (this folder) | Build and install scripts, rc.d service, documentation. |

Nothing else in the PhotoPrism sources is modified.

## What you lose without TensorFlow

Only FaceNet. Existing FaceNet face embeddings must be migrated once:

```sh
photoprism faces migrate --to sface --yes
```

Automatic labels may differ slightly from older TensorFlow (NASNet) versions after
reindexing. Manually set labels are kept.

## Prebuilt packages

Each GitHub release of this fork has:

- `onnxruntime-1.30.0.pkg`: ONNX Runtime built from the ports tree for FreeBSD 13 amd64 (see below)
- `photoprism-ce-<version>.tar.gz`: CE binary, built frontend and assets, plus `freebsd/` and `scripts/dist/download-models.sh`
- `SHA256SUMS`

ONNX models are not included. `install.sh` downloads them from dl.photoprism.app
(checksum-pinned). Plus builds are never published, because the Plus license does not
allow distributing them; build Plus yourself (see below).

### Install from a release

```sh
fetch https://github.com/mrmuro/photoprism/releases/download/freebsd13.3-261005-eea2460/onnxruntime-1.30.0.pkg
fetch https://github.com/mrmuro/photoprism/releases/download/freebsd13.3-261005-eea2460/photoprism-ce-261005-eea246040-FreeBSD-AMD64-notensorflow.tar.gz
fetch https://github.com/mrmuro/photoprism/releases/download/freebsd13.3-261005-eea2460/SHA256SUMS
sha256sum -c SHA256SUMS

env IGNORE_OSVERSION=yes pkg install ./onnxruntime-1.30.0.pkg
pkg lock -y onnxruntime     # keeps pkg upgrade from going back to 1.23.2

tar -xzf photoprism-ce-261005-eea246040-FreeBSD-AMD64-notensorflow.tar.gz
cd photoprism-ce-261005-eea246040-FreeBSD-AMD64-notensorflow
sh freebsd/scripts/install.sh . ce
```

Then switch the service (back up your storage path first, because the new version migrates
the database schema):

```sh
tar -czf /var/db/photoprism/storage-backup.tgz -C /var/db/photoprism storage
service photoprism onestop; sysrc photoprism_enable=NO
sysrc photoprism_develop_enable=YES
service photoprism_develop start
```

## Building from source

### 1. Packages

FreeBSD 13 is end-of-life and its package repository is frozen, so set
`IGNORE_OSVERSION=yes` when a jail's userland and the host kernel differ.

```sh
export IGNORE_OSVERSION=yes
pkg install git go126 node24 npm-node24 gmake vips ffmpeg p5-Image-ExifTool libheif bash curl
```

Newer git and node packages need newer shared libraries than an older jail may have.
If `git` or `node` fails with `Undefined symbol`, upgrade the libraries it names
(seen: `pcre2`, `libuv`, `sqlite3`, `zstd`, `brotli`, `c-ares`, `libedit`, `libnghttp2`).
`node24` replaces `node20`.

### 2. ONNX Runtime 1.29 or newer

PhotoPrism uses `github.com/yalue/onnxruntime_go` v1.36, which needs ORT API 29.
FreeBSD 13 packages have 1.23.2 (API 23), so PhotoPrism logs
`The requested API version [29] is not available` and disables all ONNX models.
Use the release package, or build it (about 1.5 hours on 6 cores):

```sh
sh freebsd/scripts/build-onnxruntime.sh /root/build
env IGNORE_OSVERSION=yes pkg install /root/build/onnxruntime-1.30.0.pkg
pkg lock -y onnxruntime
```

The script clones the current ports tree into a separate directory, builds
`misc/onnxruntime` with `ALLOW_UNSUPPORTED_SYSTEM=yes`, and temporarily removes
packages the port conflicts with (`googletest`, needed by node24).

On FreeBSD 14.4+ or 15.1+ this step is not needed: `pkg install onnxruntime` from the
`latest` branch has 1.30.

### 3. PhotoPrism

```sh
git clone -b freebsd13 https://github.com/mrmuro/photoprism.git
cd photoprism
sh freebsd/scripts/build.sh ce build/freebsd
sh freebsd/scripts/install.sh build/freebsd ce
```

`build.sh` works around three FreeBSD issues:

- `go build` runs with `GOTOOLCHAIN=local`, because go126 1.26.2 satisfies `go 1.26.0`
  and would otherwise download the toolchain named in `go.mod`.
- The frontend Makefile needs GNU make, so `build.sh` calls npm directly.
- `sass-embedded` has no FreeBSD binary, and Vite hangs forever after
  `sass --embedded is unavailable in pure JS mode`. The script removes it, so Vite uses
  the pure JavaScript `sass` package.

### PhotoPrism Plus

With access to [photoprism/plus](https://github.com/photoprism/plus):

```sh
git submodule update --init plus
sh freebsd/scripts/build.sh plus build/freebsd-plus
sh freebsd/scripts/install.sh build/freebsd-plus plus
```

The Plus build only unlocks features your membership includes. A new or unlinked
instance shows **Essentials** until you activate it under Settings > Account with your
photoprism.app account.

## Service

`freebsd/rc.d/photoprism_develop` reads the existing `photoprism_*` rc.conf settings of
the `photoprism` package (storage path, auth mode, defaults YAML, args), so it uses the
same storage, originals and import folders. Its own settings:

| rc.conf | Default |
|---|---|
| `photoprism_develop_enable` | `NO` |
| `photoprism_develop_bin` | `/usr/local/bin/photoprism-develop` |
| `photoprism_develop_assetspath` | `/var/db/photoprism/assets-develop` |
| `photoprism_develop_storagepath` | `photoprism_storagepath` |
| `photoprism_develop_face_model` | `sface` |

Switch between CE and Plus with `sysrc photoprism_develop_bin=... photoprism_develop_assetspath=...`
and `service photoprism_develop restart`. Logs go to syslog (`/var/log/messages`, tag `photoprism`).

## Known issues

- **"database is locked" while indexing with SQLite.** Parallel index workers contend for
  the database; some date and label updates are skipped. Try
  `PHOTOPRISM_INDEX_WORKERS=1` (in `photoprism_develop_args`: `--index-workers=1`) or MariaDB.
- **Running CLI commands as `photoprism` from `/root`** panics with `stat .: permission denied`.
  `cd` to a directory the user can read first.
- **Face clustering needs enough faces.** People only appear after at least about 10
  faces of 112 px and quality 85 or more; with fewer, name faces manually in the photo's
  People tab.
- The `photoprism` package is still installed and can be switched back to, but only with
  a storage backup from before the migration.

## Rolling back

```sh
service photoprism_develop stop; sysrc photoprism_develop_enable=NO
# restore the storage backup taken before the switch
sysrc photoprism_enable=YES; service photoprism start
```
