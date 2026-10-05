#!/bin/sh
#
# Builds ONNX Runtime from the current FreeBSD ports tree as a package.
#
# FreeBSD 13 packages stop at onnxruntime 1.23.2 (ORT API 23), but PhotoPrism
# uses github.com/yalue/onnxruntime_go v1.36, which needs ORT API 29 or later.
# The ports tree has a newer misc/onnxruntime that still builds on 13.x once the
# end-of-life check is bypassed.
#
# Usage: build-onnxruntime.sh [WORKDIR]   (default: /root/build)
# Output: $WORKDIR/onnxruntime-<version>.pkg

set -eu

WORKDIR=${1:-/root/build}
PORTS="$WORKDIR/ports"
JOBS=$(sysctl -n hw.ncpu)

export IGNORE_OSVERSION=yes ASSUME_ALWAYS_YES=yes

mkdir -p "$WORKDIR"

# A separate ports tree, so the system /usr/ports stays untouched.
if [ ! -d "$PORTS" ]; then
	git clone --depth 1 https://git.FreeBSD.org/ports.git "$PORTS"
fi

pkg install cmake-core ninja patch python312

# The port refuses to build while these are installed (CONFLICTS_BUILD).
# googletest is pulled in by node24, so it is removed for the build and restored afterwards.
REINSTALL=""
for p in abseil benchmark nsync googletest dlpack flatbuffers gsl mimalloc \
	nlohmann-json onnx protobuf psimd pthreadpool pybind11 re2; do
	if pkg info -e "$p"; then
		REINSTALL="$REINSTALL $p"
		pkg delete -f "$p"
	fi
done

cd "$PORTS/misc/onnxruntime"
env ALLOW_UNSUPPORTED_SYSTEM=yes PORTSDIR="$PORTS" BATCH=yes MAKE_JOBS_NUMBER="$JOBS" \
	make clean package
cp work/pkg/onnxruntime-*.pkg "$WORKDIR/"

if [ -n "$REINSTALL" ]; then
	# shellcheck disable=SC2086
	pkg install $REINSTALL
fi

ls -la "$WORKDIR"/onnxruntime-*.pkg
echo "Install with: pkg install $WORKDIR/onnxruntime-<version>.pkg && pkg lock -y onnxruntime"
