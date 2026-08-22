# M1–M3 physical-device testing

M1, M2, and M3 are evidence gates. A successful compile, Simulator launch, or
signature alone does not close them. Keep the iPhone unlocked, connected, paired,
trusted, and in Developer Mode throughout each device action.

## Local values

Choose values that belong to your Apple development account. Do not add them to
Git, screenshots, issues, or logs:

```sh
export VITA3KIOS_DEVICE='your device name or CoreDevice hostname'
export VITA3KIOS_DEVELOPMENT_TEAM='YOUR_TEAM_ID'
export VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER='your.reverse.dns.vita3kios'
export VITA3KIOS_PROBE_BUNDLE_PREFIX='your.reverse.dns.vita3kios.probes'
```

Build and inspect all three signed artifacts:

```sh
Scripts/run-device-gates.sh build
```

Evidence is copied under ignored `Build/DeviceEvidence/<UTC timestamp>/`
directories. Never commit raw device JSON, signing material, or personal device
identifiers.

## Free development-profile limit

A free Apple development profile may allow only a small number of installed
development apps. Each device action rotates only this project's JIT probe,
MoltenVK probe, and product bundles before installing the requested one. This
deletes that project's on-device test app and its local report; the collector
copies a passing report first. It does not remove unrelated applications.

## M1: Dynarmic JIT

Install and open the JIT probe:

```sh
Scripts/run-device-gates.sh m1
```

Enable JIT through the locally installed, trusted workflow recorded for this
device. Return to **vita3kios JIT Probe** and tap **Run Probe**. When the UI says
the report was saved, validate and collect it:

```sh
Scripts/run-device-gates.sh collect-m1
```

The command passes only when all 20 iterations pass, with zero failed and zero
skipped cases. If executable-memory cases are skipped, the JIT route is not yet
active and M1 remains open.

## M2: MoltenVK and CAMetalLayer

```sh
Scripts/run-device-gates.sh m2
```

The probe runs automatically after launch. The command passes only when the
report confirms both a clear presentation and a triangle presentation. Visually
confirm the small blue triangle appears in the probe surface before leaving it.

## M3: SwiftUI and Vita3KCore

```sh
Scripts/run-device-gates.sh m3
```

The command leaves the product app installed. It passes only when the physical
device loads the versioned C ABI, queries the iPhoneOS core information, and the
pinned Vita3K allocator self-test succeeds. Also verify:

- the Library screen uses standard Apple navigation, typography, materials,
  spacing, and accessibility behavior;
- PlayStation-inspired colors appear only as restrained accent details;
- Settings opens and Core Diagnostics shows the ABI, platform, upstream version,
  commit, and passing allocator result;
- Import remains disabled because Direct Game and firmware boot are later gates.

## Current functional boundary

These gates do not make games or firmware bootable. Direct Game Mode, firmware
installation, authentic SceShell/LiveArea boot, detailed settings behavior, and
the performance HUD remain later roadmap phases.
