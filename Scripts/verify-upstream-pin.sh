#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_REPO_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_UPSTREAM_DIR="$VITA3KIOS_REPO_ROOT/External/Vita3K"
VITA3KIOS_EXPECTED_SHA="496939b602703951277263c7b3e60a9ae36879c1"
VITA3KIOS_EXPECTED_RECURSIVE_COUNT="41"

VITA3KIOS_ACTUAL_SHA=$(git -C "$VITA3KIOS_UPSTREAM_DIR" rev-parse HEAD)
if [ "$VITA3KIOS_ACTUAL_SHA" != "$VITA3KIOS_EXPECTED_SHA" ]; then
    echo "error: Vita3K pin mismatch" >&2
    echo "expected=$VITA3KIOS_EXPECTED_SHA" >&2
    echo "actual=$VITA3KIOS_ACTUAL_SHA" >&2
    exit 1
fi

VITA3KIOS_SUBMODULE_STATUS=$(git -C "$VITA3KIOS_REPO_ROOT" submodule status --recursive)
VITA3KIOS_RECURSIVE_COUNT=$(printf '%s\n' "$VITA3KIOS_SUBMODULE_STATUS" | wc -l | tr -d ' ')
if [ "$VITA3KIOS_RECURSIVE_COUNT" != "$VITA3KIOS_EXPECTED_RECURSIVE_COUNT" ]; then
    echo "error: unexpected recursive submodule count" >&2
    echo "expected=$VITA3KIOS_EXPECTED_RECURSIVE_COUNT" >&2
    echo "actual=$VITA3KIOS_RECURSIVE_COUNT" >&2
    exit 1
fi

VITA3KIOS_BAD_STATUS=$(printf '%s\n' "$VITA3KIOS_SUBMODULE_STATUS" | sed -n '/^[-+U]/p')
if [ -n "$VITA3KIOS_BAD_STATUS" ]; then
    echo "error: uninitialized, mismatched or conflicted submodule" >&2
    echo "$VITA3KIOS_BAD_STATUS" >&2
    exit 1
fi

if [ -n "$(git -C "$VITA3KIOS_UPSTREAM_DIR" status --short --ignore-submodules=none)" ]; then
    echo "error: pinned Vita3K worktree or nested submodule is dirty" >&2
    git -C "$VITA3KIOS_UPSTREAM_DIR" status --short --ignore-submodules=none >&2
    exit 1
fi

echo "vita3k_sha=$VITA3KIOS_ACTUAL_SHA"
echo "recursive_submodules=$VITA3KIOS_RECURSIVE_COUNT"
echo "submodule_state=clean"
