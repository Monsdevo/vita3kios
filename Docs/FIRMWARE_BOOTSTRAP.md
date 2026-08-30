# Firmware bootstrap status

## What this gate implements

The ABI v5 firmware bootstrap is a real, content-backed installation and
preflight path for Direct Game and System
Software Mode. It does not draw a native imitation of LiveArea and it never
ships Sony content.

The current app can:

- validate the structure and record ranges of a user-selected official PUP;
- install that PUP using Vita3K's PUP decryption, FAT extraction, and exFAT
  extraction implementation compiled for iPhoneOS arm64;
- copy a user-selected extracted VitaFS into an app-owned staging directory;
- reject symlinks, missing partition layouts, unreadable files, excessive entry
  counts, and invalid SceShell containers;
- atomically promote a Direct Game-ready import to an immutable firmware generation;
- inventory `os0`, `pd0`, `sa0`, and `vs0` without storing the provider path;
- locate the authentic firmware-provided `sce_shell.self` instead of using the
  desktop Qt LiveArea widget;
- verify `os0/kd/bootimage.skprx`, `os0/kd/sysmodule.skprx`, and the SceShell
  SELF/ELF container before a boot request;
- emit a typed last checkpoint and blocker through the C ABI and a redacted JSON
  report in the app Documents directory.

Firmware installation is now part of the linked core. Direct Game readiness
requires usable `os0` and `vs0` content; it does not require the stricter
`bootimage.skprx`, `sysmodule.skprx`, and SceShell combination. Those remain
System Software-only prerequisites. The `SYSTEM_SOFTWARE` capability remains
disabled until a firmware guest main thread and guest-rendered frame are proven.

## Supported inputs at this gate

`Install Official PUP` accepts a user-provided `.PUP`, performs a bounded
container preflight, extracts it into app-owned staging, inventories the result,
and atomically promotes a valid immutable generation.

`Import Extracted VitaFS` accepts a directory that directly contains `os0` and
`vs0`, or a directory with those partitions under a `vita` child. This remains
a developer fallback for already extracted, user-owned firmware content.

No firmware, module, key, decrypted image, or extracted artwork may be committed
to this repository.

## Device test

1. Build and sideload the signed app using the existing device build procedure.
2. Enable JIT using the already verified sideload workflow.
3. Open **Import Firmware** and choose **Install Official PUP**. Select the
   user's official firmware file.
4. Wait for the inventory summary. A Direct Game-ready generation reports its
   version, file count, and storage size. Shell readiness is reported separately.
5. Tap **Boot System Software** only when its separate shell status is ready.
6. Confirm that the checkpoint is `SceShell SELF container verified`; interactive
   SceShell execution remains a later System Software engineering gate.
7. Export `system-software-preflight-report.json` from the app Documents
   directory. Review it before sharing; it contains metadata only and no absolute
   provider path or firmware bytes.

This test proves the firmware transaction and boot-target boundary. It does not
prove that PS Vita System Software is running. That requires a separate shell
launch composition plus the missing process, IPC, service, and lifecycle work.
The measured source and dependency boundary is recorded in
[Audits/IOS_FULL_CORE_BOUNDARY.md](Audits/IOS_FULL_CORE_BOUNDARY.md).

## Automated coverage

`./Scripts/build-app.sh host` creates synthetic, non-Sony fixtures and verifies:

- lifecycle and invalid-state behavior;
- bounded PUP header and record parsing;
- deterministic partition inventory generation;
- SceShell and boot-module readiness;
- generation mismatch rejection;
- the exact current raw-boot checkpoint and typed blocker.

Simulator and unsigned iPhoneOS builds verify that the same ABI and SwiftUI flow
compile for Apple targets. Only a signed physical-device run with user-supplied
firmware can provide firmware-backed evidence.
