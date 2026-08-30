#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_UPSTREAM="$VITA3KIOS_ROOT/External/Vita3K"
VITA3KIOS_BUILD_ROOT="$VITA3KIOS_ROOT/Build/Dependencies"
VITA3KIOS_VCPKG_ROOT="$VITA3KIOS_BUILD_ROOT/vcpkg"
VITA3KIOS_VCPKG_REVISION=34823ada10080ddca99b60e85f80f55e18a44eea
VITA3KIOS_TRIPLET=arm64-ios-vita3k
VITA3KIOS_TRIPLET_ROOT="$VITA3KIOS_ROOT/Toolchains"
VITA3KIOS_VCPKG_PATCH="$VITA3KIOS_ROOT/Patches/Dependencies/0001-curl-disable-ios-pipe2.patch"
VITA3KIOS_VCPKG_PATCH_APPLIED=0
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

if [ ! -f "$VITA3KIOS_UPSTREAM/external/ffmpeg/include/libavcodec/avcodec.h" ]; then
    echo "error: pinned Vita3K FFmpeg headers are missing" >&2
    exit 1
fi

mkdir -p -- "$VITA3KIOS_BUILD_ROOT"

if [ ! -d "$VITA3KIOS_VCPKG_ROOT/.git" ]; then
    git clone --filter=blob:none https://github.com/microsoft/vcpkg.git \
        "$VITA3KIOS_VCPKG_ROOT"
fi

VITA3KIOS_ACTUAL_REMOTE=$(git -C "$VITA3KIOS_VCPKG_ROOT" remote get-url origin)
if [ "$VITA3KIOS_ACTUAL_REMOTE" != "https://github.com/microsoft/vcpkg.git" ]; then
    echo "error: refusing to use an unexpected vcpkg checkout: $VITA3KIOS_ACTUAL_REMOTE" >&2
    exit 1
fi

git -C "$VITA3KIOS_VCPKG_ROOT" fetch --depth 1 origin "$VITA3KIOS_VCPKG_REVISION"
git -C "$VITA3KIOS_VCPKG_ROOT" checkout --detach "$VITA3KIOS_VCPKG_REVISION"

vita3kios_cleanup() {
    VITA3KIOS_STATUS=$?
    trap - EXIT HUP INT TERM
    if [ "$VITA3KIOS_VCPKG_PATCH_APPLIED" -eq 1 ]; then
        git -C "$VITA3KIOS_VCPKG_ROOT" apply --reverse "$VITA3KIOS_VCPKG_PATCH"
    fi
    exit "$VITA3KIOS_STATUS"
}
trap vita3kios_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

git -C "$VITA3KIOS_VCPKG_ROOT" apply --check "$VITA3KIOS_VCPKG_PATCH"
git -C "$VITA3KIOS_VCPKG_ROOT" apply "$VITA3KIOS_VCPKG_PATCH"
VITA3KIOS_VCPKG_PATCH_APPLIED=1

if [ ! -x "$VITA3KIOS_VCPKG_ROOT/vcpkg" ]; then
    "$VITA3KIOS_VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
fi

export VCPKG_DISABLE_METRICS=1
export VCPKG_DEFAULT_BINARY_CACHE="$VITA3KIOS_BUILD_ROOT/vcpkg-cache"
mkdir -p -- "$VCPKG_DEFAULT_BINARY_CACHE"

"$VITA3KIOS_VCPKG_ROOT/vcpkg" install \
    "ffmpeg[avcodec,avfilter,avdevice,avformat,swresample,swscale]:$VITA3KIOS_TRIPLET" \
    "openssl:$VITA3KIOS_TRIPLET" \
    "curl:$VITA3KIOS_TRIPLET" \
    "boost-algorithm:$VITA3KIOS_TRIPLET" \
    "boost-describe:$VITA3KIOS_TRIPLET" \
    "boost-filesystem:$VITA3KIOS_TRIPLET" \
    "boost-icl:$VITA3KIOS_TRIPLET" \
    "boost-program-options:$VITA3KIOS_TRIPLET" \
    "boost-spirit:$VITA3KIOS_TRIPLET" \
    "boost-system:$VITA3KIOS_TRIPLET" \
    "boost-timer:$VITA3KIOS_TRIPLET" \
    "boost-unordered:$VITA3KIOS_TRIPLET" \
    "boost-variant:$VITA3KIOS_TRIPLET" \
    --overlay-triplets="$VITA3KIOS_TRIPLET_ROOT" \
    --clean-after-build

"$VITA3KIOS_SCRIPT_DIR/fetch-device-probe-deps.sh"

echo "ios_dependency_prefix=$VITA3KIOS_VCPKG_ROOT/installed/$VITA3KIOS_TRIPLET"
echo "moltenvk_root=$VITA3KIOS_BUILD_ROOT/MoltenVK/v1.4.1-ios/MoltenVK/MoltenVK"
