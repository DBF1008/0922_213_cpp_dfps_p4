#!/bin/bash
# Unit test: dfps still compiles with the NDK toolchain.
# Skipped gracefully when ANDROID_NDK is not available on this host.
set -e
BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${ANDROID_NDK:-}" ] || [ ! -d "$ANDROID_NDK" ]; then
    echo "SKIP ut_compile_dfps: ANDROID_NDK not set"
    exit 0
fi

BUILD_TYPE="${BUILD_TYPE:-Release}"
"$BASEDIR/build.sh" "$BUILD_TYPE" make
echo "PASS ut_compile_dfps"
