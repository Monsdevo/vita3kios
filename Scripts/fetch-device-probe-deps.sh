#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_DEP_DIR="$VITA3KIOS_ROOT/Build/Dependencies/MoltenVK"
VITA3KIOS_ARCHIVE="$VITA3KIOS_DEP_DIR/MoltenVK-ios-v1.4.1.tar"
VITA3KIOS_PACKAGE="$VITA3KIOS_DEP_DIR/v1.4.1-ios"
VITA3KIOS_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.1/MoltenVK-ios.tar"
VITA3KIOS_EXPECTED_SHA="54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701"
VITA3KIOS_DOWNLOAD="$VITA3KIOS_ARCHIVE.download.$$"
VITA3KIOS_STAGE="$VITA3KIOS_DEP_DIR/.extract.$$"

cleanup() {
    rm -f -- "$VITA3KIOS_DOWNLOAD"
    rm -rf -- "$VITA3KIOS_STAGE"
}
trap cleanup EXIT HUP INT TERM

mkdir -p -- "$VITA3KIOS_DEP_DIR"

if [ -f "$VITA3KIOS_ARCHIVE" ]; then
    VITA3KIOS_ACTUAL_SHA=$(shasum -a 256 "$VITA3KIOS_ARCHIVE" | awk '{print $1}')
    if [ "$VITA3KIOS_ACTUAL_SHA" != "$VITA3KIOS_EXPECTED_SHA" ]; then
        echo "error: cached MoltenVK archive hash mismatch" >&2
        echo "expected=$VITA3KIOS_EXPECTED_SHA" >&2
        echo "actual=$VITA3KIOS_ACTUAL_SHA" >&2
        exit 1
    fi
else
    curl --fail --location --retry 3 --silent --show-error \
        "$VITA3KIOS_URL" --output "$VITA3KIOS_DOWNLOAD"
    VITA3KIOS_ACTUAL_SHA=$(shasum -a 256 "$VITA3KIOS_DOWNLOAD" | awk '{print $1}')
    if [ "$VITA3KIOS_ACTUAL_SHA" != "$VITA3KIOS_EXPECTED_SHA" ]; then
        echo "error: downloaded MoltenVK archive hash mismatch" >&2
        echo "expected=$VITA3KIOS_EXPECTED_SHA" >&2
        echo "actual=$VITA3KIOS_ACTUAL_SHA" >&2
        exit 1
    fi
    mv -- "$VITA3KIOS_DOWNLOAD" "$VITA3KIOS_ARCHIVE"
fi

VITA3KIOS_STATIC_REL="MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
VITA3KIOS_HEADERS_REL="MoltenVK/MoltenVK/include/vulkan/vulkan.h"

if [ ! -f "$VITA3KIOS_PACKAGE/$VITA3KIOS_STATIC_REL" ] || \
   [ ! -f "$VITA3KIOS_PACKAGE/$VITA3KIOS_HEADERS_REL" ]; then
    mkdir -p -- "$VITA3KIOS_STAGE"
    tar xf "$VITA3KIOS_ARCHIVE" -C "$VITA3KIOS_STAGE"
    if [ ! -f "$VITA3KIOS_STAGE/$VITA3KIOS_STATIC_REL" ] || \
       [ ! -f "$VITA3KIOS_STAGE/$VITA3KIOS_HEADERS_REL" ]; then
        echo "error: MoltenVK archive does not contain the expected iOS package" >&2
        exit 1
    fi
    rm -rf -- "$VITA3KIOS_PACKAGE"
    mkdir -p -- "$VITA3KIOS_PACKAGE"
    mv -- "$VITA3KIOS_STAGE/MoltenVK" "$VITA3KIOS_PACKAGE/MoltenVK"
fi

VITA3KIOS_STATIC="$VITA3KIOS_PACKAGE/$VITA3KIOS_STATIC_REL"
VITA3KIOS_ARCHS=$(lipo -archs "$VITA3KIOS_STATIC")
if [ "$VITA3KIOS_ARCHS" != "arm64" ]; then
    echo "error: expected a device-only arm64 MoltenVK archive, got: $VITA3KIOS_ARCHS" >&2
    exit 1
fi

echo "moltenvk_version=1.4.1"
echo "moltenvk_sha256=$VITA3KIOS_EXPECTED_SHA"
echo "moltenvk_architectures=$VITA3KIOS_ARCHS"
echo "moltenvk_root=$VITA3KIOS_PACKAGE/MoltenVK/MoltenVK"
