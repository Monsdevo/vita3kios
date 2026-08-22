#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

echo "developer_dir=$DEVELOPER_DIR"
echo "host_arch=$(uname -m)"
echo "macos_version=$(sw_vers -productVersion)"
echo "macos_build=$(sw_vers -buildVersion)"
echo "xcode=$(xcodebuild -version | tr '\n' ' ')"
echo "iphoneos_sdk=$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iphonesimulator_sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)"
echo "swift=$(xcrun swift --version | sed -n '1p')"
echo "clang=$(xcrun clang --version | sed -n '1p')"
echo "cmake=$(cmake --version | sed -n '1p')"
echo "ninja=$(ninja --version)"
echo "git=$(git --version)"
echo "brew=$(brew --version | sed -n '1p')"
