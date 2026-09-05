#!/bin/sh
set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"
VITA3KIOS_DEVICE=${1:?usage: launch-game-with-jit.sh DEVICE_IDENTIFIER}
VITA3KIOS_BUNDLE=${VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER:-org.vita3kios.app}
VITA3KIOS_EXECUTABLE=${VITA3KIOS_DEBUG_EXECUTABLE:?Set VITA3KIOS_DEBUG_EXECUTABLE to the matching signed app executable}
if [ ! -f "$VITA3KIOS_EXECUTABLE" ]; then
    echo "error: the local app executable is missing" >&2
    exit 1
fi
VITA3KIOS_LAUNCH_DIR=$(mktemp -d /tmp/vita3kios-jit-launch.XXXXXX)
trap 'rm -f -- "$VITA3KIOS_LAUNCH_DIR/launch.json"; rmdir -- "$VITA3KIOS_LAUNCH_DIR"' EXIT

xcrun devicectl --timeout 30 device process launch \
    --device "$VITA3KIOS_DEVICE" --terminate-existing \
    --json-output "$VITA3KIOS_LAUNCH_DIR/launch.json" \
    "$VITA3KIOS_BUNDLE"
VITA3KIOS_PID=$(plutil -extract result.process.processIdentifier raw -o - \
    "$VITA3KIOS_LAUNCH_DIR/launch.json")
case "$VITA3KIOS_PID" in
    ''|*[!0-9]*) echo "error: invalid launched process identifier" >&2; exit 1 ;;
esac

# Attach after normal startup so remote system-symbol reads do not hold dyld
# at its launch notification. The helper opens the game after setup completes.
sleep 2
export VITA3KIOS_JIT_DEVICE="$VITA3KIOS_DEVICE"
export VITA3KIOS_JIT_BUNDLE="$VITA3KIOS_BUNDLE"

echo "Keep this debugger connected while testing. Type quit to end the debug session."
xcrun lldb --no-lldbinit \
    -o "settings set target.parallel-module-load false" \
    -o "settings set symbols.enable-external-lookup false" \
    -o "settings set target.memory-module-load-level minimal" \
    -o "settings set target.preload-symbols false" \
    -o "command script import \"$VITA3KIOS_SCRIPT_DIR/jit_debugger.py\"" \
    -o "target create --arch arm64 \"$VITA3KIOS_EXECUTABLE\"" \
    -o "device select $VITA3KIOS_DEVICE" \
    -o "device process attach -p $VITA3KIOS_PID" \
    -o "vita3kios-run"
