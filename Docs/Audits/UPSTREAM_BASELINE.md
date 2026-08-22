# Upstream baseline — 2026-08-22

## Pinned source

- Repository: `https://github.com/Vita3K/Vita3K.git`
- Exact commit: `496939b602703951277263c7b3e60a9ae36879c1`
- Commit subject: `modules/SceVideodec: Align sceAvcdecQueryDecoderMemSize frameMemSize result`
- Commit date: `2026-08-08T18:19:45+02:00`
- Upstream continuous build number at the snapshot: 4074

The `continuous` tag is moving and is not used as the reproducibility pin. The
parent repository stores the exact Git submodule object ID.

## Toolchain

```text
developer_dir=/Applications/Xcode-beta.app/Contents/Developer
host_arch=arm64
macos_version=27.0
macos_build=26A5388g
xcode=Xcode 27.0 (27A5194q)
iphoneos_sdk=27.0
iphonesimulator_sdk=27.0
swift=Apple Swift 6.4 (swiftlang-6.4.0.20.104 clang-2100.3.20.102)
clang=Apple clang 21.0.0 (clang-2100.3.20.102)
cmake=4.4.0
ninja=1.13.2
git=2.48.0
homebrew=6.0.18
```

## Upstream requirements and build decisions

- CMake minimum: 3.22.
- Source requirement: C++23 with extensions disabled. `building.md` saying C++20
  is stale for this pin.
- macOS deployment target in upstream: 13.3.
- Qt minimum: 6.11; baseline uses Homebrew Qt 6.11.1.
- Configure preset: `macos-xcode`, explicitly constrained to arm64.
- Discord Rich Presence is disabled to avoid an irrelevant proprietary SDK and
  architecture-specific dylib in the baseline.
- Upstream downloads hash-pinned MoltenVK 1.4.1 for macOS. That artifact is not
  reusable for iOS; the future iOS target needs the iOS static/XCFramework slice.
- Upstream's FFmpeg prebuilt download lacks an `EXPECTED_HASH`. vita3kios pins
  the observed arm64 archive independently in `UPSTREAM_ARTIFACTS.sha256`.
- The build wrapper forces Vita3K's pinned Boost 1.89 distribution, rejects
  MacPorts path contamination and uses the selected Xcode SDK's Zlib.
- Two patches are applied only during the wrapper process: Xcode 27 legacy
  linker compatibility and direct `Boost::filesystem` imported-target linking.
  The exit trap restored the pinned upstream tree after the successful run.

## Test scope

The Vita3K-owned CTest targets at this pin are `mem-tests` and `module-tests`.
Third-party test suites are disabled by upstream configuration.

## Verified run — 2026-08-22

The recorded run used the source and toolchain above. The repository commit is
recorded in the follow-up evidence commit after the initial project commit; no
source file in the pinned Vita3K submodule remained modified.

```text
configure_generator=Xcode
configure_preset=macos-xcode
configure_arch=arm64
configure_sdk=MacOSX27.0.sdk
configure_time=881.7s
release_build=passed
staged_adhoc_codesign=passed
ctest=2/2 passed
ctest_time=3.79s
gui_smoke=passed
gui_marker=[apply_theme_entry]
gui_storage=isolated temporary portable directory
```

The generated project contains neither `/opt/local` nor the removed `-ld64`
option. Its Release final-link settings contain
`external/boost/lib/libboost_filesystem.a`.

`file` and `lipo` report the executable as a single arm64 Mach-O. `otool -L`
shows only macOS system libraries/frameworks plus Qt frameworks embedded under
`@executable_path/../Frameworks`; no MacPorts dynamic library is present.

The GUI smoke test copied and ad-hoc signed the app in `/private/tmp`, created a
sibling `portable` directory, observed both `portable/config.yml` and the theme
initialization marker, then force-terminated the upstream GUI after its ignored
SIGTERM and removed the entire stage. It did not touch the user's normal Vita3K
storage.

## Artifact verification

```text
MoltenVK-macos.tar sha256=5ea0c259df7ded9a275444820f09cced54d6e5a7c7a31d262de62a5cdb7e15cf
ffmpeg.zip          sha256=e4fbe69038663be71b9c4dd1432482925e30f1be212cde24b7a01019a8dfb8c3
```

Both entries passed `Scripts/verify-upstream-artifacts.sh`.

## Baseline deviations and warnings

- Xcode 27 no longer provides the classic linker selected by upstream `-ld64`.
  The transient compatibility patch removes that flag.
- Repeated modern Boost package discovery emptied the legacy
  `${Boost_LIBRARIES}` variable, leaving correct arm64 symbols unlinked. The
  transient patch uses `Boost::filesystem`; the build and both tests now link.
- The pinned upstream target remains macOS 13.3 while current Homebrew Qt and
  OpenSSL archives contain objects with newer deployment targets. Xcode emits
  deployment-version warnings, but the app links and launches on this macOS 27
  host. This macOS baseline is not a distributable compatibility promise.
- Upstream emits existing conversion, deprecation and switch warnings. They are
  baseline debt, not permission for warnings in new vita3kios port code.

## Remaining M0 evidence

- [x] macOS arm64 configure succeeds.
- [x] `vita3k` Release build succeeds.
- [x] `mem-tests` and `module-tests` build and pass.
- [x] Built executable is arm64 and its dynamic links are recorded.
- [x] Downloaded MoltenVK and FFmpeg artifacts are checksummed.
- [x] Isolated GUI initialization smoke passes.
- [ ] Repeat the documented flow from the first committed clean checkout.
