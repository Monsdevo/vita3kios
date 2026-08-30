# iOS full-core boundary audit

Pinned upstream: `496939b602703951277263c7b3e60a9ae36879c1`

## Measured launch path

The pinned upstream runtime was not originally exposed as a reusable Apple
headless library. vita3kios now provides that composition for Direct Game.

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

The iOS static target now composes the required Direct Game sources without Qt,
Discord, JNI, or the desktop `main()`. System Software still requires a distinct
SystemShell content resolver and process/service lifecycle; it must not reuse the
installed-title `ux0/app/<TITLE_ID>` path deceptively.

## Firmware installer graph

Upstream `packages/src/pup.cpp` already implements the correct functional
sequence: extract PUP records, decrypt SPKG segments, join partition images,
extract FAT/exFAT files, and return the firmware version. Its target currently
depends on:

- OpenSSL EVP crypto;
- Vita3K `packages`, `util`, `config`, `emuenv`, and `io` code;
- `libfat16`, `miniz`, `psvpfstools`, and `vita-toolchain`;
- the existing logging and filesystem abstractions.

These dependencies now build into the verified iPhoneOS arm64 static archive.
ABI v5 invokes the real `install_pup()` path in app-owned staging, inventories
the extracted result, and promotes a valid immutable firmware generation.

## Integration seam added by vita3kios

`App/Core/src/runtime.h` remains the private boundary behind stable ABI v5.
Physical-device builds compile `runtime_vita3k.cpp`; host and Simulator builds
retain `runtime_stub.cpp` so parser and UI tests never claim guest execution.

The physical-device Direct Game implementation:

1. owns an initialized `EmuEnvState` and serialized `AppSessionController`;
2. mounts the imported game as `ux0/app/<TITLE_ID>` and the selected firmware
   partitions as app-owned VitaFS system roots;
3. invokes the real module loader and starts the guest main thread;
4. connects Dynarmic to separate writable/executable iOS code-cache aliases;
5. connects the Vulkan renderer to the SwiftUI-owned `CAMetalLayer` via MoltenVK;
6. forwards controller state and validity-tagged frame metrics through the C ABI.

## Ordered next build slices

The remaining ordered slices are:

1. Repeat the JIT-enabled Minecraft boot with optional Direct Game firmware
   support files; do not require System Software shell readiness.
2. Require a visible first guest frame and nonzero frame metrics before calling
   Direct Game playable.
3. Add a typed SystemShell resolver and direct system-content mount separately.
4. Publish missing NID, sysmodule, IPC, registry, event, and framebuffer blockers
   without copying proprietary payloads into diagnostics.
5. Require a real guest SceShell frame before enabling the public System Software
   capability.

This ordering prevents PUP installation, SELF parsing, guest execution, and
interactive System Software from being collapsed into one misleading status.
