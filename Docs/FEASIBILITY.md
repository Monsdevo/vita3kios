# Feasibility snapshot

Snapshot: official Vita3K commit
`496939b602703951277263c7b3e60a9ae36879c1`, audited 2026-08-22.

## Phase 2A compile evidence

The isolated Dynarmic and MoltenVK Release targets compile and link for the
physical-device iPhoneOS SDK as arm64-only application bundles. The Dynarmic
target contains fixed ARMv7 arithmetic, flags, branch, callback-memory, code
invalidation, cache-clear, and executable-memory tests. The MoltenVK target
creates a UIKit-owned `CAMetalLayer`, builds a Vulkan surface and swapchain,
presents a clear frame and a triangle using pinned Vita3K overlay SPIR-V, and
emits a capability report.

The verified MoltenVK input is the official v1.4.1 iOS archive with SHA-256
`54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701`.
Artifact inspection reports one arm64 slice and no Qt, host-machine, or dynamic
MoltenVK dependency. Development-signed bundles were built and their effective
`get-task-allow` entitlement was inspected locally without recording personal
signing data. No physical-device runtime pass is claimed, and M1/M2 remain open
until signed runs produce the required consecutive JIT and clear/triangle
presentation evidence.

## M3 scaffold evidence

The generated SwiftUI product target builds for macOS-host tests, iOS Simulator,
and arm64 iPhoneOS. A versioned C ABI owns opaque core handles, typed results,
version/capability queries, and exception containment. Its bootstrap self-test
directly compiles and exercises the pinned upstream Vita3K bitmap allocator.

The Simulator app launches, writes a passing `m3-core-report.json`, and displays
the returned ABI, upstream version, commit, platform, and allocator result. A
development-signed arm64 product bundle also passes signature and dependency
inspection and installs on the recorded iPhone. The device was locked when the
launch was attempted, so the physical-device report and M3 remain open.

## Direct Game Mode

Upstream's application path initializes an HLE kernel, mounts an installed
application as `app0`, loads its `eboot.bin`, preloads selected firmware/LLE
modules and creates the application's main thread. This is the reusable base for
vita3kios Direct Game Mode.

Relevant source:

- `External/Vita3K/vita3k/interface.cpp`, app load/run flow around lines 424–550.
- `External/Vita3K/vita3k/app/src/apps_list.cpp`, installed `ux0/app` scan.

## Firmware installation is not system-software boot

The PUP installer extracts available `os0`, `pd0`, `sa0` and `vs0` partition
payloads. Upstream then consumes firmware files/modules while running individual
applications. It does not execute a Vita secure cold-boot chain or start an
authentic persistent SceShell/LiveArea session.

Evidence at the pinned source:

- `vita3k/packages/src/pup.cpp`: partition extraction.
- `vita3k/app/src/apps_list.cpp`: scans `ux0/app`, not firmware system apps.
- `vita3k/gui-qt/src/live_area_widget.cpp`: host Qt rendering of a title's
  `template.xml`; this is not guest SceShell.
- `vita3k/modules/SceShellSvc/SceShellUtil.cpp`: shell utility exports are
  unimplemented.
- `vita3k/modules/SceShellSvc/SceShellUtilLaunchApp.cpp`: launch request is
  unimplemented.
- At this snapshot, 186 of 191 `SceAppMgr.cpp` exports and 114 of 128
  `SceAppMgrUser.cpp` exports are marked unimplemented.
- `sceKernelGetProcessId` returns a fixed process ID of 1.
- `vita3k/app/src/app_init.cpp` tears down kernel, memory and renderer after an
  application rather than keeping a shell process alive.

## System Software Mode acceptance definition

vita3kios calls the feature complete only when firmware-provided authentic
SceShell/LiveArea userland runs on the Vita3K emulated environment, is
interactive, can launch an installed title and can receive control again after
that title exits.

A SwiftUI recreation, artwork parser or native game library is not counted as
the Vita operating system. The outer app library remains native and separate.

The first target is authentic SceShell userland on Vita3K's HLE kernel. A
hardware-accurate bootloader and Sony-kernel cold boot is a distinct, much
larger architecture and is not silently implied by that milestone.

Firmware must be selected by the user from an official/legal source. No PUP,
partition image, module, font or Sony UI asset is stored in this repository or
distributed in the IPA.

## Other early gates

Before the main product UI grows, physical-device probes must prove:

1. Dynarmic A32→A64 generated code executes correctly with the chosen JIT path.
2. MoltenVK presents through an iOS CAMetalLayer with required capabilities.
3. The first SystemShell raw-load attempt produces a reproducible missing-service
   trace from user-supplied firmware.
