#!/bin/sh
#
# Builds PhotoPrism (CE or Plus) on FreeBSD 13 without TensorFlow.
#
# Usage: freebsd/scripts/build.sh [ce|plus] [OUTDIR]
#   ce   (default) builds ./cmd/photoprism and the CE frontend
#   plus builds ./plus/cmd/photoprism-plus and the frontend with the Plus
#        extensions; needs the plus submodule (git submodule update --init plus)
# Output: $OUTDIR/photoprism (or photoprism-plus) and $OUTDIR/assets
#
# Run from the repository root. Requires: go126, node24, npm-node24, gmake,
# vips, onnxruntime >= 1.29 (see build-onnxruntime.sh).

set -eu

EDITION=${1:-ce}
OUTDIR=${2:-build/freebsd}
GO=${GO:-/usr/local/go126/bin/go}

case "$EDITION" in
	ce) SRC=./cmd/photoprism; BIN=photoprism; SUFFIX="" ;;
	plus) SRC=./plus/cmd/photoprism-plus; BIN=photoprism-plus; SUFFIX="-Plus" ;;
	*) echo "usage: $0 [ce|plus] [OUTDIR]" >&2; exit 2 ;;
esac

if [ "$EDITION" = plus ] && [ ! -f plus/cmd/photoprism-plus/photoprism-plus.go ]; then
	echo "plus submodule is missing: git submodule update --init plus" >&2
	exit 1
fi

mkdir -p "$OUTDIR"
VERSION="$(date -u +%y%m%d)-$(git rev-parse --short=9 HEAD)-FreeBSD-$(uname -m | tr a-z A-Z)${SUFFIX}-notensorflow"

echo "Building $BIN $VERSION..."
# The local toolchain satisfies the go directive in go.mod; GOTOOLCHAIN=local stops
# Go from downloading the newer toolchain named in the toolchain directive.
env GOTOOLCHAIN=local CGO_ENABLED=1 "$GO" build -tags notensorflow \
	-ldflags "-s -w -X main.version=$VERSION" -o "$OUTDIR/$BIN" "$SRC"

echo "Building frontend..."
(
	cd frontend
	# The engines field asks for node ^24.15; FreeBSD packages have 24.14, which works.
	npm ci --ignore-scripts --no-audit --no-fund --no-update-notifier
	# sass-embedded has no FreeBSD compiler binary, and Vite hangs forever when it is
	# installed. Without it, Vite uses the pure JavaScript sass package.
	rm -rf ../node_modules/sass-embedded ../node_modules/sass-embedded-*
	if [ "$EDITION" = plus ]; then
		env BUILD_ENV=production NODE_ENV=production CUSTOM_SRC="../plus/frontend" \
			CUSTOM_NAME="PhotoPrism+" npm run build
	else
		env BUILD_ENV=production NODE_ENV=production npm run build
	fi
)

echo "Collecting assets..."
rm -rf "$OUTDIR/assets"
mkdir -p "$OUTDIR/assets"
(cd assets && tar --exclude ./samples --exclude ./models -cf - .) | tar -xf - -C "$OUTDIR/assets"
mkdir -p "$OUTDIR/assets/models"
if [ "$EDITION" = plus ]; then
	(cd plus/assets/static && tar -cf - .) | tar -xf - -C "$OUTDIR/assets/static"
fi

echo "Done: $OUTDIR/$BIN ($VERSION) and $OUTDIR/assets"
echo "Models: MODELS_PATH=<assets>/models bash scripts/dist/download-models.sh efficientformerv2_s2 sface yahoo_open_nsfw yunet"
