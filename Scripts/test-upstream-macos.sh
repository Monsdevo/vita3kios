#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_REPO_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_BUILD_DIR="$VITA3KIOS_REPO_ROOT/External/Vita3K/build/macos-xcode"
VITA3KIOS_XCODE_PROJECT="$VITA3KIOS_BUILD_DIR/Vita3K.xcodeproj/project.pbxproj"
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH \
    LIBRARY_PATH LDFLAGS CPPFLAGS \
    CMAKE_PREFIX_PATH CMAKE_LIBRARY_PATH CMAKE_INCLUDE_PATH \
    CMAKE_FRAMEWORK_PATH CMAKE_APPBUNDLE_PATH CMAKE_PROGRAM_PATH \
    PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR \
    OPENSSL_ROOT_DIR CURL_ROOT ZLIB_ROOT BOOST_ROOT BOOST_INCLUDEDIR \
    BOOST_LIBRARYDIR SDKROOT MACOSX_DEPLOYMENT_TARGET \
    DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
    DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH

VITA3KIOS_MACOS_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
if [ ! -d "$VITA3KIOS_MACOS_SDKROOT" ]; then
    echo "error: selected macOS SDK is missing: $VITA3KIOS_MACOS_SDKROOT" >&2
    exit 1
fi

SDKROOT="$VITA3KIOS_MACOS_SDKROOT"
PKG_CONFIG_PATH=
PKG_CONFIG_LIBDIR="$VITA3KIOS_MACOS_SDKROOT/usr/lib/pkgconfig"
export SDKROOT PKG_CONFIG_PATH PKG_CONFIG_LIBDIR

if [ ! -d "$VITA3KIOS_BUILD_DIR" ]; then
    echo "error: upstream build directory is missing; build first" >&2
    exit 1
fi
if [ ! -f "$VITA3KIOS_XCODE_PROJECT" ]; then
    echo "error: generated Vita3K Xcode project is missing; build first" >&2
    exit 1
fi
if grep -Fq '/opt/local' "$VITA3KIOS_XCODE_PROJECT"; then
    echo "error: generated Vita3K Xcode project contains MacPorts paths; rebuild first" >&2
    exit 1
fi
if grep -Fq -- '-ld64' "$VITA3KIOS_XCODE_PROJECT"; then
    echo "error: generated Vita3K Xcode project contains the legacy -ld64 flag; rebuild first" >&2
    exit 1
fi

cmake --build "$VITA3KIOS_BUILD_DIR" --config Release \
    --target mem-tests module-tests --parallel
ctest --test-dir "$VITA3KIOS_BUILD_DIR" -C Release --output-on-failure
