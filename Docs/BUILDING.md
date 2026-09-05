# Building

The project includes an Apple-native SwiftUI application and a versioned
Vita3KCore C ABI. Physical-device builds link the pinned Vita3K Direct Game
runtime, including the loader, HLE services, Dynarmic CPU, MoltenVK renderer,
audio stack, input bridge and official PUP installer. System Software boot is a
separate experimental track and is not implemented.

## Toolchain

The scripts default to:

```text
/Applications/Xcode-beta.app/Contents/Developer
```

They set `DEVELOPER_DIR` per process and do not require a global `xcode-select`
change. Override it only for a compatible full Xcode installation:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/toolchain-report.sh
```

## macOS baseline prerequisites

The recorded baseline is an Apple-silicon Mac with a full Xcode installation.
The wrapper expects Homebrew builds of CMake, Ninja, OpenSSL and Qt's split PDF
and virtual-keyboard packages:

```sh
brew install cmake ninja openssl qt qtwebengine qtvirtualkeyboard
```

The first build needs network access for the pinned recursive submodules and
the binary artifacts downloaded by upstream CMake. Upstream currently requires
CMake 3.22 or newer and C++23. The pinned source is authoritative when its
documentation and CMake configuration differ.

## Reproducible Phase 1 flow

Run these commands from the repository root:

```sh
Scripts/bootstrap.sh
Scripts/verify-upstream-pin.sh
Scripts/build-upstream-macos.sh
Scripts/verify-upstream-artifacts.sh
Scripts/test-upstream-macos.sh
Scripts/smoke-upstream-macos.sh
```

`bootstrap.sh` initializes all recursive submodules, checks the required tools
and Homebrew formulae, records the selected toolchain, and verifies the exact
Vita3K pin. The artifact verifier checks both upstream's MoltenVK archive and
the otherwise-unpinned FFmpeg archive against this repository's manifest.

The build wrapper deliberately isolates the configure process from MacPorts
include/library paths. It forces the pinned custom Boost distribution and
applies the patches in `Patches/Upstream` only while the command is running.
Its exit trap restores the upstream tree even after a failure or interrupt.
On Xcode 27 it removes the retired classic-linker flag; a second compatibility
patch links Boost.Filesystem through its imported CMake target.

Expected Release products are:

```text
External/Vita3K/build/macos-xcode/bin/Release/Vita3K.app
External/Vita3K/build/macos-xcode/bin/Release/Vita3K.app/Contents/MacOS/Vita3K
```

The build command signs and strictly verifies a metadata-free temporary copy;
it does not mutate the baseline app bundle. The smoke command stages another
temporary copy under `/private/tmp`, uses isolated portable storage, waits for
the upstream `[apply_theme_entry]` initialization marker, then terminates and
removes it. It never reads or writes the user's normal Vita3K data directory.

For clean-checkout evidence, clone the committed repository recursively into a
new directory and run the six-command flow unchanged. A successful run must
also leave this command with no output:

```sh
git -C External/Vita3K status --short --ignore-submodules=none
```

The checked toolchain, artifact hashes and baseline results live under
`Docs/Audits`. This phase produces the macOS reference build used to validate
the upstream pin.

## iOS application and Direct Game runtime

The checked-in source of truth is `App/CMakeLists.txt`; generated Xcode projects
stay under ignored build directories. Build and test the C ABI on the host:

```sh
Scripts/build-app.sh host
```

Simulator builds use the ABI stub because the current full runtime is arm64
iPhoneOS-only. Device builds compile and aggregate the iOS dependencies and the
full Direct Game runtime automatically:

```sh
Scripts/build-app.sh simulator
Scripts/build-app.sh device
```

The first full device build can take a long time. Its reusable products are
kept in `Build/Dependencies`, `Build/Vita3K-iOS` and `Build/Core`. The upstream
patch is applied only to a materialized source tree under `/tmp`; the pinned
`External/Vita3K` submodule remains unchanged.

For the current device JIT workflow, use `Scripts/launch-game-with-jit.sh` after
installing the signed app and importing a title. This keeps an LLDB page helper
connected while the game runs; a normal launch or plain debugger attach does
not prepare the code pages. See [Direct Game testing](DIRECT_GAME_BOOTSTRAP.md).

Each core build records both the upstream revision and the iOS patch hash.
Changing either invalidates the core object cache, even when another checkout
has already refreshed the shared temporary source tree. This prevents archived
source timestamps from hiding patch changes from Ninja. Dependency builds are
retained.

Keep the working checkout and its build products in a fully local directory,
outside cloud-synchronized Desktop or Documents folders. Cloud eviction can
turn Git metadata and archives into download placeholders and stall builds.

Local signing values must be supplied through environment variables and must
never be committed:

```sh
VITA3KIOS_SIGNING=YES \
VITA3KIOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER=your.reverse.dns.vita3kios \
Scripts/build-app.sh device
```

Signed products are generated under the system temporary directory by default.
Direct Game testing requires an official user-supplied PlayStation Vita firmware
PUP, a legally dumped extracted game directory, and JIT enabled for the signed
application process. Use `Docs/DEVICE_TESTING.md` for physical-device milestone
validation.
