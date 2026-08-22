# Direct Game bootstrap status

Direct Game Mode is the primary delivery path until a user-supplied game boots
visibly and repeatably on a physical iPhone. Authentic System Software remains
the subsequent research path.

## Implemented gate

The current ABI v3 and native app can:

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
- attach that native layer and its drawable dimensions through ABI v3 before
  issuing the Direct Game boot request;
- provide native dual analog sticks, D-pad, face buttons, L/R, Start, Select,
  and PS/Home;
- submit one normalized controller snapshot through the C ABI;
- show a compact top-left performance HUD that renders only validity-tagged
  metrics and never invents FPS or frame-time values;
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

## Exact blocker

The last successful checkpoint is `Game eboot SELF container verified`. The
next blocker is `Full Vita3K runtime is not linked into the iOS core target`.

The native display attachment, controller, HUD, import transaction, and boot
contract are ready for the runtime, but the current iOS product still uses
`runtime_stub.cpp`.
It does not execute guest instructions or present a guest-rendered game frame.

The next implementation slice must create a Qt/JNI-free Vita3K runtime
composition, initialize `EmuEnvState`, mount the imported generation as `app0`,
load the eboot through the real module loader, start its guest main thread, and
connect Dynarmic and MoltenVK to the existing iOS adapters.

## Device test for this gate

1. Build, sign, and sideload the current app.
2. Enable JIT through the verified local sideload workflow.
3. Tap **Import** in **Games** and select an extracted game directory.
4. Confirm that the native library shows its title, title ID, version, size, and
   icon when available.
5. Tap **Play**.
6. Confirm that the gameplay surface, touch controller, and top-left HUD appear.
7. Confirm that the checkpoint is `Game eboot SELF container verified` and the
   blocker identifies the unlinked full runtime.
8. Export `direct-game-boot-report.json` from the app Documents directory.

This test proves the import, metadata, session UI, input, metrics, and boot-target
boundary. It does not prove game execution; that requires the next full-runtime
link and a real guest frame on the physical device.
