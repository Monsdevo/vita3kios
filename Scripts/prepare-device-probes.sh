#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_DYNARMIC_SOURCE="$VITA3KIOS_ROOT/External/Vita3K/external/dynarmic"
VITA3KIOS_PREPARED_REL="Build/DeviceProbes/Prepared/Dynarmic"
VITA3KIOS_PREPARED="$VITA3KIOS_ROOT/$VITA3KIOS_PREPARED_REL"
VITA3KIOS_DYNARMIC_PIN="86458a0bd369d63ba4c2ef812cacbb6c9080c065"
VITA3KIOS_OAKNUT_TREE="$(git -C "$VITA3KIOS_DYNARMIC_SOURCE" rev-parse HEAD:externals/oaknut)"

"$VITA3KIOS_SCRIPT_DIR/verify-upstream-pin.sh"

VITA3KIOS_ACTUAL_DYNARMIC=$(git -C "$VITA3KIOS_DYNARMIC_SOURCE" rev-parse HEAD)
if [ "$VITA3KIOS_ACTUAL_DYNARMIC" != "$VITA3KIOS_DYNARMIC_PIN" ]; then
    echo "error: Dynarmic pin mismatch" >&2
    echo "expected=$VITA3KIOS_DYNARMIC_PIN" >&2
    echo "actual=$VITA3KIOS_ACTUAL_DYNARMIC" >&2
    exit 1
fi

case "$VITA3KIOS_PREPARED" in
    "$VITA3KIOS_ROOT"/Build/DeviceProbes/Prepared/Dynarmic) ;;
    *) echo "error: refusing unsafe prepared-source path: $VITA3KIOS_PREPARED" >&2; exit 1 ;;
esac

mkdir -p -- "$(dirname -- "$VITA3KIOS_PREPARED")"
rm -rf -- "$VITA3KIOS_PREPARED"
mkdir -p -- "$VITA3KIOS_PREPARED"
rsync -a \
    --exclude='.git' \
    --exclude='build' \
    --exclude='src/dynarmic/backend/arm64/mig' \
    --exclude='src/dynarmic/backend/x64/mig' \
    "$VITA3KIOS_DYNARMIC_SOURCE/" "$VITA3KIOS_PREPARED/"

for VITA3KIOS_PATCH in \
    Patches/Dynarmic/0001-ios-select-generic-exception-handler.patch \
    Patches/Dynarmic/0002-oaknut-ios-check-executable-memory-errors.patch
do
    git -C "$VITA3KIOS_ROOT" apply --check \
        --directory="$VITA3KIOS_PREPARED_REL" "$VITA3KIOS_PATCH"
    git -C "$VITA3KIOS_ROOT" apply \
        --directory="$VITA3KIOS_PREPARED_REL" "$VITA3KIOS_PATCH"
done

echo "dynarmic_pin=$VITA3KIOS_ACTUAL_DYNARMIC"
echo "oaknut_vendor_tree=$VITA3KIOS_OAKNUT_TREE"
echo "prepared_dynarmic=$VITA3KIOS_PREPARED"
