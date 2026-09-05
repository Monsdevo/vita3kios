# Direct Game bootstrap status

Direct Game Mode is the primary delivery path until a user-supplied game boots
visibly and repeatably on a physical iPhone. Authentic System Software remains
the subsequent research path.

## Implemented gate

The current ABI v5 and native app can:

- import a user-selected extracted game directory through the Files picker;
- accept either a direct game root or one container with exactly one game root;
- require `eboot.bin` and `sce_sys/param.sfo`;
- parse bounded `TITLE_ID`, `TITLE`, `APP_VER`, `CATEGORY`, and `CONTENT_ID`
  string fields without using the desktop Qt UI;
- reject malformed SFO data, symbolic links, excessive file counts, unreadable
  trees, unsafe title identifiers, and invalid SELF/ELF containers;
- copy through app-owned staging and atomically promote an immutable generation;
- restore imported generations without persisting a File Provider URL;
- show title metadata and `ICON0.PNG` in the Apple-native library;
- submit a typed Direct Game boot request with deterministic generation identity;
- open a 960x544 aspect-fit gameplay surface backed by `CAMetalLayer`;
- attach that native layer and its drawable dimensions through the C ABI before
  issuing the Direct Game boot request;
- provide native dual analog sticks, D-pad, face buttons, L/R, Start, Select,
  and PS/Home;
- submit one normalized controller snapshot through the C ABI;
- show a compact top-left performance HUD that renders only validity-tagged
  metrics and never invents FPS or frame-time values;
- install and inventory a user-selected official firmware PUP through Vita3K's
  PUP decryption and FAT/exFAT extraction implementation;
- distinguish Direct Game firmware support from the stricter System Software
  shell prerequisites;
- mount the installed `os0`, `pd0`, `sa0`, and `vs0` partitions into the
  app-owned runtime VitaFS without duplicating firmware data;
- initialize the pinned Vita3K loader, HLE services, Dynarmic CPU, audio stack,
  Vulkan renderer, and MoltenVK dispatcher without the desktop Qt frontend;
- write a redacted `direct-game-boot-report.json` in the app Documents directory.

Synthetic automated tests verify the SFO parser, game inventory, generation
matching, eboot preflight, normalized input bounds, metric validity, and the
current typed runtime blocker.

## Supported input at this gate

Select an extracted, legally dumped game folder with this minimum layout:

```text
TITLE_ID/
  eboot.bin
  sce_sys/
    param.sfo
    icon0.png            optional
```

VPK, ZIP, PKG, license, update, and DLC transactions remain later import slices.
No game, license, key, decrypted executable, or copyrighted asset may be
committed to this repository or included in a distributed IPA.

For the first eventual runtime test, a small redistributable Vita homebrew is the
lowest-risk target. Retail dumps may additionally require Vita3K's license and
content-decryption installation path, which is not part of this folder preflight.

## Exact current gate

The latest 2026-09-05 device run passed the JIT and host SpinLock faults and
executed Minecraft's module/service calls. It then loaded
`app0:sce_module/steroid.suprx`, which the pinned upstream loader explicitly
rejects as an unsupported Vitamin dump. Missing runtime imports followed and
the guest reached PC zero without presenting a frame. A compatible replacement
dump is required for further acceptance testing. Firmware alone does not
convert this input. The app now reports this condition before entering the
runtime, even when JIT is unavailable, and preserves the imported library item.

With JIT enabled, Minecraft PCSB00560 reaches `Game main thread started` on an
iPhone 15 Pro. Vita3K creates the Apple GPU Vulkan device, links the game SELF,
starts the guest main thread, and runs the MoltenVK render thread. The original
iOS whole-cache W^X race was removed with separate writable and executable
aliases for Dynarmic's code cache.

The remaining acceptance gate is `First guest game frame presented`. The last
Minecraft run had no installed firmware, but it still reached the guest main
thread because upstream treats failed `bootimage.skprx`, `sysmodule.skprx`, and
selected firmware-module preloads as non-fatal. ABI v5 therefore does not impose
an artificial firmware gate on Direct Game. An installed PUP is retained as a
compatibility input, while JIT remains mandatory for guest execution.

## Device test for this gate

The 2026-09-05 Minecraft retest confirmed that MoltenVK creates the Apple GPU
device and swapchain, and the game SELF loads. The first generated instruction
then triggered `CODESIGNING / Invalid Page` and `SIGKILL`. The original memory
permission probe had returned a false positive: `mprotect(PROT_EXEC)` succeeded
without authorization to execute unsigned code.

Requiring `CS_DEBUGGED` prevented the normal-launch crash, but a debugger-enabled
retest exposed a second protection fault in the RW-origin code mapping. A plain
debugger attachment is therefore insufficient for this iOS development target.

The JIT allocator now starts with RX memory, creates its separate writable alias,
and calls a debugger page-preparation hook before enabling writes. The helper
acknowledges only after writing the entire RX range through debugserver. Without
that acknowledgement, allocation fails before generated code is executed. The
readiness probe uses the same allocator and tests execution and rewriting of a
small function (42, then 43). Each Dynarmic code cache uses this path too.

The probe passed on the physical device. Minecraft subsequently hit a separate
generated host SpinLock helper, which has now been replaced with native
acquire/release atomic operations on iOS. The emitted guest-side locking ABI is
unchanged. Each guest thread's code cache is capped at 16 MiB to bound eager
debugger page preparation; Dynarmic retains its normal cache-recycling behavior.

This development workflow requires the connected Mac helper to remain attached
while playing, including when the game creates new CPU code caches. The app no
longer advertises a plain StikDebug launch as sufficient. References:
[Apple code-signing status](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h)
and [Dart's iOS RX-page preparation](https://github.com/dart-lang/sdk/blob/main/runtime/vm/virtual_memory_posix.cc).

1. Build, sign, and sideload the current app.
2. Optionally select **Install Official PUP** to provide the user-owned firmware
   compatibility files used by some titles.
3. A normal launch must report JIT unavailable and must not crash on **Play**.
4. Tap **Import** in **Games** and select an extracted game directory.
5. Confirm that the native library shows its title, title ID, version, size, and
   icon when available.
6. Run the following command on the connected Mac. It opens the native library,
   attaches the page helper, and then activates the first imported game.
   Keep its debugger session open while testing.

   ```sh
   VITA3KIOS_DEBUG_EXECUTABLE=/path/to/vita3kios.app/vita3kios \
   VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER=your.reverse.dns.vita3kios \
   Scripts/launch-game-with-jit.sh YOUR_DEVICE_IDENTIFIER
   ```
7. Confirm that the gameplay surface, compact controller, and top-left HUD appear.
8. Confirm that the checkpoint advances from `Game main thread started` to
   `First guest game frame presented` and that FPS becomes valid.
9. Export `direct-game-boot-report.json` from the app Documents directory.

Only a visible guest frame and nonzero guest FPS close this gate. A successful
loader return or a running render thread alone is not counted as playability.
