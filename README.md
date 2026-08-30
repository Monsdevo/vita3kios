# vita3kios

An experimental, open-source PlayStation Vita emulator for iPhone and iPad,
built by porting the Vita3K core into an Apple-native application.

> [!IMPORTANT]
> vita3kios is in early feasibility development. There is no playable public
> build yet. Do not download applications claiming to
> be an official vita3kios release from third-party websites.

## Project status

Milestones M0 through M3 are complete. The pinned Vita3K source builds for
macOS and iPhoneOS arm64, Dynarmic JIT and MoltenVK have run on a physical
iPhone, and the signed Apple-native app links and queries the Vita3K core.

ABI v5 provides safe extracted-game inventory and import, bounded `param.sfo`
metadata parsing, authentic `eboot.bin` SELF preflight, typed Direct Game boot
checkpoints, input state, and validity-tagged performance snapshots. The native
gameplay surface owns a `CAMetalLayer`, attaches its drawable before
boot, and includes a Vita touch-controller overlay plus compact top-left HUD.
The pinned Vita3K loader, HLE services, Dynarmic CPU, audio stack, Vulkan
renderer, and MoltenVK dispatcher are linked. A Minecraft device test reaches
guest main-thread and render-thread execution; first guest-frame presentation
remains the active Direct Game gate. See
[Docs/DIRECT_GAME_BOOTSTRAP.md](Docs/DIRECT_GAME_BOOTSTRAP.md).

ABI v5 also connects Vita3K's real PUP decryption and FAT/exFAT extraction path.
An official user-selected PUP can be installed into an app-owned immutable
VitaFS generation, inventoried, and mounted into Direct Game sessions. Direct
Game firmware readiness is intentionally separate from System Software shell
readiness: missing `bootimage.skprx`, `sysmodule.skprx`, or SceShell blocks only
the System Software experiment. Direct Game can also start without installed
firmware because upstream treats missing preload modules as non-fatal, although
firmware content can still affect title compatibility. No guest firmware shell
instruction or interactive LiveArea frame is claimed. See
[Docs/FIRMWARE_BOOTSTRAP.md](Docs/FIRMWARE_BOOTSTRAP.md) for the exact checkpoint,
current blocker, and device test flow.

The current game importer accepts only an extracted folder containing
`eboot.bin` and `sce_sys/param.sfo`; `sce_sys/icon0.png` is optional. It may also
accept one parent folder containing exactly one such game root. VPK, ZIP, PKG,
updates, DLC, and retail license/decryption transactions are not implemented yet.
Passing import preflight does not guarantee title compatibility.

See [ROADMAP.txt](ROADMAP.txt) for the authoritative plan, acceptance gates,
and current progress.

## Planned features

- Native SwiftUI interface designed for iPhone and iPad, with restrained
  PlayStation-inspired accent details
- Game and application import through the iOS document picker
- **Direct Game Mode** for launching an installed Vita title directly
- **System Software Mode** for booting the authentic SceShell/LiveArea
  environment from user-supplied official firmware
- Detailed global, boot-mode, and per-title settings profiles
- Searchable Basic, Advanced, and Developer settings views
- Small, configurable top-left performance HUD in both boot modes
- Physical controllers, touch controls, front/rear touch, motion, and audio
- Vulkan rendering through MoltenVK and `CAMetalLayer`
- Dynarmic A32-to-A64 JIT with an explicitly verified iOS JIT workflow

System Software Mode is a separate core-engineering goal. Installing firmware
does not prove that the Vita operating environment can boot, and the feature
will not be marked complete until the real firmware-provided shell is
interactive and can launch a title and return to the shell.

## Requirements

Final device and OS requirements have not been established. The current
technical baseline is:

- arm64 iPhone or iPad
- iOS 17.4 or later as a provisional deployment target
- Developer Mode for development builds
- A valid development or sideloading signature
- A separately enabled and verified JIT workflow for usable performance

These values may change only after physical-device measurements are recorded.

## Building

The repository provides the reproducible macOS upstream baseline, Phase 2A
device probes, and a generated M3 SwiftUI product project.

```sh
git clone --recursive https://github.com/Monsdevo/vita3kios.git
cd vita3kios
Scripts/bootstrap.sh
Scripts/build-device-probes.sh jit
Scripts/build-device-probes.sh moltenvk
Scripts/build-app.sh host
Scripts/build-app.sh simulator
Scripts/build-app.sh device
```

Detailed instructions are in [Docs/BUILDING.md](Docs/BUILDING.md),
[Docs/DEVICE_PROBES.md](Docs/DEVICE_PROBES.md), and
[Docs/DEVICE_TESTING.md](Docs/DEVICE_TESTING.md). Firmware bootstrap testing is
covered separately in [Docs/FIRMWARE_BOOTSTRAP.md](Docs/FIRMWARE_BOOTSTRAP.md),
and the current Direct Game gate is in
[Docs/DIRECT_GAME_BOOTSTRAP.md](Docs/DIRECT_GAME_BOOTSTRAP.md).

## Installation and usage

vita3kios is permanently a self-signed/sideloaded project. App Store and
TestFlight distribution are not product targets. Verified installation
instructions will be published with the first technical alpha; until then, no
third-party IPA should be treated as an official build.

Users will supply their own legally obtained firmware and dumped applications;
neither is included with the project.

## Content and legal notice

vita3kios does not distribute Sony firmware, games, license keys, certificates,
decryption material, pairing data, or copyrighted system assets. Users are
responsible for supplying content they are legally entitled to use.

PlayStation and PlayStation Vita are trademarks of Sony Interactive
Entertainment. vita3kios is not affiliated with or endorsed by Sony.

## License

Vita3K is licensed under GPL-2.0. Distributed vita3kios source and build
materials will remain GPL-compatible. The dependency inventory is maintained in
[LICENSES/DEPENDENCIES.md](LICENSES/DEPENDENCIES.md); a complete corresponding
source and release-license review is required before binary distribution.

## Credits

- [Vita3K](https://github.com/Vita3K/Vita3K) — emulator core
- [Dynarmic](https://github.com/merryhime/dynarmic) — ARM dynamic recompiler
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) — Vulkan on Metal
- [RPCS3 iOS Releases](https://github.com/XITRIX/RPCS3-iOS-Releases) — reference
  for clear early-stage documentation and Apple-native product direction
- The open-source iOS emulation community and everyone contributing testing,
  research, and platform knowledge
