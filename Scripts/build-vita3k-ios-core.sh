#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_UPSTREAM="$VITA3KIOS_ROOT/External/Vita3K"
VITA3KIOS_PATCH="$VITA3KIOS_ROOT/Patches/Upstream/0003-add-ios-static-runtime-target.patch"
VITA3KIOS_UPSTREAM_REVISION=$(git -C "$VITA3KIOS_UPSTREAM" rev-parse HEAD)
VITA3KIOS_SOURCE_DIR="/tmp/vita3kios-vita3k-source-$VITA3KIOS_UPSTREAM_REVISION"
VITA3KIOS_DEPENDENCY_PREFIX="$VITA3KIOS_ROOT/Build/Dependencies/vcpkg/installed/arm64-ios-vita3k"
VITA3KIOS_MOLTENVK_ROOT="$VITA3KIOS_ROOT/Build/Dependencies/MoltenVK/v1.4.1-ios/MoltenVK/MoltenVK"
VITA3KIOS_BUILD_DIR="$VITA3KIOS_ROOT/Build/Vita3K-iOS"
VITA3KIOS_PRODUCT_DIR="$VITA3KIOS_ROOT/Build/Core"
VITA3KIOS_PRODUCT="$VITA3KIOS_PRODUCT_DIR/libVita3KFullCore.a"
VITA3KIOS_BUILD_JOBS=${VITA3KIOS_BUILD_JOBS:-4}
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

if [ ! -f "$VITA3KIOS_PATCH" ]; then
    echo "error: iOS runtime patch is missing" >&2
    exit 1
fi

if [ ! -f "$VITA3KIOS_DEPENDENCY_PREFIX/lib/libavcodec.a" ] || \
   [ ! -f "$VITA3KIOS_DEPENDENCY_PREFIX/lib/libcrypto.a" ]; then
    "$VITA3KIOS_SCRIPT_DIR/build-ios-dependencies.sh"
fi

if [ ! -f "$VITA3KIOS_MOLTENVK_ROOT/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a" ]; then
    echo "error: iOS MoltenVK archive is missing" >&2
    exit 1
fi

VITA3KIOS_PATCH_SHA=$(shasum -a 256 "$VITA3KIOS_PATCH" | awk '{print $1}')
VITA3KIOS_SOURCE_READY=0
if [ -f "$VITA3KIOS_SOURCE_DIR/.vita3kios-patch-sha" ]; then
    if [ "$(sed -n '1p' "$VITA3KIOS_SOURCE_DIR/.vita3kios-patch-sha")" = "$VITA3KIOS_PATCH_SHA" ]; then
        VITA3KIOS_SOURCE_READY=1
    fi
fi

if [ "$VITA3KIOS_SOURCE_READY" -eq 0 ]; then
    VITA3KIOS_SOURCE_STAGE=$(mktemp -d /tmp/vita3kios-vita3k-source.XXXXXX)
    git -C "$VITA3KIOS_UPSTREAM" archive HEAD | tar -x -C "$VITA3KIOS_SOURCE_STAGE"
    git -C "$VITA3KIOS_UPSTREAM" submodule status --recursive |
    while read -r VITA3KIOS_SUBMODULE_REVISION VITA3KIOS_SUBMODULE_PATH VITA3KIOS_SUBMODULE_DESCRIPTION; do
        mkdir -p "$VITA3KIOS_SOURCE_STAGE/$VITA3KIOS_SUBMODULE_PATH"
        git -C "$VITA3KIOS_UPSTREAM/$VITA3KIOS_SUBMODULE_PATH" archive HEAD |
            tar -x -C "$VITA3KIOS_SOURCE_STAGE/$VITA3KIOS_SUBMODULE_PATH"
    done
    patch -s -d "$VITA3KIOS_SOURCE_STAGE" -p1 < "$VITA3KIOS_PATCH"
    printf '%s\n' "$VITA3KIOS_PATCH_SHA" > "$VITA3KIOS_SOURCE_STAGE/.vita3kios-patch-sha"
    rm -rf -- "$VITA3KIOS_SOURCE_DIR"
    mv -- "$VITA3KIOS_SOURCE_STAGE" "$VITA3KIOS_SOURCE_DIR"
fi

VITA3KIOS_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path)

cmake -S "$VITA3KIOS_SOURCE_DIR" -B "$VITA3KIOS_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_SYSROOT="$VITA3KIOS_SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_PREFIX_PATH="$VITA3KIOS_DEPENDENCY_PREFIX" \
    -DOPENSSL_ROOT_DIR="$VITA3KIOS_DEPENDENCY_PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DBOOST_ROOT="$VITA3KIOS_DEPENDENCY_PREFIX" \
    -DBoost_NO_SYSTEM_PATHS=ON \
    -DBoost_INCLUDE_DIR="$VITA3KIOS_DEPENDENCY_PREFIX/include" \
    -DBoost_LIBRARY_DIR_RELEASE="$VITA3KIOS_DEPENDENCY_PREFIX/lib" \
    -DBoost_FILESYSTEM_LIBRARY_RELEASE="$VITA3KIOS_DEPENDENCY_PREFIX/lib/libboost_filesystem.a" \
    -DVITA3K_FORCE_SYSTEM_BOOST=ON \
    -DVITA3K_IOS_DEPENDENCY_PREFIX="$VITA3KIOS_DEPENDENCY_PREFIX" \
    -DVITA3K_IOS_MOLTENVK_ROOT="$VITA3KIOS_MOLTENVK_ROOT" \
    -DVITA3K_IOS_METAL_LAYER_SOURCE="$VITA3KIOS_ROOT/App/Core/src/metal_layer_ios.mm" \
    -DUSE_DISCORD_RICH_PRESENCE=OFF \
    -DUSE_LTO=NEVER \
    -DBUILD_TESTING=OFF \
    -DCAPSTONE_BUILD_MACOS_THIN=ON

CCACHE_DISABLE=1 cmake --build "$VITA3KIOS_BUILD_DIR" --target vita3k \
    --parallel "$VITA3KIOS_BUILD_JOBS"

mkdir -p -- "$VITA3KIOS_PRODUCT_DIR"
set --
while IFS= read -r VITA3KIOS_ARCHIVE; do
    set -- "$@" "$VITA3KIOS_ARCHIVE"
done <<EOF
$(find "$VITA3KIOS_BUILD_DIR" -type f -name '*.a' -print | sort)
$(find "$VITA3KIOS_DEPENDENCY_PREFIX/lib" -maxdepth 1 -type f -name '*.a' -print | sort)
$VITA3KIOS_MOLTENVK_ROOT/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a
EOF

if [ "$#" -eq 0 ]; then
    echo "error: no iOS runtime archives were produced" >&2
    exit 1
fi

libtool -static -D -o "$VITA3KIOS_PRODUCT" "$@"

VITA3KIOS_ARCHS=$(lipo -archs "$VITA3KIOS_PRODUCT")
if [ "$VITA3KIOS_ARCHS" != "arm64" ]; then
    echo "error: full core archive has unexpected architectures: $VITA3KIOS_ARCHS" >&2
    exit 1
fi

echo "vita3k_ios_core=$VITA3KIOS_PRODUCT"
echo "vita3k_ios_core_architectures=$VITA3KIOS_ARCHS"
