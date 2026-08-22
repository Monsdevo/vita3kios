#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_REPO_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_MANIFEST="$VITA3KIOS_REPO_ROOT/Docs/Audits/UPSTREAM_ARTIFACTS.sha256"

if [ ! -f "$VITA3KIOS_MANIFEST" ]; then
    echo "error: artifact checksum manifest is missing" >&2
    exit 1
fi

cd "$VITA3KIOS_REPO_ROOT"
shasum -a 256 --check "$VITA3KIOS_MANIFEST"
