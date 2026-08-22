#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

VITA3KIOS_MODE=${1:-all}
VITA3KIOS_SOURCE="$VITA3KIOS_ROOT/Probes/Device"
VITA3KIOS_SIGNING=${VITA3KIOS_SIGNING:-NO}
VITA3KIOS_BUNDLE_PREFIX=${VITA3KIOS_PROBE_BUNDLE_PREFIX:-org.vita3kios.probes}
VITA3KIOS_TEAM=${VITA3KIOS_DEVELOPMENT_TEAM:-}

case "$VITA3KIOS_MODE" in
    jit|moltenvk|all) ;;
    *) echo "usage: $0 [jit|moltenvk|all]" >&2; exit 64 ;;
esac

if [ "$VITA3KIOS_SIGNING" = "YES" ] && [ -z "$VITA3KIOS_TEAM" ]; then
    echo "error: VITA3KIOS_DEVELOPMENT_TEAM is required when VITA3KIOS_SIGNING=YES" >&2
    exit 1
fi

configure_and_build() {
    VITA3KIOS_KIND=$1
    VITA3KIOS_TARGET=$2
    if [ "$VITA3KIOS_SIGNING" = "YES" ]; then
        VITA3KIOS_SIGNED_ROOT=${VITA3KIOS_SIGNED_BUILD_ROOT:-${TMPDIR:-/tmp}/vita3kios-device-probes}
        VITA3KIOS_BUILD_DIR="${VITA3KIOS_SIGNED_ROOT%/}/$VITA3KIOS_KIND"
    else
        VITA3KIOS_BUILD_DIR="$VITA3KIOS_ROOT/Build/DeviceProbes/$VITA3KIOS_KIND"
    fi
    shift 2

    cmake --fresh -S "$VITA3KIOS_SOURCE" -B "$VITA3KIOS_BUILD_DIR" -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DVITA3KIOS_PROBE_BUNDLE_PREFIX="$VITA3KIOS_BUNDLE_PREFIX" \
        -DVITA3KIOS_DEVELOPMENT_TEAM="$VITA3KIOS_TEAM" \
        "$@"

    if [ "$VITA3KIOS_SIGNING" = "YES" ]; then
        cmake --build "$VITA3KIOS_BUILD_DIR" --config Release \
            --target "$VITA3KIOS_TARGET" -- \
            -sdk iphoneos \
            -allowProvisioningUpdates \
            CODE_SIGNING_ALLOWED=YES \
            DEVELOPMENT_TEAM="$VITA3KIOS_TEAM"
    else
        cmake --build "$VITA3KIOS_BUILD_DIR" --config Release \
            --target "$VITA3KIOS_TARGET" -- \
            -sdk iphoneos \
            CODE_SIGNING_ALLOWED=NO
    fi

    echo "probe_target=$VITA3KIOS_TARGET"
    echo "probe_build_dir=$VITA3KIOS_BUILD_DIR"
}

if [ "$VITA3KIOS_MODE" = "jit" ] || [ "$VITA3KIOS_MODE" = "all" ]; then
    "$VITA3KIOS_SCRIPT_DIR/prepare-device-probes.sh"
    configure_and_build JIT Vita3KiOSJITProbe \
        -DVITA3KIOS_ENABLE_JIT_PROBE=ON \
        -DVITA3KIOS_ENABLE_MOLTENVK_PROBE=OFF \
        -DVITA3KIOS_PREPARED_DYNARMIC_DIR="$VITA3KIOS_ROOT/Build/DeviceProbes/Prepared/Dynarmic"
fi

if [ "$VITA3KIOS_MODE" = "moltenvk" ] || [ "$VITA3KIOS_MODE" = "all" ]; then
    "$VITA3KIOS_SCRIPT_DIR/fetch-device-probe-deps.sh"
    configure_and_build MoltenVK Vita3KiOSMoltenVKProbe \
        -DVITA3KIOS_ENABLE_JIT_PROBE=OFF \
        -DVITA3KIOS_ENABLE_MOLTENVK_PROBE=ON \
        -DVITA3KIOS_MOLTENVK_ROOT="$VITA3KIOS_ROOT/Build/Dependencies/MoltenVK/v1.4.1-ios/MoltenVK/MoltenVK"
fi
