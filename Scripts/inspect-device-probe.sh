#!/bin/sh

set -eu

VITA3KIOS_REQUIRE_SIGNED=NO
if [ "${1:-}" = "--require-signed" ]; then
    VITA3KIOS_REQUIRE_SIGNED=YES
    shift
fi

if [ "$#" -ne 1 ]; then
    echo "usage: $0 [--require-signed] /absolute/path/to/Probe.app" >&2
    exit 64
fi

VITA3KIOS_APP=$1
if [ ! -d "$VITA3KIOS_APP" ]; then
    echo "error: app bundle not found: $VITA3KIOS_APP" >&2
    exit 1
fi

VITA3KIOS_EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$VITA3KIOS_APP/Info.plist")
VITA3KIOS_BINARY="$VITA3KIOS_APP/$VITA3KIOS_EXECUTABLE"

VITA3KIOS_PLATFORM=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' \
    "$VITA3KIOS_APP/Info.plist" 2>/dev/null || true)
if [ "$VITA3KIOS_PLATFORM" != "iPhoneOS" ]; then
    echo "error: expected CFBundleSupportedPlatforms to contain iPhoneOS" >&2
    exit 1
fi

file "$VITA3KIOS_BINARY"
VITA3KIOS_ARCHS=$(lipo -archs "$VITA3KIOS_BINARY")
if [ "$VITA3KIOS_ARCHS" != "arm64" ]; then
    echo "error: expected a single arm64 slice, got: $VITA3KIOS_ARCHS" >&2
    exit 1
fi

VITA3KIOS_LINKS=$(otool -L "$VITA3KIOS_BINARY")
printf '%s\n' "$VITA3KIOS_LINKS"
if printf '%s\n' "$VITA3KIOS_LINKS" | rg -q '/opt/(homebrew|local)|Qt|MoltenVK\.framework|libMoltenVK\.dylib'; then
    echo "error: unexpected development-machine or dynamic third-party dependency" >&2
    exit 1
fi

if codesign --verify --strict "$VITA3KIOS_APP" >/dev/null 2>&1; then
    echo "codesign=valid"
    codesign -d --entitlements :- "$VITA3KIOS_APP" 2>/dev/null
else
    echo "codesign=unsigned-or-invalid"
    if [ "$VITA3KIOS_REQUIRE_SIGNED" = "YES" ]; then
        echo "error: a valid signature is required for this inspection gate" >&2
        exit 1
    fi
fi

echo "probe_architectures=$VITA3KIOS_ARCHS"
echo "probe_app=$VITA3KIOS_APP"
