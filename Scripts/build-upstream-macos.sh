#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_REPO_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
VITA3KIOS_UPSTREAM_DIR="$VITA3KIOS_REPO_ROOT/External/Vita3K"
VITA3KIOS_XCODE27_PATCH="$VITA3KIOS_REPO_ROOT/Patches/Upstream/0001-xcode-27-remove-legacy-ld64.patch"
VITA3KIOS_BOOST_TARGET_PATCH="$VITA3KIOS_REPO_ROOT/Patches/Upstream/0002-cmake-link-imported-boost-filesystem.patch"
VITA3KIOS_BOOST_DIR="$VITA3KIOS_UPSTREAM_DIR/external/boost"
VITA3KIOS_BOOST_BOOTSTRAP="tools/build/src/engine/build.sh"
VITA3KIOS_BUILD_DIR="$VITA3KIOS_UPSTREAM_DIR/build/macos-xcode"
VITA3KIOS_CMAKE_CACHE="$VITA3KIOS_BUILD_DIR/CMakeCache.txt"
VITA3KIOS_XCODE_PROJECT="$VITA3KIOS_BUILD_DIR/Vita3K.xcodeproj/project.pbxproj"
VITA3KIOS_APP_BUNDLE="$VITA3KIOS_BUILD_DIR/bin/Release/Vita3K.app"
VITA3KIOS_XCODE27_PATCH_APPLIED=0
VITA3KIOS_BOOST_TARGET_PATCH_APPLIED=0
VITA3KIOS_BOOST_CLEANUP=0
VITA3KIOS_SIGN_STAGE=
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH \
    LIBRARY_PATH LDFLAGS CPPFLAGS \
    CMAKE_PREFIX_PATH CMAKE_LIBRARY_PATH CMAKE_INCLUDE_PATH \
    CMAKE_FRAMEWORK_PATH CMAKE_APPBUNDLE_PATH CMAKE_PROGRAM_PATH \
    PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR \
    OPENSSL_ROOT_DIR CURL_ROOT ZLIB_ROOT BOOST_ROOT BOOST_INCLUDEDIR \
    BOOST_LIBRARYDIR SDKROOT MACOSX_DEPLOYMENT_TARGET \
    DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
    DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH

VITA3KIOS_MACOS_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
if [ ! -d "$VITA3KIOS_MACOS_SDKROOT" ]; then
    echo "error: selected macOS SDK is missing: $VITA3KIOS_MACOS_SDKROOT" >&2
    exit 1
fi

SDKROOT="$VITA3KIOS_MACOS_SDKROOT"
PKG_CONFIG_PATH=
PKG_CONFIG_LIBDIR="$VITA3KIOS_MACOS_SDKROOT/usr/lib/pkgconfig"
export SDKROOT PKG_CONFIG_PATH PKG_CONFIG_LIBDIR

if [ ! -f "$VITA3KIOS_UPSTREAM_DIR/CMakeLists.txt" ]; then
    echo "error: Vita3K submodule is missing; run Scripts/bootstrap.sh" >&2
    exit 1
fi

if [ ! -f "$VITA3KIOS_XCODE27_PATCH" ]; then
    echo "error: Xcode 27 compatibility patch is missing" >&2
    exit 1
fi
if [ ! -f "$VITA3KIOS_BOOST_TARGET_PATCH" ]; then
    echo "error: Boost target compatibility patch is missing" >&2
    exit 1
fi

VITA3KIOS_XCODE_VERSION=$(xcodebuild -version | sed -n '1s/^Xcode //p')
VITA3KIOS_XCODE_MAJOR=${VITA3KIOS_XCODE_VERSION%%.*}
case "$VITA3KIOS_XCODE_MAJOR" in
    ''|*[!0-9]*)
        echo "error: unable to parse Xcode version: $VITA3KIOS_XCODE_VERSION" >&2
        exit 1
        ;;
esac

VITA3KIOS_BOOST_INDEX_ENTRY=$(git -C "$VITA3KIOS_BOOST_DIR" ls-files -s -- "$VITA3KIOS_BOOST_BOOTSTRAP")
VITA3KIOS_BOOST_EXPECTED_MODE=${VITA3KIOS_BOOST_INDEX_ENTRY%% *}
VITA3KIOS_BOOST_INDEX_REMAINDER=${VITA3KIOS_BOOST_INDEX_ENTRY#* }
VITA3KIOS_BOOST_EXPECTED_BLOB=${VITA3KIOS_BOOST_INDEX_REMAINDER%% *}

if [ -z "$VITA3KIOS_BOOST_EXPECTED_BLOB" ]; then
    echo "error: unable to resolve pinned Boost bootstrap file" >&2
    exit 1
fi

VITA3KIOS_CLEANUP_STATUS=0
vita3kios_cleanup() {
    VITA3KIOS_BUILD_STATUS=$?
    trap - EXIT HUP INT TERM

    if [ "$VITA3KIOS_BOOST_TARGET_PATCH_APPLIED" -eq 1 ]; then
        if ! git -C "$VITA3KIOS_UPSTREAM_DIR" apply --reverse "$VITA3KIOS_BOOST_TARGET_PATCH"; then
            echo "error: failed to reverse the transient Boost target patch" >&2
            VITA3KIOS_CLEANUP_STATUS=1
        fi
    fi

    if [ "$VITA3KIOS_XCODE27_PATCH_APPLIED" -eq 1 ]; then
        if ! git -C "$VITA3KIOS_UPSTREAM_DIR" apply --reverse "$VITA3KIOS_XCODE27_PATCH"; then
            echo "error: failed to reverse the transient Xcode 27 patch" >&2
            VITA3KIOS_CLEANUP_STATUS=1
        fi
    fi

    if [ "$VITA3KIOS_BOOST_CLEANUP" -eq 1 ]; then
        VITA3KIOS_BOOST_ACTUAL_BLOB=$(git -C "$VITA3KIOS_BOOST_DIR" hash-object "$VITA3KIOS_BOOST_BOOTSTRAP")
        if [ "$VITA3KIOS_BOOST_ACTUAL_BLOB" != "$VITA3KIOS_BOOST_EXPECTED_BLOB" ]; then
            echo "error: Boost bootstrap content changed during build; leaving its mode untouched" >&2
            VITA3KIOS_CLEANUP_STATUS=1
        else
            case "$VITA3KIOS_BOOST_EXPECTED_MODE" in
                100644) chmod 0644 "$VITA3KIOS_BOOST_DIR/$VITA3KIOS_BOOST_BOOTSTRAP" ;;
                100755) chmod 0755 "$VITA3KIOS_BOOST_DIR/$VITA3KIOS_BOOST_BOOTSTRAP" ;;
                *)
                    echo "error: unsupported Boost bootstrap mode: $VITA3KIOS_BOOST_EXPECTED_MODE" >&2
                    VITA3KIOS_CLEANUP_STATUS=1
                    ;;
            esac
        fi
    fi

    if [ -n "$VITA3KIOS_SIGN_STAGE" ]; then
        case "$VITA3KIOS_SIGN_STAGE" in
            /private/tmp/vita3kios-codesign.*)
                /bin/rm -rf -- "$VITA3KIOS_SIGN_STAGE"
                ;;
            *)
                echo "error: refusing to remove unexpected signing stage: $VITA3KIOS_SIGN_STAGE" >&2
                VITA3KIOS_CLEANUP_STATUS=1
                ;;
        esac
    fi

    if [ "$VITA3KIOS_BUILD_STATUS" -eq 0 ] && [ "$VITA3KIOS_CLEANUP_STATUS" -ne 0 ]; then
        VITA3KIOS_BUILD_STATUS=$VITA3KIOS_CLEANUP_STATUS
    fi
    exit "$VITA3KIOS_BUILD_STATUS"
}

trap vita3kios_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! git -C "$VITA3KIOS_BOOST_DIR" diff --quiet -- "$VITA3KIOS_BOOST_BOOTSTRAP"; then
    echo "error: Boost bootstrap file is already modified; refusing to overwrite it" >&2
    exit 1
fi
VITA3KIOS_BOOST_CLEANUP=1

if [ "$VITA3KIOS_XCODE_MAJOR" -ge 27 ]; then
    if ! git -C "$VITA3KIOS_UPSTREAM_DIR" apply --check "$VITA3KIOS_XCODE27_PATCH"; then
        echo "error: Xcode 27 compatibility patch does not apply cleanly to the pinned upstream" >&2
        exit 1
    fi
    git -C "$VITA3KIOS_UPSTREAM_DIR" apply "$VITA3KIOS_XCODE27_PATCH"
    VITA3KIOS_XCODE27_PATCH_APPLIED=1
fi

if ! git -C "$VITA3KIOS_UPSTREAM_DIR" apply --check "$VITA3KIOS_BOOST_TARGET_PATCH"; then
    echo "error: Boost target compatibility patch does not apply cleanly to the pinned upstream" >&2
    exit 1
fi
git -C "$VITA3KIOS_UPSTREAM_DIR" apply "$VITA3KIOS_BOOST_TARGET_PATCH"
VITA3KIOS_BOOST_TARGET_PATCH_APPLIED=1

VITA3KIOS_QT6_ROOT=$(brew --prefix qt)
VITA3KIOS_QTWEBENGINE_ROOT=$(brew --prefix qtwebengine)
VITA3KIOS_QTVIRTUALKEYBOARD_ROOT=$(brew --prefix qtvirtualkeyboard)
Qt6_ROOT="$VITA3KIOS_QT6_ROOT"
export Qt6_ROOT

if [ ! -d "$VITA3KIOS_QTWEBENGINE_ROOT/lib/QtPdf.framework" ]; then
    echo "error: Homebrew QtPdf framework is missing; reinstall the qt formula" >&2
    exit 1
fi
if [ ! -d "$VITA3KIOS_QTVIRTUALKEYBOARD_ROOT/lib/QtVirtualKeyboard.framework" ]; then
    echo "error: Homebrew QtVirtualKeyboard framework is missing; reinstall the qt formula" >&2
    exit 1
fi

VITA3KIOS_MACDEPLOYQT_EXTRA_ARGS="-no-codesign;-libpath=$VITA3KIOS_QTWEBENGINE_ROOT/lib;-libpath=$VITA3KIOS_QTVIRTUALKEYBOARD_ROOT/lib"

VITA3KIOS_FRESH_CONFIGURE=0
if [ -f "$VITA3KIOS_CMAKE_CACHE" ] && awk '
    /\/opt\/local/ && $0 !~ /^CMAKE_IGNORE_PREFIX_PATH:/ { found = 1 }
    END { exit(found ? 0 : 1) }
' "$VITA3KIOS_CMAKE_CACHE"; then
    VITA3KIOS_FRESH_CONFIGURE=1
    echo "info: MacPorts paths found in the CMake cache; configuring fresh once"
elif [ -f "$VITA3KIOS_CMAKE_CACHE" ] && \
    { ! grep -Fq 'CMAKE_GENERATOR:INTERNAL=Xcode' "$VITA3KIOS_CMAKE_CACHE" || \
      [ ! -f "$VITA3KIOS_XCODE_PROJECT" ]; }; then
    VITA3KIOS_FRESH_CONFIGURE=1
    echo "info: incomplete or non-Xcode CMake generation found; configuring fresh once"
fi

vita3kios_configure() {
    cmake "$@" --preset macos-xcode -S "$VITA3KIOS_UPSTREAM_DIR" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_SYSROOT="$VITA3KIOS_MACOS_SDKROOT" \
        -DCMAKE_IGNORE_PREFIX_PATH=/opt/local \
        -DCMAKE_SUPPRESS_REGENERATION=ON \
        -DBoost_USE_DEBUG_RUNTIME=OFF \
        -DVITA3K_FORCE_CUSTOM_BOOST=ON \
        -DUSE_DISCORD_RICH_PRESENCE=OFF \
        "-DVITA3KIOS_MACDEPLOYQT_EXTRA_ARGS=$VITA3KIOS_MACDEPLOYQT_EXTRA_ARGS"
}

if [ "$VITA3KIOS_FRESH_CONFIGURE" -eq 1 ]; then
    vita3kios_configure --fresh
else
    vita3kios_configure
fi

if [ ! -f "$VITA3KIOS_XCODE_PROJECT" ]; then
    echo "error: generated Vita3K Xcode project is missing" >&2
    exit 1
fi
if grep -Fq '/opt/local' "$VITA3KIOS_XCODE_PROJECT"; then
    echo "error: generated Vita3K Xcode project contains MacPorts paths" >&2
    exit 1
fi
if grep -Fq -- '-ld64' "$VITA3KIOS_XCODE_PROJECT"; then
    echo "error: generated Vita3K Xcode project contains the legacy -ld64 flag" >&2
    exit 1
fi
if ! grep -Fq 'libboost_filesystem.a' "$VITA3KIOS_XCODE_PROJECT"; then
    echo "error: generated Vita3K Xcode project does not link Boost.Filesystem" >&2
    exit 1
fi

if [ "$VITA3KIOS_FRESH_CONFIGURE" -eq 1 ]; then
    echo "info: cleaning Release products after the fresh configure"
    cmake --build "$VITA3KIOS_BUILD_DIR" \
        --config Release --target clean -- -quiet
fi

cmake --build "$VITA3KIOS_BUILD_DIR" \
    --config Release --target vita3k --parallel -- \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet

if [ ! -d "$VITA3KIOS_APP_BUNDLE" ]; then
    echo "error: expected Vita3K app bundle was not produced" >&2
    exit 1
fi
VITA3KIOS_APP_EXECUTABLE="$VITA3KIOS_APP_BUNDLE/Contents/MacOS/Vita3K"
if [ ! -x "$VITA3KIOS_APP_EXECUTABLE" ]; then
    echo "error: expected Vita3K executable was not produced" >&2
    exit 1
fi

VITA3KIOS_SIGN_STAGE=$(mktemp -d /private/tmp/vita3kios-codesign.XXXXXX)
VITA3KIOS_STAGED_APP="$VITA3KIOS_SIGN_STAGE/Vita3K.app"
VITA3KIOS_STAGED_EXECUTABLE="$VITA3KIOS_STAGED_APP/Contents/MacOS/Vita3K"
ditto --norsrc --noextattr --noqtn --noacl "$VITA3KIOS_APP_BUNDLE" "$VITA3KIOS_STAGED_APP"
xattr -cr "$VITA3KIOS_STAGED_APP"
codesign --force --deep --sign - "$VITA3KIOS_STAGED_APP"
codesign --verify --deep --strict "$VITA3KIOS_STAGED_APP"

if [ ! -x "$VITA3KIOS_STAGED_EXECUTABLE" ]; then
    echo "error: staged Vita3K executable is missing" >&2
    exit 1
fi

echo "ok: staged ad-hoc codesign verification succeeded"
echo "staged app (temporary): $VITA3KIOS_STAGED_APP"
echo "staged executable (temporary): $VITA3KIOS_STAGED_EXECUTABLE"
echo "app bundle: $VITA3KIOS_APP_BUNDLE"
echo "executable: $VITA3KIOS_APP_EXECUTABLE"
