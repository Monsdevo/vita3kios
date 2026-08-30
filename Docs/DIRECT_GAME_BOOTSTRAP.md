# Direct Game bootstrap status

Direct Game Mode is the primary delivery path until a user-supplied game boots
visibly and repeatably on a physical iPhone. Authentic System Software remains
the subsequent research path.

## Implemented gate

The current ABI v4 and native app can:

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

With JIT enabled, Minecraft PCSB00560 reaches `Game main thread started` on an
iPhone 15 Pro. Vita3K creates the Apple GPU Vulkan device, links the game SELF,
starts the guest main thread, and runs the MoltenVK render thread. The original
iOS whole-cache W^X race was removed with separate writable and executable
aliases for Dynarmic's code cache.

The remaining acceptance gate is `First guest game frame presented`. Firmware
was not installed during the last game run, so ABI v4 now requires an installed
official firmware generation before Direct Game begins. The next device test
must install the user's official PUP, repeat the boot, and distinguish missing
system-module dependencies from any later title-specific compatibility issue.

## Device test for this gate

1. Build, sign, and sideload the current app.
2. Select **Install Official PUP** and allow Vita3K to install and inventory the
   user-provided firmware.
3. Enable JIT through the verified local sideload workflow.
4. Tap **Import** in **Games** and select an extracted game directory.
5. Confirm that the native library shows its title, title ID, version, size, and
   icon when available.
6. Tap **Play**.
7. Confirm that the gameplay surface, compact controller, and top-left HUD appear.
8. Confirm that the checkpoint advances from `Game main thread started` to
   `First guest game frame presented` and that FPS becomes valid.
9. Export `direct-game-boot-report.json` from the app Documents directory.

Only a visible guest frame and nonzero guest FPS close this gate. A successful
loader return or a running render thread alone is not counted as playability.
