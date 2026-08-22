#!/bin/sh

set -eu

VITA3KIOS_DEFAULT_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
VITA3KIOS_DEVELOPER_DIR="${DEVELOPER_DIR:-$VITA3KIOS_DEFAULT_DEVELOPER_DIR}"

if [ ! -d "$VITA3KIOS_DEVELOPER_DIR" ]; then
    echo "error: Xcode developer directory not found: $VITA3KIOS_DEVELOPER_DIR" >&2
    exit 1
fi

DEVELOPER_DIR="$VITA3KIOS_DEVELOPER_DIR"
export DEVELOPER_DIR
