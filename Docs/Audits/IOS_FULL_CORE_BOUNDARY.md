# iOS full-core boundary audit

Pinned upstream: `496939b602703951277263c7b3e60a9ae36879c1`

## Measured launch path

The pinned upstream runtime is not a reusable headless library yet.

1. `vita3k/app/src/session_controller.cpp` begins every launch with
   `setup_game_launch()`, which resolves an installed `ux0` application.
2. `vita3k/interface.cpp` builds `app0:` from that installed application and
   loads the main executable through `load_module()`.
3. The same function preloads `os0:kd/bootimage.skprx`,
   `os0:kd/sysmodule.skprx`, and selected `vs0:sys/external` modules.
4. `run_app()` creates the guest main thread only after the complete kernel,
   memory, module, configuration, renderer, and runtime state exists.
5. Upstream CMake creates a Qt executable on Apple platforms. Its only existing
   UI-free shared-library composition is the Android/JNI target.

This explains the current typed blocker. The iOS app can resolve and validate
the authentic firmware shell, but calling the real loader requires a reusable
runtime composition plus a SystemShell content mount that does not impersonate
an installed `ux0/app/<TITLE_ID>`.

## Firmware installer graph

Upstream `packages/src/pup.cpp` already implements the correct functional
sequence: extract PUP records, decrypt SPKG segments, join partition images,
extract FAT/exFAT files, and return the firmware version. Its target currently
depends on:

- OpenSSL EVP crypto;
- Vita3K `packages`, `util`, `config`, `emuenv`, and `io` code;
- `libfat16`, `miniz`, `psvpfstools`, and `vita-toolchain`;
- the existing logging and filesystem abstractions.

These dependencies do not yet have a verified iPhoneOS static composition. The
native app therefore exposes PUP structural validation, but it does not claim
that validation installed firmware.

## Integration seam added by vita3kios

`App/Core/src/runtime.h` is the private boundary between stable ABI v2 and the
full emulator composition. `runtime_stub.cpp` is compiled today and returns the
exact `UPSTREAM_CORE_NOT_LINKED` blocker after the SceShell SELF preflight.

The stub must be replaced, not bypassed, by a runtime implementation that:

1. owns an initialized `EmuEnvState` and serialized session lifecycle;
2. resolves a typed SystemShell target to the selected firmware generation;
3. mounts the firmware system-content root directly as `app0` for SceShell;
4. invokes the real Vita3K module loader and records its module ID;
5. starts the guest main thread and watchdog;
6. publishes missing NID, sysmodule, IPC, registry, event, and framebuffer
   blockers without copying proprietary payloads into diagnostics;
7. enables `V3KIOS_CAPABILITY_SYSTEM_SOFTWARE` only after the implementation is
   linked and its minimum runtime contract is available.

## Ordered next build slices

The full runtime should be introduced in independently testable slices:

1. Cross-compile and link the PUP installer dependency graph for iPhoneOS.
2. Create a Qt/Discord-free upstream static runtime composition based on the
   Android target's source boundary, without JNI or Android platform code.
3. Add the typed SystemShell resolver and direct system-content mount.
4. Reach `CORE_INITIALIZED`, then `MAIN_MODULE_LOADED`, then
   `MAIN_THREAD_STARTED` in separate commits with typed failures.
5. Connect the existing MoltenVK and JIT device paths and require a real guest
   SceShell frame before enabling the public System Software capability.

This ordering prevents PUP installation, SELF parsing, guest execution, and
interactive System Software from being collapsed into one misleading status.
