# vita3kios Settings and Performance HUD Design Contract

- Status: Binding pre-implementation design baseline
- Roadmap authority: `ROADMAP.txt` v0.5
- Upstream baseline: Vita3K `496939b602703951277263c7b3e60a9ae36879c1`
- Last updated: 2026-08-22

This document defines the data model, C ABI, SwiftUI information architecture,
validation, persistence, metrics, and acceptance tests for settings and the
performance HUD. `ROADMAP.txt` remains authoritative.

## 1. Required product behavior

- Setting precedence is `built-in < global < mode < title < session`.
- Direct Game and System Software use separate mode profiles.
- A title launched by SceShell receives title overrides. Returning to the shell
  restores the effective System Software profile.
- Standard shows safe daily controls. Advanced shows compatibility controls.
  Developer Mode shows diagnostics only.
- Swift never reads or writes upstream C++ `Config`, YAML, or XML directly.
- Unsupported settings are hidden or show a specific reason.
- The HUD defaults to Compact, enabled, and top-right in both boot modes.
- An unavailable metric is hidden or displayed as an em dash. It is never
  represented by zero, an estimate, or an unrelated counter.
- Firmware, games, licenses, keys, and private user data are never copied into
  profiles, fixtures, or diagnostic bundles.
- All repository-owned UI strings, diagnostics, comments, and documentation are
  written in English.

## 2. Upstream adaptation boundary

At the pinned revision, Vita3K loads global values through `config.yml` and
collects per-game values in `Config::CurrentConfig`. Its custom XML profile is a
complete snapshot, not a sparse override list. vita3kios therefore stores only
explicitly overridden fields and resolves them before applying an effective
`CurrentConfig`.

The upstream restart-required set includes CPU optimizations, renderer, GPU
device, Android custom driver, high accuracy, resolution multiplier, memory
mapping, audio backend, and validation layer. On iOS, the renderer is fixed to
Vulkan through MoltenVK. Renderer, GPU, and Android driver choices are not normal
settings. Other fields use `sessionRecreateRequired`; capability results may
raise this to `hostRestartRequired` if safe in-process recreation is unavailable.

Defaults come from the bridge. Swift does not duplicate them. The pinned global
default for `disable-surface-sync`, for example, differs from the bare
`CurrentConfig` field initializer.

The existing upstream overlay counts accepted `sceDisplaySetFrameBuf` calls in
roughly one-second wall-time buckets. Its historical average/minimum/maximum
values are not a frame-time distribution or 1% low. vita3kios must not relabel
those values with stronger semantics.

## 3. Scope, inheritance, and reset

| Scope | Persistence | Identity | Purpose |
| --- | --- | --- | --- |
| Built-in | Read-only | Core/schema version | Safe core defaults |
| Global | Persistent | One profile | User default for every session |
| Mode | Persistent | `directGame` or `systemSoftware` | Boot-mode defaults |
| Title | Persistent | Canonical title ID | Per-title compatibility overrides |
| Session | Temporary | Session UUID | Changes until stop |
| Host | Persistent | App/device | Native UI, storage, permission, and JIT preferences |

Absolute sandbox paths never identify title profiles. The library's validated
canonical title ID survives update and reimport. The shell uses the System
Software mode profile; real system apps may have title profiles.

```text
effective = schema.builtInDefaults
effective.apply(profile.global)
effective.apply(profile.mode[session.mode])
if session.activeTitleID != nil:
    effective.apply(profile.title[session.activeTitleID])
effective.apply(session.transientOverrides)
effective = validateAgainstCapabilities(effective)
```

Capability and safety limits are applied after user overrides.

- Use Parent Profile removes a field from the current sparse profile.
- Reset Category removes only category keys in the open scope.
- Reset Profile removes all overrides in the open scope. It never removes games,
  saves, caches, or firmware.
- A global reset returns to the built-in value.
- Session overrides are not persisted unless the user explicitly saves them in a
  separate transaction.
- The System Software safe preset is read-only. Risky shell changes require
  explicit confirmation.

## 4. Descriptor model

The UI is generated from versioned bridge descriptors. Each descriptor provides:

- a stable, nonlocalized key;
- title, summary, and warning localization keys;
- a typed value and default, range, step, or choices;
- allowed scopes and visibility level;
- capability requirements and an unsupported reason;
- live, next-boot, session-recreate, or host-restart behavior;
- safe, compatibility, destructive-data, or diagnostic risk;
- dependencies and cross-field validation identifiers;
- export and redaction policy; and
- introduced and removed schema versions.

Localized labels are never persistence keys. `Live` means the running-core effect
has been tested. Scope abbreviations below are G (Global), DG (Direct Game), SS
(System Software), T (Title), X (Session), and H (Host).

## 5. Settings catalog

Every row is capability gated. An upstream mapping does not guarantee visibility.

### 5.1 Core, CPU, graphics, and display

| vita3kios key | Upstream mapping | Scope | Level | Apply | Notes |
| --- | --- | --- | --- | --- | --- |
| `core.modules.mode` | `modules-mode` | G,DG,SS,T | Advanced | Boot | Automatic is safe; manual modes require module inventory |
| `core.modules.lle` | `lle-modules` | G,DG,SS,T | Advanced | Boot | Only validated decrypted modules are selectable |
| `cpu.optimizations` | `cpu-opt` | G,DG,SS,T | Advanced | Recreate | Disabling Dynarmic optimizations can be very slow |
| `jit.status` | Native | H, read-only | Standard | None | Enabled, unavailable, preparation, or error |
| `jit.launchProvider` | Native | H | Advanced | Host | Only with multiple validated providers |
| `firmware.activeInstall` | Native | H,SS | Standard | Boot | Stores inventory identity, never the source PUP path |
| `system.mode.safePreset` | Native | SS | Standard | Boot | Tested shell baseline |
| `graphics.accuracy` | `high-accuracy` | G,DG,SS,T | Advanced | Recreate | Capability-gated tradeoff |
| `graphics.resolutionScale` | `resolution-multiplier` | G,DG,SS,T,X | Standard | Recreate | Device-tested range; safe default 1x |
| `graphics.memoryMapping` | `memory-mapping` | G,DG,SS,T | Advanced | Recreate | Only runtime-supported methods |
| `graphics.disableSurfaceSync` | `disable-surface-sync` | G,DG,T,X | Advanced | Live | Compatibility-sensitive speed option |
| `graphics.screenFilter` | Runtime filter list | G,DG,SS,T,X | Standard | Live | Renderer supplies choices |
| `graphics.framePacing` | Native | G,DG,SS,T,X | Standard | Live/Recreate | Host refresh must not alter guest timing |
| `graphics.anisotropicFiltering` | `anisotropic-filtering` | G,DG,SS,T,X | Standard | Live | Device-limited choices |
| `graphics.asyncPipelineCompilation` | upstream field | G,DG,SS,T,X | Standard | Live | Requires thread-safe compilation |
| `graphics.shaderCache` | `shader-cache` | G,DG,SS,T | Standard | Boot | Versioned with the core pin |
| `graphics.textureCache` | `texture-cache` | G,DG,SS,T | Standard | Boot | Explain memory cost |
| `graphics.fpsHack` | `fps-hack` | G,DG,T,X | Advanced | Live | May double game speed; forbidden for System Software |
| `textures.replacementsEnabled` | `import-textures` | G,DG,T,X | Advanced | Live | Import content into app storage |
| `textures.exportEnabled` | `export-textures` | G,DG,T,X | Developer | Live | Requires quota and approval |
| `display.scalingMode` | desktop scaling flags | G,DG,SS,T,X | Standard | Live | Aspect Fit, Fill/Crop, validated Integer |
| `display.fileLoadingDelay` | `file-loading-delay` | G,DG,T | Advanced | Boot | Range 0-30 |
| `display.shaderCompileNotice` | `show-compile-shaders` | G,DG,SS,T | Standard | Live | Brief native notice |
| `display.screenshotFormat` | `screenshot-format` | H | Standard | Live | None, JPEG, or PNG |

Renderer backend, GPU index, Android driver, and direct-SPIR-V controls remain
hidden unless a future iOS capability makes them meaningful.

### 5.2 Audio, system, sensors, and network

| vita3kios key | Upstream mapping | Scope | Level | Apply | Notes |
| --- | --- | --- | --- | --- | --- |
| `audio.volume` | `audio-volume` | G,DG,SS,T,X | Standard | Live | Range 0-100 |
| `audio.ngsEnabled` | `ngs-enable` | G,DG,SS,T | Advanced | Boot | Only when NGS is built |
| `audio.bufferDuration` | Native | G,DG,SS,T | Advanced | Recreate | Device-measured choices |
| `audio.mixWithOthers` | Native | H | Standard | Live/Recreate | Test routes and interruptions |
| `system.pstvMode` | `pstv-mode` | G,DG,SS,T | Advanced | Boot | Changes emulated hardware |
| `system.confirmButton` | `sys-button` | G,DG,SS,T | Standard | Boot | Cross or Circle |
| `system.language` | `sys-lang` | G,DG,SS,T | Standard | Boot | Separate from app language |
| `system.dateFormat` | `sys-date-format` | G,DG,SS,T | Standard | Boot | Supported SCE formats |
| `system.timeFormat` | `sys-time-format` | G,DG,SS,T | Standard | Boot | 12-hour or 24-hour |
| `system.imeLanguages` | `ime-langs` | G,DG,SS,T | Advanced | Boot | Requires implemented IME |
| `camera.front.source` | front camera fields | G,T | Advanced | Boot | None, device, imported image, or color |
| `camera.back.source` | back camera fields | G,T | Advanced | Boot | Ask permission only when needed |
| `motion.enabled` | inverse `disable-motion` | G,DG,SS,T,X | Standard | Live | Negation exists only in bridge |
| `network.httpEnabled` | `http-enable` | G,DG,SS,T | Advanced | Boot | Disclose external-network behavior |
| `network.psnPresenceOffline` | `psn-signed-in` | G,DG,SS,T | Advanced | Boot | Offline emulation, not PSN login |
| `network.httpTimeout*` | timeout fields | G,DG,SS,T | Developer | Boot | Descriptor-bounded ranges |
| `network.adhocAddress` | `adhoc-addr` | G,DG,SS,T | Developer | Boot | Interface index is not identity |

The audio backend is fixed to the validated iOS host.

### 5.3 Input and native host

| vita3kios key | Upstream mapping | Scope | Level | Apply | Notes |
| --- | --- | --- | --- | --- | --- |
| `input.controllerProfile` | controller binds | G,DG,SS,T | Standard | Live | Stable Vita actions, never SDL indexes |
| `input.analogMultiplier` | upstream field | G,DG,SS,T,X | Advanced | Live | Descriptor-bounded |
| `input.deadzone.left/right` | Native | G,DG,SS,T,X | Standard | Live | Independent live preview |
| `touch.enabled` | Native | G,DG,SS,T,X | Standard | Live | Optional controller auto-hide |
| `touch.layoutID` | Native | G,DG,SS,T | Standard | Live | Normalized orientation variants |
| `touch.opacity` | Native | G,DG,SS,T,X | Standard | Live | Enforce readable visibility |
| `touch.scale` | Native | G,DG,SS,T,X | Standard | Live | Reject unsafe layouts |
| `touch.rearPanelMode` | Native | G,DG,SS,T | Advanced | Live | Visible zones or teachable gesture |
| `motion.sensitivity` | Native | G,DG,SS,T,X | Advanced | Live | Host converts orientation |
| `haptics.enabled` | Native | G,DG,SS,T,X | Standard | Live | Device/controller gated |
| `lifecycle.pauseOnBackground` | Native | H | Standard | Live | Resource loss may force pause |

Desktop key-code arrays are not copied into the initial iPhone UI.

### 5.4 HUD, logging, and developer settings

| vita3kios key | Upstream mapping | Scope | Level | Apply | Notes |
| --- | --- | --- | --- | --- | --- |
| `hud.preset` | overlay fields | G,DG,SS,T,X | Standard | Live | Off, Compact, Standard, Detailed, Custom |
| `hud.position` | overlay position | G,DG,SS,T,X | Advanced | Live | Top Right by default |
| `hud.opacity` | Native | G,DG,SS,T,X | Advanced | Live | Enforce readable contrast |
| `hud.scale` | Native | G,DG,SS,T,X | Advanced | Live | Compact starts near 11 pt |
| `hud.updateRateHz` | Native | G,DG,SS,T,X | Advanced | Live | Default 4 Hz |
| `hud.metricSelection` | Native | G,DG,SS,T,X | Advanced | Live | Capability-filtered |
| `hud.includeInAppScreenshot` | Native | G,DG,SS,T | Advanced | Live | Only with compositor support |
| `logging.level` | `log-level` | G | Developer | Live/Boot | Depends on live logger support |
| `logging.archivePerTitle` | `archive-log` | G,DG,SS,T | Advanced | Boot | Redact private data |
| `logging.activeShaders` | upstream field | G,DG,SS,T | Developer | Boot | High-volume warning |
| `logging.uniforms` | upstream field | G,DG,SS,T | Developer | Boot | High-volume warning |
| `debug.validationLayer` | `validation-layer` | G,DG,SS,T | Developer | Recreate | Only when packaged |
| `debug.gdbStub` | `gdbstub` | G | Developer | Host | Debug builds only |
| `debug.waitForDebugger` | upstream field | G | Developer | Host | Timeout and cancel required |
| `debug.tracy*` | Tracy fields | G,DG,SS,T | Developer | Recreate | Tracy build only |

The upstream overlay is disabled while the native HUD is active. Desktop
onboarding, update checks, preferred path, Discord presence, raw user IDs,
Android settings, and raw keyboard codes are internal, replaced, or unsupported.

## 6. Versioned C ABI

- Public headers use C99-compatible POD types.
- Extensible structures begin with `struct_size` and `abi_version`.
- ABI, settings schema, and store format versions are independent.
- Swift and C++ never exchange heap ownership. Variable data uses caller-owned
  buffers and two-call sizing or copying callbacks.
- Strings are UTF-8 and pointers do not outlive a call.
- Every function returns a typed result; exceptions never cross the ABI.
- Settings commits and lifecycle operations share the serial emulation queue.
- UI, render, and audio threads never perform profile disk I/O.

```c
typedef uint64_t v3kios_core_handle_t;
typedef uint64_t v3kios_settings_txn_t;

typedef enum v3kios_setting_scope_v1 {
    V3KIOS_SCOPE_GLOBAL = 1,
    V3KIOS_SCOPE_MODE_DIRECT_GAME = 2,
    V3KIOS_SCOPE_MODE_SYSTEM_SOFTWARE = 3,
    V3KIOS_SCOPE_TITLE = 4,
    V3KIOS_SCOPE_SESSION = 5,
    V3KIOS_SCOPE_HOST = 6
} v3kios_setting_scope_v1;

typedef struct v3kios_setting_descriptor_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t value_type;
    uint32_t scope_mask;
    uint32_t visibility;
    uint32_t apply_requirement;
    uint32_t risk;
    uint64_t capability_mask;
} v3kios_setting_descriptor_v1;
```

Values use a tagged union. The bridge supplies descriptor enumeration, typed
get/set, effective resolution, transaction begin/set/unset/validate/commit/cancel,
category/profile reset, and capability-domain queries.

Results distinguish type/range errors, unsupported capabilities, invalid scopes,
cross-field conflicts, safety warnings, live changes, next-boot changes,
recreation, host restart, and recovery. Transactions are atomic.

Capabilities include option domains: filters, resolution range/step, memory
mapping modes, audio buffers, controller features, GPU timestamps, screenshot
composition, and Developer features. Cache identity includes core build,
device/OS, firmware inventory, and session kind.

## 7. Validation, migration, and persistence

Validation order is descriptor/version, type, domain, scope, capability,
dependencies, cross-field rules, risk acknowledgement, and apply planning.
Values are rejected rather than silently clamped unless the descriptor explicitly
defines layout normalization.

The native store records format/schema version, core commit, scope identity,
timestamps, and sparse values. It never stores absolute sandbox paths, import
bookmarks, license material, or firmware/game content.

Writes use a temporary file, flush, atomic replacement, and last-known-good copy.
Startup validates structure and identity. Corruption falls back with a typed,
nonfatal error. One actor/queue serializes writers.

Every format change has fixture-based migration tests. Unknown newer keys are
preserved when safe or produce explicit incompatibility. Removed capabilities
retain values but mark them unsupported. Migration logs contain keys and result
codes, not values. Every upstream pin change requires a config inventory diff.

## 8. SwiftUI information architecture

Main Settings opens Global/Host. Game detail opens Title. System Software
readiness opens its mode profile. Pause exposes the active profile and safe live
controls. Recreate changes offer Apply on Next Boot or Restart Now.

iPhone uses `NavigationStack`; iPad uses `NavigationSplitView`. The layout shows
profile summary, search, Standard/Advanced selector, readiness, categories,
changed-only filter, reset/export, and Developer/Logging when enabled. Categories
cover System/Firmware, Core/CPU/JIT, GPU/Renderer, Display, Audio, Input, Touch,
Motion, Camera/Microphone, Network, Storage/Cache, Compatibility, HUD, and logs.

Rows show title, effective value, source, override, explanation, apply/risk badges,
and unsupported reason. Sliders snap to descriptor steps. Risky enablement needs
one confirmation; disablement does not. Search respects visibility boundaries.
Developer keys do not leak while Developer Mode is off.

Dynamic Type must preserve meaning. VoiceOver announces title, value, source,
risk, and apply behavior. Color is never the only cue. Reduce Motion limits
profile and graph animations. User-facing project strings are English at this
stage; future localization must not change stable keys.

## 9. Metrics contract

The core publishes a preallocated, double-buffered snapshot. SwiftUI copies the
latest snapshot on its own 2-4 Hz timer and receives no per-frame callbacks.

```c
typedef struct v3kios_metrics_snapshot_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t monotonic_timestamp_ns;
    uint64_t session_id;
    uint64_t sample_epoch;
    uint64_t validity_mask;
    uint32_t session_kind;
    uint32_t run_state;
    double guest_fps;
    double present_fps;
    double guest_frame_interval_ema_ms;
    double guest_frame_interval_p50_ms;
    double guest_frame_interval_p95_ms;
    double one_percent_low_fps;
    double cpu_frame_time_ms;
    double gpu_frame_time_ms;
    uint64_t resident_memory_bytes;
    uint64_t jit_cache_bytes;
    uint64_t jit_compiled_blocks;
    uint64_t pipeline_compiles_total;
    uint64_t audio_underruns_total;
    uint32_t thermal_state;
    uint32_t guest_width;
    uint32_t guest_height;
    double resolution_scale;
} v3kios_metrics_snapshot_v1;
```

Every boot/restart and shell/title transition increments `sample_epoch`.

| Metric | Required meaning |
| --- | --- |
| Guest FPS | Accepted guest display events / nonpaused monotonic time |
| Present FPS | Successful host presents / monotonic time |
| Guest frame interval | Difference between guest-frame timestamps |
| Rolling average | Guest frames / actual elapsed window time |
| 1% low FPS | `1000 / p99_frame_interval_ms` over enough samples |
| CPU frame time | Documented instrumented core critical path |
| GPU frame time | Valid Vulkan timestamp query interval |
| Resident memory | Process footprint/RSS from supported public iOS API |
| Thermal state | Native semantic state, never fake temperature |
| Audio underrun | PCM ring could not satisfy callback demand |
| Pipeline compile | Monotonic completed compilation count |
| JIT cache/blocks | Values directly reported by Dynarmic adapter |
| Resolution | Guest framebuffer, scale, and host drawable kept distinct |
| Emulation speed | Guest virtual-time progress / nonpaused wall time |

`1000 / FPS` is not CPU or GPU time. Utilization is not inferred from frame time.
JIT is not active merely because executable memory was allocated. Invalid metrics
clear their validity bit and stale values disappear.

Hooks only update atomics or a preallocated ring. They do no allocation,
formatting, disk I/O, or Swift callbacks. Monotonic time excludes pause and
background duration. Before the first frame, FPS is invalid rather than zero.

## 10. HUD contract

| Preset | Contents |
| --- | --- |
| Off | No HUD; expensive collection stops without another consumer |
| Compact | Guest FPS and guest frame-interval EMA |
| Standard | Guest/present FPS, rolling average, and 1% low |
| Detailed | Standard plus every valid advanced metric and pacing graph |
| Custom | Capability-filtered user selection |

Defaults are Compact, Top Right, 4 Hz, scale 1.0. Compact normally renders as
`59.9 FPS · 16.7 ms` in a small translucent capsule with monospaced digits.

The HUD is a native SwiftUI layer above `CAMetalLayer`, not part of the Vita
framebuffer. It respects all safe areas and has hit testing disabled. It does not
repeatedly announce live values; Pause/Settings provides an accessible summary.
Pause freezes or resets rolling windows. Epoch changes discard old title data.

The screenshot option appears only if the compositor can explicitly include or
exclude the HUD. No guarantee is made about iOS system recording.

## 11. Test and acceptance gates

Settings tests cover unique keys, typed round trips, precedence combinations,
unset behavior, both boot modes, shell-title-shell transitions, title persistence,
capability rejection, apply behavior, rollback, crash recovery, migrations,
redaction, and lifecycle concurrency.

UI tests cover iPhone/iPad navigation, scope entry points, source badges, Use
Parent behavior, visibility/search boundaries, unsupported states, restart
messaging, Dynamic Type, VoiceOver, contrast, motion, and focus.

Metrics tests use a fake monotonic clock and synthetic 30/60/irregular sequences.
They cover EMA, percentiles, 1% low, pause exclusion, epochs, ring wrap, stalls,
audio underruns, and validity. On device, counters match instrumented traces. FPS
tolerance is the greater of 1 FPS or 2%; interval tolerance is the greater of
0.5 ms or 5%.

HUD tests cover first display within one second of the first valid frame, all
safe areas, wrapping, pass-through touch, presets, validity changes, lifecycle,
surface recreation, and accessibility.

For MHUD, run at least three ten-minute HUD Off/Compact A/B trials on the same
device, build, checkpoint, and settings after warm-up. Compact overhead is at
most 1% CPU. Initial p95 frame-time cost is at most 0.2 ms or the Off-run 95%
confidence interval, whichever is wider. Hooks allocate nothing per frame.
Memory is bounded and unused heavy queries stop. Two-hour Direct Game and System
Software soak tests show no overflow, growth, deadlock, or UI backlog.

MHUD is complete only when semantics, validity, layout, and performance pass in
both boot modes.

## 12. Implementation order

1. Phase 2B: descriptor/value/result types and settings/metrics ABI skeleton.
2. Phase 2C: System Software boot target and mode profile identity.
3. Phases 3-5: real renderer, audio, JIT, and device capability domains.
4. Phase 7: ProfileStore, merge engine, and SwiftUI settings screens.
5. Phase 7A: timestamp ring, metrics publisher, and native HUD.
6. Phases 8-9: session, shell, audio/input lifecycle integration.
7. Phases 10-12: persistence, migration, recovery, privacy, and fuzz tests.
8. Phase 15: config/HUD diff and migration matrix for each upstream pin update.

## 13. Pinned upstream references

- [Global config and HUD enums](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/config/include/config/config.h)
- [Per-app CurrentConfig](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/config/include/config/state.h)
- [Custom config persistence](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/config/src/settings.cpp)
- [Settings application and Apple renderer](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/app/src/app_init.cpp)
- [Runtime FPS calculation](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/app/src/app.cpp)
- [SceDisplay frame counter](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/modules/SceDisplay/SceDisplay.cpp)
- [Current performance overlay](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/overlay/src/perf_overlay.cpp)

When a new upstream pin changes these behaviors, Phase 15 updates this document,
the schema, and migration tests together.
