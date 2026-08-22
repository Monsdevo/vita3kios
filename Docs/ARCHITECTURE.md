# Architecture

## Product boundary

The native app and the emulation core are separate layers:

```text
SwiftUI app
  ├─ Library, imports, firmware, settings, diagnostics
  ├─ Session coordinator and performance HUD
  └─ C ABI
       └─ Objective-C++ / iOS host adapters
            └─ Vita3K core
                 ├─ Dynarmic A32 → A64
                 ├─ GXM → SPIR-V → Vulkan → MoltenVK
                 └─ HLE/LLE, kernel, packages, IO, audio and services
```

Swift must not receive C++ STL, Qt objects or C++ exceptions. All long-running
core operations expose typed errors, progress and explicitly documented callback
threads through a versioned C ABI.

## Boot modes

### Direct Game Mode

Boots an installed `ux0/app/<TITLE_ID>/eboot.bin` through the Vita3K emulated
environment without starting the Vita shell first. This matches upstream's
current primary execution model.

### System Software Mode

The acceptance target is an authentic firmware-provided SceShell/LiveArea
userland session, not a SwiftUI recreation. The user supplies the official PUP;
no Sony binary or resource is committed or bundled.

Current upstream installs/decrypts firmware partitions and uses selected modules
for games, but does not implement a persistent SceShell process, full process
manager or LiveArea-to-title-to-LiveArea lifecycle. System Software Mode is
therefore a gated core R&D track rather than a pre-existing frontend option.

Hardware-accurate cold boot through the secure bootloader/kernel is distinct
from running the authentic firmware shell on Vita3K's HLE kernel. The first
System Software milestone targets the latter. Any expansion to full cold boot
must receive its own roadmap decision and evidence.

## Settings model

Effective settings use deterministic precedence:

```text
built-in defaults < global < boot-mode profile < per-title override < session
```

Each setting has a stable key, schema version, type/range, default, capability
predicate, restart requirement and user-facing explanation. Invalid values fall
back safely and never prevent the library from opening.

## Performance HUD

The HUD is a native non-interactive overlay above the guest drawable. Compact is
the default and appears at the top-right in both boot modes. Core/render/audio
threads publish low-contention snapshots; SwiftUI samples them at a limited
rate. Disabling the HUD stops its sampling work.
