# Phase 2A device probes

The device probes are deliberately separate from the future SwiftUI product.
They answer two feasibility questions before the native application grows:

1. Can pinned Dynarmic execute generated AArch64 code correctly on a physical
   iPhone under an explicitly recorded JIT-enablement path?
2. Can pinned MoltenVK create and present a Vulkan swapchain through a UIKit-owned
   `CAMetalLayer`, while exposing the features Vita3K will need?

Generated Xcode projects, downloaded binaries, prepared third-party sources,
signing data and run evidence live under ignored `Build/` paths.

## Current verified result

On 2026-08-22, both Release probes compiled successfully for the physical-device
`iphoneos` SDK as single-slice arm64 application bundles. Artifact inspection
found only Apple system frameworks/libraries and the statically linked probe
dependencies. The inspected bundles were unsigned, so this is compile and link
evidence only. It does not complete the physical-device M1 or M2 runtime gates.

## Source targets

- `Vita3KiOSJITProbe`: A32-only Dynarmic, callback memory and executable-memory
  preflight. It does not link Vita3K core, Qt or MoltenVK.
- `Vita3KiOSMoltenVKProbe`: UIKit, Vulkan and the official static MoltenVK iOS
  archive. It does not link Vita3K core, Qt, SDL or Dynarmic.

Both targets are generated from `Probes/Device/CMakeLists.txt`. Do not commit the
generated `.xcodeproj` and do not create the product Xcode project at this gate.

## Unsigned compile gate

```sh
Scripts/build-device-probes.sh jit
Scripts/build-device-probes.sh moltenvk
```

The MoltenVK script downloads the official v1.4.1 iOS release and refuses to
extract it unless SHA-256 is
`54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701`.
Only its static `ios-arm64` archive is linked.

## Local signing inputs

Team and bundle-prefix values must remain local:

```sh
VITA3KIOS_SIGNING=YES \
VITA3KIOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
VITA3KIOS_PROBE_BUNDLE_PREFIX=your.reverse.dns.probes \
Scripts/build-device-probes.sh jit
```

`get-task-allow` or a JIT entitlement is not hard-coded. The installed app's
actual signature and embedded provisioning profile must be inspected. A generic
unsigned build proves compilation only; it does not complete M1 or M2.

## Artifact inspection

```sh
Scripts/inspect-device-probe.sh /absolute/path/to/Probe.app
Scripts/inspect-device-probe.sh --require-signed /absolute/path/to/Probe.app
```

The inspector requires one arm64 slice and rejects Homebrew/MacPorts, Qt or a
dynamic MoltenVK dependency. For a signed artifact it also verifies and prints
the effective code-signing entitlements. Provisioning files, device identifiers,
pairing files and raw evidence must never be committed.
