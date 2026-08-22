#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_REPO_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

for VITA3KIOS_TOOL in git cmake ninja brew xcodebuild xcrun; do
    if ! command -v "$VITA3KIOS_TOOL" >/dev/null 2>&1; then
        echo "error: required tool is missing: $VITA3KIOS_TOOL" >&2
        exit 1
    fi
done

for VITA3KIOS_FORMULA in openssl qt qtwebengine qtvirtualkeyboard; do
    if ! VITA3KIOS_FORMULA_PREFIX=$(brew --prefix "$VITA3KIOS_FORMULA" 2>/dev/null) || \
        [ ! -d "$VITA3KIOS_FORMULA_PREFIX" ]; then
        echo "error: required Homebrew formula is missing: $VITA3KIOS_FORMULA" >&2
        exit 1
    fi
done

if [ ! -f "$VITA3KIOS_REPO_ROOT/.gitmodules" ]; then
    echo "error: External/Vita3K submodule has not been added yet" >&2
    exit 1
fi

git -C "$VITA3KIOS_REPO_ROOT" submodule update --init --recursive
"$VITA3KIOS_SCRIPT_DIR/toolchain-report.sh"
"$VITA3KIOS_SCRIPT_DIR/verify-upstream-pin.sh"
