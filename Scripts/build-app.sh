#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

VITA3KIOS_MODE=${1:-device}
VITA3KIOS_SIGNING=${VITA3KIOS_SIGNING:-NO}
VITA3KIOS_TEAM=${VITA3KIOS_DEVELOPMENT_TEAM:-}
VITA3KIOS_BUNDLE_ID=${VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER:-org.vita3kios.app}

case "$VITA3KIOS_MODE" in
    host)
        VITA3KIOS_BUILD_DIR="$VITA3KIOS_ROOT/Build/AppHost"
        cmake --fresh -S "$VITA3KIOS_ROOT/App" -B "$VITA3KIOS_BUILD_DIR" -G Ninja
        cmake --build "$VITA3KIOS_BUILD_DIR"
        ctest --test-dir "$VITA3KIOS_BUILD_DIR" --output-on-failure
        echo "app_host_tests=passed"
        exit 0
        ;;
    device)
        VITA3KIOS_SYSROOT=iphoneos
        VITA3KIOS_FULL_CORE=${VITA3KIOS_FULL_CORE:-YES}
        ;;
    simulator)
        VITA3KIOS_SYSROOT=iphonesimulator
        VITA3KIOS_SIGNING=NO
        VITA3KIOS_FULL_CORE=NO
        ;;
    *)
        echo "usage: $0 [host|device|simulator]" >&2
        exit 64
        ;;
esac

if [ "${VITA3KIOS_FULL_CORE:-NO}" = "YES" ]; then
    "$VITA3KIOS_SCRIPT_DIR/build-vita3k-ios-core.sh"
fi

if [ "$VITA3KIOS_SIGNING" = "YES" ] && [ -z "$VITA3KIOS_TEAM" ]; then
    echo "error: VITA3KIOS_DEVELOPMENT_TEAM is required when VITA3KIOS_SIGNING=YES" >&2
    exit 1
fi

if [ "$VITA3KIOS_SIGNING" = "YES" ]; then
    VITA3KIOS_SIGNED_ROOT=${VITA3KIOS_SIGNED_BUILD_ROOT:-${TMPDIR:-/tmp}/vita3kios-product}
    VITA3KIOS_BUILD_DIR="${VITA3KIOS_SIGNED_ROOT%/}/$VITA3KIOS_MODE"
else
    VITA3KIOS_BUILD_DIR="$VITA3KIOS_ROOT/Build/App/$VITA3KIOS_MODE"
fi

cmake -S "$VITA3KIOS_ROOT/App" -B "$VITA3KIOS_BUILD_DIR" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$VITA3KIOS_SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DVITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER="$VITA3KIOS_BUNDLE_ID" \
    -DVITA3KIOS_DEVELOPMENT_TEAM="$VITA3KIOS_TEAM" \
    -DVITA3KIOS_FULL_CORE="$VITA3KIOS_FULL_CORE"

if [ "$VITA3KIOS_SIGNING" = "YES" ]; then
    cmake --build "$VITA3KIOS_BUILD_DIR" --config Release --target vita3kios -- \
        -sdk iphoneos \
        -allowProvisioningUpdates \
        CODE_SIGNING_ALLOWED=YES \
        DEVELOPMENT_TEAM="$VITA3KIOS_TEAM"
else
    cmake --build "$VITA3KIOS_BUILD_DIR" --config Release --target vita3kios -- \
        -sdk "$VITA3KIOS_SYSROOT" \
        CODE_SIGNING_ALLOWED=NO
fi

echo "app_mode=$VITA3KIOS_MODE"
echo "app_build_dir=$VITA3KIOS_BUILD_DIR"
