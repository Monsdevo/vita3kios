# System Software Boot

- Status: design and investigation specification
- Roadmap owners: Phase 2C and Phase 8A
- Upstream baseline: Vita3K
  `496939b602703951277263c7b3e60a9ae36879c1`, audited 2026-08-22

This document defines what vita3kios means by **System Software Mode**, how it
differs from Direct Game Mode, and how the project will turn the current
upstream gap into reproducible engineering work. It does not claim that the
pinned upstream can already boot the Vita operating-system shell.

`ROADMAP.txt` remains the project authority. This document elaborates its Phase
2C, Phase 6 and Phase 8A work without changing their order or exit gates.

## 1. Target definition

### 1.1 Direct Game Mode

Direct Game Mode starts one installed title without first starting the Vita
system shell:

```text
native library -> InstalledGame target -> ux0/app/<TITLE_ID>/eboot.bin
               -> title main thread -> title exit -> native library
```

This is the pinned upstream's primary execution model. Upstream initializes its
HLE kernel, maps the selected application as `app0`, loads `eboot.bin`, loads
selected firmware/LLE modules, and starts the title's main thread.

Direct Game Mode is independently useful and must remain working while System
Software Mode is developed. System-shell work must not make a shell process a
prerequisite for direct title boot.

### 1.2 System Software Mode

The first System Software Mode target is:

> Authentic firmware-provided SceShell/LiveArea userland running on Vita3K's
> HLE kernel, with guest-rendered interactive UI, the ability to launch an
> installed title, and a controlled return to the shell after that title exits.

The outer library, importer, settings screens, readiness UI and diagnostics
remain native SwiftUI. They are not part of the emulated Vita system software.

The following do **not** satisfy the target:

- successfully extracting a PUP;
- loading a few firmware modules for a game;
- a black frame or a shell executable that immediately exits;
- the upstream Qt `LiveAreaWidget`, which parses a title's LiveArea artwork on
  the host;
- a SwiftUI recreation of Vita bubbles, lock screen or Settings;
- copying Sony UI artwork into native app assets;
- showing a first frame without working input or shell lifecycle;
- launching a title by secretly falling back to Direct Game Mode.

The first complete flow is:

```text
native library
    -> SystemShell target
    -> authentic guest SceShell/LiveArea becomes interactive
    -> guest shell requests launch of an installed title
    -> title runs as a managed guest process
    -> title exits
    -> guest shell regains control and becomes interactive again
```

The native performance HUD remains a separate, non-interactive overlay above
the guest drawable in both modes. It must not be rendered into or mistaken for
the guest shell.

### 1.3 What “system software” does not silently imply

Authentic SceShell userland on the HLE kernel is distinct from a
hardware-accurate cold boot through Boot ROM, secure bootloader and Sony kernel.
The latter would require a separate architecture decision, threat/legal review,
and roadmap amendment backed by measurements. It is not an undocumented
fallback or hidden requirement of the first MSYS milestone.

System applications beyond the shell, including Settings and Content Manager,
are tracked in a capability matrix. Settings is the first system-app proof.
Network-backed or discontinued Sony services, PlayStation Network, Store,
account provisioning, system update and every bundled system application are
not implied by the first MSYS milestone.

## 2. Evidence at the pinned upstream

Firmware installation and system-software boot are different operations in the
pinned source.

| Evidence | Pinned source | Consequence |
| --- | --- | --- |
| PUP handling joins and extracts available `os0`, `pd0`, `sa0` and `vs0` images. | `External/Vita3K/vita3k/packages/src/pup.cpp`, `decrypt_pup_packages()` and `install_pup()` | Firmware content can be installed, but extraction alone says nothing about a shell boot path. |
| The installed-app cache scans `ux0/app`. | `External/Vita3K/vita3k/app/src/apps_list.cpp`, `collect_app_cache_sources()` and `scan_apps()` | Firmware system applications are not normal launch entries. |
| App-file reads and `app0` setup are tied to the selected installed-app model. | `External/Vita3K/vita3k/io/src/io.cpp`, `vfs::read_app_file()` and `init_device_paths()` | A system partition needs an explicit, validated mount source instead of pretending to be an `ux0` title. |
| `load_app_impl()` initializes the HLE kernel, loads `app0:<self>`, and preloads selected `os0`/`vs0` modules. | `External/Vita3K/vita3k/interface.cpp` | This is app-centric execution, not a console cold boot. |
| `run_app()` creates one title main thread and starts loaded libraries. | `External/Vita3K/vita3k/interface.cpp` | It is a reusable loader base, not a shell/process manager. |
| The public request describes `app_path`, `self_path`, arguments and reason, but no boot-target kind or source mount. | `External/Vita3K/vita3k/emuenv/include/emuenv/app_launch_request.h` | The request model must be generalized without breaking the old direct-game mapping. |
| The Qt LiveArea widget reads `sce_sys/livearea/contents/template.xml` and paints with Qt. | `External/Vita3K/vita3k/gui-qt/src/live_area_widget.cpp`, `LiveAreaWidget::load_contents()` and `paint_live_area()` | It is a host title-artwork view, not guest SceShell. |
| Shell utility and shell launch exports are unimplemented. | `External/Vita3K/vita3k/modules/SceShellSvc/SceShellUtil.cpp` and `SceShellUtilLaunchApp.cpp` | Shell event and title-launch semantics need real implementations. |
| Most app-manager exports are placeholders at this pin. | `External/Vita3K/vita3k/modules/SceAppMgr/SceAppMgr.cpp` and `SceDriverUser/SceAppMgrUser.cpp` | Missing APIs must be discovered and prioritized from traces, not bulk-no-op stubbed. |
| An unresolved import is logged but its guest return register is currently set to zero. | `External/Vita3K/vita3k/modules/module_parent.cpp`, `call_import()` | Checkpoint progress can be false progress unless unresolved calls remain visible and gain tested semantics. |
| `sceKernelGetProcessId()` returns a fixed PID of 1. | `External/Vita3K/vita3k/modules/SceKernelThreadMgr/SceThreadmgr.cpp` | A persistent shell plus foreground title requires a real process identity model. |
| App shutdown tears down guest threads, kernel state, memory and renderer. | `External/Vita3K/vita3k/app/src/app_init.cpp`, `shutdown_app_runtime()` | The current lifecycle cannot preserve a shell while switching to and from a title. |

The `SceAppMgr` counts recorded in `Docs/FEASIBILITY.md` are a mechanical
snapshot, not a permanent coverage metric. Progress is measured by semantic
behavior and acceptance tests, never by reducing a raw stub count alone.

## 3. Firmware ownership, safety and legal boundary

### 3.1 Non-negotiable content rules

- The user selects firmware obtained from an official/legal source.
- No PUP, partition image, decrypted SELF/SUPRX, font, registry, database,
  screenshot, video, sound or Sony UI asset is committed to this repository.
- None of those artifacts is bundled in an app, framework, test fixture, CI
  cache, release archive or diagnostic attachment.
- The initial implementation does not download a PUP on the user's behalf,
  including from the official URL; it imports a local file explicitly selected
  by the user.
- The app does not provide a firmware mirror, firmware catalog, copyrighted
  asset pack or automatic fallback download from an unofficial source.
- A link to Sony's public system-software page may be shown as guidance, subject
  to distribution and legal review. The app must not imply Sony endorsement.
- Users must not be asked to submit license keys, zRIF values, account data or
  decrypted firmware modules in bug reports.
- This document is an engineering boundary, not legal advice. Public
  distribution still requires the roadmap's license and distribution review.

Sony's public PS Vita system-software page is:

`https://www.playstation.com/en-gb/support/hardware/psvita/system-software/`

### 3.2 Safe firmware ingestion

Firmware import follows the Phase 6 transaction model:

```text
security-scoped file URL
    -> bounded copy to private staging
    -> PUP structural validation
    -> capacity/quota check
    -> extraction into a new firmware generation
    -> partition and readiness validation
    -> atomic activation
    -> removal of transient source and extraction files
```

The importer must validate at least:

- PUP magic, declared record count, offsets and lengths;
- integer overflow and out-of-file ranges before allocation or seek;
- supported package/partition types and a configured expansion limit;
- available disk space before and during extraction;
- cancellation at bounded checkpoints;
- output paths, symlinks and any attempt to escape the staging root;
- required partition readability and inventory consistency;
- the firmware generation identifier used by every later boot request.

The current active firmware is never modified in place. A failed install,
update, cancellation or crash leaves the previous generation selectable.
System partitions are treated as an immutable base where practical; registry,
user and runtime writes go to a generation-aware writable overlay. Firmware
update must not replace `ux0` games, saves or unrelated user data.

Imported firmware is rebuildable user content and should be excluded from cloud
backup unless a later product decision says otherwise. At-rest file-protection
policy must be documented for iOS. The provider's external absolute path is not
persisted after the staged copy completes.

### 3.3 Safe diagnostics

Shared diagnostics contain text metadata only. They must exclude:

- PUP bytes, partition images, guest module bytes and ELF dumps;
- guest frame captures and extracted Sony artwork;
- absolute host paths, provider names and user account names;
- license material, content keys, zRIF values and certificate data;
- arbitrary IPC payloads, registry values or guest memory dumps.

Local development may retain a user-approved firmware installation outside the
repository. Generated diagnostic directories live under ignored `Build/` or a
temporary directory. Before packaging a trace, an allowlist-based exporter
creates a new redacted text-only bundle; it never archives the raw log directory.

## 4. Boot-target model

The current `AppLaunchRequest` overloads “application path” with an installed
`ux0` title. System boot needs a typed target and a separate internal resolution
step.

Conceptual C++ model:

```cpp
enum class BootTargetKind : uint8_t {
    InstalledGame,
    SystemShell,
    SystemApp,
};

struct InstalledGameTarget {
    std::string title_id;
};

struct SystemShellTarget {
    std::string firmware_generation_id;
    std::string user_profile_id;
};

struct SystemAppTarget {
    std::string firmware_generation_id;
    std::string system_title_id;
    std::string user_profile_id;
};

using BootTarget = std::variant<
    InstalledGameTarget,
    SystemShellTarget,
    SystemAppTarget>;
```

This is an internal design sketch, not the C ABI. The public bridge uses tagged
C structs or dedicated functions and never exposes `std::variant` or C++
ownership to Swift.

The host-facing target contains stable identifiers, not arbitrary filesystem
paths. A trusted resolver produces an internal descriptor:

```text
ResolvedBootTarget
  kind
  firmware generation, if required
  content source device/partition
  validated content root relative to VitaFS
  guest executable path relative to that root
  title/system identity and metadata
  user profile
  boot arguments
  HLE/LLE module policy
  writable-overlay policy
```

### 4.1 Resolution rules

| Target | Content source | `app0` policy | Session owner |
| --- | --- | --- | --- |
| `InstalledGame` | Active VitaFS `ux0/app/<TITLE_ID>` | Existing direct-game mount semantics | Direct Game session, or a title process launched by the system session |
| `SystemShell` | Shell descriptor from the selected firmware inventory | Mount the inventory-resolved system content root directly; never copy it into `ux0` | System Software session |
| `SystemApp` | System-app descriptor from the same firmware generation | Mount the inventory-resolved system-app root | System Software session/process manager |

The exact shell executable path, system title identifiers and companion modules
must be learned from the user-supplied firmware inventory and recorded as local
metadata. This document deliberately does not guess or hard-code a proprietary
layout that has not yet been verified at the pinned baseline.

Every resolution must reject:

- a title or system-app identifier absent from the active inventory;
- a path outside the active VitaFS and firmware generation;
- `..`, absolute host paths, symlink escapes and cross-generation references;
- a shell/app descriptor whose expected files changed after inventory;
- mixing the base partitions of one firmware generation with module policy or
  registry state from another generation.

### 4.2 Compatibility with Direct Game Mode

The legacy request maps deterministically to `InstalledGame`. Existing direct
game call sites keep their behavior while they migrate to the typed model. A
target resolver is added before loader state is mutated, so a bad System target
cannot partially overwrite a working Direct Game session.

The planned bridge remains explicit:

```text
boot_title(title_id)
boot_system_software(firmware_generation_id, user_profile_id)
boot_system_app(firmware_generation_id, system_title_id, user_profile_id)
```

Capability queries report whether these entry points are compiled, whether the
selected firmware is ready, and the highest verified milestone. “API exists”
must not be presented as “System Software Mode works.”

## 5. First raw-load experiment

The first experiment runs on the macOS host harness after the Phase 2B core
boundary exists. “Headless” means no Qt or SwiftUI frontend; an offscreen or
minimal frame host may still be initialized when guest graphics requires it.
The experiment is repeated on iOS only after the relevant device gates pass.

### 5.1 Preconditions

1. Parent and upstream commits are recorded, with the upstream submodule still
   at the audited pin.
2. The user supplies an official firmware file through a path outside the
   repository.
3. A new temporary VitaFS and diagnostic directory are created for the run.
4. Binary/module dumping and frame capture are disabled.
5. Logs use the redaction and allowlist rules in this document.
6. The harness has deterministic watchdogs and can tear down guest threads after
   failure without leaving the firmware generation partially active.

### 5.2 Experiment stages

1. **Validate input.** Parse only the PUP structure needed to prove bounds and
   supported records before extraction.
2. **Install transactionally.** Extract into an inactive generation, validate
   it, activate it, and remove transient PUP/extraction files.
3. **Build inventory.** Record firmware version, present partitions, component
   classes, local integrity hashes, sizes and missing readiness requirements.
4. **Resolve candidates.** Locate system-shell metadata and executable
   candidates from that inventory. Record why one descriptor was selected; do
   not expose raw module contents.
5. **Resolve target.** Convert `SystemShell` into a `ResolvedBootTarget`; validate
   all guest-relative paths and firmware-generation ownership.
6. **Mount only.** Establish partition and `app0` mappings, then verify expected
   guest-path reads without loading executable code.
7. **Load only.** Initialize memory/HLE kernel and parse/load the shell main
   executable without starting its main thread. Record loader/decryption/import
   outcome.
8. **Preload.** Apply an explicit HLE/LLE module policy and load required
   preloads. Every fallback and unresolved module is traced.
9. **Start.** Create the shell process identity and main thread, then run under a
   bounded watchdog.
10. **Advance checkpoints.** Continue through first graphics initialization,
    first guest-produced frame and input loop only as real implementations make
    those checkpoints reachable.
11. **Stop cleanly.** Stop guest processes and services, close the frame host,
    and verify that a second clean run produces the same first blocker.
12. **Export evidence.** Produce redacted JSONL and summary JSON only, then scan
    the export for forbidden paths, secrets and binary files.

No missing call may be changed to an unconditional success merely to advance a
checkpoint. A semantically harmless no-op requires a comment, a focused test,
and trace visibility. Unknown imports silently returning zero are not accepted
as proof of working system software.

### 5.3 Checkpoint ladder

Checkpoints are monotonic within an attempt:

```text
SB00 harness_started
SB01 pup_validated
SB02 firmware_inventory_complete
SB03 shell_target_resolved
SB04 guest_mounts_ready
SB05 hle_kernel_initialized
SB06 shell_main_loaded
SB07 preloads_complete
SB08 shell_process_created
SB09 shell_main_thread_started
SB10 first_gxm_initialization
SB11 first_guest_frame
SB12 shell_input_loop
SB13 shell_interactive
SB14 title_launch_requested
SB15 title_foreground
SB16 title_exited
SB17 shell_resumed
```

Later implementation may insert a checkpoint, but it must not rename an
existing meaning without a trace schema version bump.

### 5.4 Phase 2C raw-load exit gate

The experiment passes the Phase 2C evidence gate when:

- two clean attempts at the same commits and local firmware inventory reach the
  same last successful checkpoint;
- the next blocker is represented by a typed trace event rather than inference;
- loader failure, missing service, guest crash, host crash and watchdog timeout
  are distinguishable outcomes;
- a machine-generated unique-blocker summary assigns subsystem and priority;
- no Sony/user binary, frame, secret or absolute path exists in the exported
  artifact; and
- the result creates a bounded Phase 8A work ledger.

Reaching `SB06` or even `SB11` does not complete System Software Mode. The Phase
2C goal is reproducible evidence and an implementation ledger.

## 6. Trace and blocker format

### 6.1 Storage format

The canonical stream is UTF-8 JSON Lines:

```text
Build/Diagnostics/SystemSoftware/<session-id>/system-boot-trace.jsonl
Build/Diagnostics/SystemSoftware/<session-id>/system-boot-summary.json
```

Each line is one event and can be consumed before the run finishes. Monotonic
time is used for ordering; wall-clock time is optional and never the event key.

Synthetic example:

```json
{"schema":"vita3kios.system-boot.trace.v1","seq":41,"monotonic_ns":8273100,"session_id":"local-7f2c","app_commit":"<sha>","upstream_commit":"496939b602703951277263c7b3e60a9ae36879c1","firmware":{"version":"<redacted-version>","inventory_id":"local-generation-1"},"target":{"kind":"SystemShell"},"checkpoint":"SB09","subsystem":"nid","event":"missing_nid","priority":"P1","guest":{"pid":2,"thread_id":19,"module":"<guest-module-name>"},"call":{"library":"<library>","nid":"0x12345678"},"outcome":"blocked"}
```

Example values are synthetic and must never be replaced in repository fixtures
with extracted firmware data.

### 6.2 Required envelope fields

Every event carries:

- trace schema version, sequence number, monotonic timestamp and session ID;
- parent and upstream commit IDs;
- host platform, architecture and build flavor in the run header;
- firmware version and local inventory generation ID, but no source path;
- boot-target kind and stable target identifier where safe;
- current checkpoint, subsystem, event type, severity/priority and outcome;
- guest PID/thread/module context when known;
- a typed error code; free-form messages are supplementary, not parsers' input.

### 6.3 Typed event families

| Family | Minimum payload |
| --- | --- |
| `checkpoint` | checkpoint ID, enter/reached/failed, elapsed time |
| `loader` | guest path class, SELF/module stage, error category; no bytes |
| `nid` | NID, resolved library/function if known, caller module, PC/LR if safe, resolution policy |
| `sysmodule` | requested module ID/name, HLE/LLE policy, candidate source class, result |
| `ipc` | service/channel and command/method ID, request/response sizes, endpoint state; no payload bytes |
| `system_event` | event class, source/destination process, delivery/result |
| `process` | PID, target kind, old/new state, parent/foreground relationship |
| `vfs` | guest device/path class, operation and sanitized error; no absolute host path |
| `registry` | operation/category identifier and result; no value data |
| `renderer` | GXM/display/shared-framebuffer checkpoint and typed result |
| `watchdog` | timeout class, last progress checkpoint, responsive thread counts |
| `fatal` | guest exception, host exception or invariant category and last checkpoint |

### 6.4 Aggregation and ownership

Repeated events are keyed by event family plus stable identifiers, caller module
and checkpoint. The stream preserves the first occurrence and bounded samples;
the summary records total count. This avoids hiding frequency while preventing
an unbounded log.

Priorities mean:

- `P0`: prevents inventory, target resolution, mount or executable load;
- `P1`: prevents main-thread progress or first guest frame;
- `P2`: prevents interaction, system-app launch or shell/title lifecycle;
- `P3`: degraded optional behavior outside the current milestone.

Every unique blocker has one owner category: `packages`, `loader`, `kernel`,
`modules`, `ipc`, `process`, `vfs-registry`, `renderer`, `audio-codec`, `session`
or `ios-host`. A blocker is closed only by a semantic test or by documented
evidence that the guest path does not require it. Returning zero is not closure.

## 7. Process and session architecture

### 7.1 Ownership boundary

The native `SessionCoordinator` owns one active emulation session. The session
is either:

- `DirectGameSession`, optimized for one installed title; or
- `SystemSoftwareSession`, owning persistent system services, a shell process
  and any foreground title/system-app processes.

Both share the same validated VitaFS and setting resolver, but they do not share
live kernel objects concurrently. The coordinator enforces a single writer to
games, saves, registry overlays and shader caches.

### 7.2 System-session state machine

```text
idle
  -> validatingFirmware
  -> startingServices
  -> startingShell
  -> shellForeground
       -> startingTitle
       -> titleForeground
       -> stoppingTitle
       -> resumingShell
       -> shellForeground
  -> stopping
  -> idle
```

`paused` is an orthogonal reason set—user, menu, iOS background, audio
interruption, device lock or debugger—not a second lifecycle. A failed title
launch returns to `shellForeground` when the shell is healthy. A fatal shell or
service failure stops System Software Mode and returns to the native library
with a diagnostic; it must not substitute a native fake shell.

### 7.3 Guest process model

The system path needs explicit process state:

```text
GuestProcess
  pid and process generation
  BootTarget / ResolvedBootTarget
  address-space and memory ownership
  thread and module table
  kernel object namespace
  app0 and device mounts
  user/profile and registry view
  lifecycle: created -> loading -> running <-> suspended -> exiting -> dead
```

The kernel/service layer needs:

- unique process IDs rather than the current fixed PID;
- process-scoped threads, modules, TLS, callbacks and exported variables;
- explicit rules for kernel-global versus process-local objects;
- process-aware AppMgr, ShellSvc, system-event and IPC routing;
- per-process address spaces or another measured design that preserves guest
  isolation and address expectations;
- bounded process teardown that does not destroy the system session;
- a foreground-process record and compositor ownership;
- launch arguments and result/event delivery back to the shell.

A temporary sequential prototype may destroy the shell to learn loader
requirements, but it cannot satisfy `shell -> title -> shell` or MSYS.

### 7.4 Persistent services and display

The `SystemSoftwareSession` owns services that outlive a foreground title:

- AppMgr/ShellSvc launch broker and system-event queues;
- IPMI/service endpoints required by traced shell paths;
- registry service and per-user writable overlay;
- display/compositor and shared-framebuffer ownership;
- input focus and common-dialog arbitration;
- audio focus and system/title mixing policy;
- virtual clock, device lifecycle and notification state required by the shell.

There is one host CAMetalLayer. Guest shell, system UI and title surfaces are
composed according to guest state; SwiftUI must not choose which guest frame is
visible based on copied shell semantics. `SceSharedFb` and related display calls
must be implemented from observed contracts rather than converted to permanent
success stubs.

### 7.5 Shell-to-title-to-shell sequence

1. SceShell emits a launch request through implemented guest ShellSvc/AppMgr
   semantics.
2. The launch broker resolves the requested installed title using the same
   library/VitaFS database as Direct Game Mode.
3. The system session creates a title process with a distinct PID, address
   space, module table, `app0` mount and effective settings.
4. Shell receives the correct background/suspend event; guest input and
   foreground rendering transfer to the title.
5. The title runs without tearing down system services, compositor or the shell
   process.
6. Normal exit, user quit and guest crash are classified separately. Save and
   cache writes are flushed under the same integrity rules as Direct Game Mode.
7. AppMgr delivers the corresponding exit/resume event, foreground ownership
   returns to SceShell, and shell input/rendering resume.
8. The same transition succeeds again without restarting the native app or
   reinstalling firmware.

Direct and System modes use the same title-specific configuration and save
locations. Boot-mode settings layer above global settings but below per-title
overrides, as defined in `Docs/ARCHITECTURE.md`.

## 8. Implementation workstreams

The first trace produces work items in these streams:

1. **Packages and inventory:** safe PUP transaction, component manifest,
   generation activation and rollback.
2. **General loader:** typed target resolution, non-`ux0` content roots,
   process-aware `app0`, SELF/load metadata and boot arguments.
3. **HLE/LLE policy:** deterministic module selection bound to firmware version,
   with every fallback visible in trace.
4. **Kernel/process:** PID, address-space, process-scoped objects, exit and
   suspend/resume semantics.
5. **ShellSvc/AppMgr:** launch requests, shell/system events, result delivery and
   application lifecycle.
6. **IPMI and persistent services:** traced service endpoints and command
   semantics, with request payloads kept out of shared traces.
7. **Registry and filesystem:** system/user views, writable overlays, mount
   permissions and firmware-generation isolation.
8. **Display/compositor:** shared framebuffer, foreground routing, first frame
   and shell/title surface transitions.
9. **System applications:** Settings first, then a capability matrix for other
   firmware applications.
10. **iOS host lifecycle:** JIT readiness, foreground/background, memory
    pressure, thermal behavior, audio interruption and safe stop.

Changes should remain small and upstreamable. Generic loader, process and HLE
fixes belong upstream where practical; iOS host policy remains in the port.

## 9. Milestones and exit criteria

These sub-milestones refine, but do not replace, ROADMAP milestones:

| ID | Roadmap mapping | Exit evidence |
| --- | --- | --- |
| `SYS-D0` | 2C.1 | Pinned upstream gap is documented in `Docs/FEASIBILITY.md`. |
| `SYS-D1` | 2C.2 | Typed target design and resolver negative tests cover `InstalledGame`, `SystemShell` and `SystemApp`; Direct Game behavior is unchanged. |
| `SYS-I0` | 2C.3 / 6.13 | User-supplied firmware produces a local versioned inventory and explicit shell/system-app readiness report without repository artifacts. |
| `SYS-R0` | 2C.4 | Two clean raw-load attempts produce the same last checkpoint and typed next blocker. |
| `SYS-R1` | 2C.5–2C.6 | Unique NID/sysmodule/IPC/process blockers are machine-summarized, prioritized and assigned to workstreams. This closes the Phase 2C evidence gate. |
| `SYS-B0` | 8A.4–8A.5 | Shell process and main thread remain alive for 60 seconds under the watchdog with no unclassified host failure. |
| `SYS-F0` | 8A.6 | A guest-rendered SceShell frame reaches the real renderer; proof does not use Qt LiveArea or native artwork. |
| `SYS-U0` | 8A.6 | Guest shell accepts controller/touch input and returns observable guest state changes for a 10-minute interaction session. |
| `SYS-A0` | 8A.7 | Firmware Settings system app launches through the process manager, performs one locally safe setting change, returns, and persists through one system-session restart. |
| `SYS-L0` | 8A.9 | Guest shell launches one user-supplied installed title, the title exits, and the same shell process/session regains interactive foreground control. |
| `SYS-L1` | 8A.9–8A.10 / MSYS | Twenty shell-title-shell cycles complete without native restart, stale input/audio ownership, corrupted save/registry state or unbounded memory growth; iOS pause/resume and device lock tests pass. |

MSYS is complete only when the authentic UI is interactive and `SYS-L1` passes.
It remains a version 1.0 release blocker exactly as stated in `ROADMAP.txt`.

### 9.1 Evidence required for every system milestone

- parent and upstream commit IDs;
- firmware version and local inventory generation ID, not source file path;
- host/device model, OS version, build flavor and JIT method when applicable;
- last checkpoint and trace schema version;
- test command or harness action;
- redacted text trace/summary and known-blocker list;
- explicit confirmation that exported evidence contains no proprietary binary,
  frame or secret.

## 10. Test strategy

Automated CI uses only synthetic/open fixtures and cannot claim firmware boot
coverage. Firmware-backed tests are local/manual gates using user-supplied legal
content.

### 10.1 Automated tests without Sony content

- BootTarget construction, C ABI validation and legacy-request mapping;
- resolver rejection of traversal, wrong generation and missing inventory IDs;
- synthetic inventory parsing and migration;
- trace serialization, aggregation, schema migration and redaction;
- process/session state-machine transitions and illegal transitions;
- launch-broker behavior with synthetic processes;
- firmware transaction cancellation/rollback using artificial containers;
- save/registry writer locking and generation selection;
- Direct Game regression tests.

### 10.2 Local firmware-backed gates

- clean inventory and raw-load reproducibility;
- loader/preload/main-thread checkpoint progression;
- guest first-frame provenance;
- shell input and soak;
- Settings capability proof;
- shell-title-shell repetition;
- firmware update/rollback while preserving user partitions;
- iOS foreground/background, audio interruption, device lock, memory warning and
  thermal tests after the device port reaches this phase.

No local firmware-backed result is promoted to “supported” without recording
the exact commits and firmware version. One successful firmware version does
not authorize mixing or claiming support for other versions.

## 11. Major risks and responses

| Risk | Impact | Required response |
| --- | --- | --- |
| Shell executable or companion content cannot be resolved/loaded from the official PUP. | Stops before main thread. | Preserve the `P0` trace, verify inventory/decryption at the pin, and decide explicitly whether the missing capability belongs in Vita3K's general loader. Do not copy files into `ux0` as a product workaround. |
| Required behavior depends on secure cold boot or Sony kernel state unavailable to HLE. | Could expand into a different emulator architecture. | Produce evidence at the failing checkpoint and request a separate roadmap decision; do not silently claim the HLE-shell target includes cold boot. |
| HLE/LLE ABI or firmware-version mismatch. | Crashes, subtle state corruption or false progress. | Bind module policy to one firmware generation, log every selection, and start with one controlled firmware version. Never mix generations. |
| Very large missing ShellSvc/AppMgr/IPMI surface. | Long R&D schedule. | Implement only trace-reached semantics in dependency order, backed by focused tests; maintain an honest capability matrix. |
| Fixed/single-process assumptions are spread through memory, kernel and IO. | Shell cannot survive title launch. | Introduce process ownership incrementally behind Direct Game regression tests; a sequential prototype cannot close MSYS. |
| Shared framebuffer/compositor behavior is incomplete. | Black/flickering shell or wrong foreground surface. | Trace display ownership, implement guest contracts, and verify first-frame provenance with renderer instrumentation. |
| Returning success from unknown imports creates misleading UI progress. | Apparent boot with broken semantics. | Keep unresolved calls visible; require semantic tests for any stub/no-op. Checkpoint count is not compatibility. |
| Firmware or diagnostic data leaks into Git/CI/release artifacts. | Copyright, privacy and distribution risk. | Text-only allowlist export, secret/path scanner, ignored local storage and release artifact inspection. |
| Malformed PUP exhausts disk/memory or escapes staging. | Data loss or app compromise. | Bounds, quota, path, cancellation and transaction tests before enabling UI import. |
| iOS JIT, memory and thermal limits differ from macOS. | Host success fails on device. | Keep host proof separate; repeat measured gates on supported devices after Phases 2A–5. |
| System services need unavailable/discontinued Sony network endpoints. | Some apps/features remain unusable. | Keep offline shell/MSYS core separate and mark network-dependent system apps unsupported unless independently proven. |
| Large upstream divergence. | Unmaintainable fork. | Small subsystem commits, upstreamable generic fixes, pin-based regression and documented sync. |
| Direct Game regressions while generalizing loader/kernel. | Existing usable mode breaks. | Treat Direct Game tests as a gate for every target/process change. |

## 12. Open questions and decision evidence

These are questions to answer with the Phase 2C inventory and trace, not with
assumptions:

1. Which executable and metadata form the shell entry point in the selected
   official firmware generation?
2. Which partitions and supplemental packages are required for loader success,
   first frame, fonts and interactive UI?
3. Which modules must run LLE, which must remain HLE, and which combinations are
   version-sensitive?
4. What is the first unresolved import/service call after each checkpoint?
5. Does SceShell require a second guest process or persistent service before its
   first frame?
6. Which AppMgr/ShellSvc/IPMI events constitute the real title-launch and return
   protocol?
7. What are the minimum process/address-space isolation semantics needed before
   a title can coexist with a suspended shell?
8. Which shared-framebuffer and compositor contracts determine shell/title
   foreground ownership?
9. Which registry roots are immutable firmware defaults versus per-user writable
   state?
10. Can Settings complete a safe local operation without network/account
    services, and which operation is suitable for `SYS-A0`?
11. Which codecs or media services are first-frame blockers versus optional
    shell features?
12. What is the measured memory cost of persistent shell plus one title on the
    minimum supported iOS device?
13. Can the shell be suspended during iOS backgrounding without losing JIT,
    display, audio or system-event state?
14. Which system applications are meaningful offline and legal to test, and how
    will unsupported ones be labelled?
15. Does any observed blocker require the separate secure cold-boot architecture
    rather than the HLE-userland target?

Each answer is added to the trace-backed work ledger with commit, firmware
version, checkpoint and test evidence. If question 15 is answered “yes,” work
stops at that boundary until `ROADMAP.txt` records an explicit decision.

## 13. Related project documents

- `ROADMAP.txt`: authoritative phases, MSYS definition and release gate.
- `Docs/ARCHITECTURE.md`: native/core boundary, boot modes and settings/HUD
  relationship.
- `Docs/FEASIBILITY.md`: pinned upstream findings.
- `Docs/Audits/UPSTREAM_BASELINE.md`: exact source and toolchain pin.
- `Docs/BUILDING.md`: reproducible host build instructions.
- `Docs/TESTING.md`: project-wide evidence policy.
- `Docs/DISTRIBUTION.md`: licensing, source correspondence and release boundary.

Relevant pinned source roots:

- `External/Vita3K/vita3k/packages/src/pup.cpp`
- `External/Vita3K/vita3k/emuenv/include/emuenv/app_launch_request.h`
- `External/Vita3K/vita3k/app/src/apps_list.cpp`
- `External/Vita3K/vita3k/app/src/session_controller.cpp`
- `External/Vita3K/vita3k/app/src/app_init.cpp`
- `External/Vita3K/vita3k/io/src/io.cpp`
- `External/Vita3K/vita3k/interface.cpp`
- `External/Vita3K/vita3k/kernel/src/kernel.cpp`
- `External/Vita3K/vita3k/modules/module_parent.cpp`
- `External/Vita3K/vita3k/modules/SceKernelThreadMgr/SceThreadmgr.cpp`
- `External/Vita3K/vita3k/modules/SceShellSvc/`
- `External/Vita3K/vita3k/modules/SceAppMgr/`
- `External/Vita3K/vita3k/modules/SceDriverUser/SceAppMgrUser.cpp`
- `External/Vita3K/vita3k/gui-qt/src/live_area_widget.cpp`
