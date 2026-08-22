# Firmware bootstrap status

## What this gate implements

The ABI v2 firmware bootstrap is a real, content-backed preflight for System
Software Mode. It does not draw a native imitation of LiveArea and it never
ships Sony content.

The current app can:

- validate the structure and record ranges of a user-selected official PUP;
- copy a user-selected extracted VitaFS into an app-owned staging directory;
- reject symlinks, missing partition layouts, unreadable files, excessive entry
  counts, and invalid SceShell containers;
- atomically promote a shell-ready import to an immutable firmware generation;
- inventory `os0`, `pd0`, `sa0`, and `vs0` without storing the provider path;
- locate the authentic firmware-provided `sce_shell.self` instead of using the
  desktop Qt LiveArea widget;
- verify `os0/kd/bootimage.skprx`, `os0/kd/sysmodule.skprx`, and the SceShell
  SELF/ELF container before a boot request;
- emit a typed last checkpoint and blocker through the C ABI and a redacted JSON
  report in the app Documents directory.

The current last successful checkpoint is
`SceShell SELF container verified`. The next typed blocker is
`Full Vita3K runtime is not linked into the iOS core target`.

That distinction is deliberate: firmware readiness is implemented, but an
interactive guest SceShell is not yet running. The `SYSTEM_SOFTWARE` capability
remains disabled until a guest main thread and guest-rendered frame are proven.

## Supported inputs at this gate

`Validate Official PUP` accepts a user-provided `.PUP` and performs a bounded,
read-only container preflight. Vita3K's PUP decryption and FAT/exFAT extraction
graph still needs to be cross-compiled and linked for iOS, so PUP validation does
not install partitions yet.

`Import Extracted VitaFS` accepts a directory that directly contains `os0` and
`vs0`, or a directory with those partitions under a `vita` child. This is a
temporary developer path for reaching the raw shell experiment before the iOS
PUP extractor lands. A compatible desktop Vita3K installation can produce this
layout from the same user-supplied official firmware.

No firmware, module, key, decrypted image, or extracted artwork may be committed
to this repository.

## Device test

1. Build and sideload the signed app using the existing device build procedure.
2. Enable JIT using the already verified sideload workflow.
3. Open **Import Firmware** and choose **Validate Official PUP**. Select the
   user's official firmware file and confirm that the PUP record summary appears.
4. For this development gate, choose **Import Extracted VitaFS** and select a
   previously extracted VitaFS directory.
5. Wait for the inventory summary. A ready generation reports its version, file
   count, storage size, and relative SceShell path.
6. Tap **Boot System Software**.
7. Confirm that the checkpoint is `SceShell SELF container verified` and that the
   blocker is `Full Vita3K runtime is not linked into the iOS core target`.
8. Export `system-software-preflight-report.json` from the app Documents
   directory. Review it before sharing; it contains metadata only and no absolute
   provider path or firmware bytes.

This test proves the firmware transaction and boot-target boundary. It does not
prove that PS Vita System Software is running. That requires the next full-core
link, loader, HLE service, renderer, and guest-main-thread checkpoints.
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
