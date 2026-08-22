#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_REPO_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_APP_BUNDLE="$VITA3KIOS_REPO_ROOT/External/Vita3K/build/macos-xcode/bin/Release/Vita3K.app"
VITA3KIOS_SMOKE_STAGE=
VITA3KIOS_SMOKE_PID=
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

if [ ! -d "$VITA3KIOS_APP_BUNDLE" ]; then
    echo "error: upstream app bundle is missing; build it first" >&2
    exit 1
fi

vita3kios_smoke_cleanup() {
    VITA3KIOS_SMOKE_STATUS=$?
    trap - EXIT HUP INT TERM

    if [ -n "$VITA3KIOS_SMOKE_PID" ] && kill -0 "$VITA3KIOS_SMOKE_PID" 2>/dev/null; then
        kill -TERM "$VITA3KIOS_SMOKE_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$VITA3KIOS_SMOKE_PID" 2>/dev/null; then
            kill -KILL "$VITA3KIOS_SMOKE_PID" 2>/dev/null || true
        fi
        wait "$VITA3KIOS_SMOKE_PID" 2>/dev/null || true
    fi

    if [ -n "$VITA3KIOS_SMOKE_STAGE" ]; then
        case "$VITA3KIOS_SMOKE_STAGE" in
            /private/tmp/vita3kios-smoke.*)
                /bin/rm -rf -- "$VITA3KIOS_SMOKE_STAGE"
                ;;
            *)
                echo "error: refusing to remove unexpected smoke stage: $VITA3KIOS_SMOKE_STAGE" >&2
                VITA3KIOS_SMOKE_STATUS=1
                ;;
        esac
    fi

    exit "$VITA3KIOS_SMOKE_STATUS"
}

trap vita3kios_smoke_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

VITA3KIOS_SMOKE_STAGE=$(mktemp -d /private/tmp/vita3kios-smoke.XXXXXX)
VITA3KIOS_STAGED_APP="$VITA3KIOS_SMOKE_STAGE/Vita3K.app"
VITA3KIOS_STAGED_EXE="$VITA3KIOS_STAGED_APP/Contents/MacOS/Vita3K"

ditto --norsrc --noextattr --noqtn --noacl "$VITA3KIOS_APP_BUNDLE" "$VITA3KIOS_STAGED_APP"

# SDL_GetBasePath returns a trailing slash. Upstream's Apple path calculation
# walks four parents from that path, so this directory selects isolated portable
# mode and prevents the smoke test from touching the user's Vita3K data.
mkdir "$VITA3KIOS_SMOKE_STAGE/portable"
xattr -cr "$VITA3KIOS_STAGED_APP"
codesign --force --deep --sign - "$VITA3KIOS_STAGED_APP"
codesign --verify --deep --strict "$VITA3KIOS_STAGED_APP"

VITA3KIOS_SMOKE_LOG="$VITA3KIOS_SMOKE_STAGE/stdout-stderr.log"
"$VITA3KIOS_STAGED_EXE" >"$VITA3KIOS_SMOKE_LOG" 2>&1 &
VITA3KIOS_SMOKE_PID=$!

VITA3KIOS_SMOKE_ATTEMPT=0
while [ "$VITA3KIOS_SMOKE_ATTEMPT" -lt 20 ]; do
    if ! kill -0 "$VITA3KIOS_SMOKE_PID" 2>/dev/null; then
        break
    fi
    if [ -f "$VITA3KIOS_SMOKE_STAGE/portable/config.yml" ] && \
        grep -Fq '[apply_theme_entry]' "$VITA3KIOS_SMOKE_LOG"; then
        break
    fi
    sleep 1
    VITA3KIOS_SMOKE_ATTEMPT=$((VITA3KIOS_SMOKE_ATTEMPT + 1))
done

if ! kill -0 "$VITA3KIOS_SMOKE_PID" 2>/dev/null; then
    set +e
    wait "$VITA3KIOS_SMOKE_PID"
    VITA3KIOS_SMOKE_EXEC_STATUS=$?
    set -e
    VITA3KIOS_SMOKE_PID=
    sed -n '1,200p' "$VITA3KIOS_SMOKE_LOG"
    echo "error: staged Vita3K exited during launch with status $VITA3KIOS_SMOKE_EXEC_STATUS" >&2
    exit 1
fi

if [ ! -f "$VITA3KIOS_SMOKE_STAGE/portable/config.yml" ]; then
    sed -n '1,200p' "$VITA3KIOS_SMOKE_LOG"
    echo "error: isolated portable config was not created during smoke test" >&2
    exit 1
fi
if ! grep -Fq '[apply_theme_entry]' "$VITA3KIOS_SMOKE_LOG"; then
    sed -n '1,200p' "$VITA3KIOS_SMOKE_LOG"
    echo "error: Vita3K did not reach the initialized UI marker" >&2
    exit 1
fi

kill -TERM "$VITA3KIOS_SMOKE_PID"
VITA3KIOS_SMOKE_STOP_ATTEMPT=0
while kill -0 "$VITA3KIOS_SMOKE_PID" 2>/dev/null && [ "$VITA3KIOS_SMOKE_STOP_ATTEMPT" -lt 5 ]; do
    sleep 1
    VITA3KIOS_SMOKE_STOP_ATTEMPT=$((VITA3KIOS_SMOKE_STOP_ATTEMPT + 1))
done
if kill -0 "$VITA3KIOS_SMOKE_PID" 2>/dev/null; then
    kill -KILL "$VITA3KIOS_SMOKE_PID"
fi
set +e
wait "$VITA3KIOS_SMOKE_PID"
VITA3KIOS_SMOKE_EXEC_STATUS=$?
set -e
VITA3KIOS_SMOKE_PID=

case "$VITA3KIOS_SMOKE_EXEC_STATUS" in
    0|137|143) ;;
    *)
        sed -n '1,200p' "$VITA3KIOS_SMOKE_LOG"
        echo "error: staged Vita3K stopped with unexpected status $VITA3KIOS_SMOKE_EXEC_STATUS" >&2
        exit 1
        ;;
esac

codesign --verify --deep --strict "$VITA3KIOS_STAGED_APP"
echo "smoke_test=passed"
echo "storage_scope=$VITA3KIOS_SMOKE_STAGE/portable"
