#!/bin/sh
#
# Installs a FreeBSD build (from build.sh or a release archive) as the
# photoprism_develop service.
#
# Usage: freebsd/scripts/install.sh BUILDDIR [ce|plus]
#   BUILDDIR contains photoprism (or photoprism-plus) and assets/
# Runs from a repository checkout or from an extracted release archive, which
# has the same freebsd/ and scripts/dist/ layout.
#
# Installs:
#   /usr/local/bin/photoprism-develop or /usr/local/bin/photoprism-plus
#   /var/db/photoprism/assets-develop or /var/db/photoprism/assets-plus (with ONNX models)
#   /usr/local/etc/rc.d/photoprism_develop
# The service reuses the photoprism_* settings of the photoprism package (storage,
# originals, import path, auth mode) and does not change data until it is started.

set -eu

BUILDDIR=${1:?usage: $0 BUILDDIR [ce|plus]}
EDITION=${2:-ce}
HERE=$(cd "$(dirname "$0")/.." && pwd)

case "$EDITION" in
	ce) BIN=photoprism; DEST_BIN=/usr/local/bin/photoprism-develop; ASSETS=/var/db/photoprism/assets-develop ;;
	plus) BIN=photoprism-plus; DEST_BIN=/usr/local/bin/photoprism-plus; ASSETS=/var/db/photoprism/assets-plus ;;
	*) echo "usage: $0 BUILDDIR [ce|plus]" >&2; exit 2 ;;
esac

export IGNORE_OSVERSION=yes ASSUME_ALWAYS_YES=yes

if ! pkg info -e onnxruntime || [ "$(pkg query %v onnxruntime | cut -d. -f2)" -lt 29 ]; then
	echo "onnxruntime >= 1.29 is required; install the release package or run build-onnxruntime.sh" >&2
	exit 1
fi

pkg install vips ffmpeg p5-Image-ExifTool libheif bash curl

if ! pw usershow photoprism >/dev/null 2>&1; then
	pw useradd photoprism -d /var/db/photoprism -s /usr/sbin/nologin -c "PhotoPrism"
fi

install -m 555 "$BUILDDIR/$BIN" "$DEST_BIN"

rm -rf "$ASSETS"
mkdir -p "$ASSETS"
(cd "$BUILDDIR/assets" && tar -cf - .) | tar -xf - -C "$ASSETS"

if [ ! -f "$ASSETS/models/sface/face_recognition_sface_2021dec.onnx" ]; then
	MODELS_PATH="$ASSETS/models" BACKUP_PATH=/tmp/photoprism-model-backup \
		bash "$HERE/../scripts/dist/download-models.sh" efficientformerv2_s2 sface yahoo_open_nsfw yunet
fi
chown -R photoprism:photoprism "$ASSETS"

install -m 555 "$HERE/rc.d/photoprism_develop" /usr/local/etc/rc.d/photoprism_develop
sysrc photoprism_develop_bin="$DEST_BIN" photoprism_develop_assetspath="$ASSETS"

echo
echo "Installed. Back up your storage path, then switch services:"
echo "  service photoprism onestop; sysrc photoprism_enable=NO"
echo "  sysrc photoprism_develop_enable=YES && service photoprism_develop start"
