# vita3kios

An experimental, open-source PlayStation Vita emulator for iPhone and iPad,
built by porting the Vita3K core into an Apple-native application.

> [!IMPORTANT]
> vita3kios is in early feasibility development. There is no playable public
> build yet. Do not download applications claiming to
> be an official vita3kios release from third-party websites.

## Project status

Phase 1 and milestone M0 are complete. The pinned Vita3K source builds and
passes its selected tests from a clean macOS arm64 checkout.

Phase 2A is in progress. Independent iPhoneOS arm64 probes for Dynarmic JIT and
MoltenVK compile, sign, and pass artifact inspection. The MoltenVK probe now
presents both a clear frame and a triangle using pinned Vita3K SPIR-V. Signed
physical-device runtime reports are still required, so M1 and M2 remain open.

The first M3 product scaffold also exists. Its Apple-native SwiftUI shell links
a versioned C ABI and a real pinned Vita3K allocator source, displays core
version/capability diagnostics, and passes host and Simulator smoke tests. The
signed app installs on a physical iPhone; an unlocked-device launch report is
still required before M3 can be closed.

ABI v3 adds safe extracted-game inventory and import, bounded `param.sfo`
metadata parsing, authentic `eboot.bin` SELF preflight, typed Direct Game boot
checkpoints, input state, and validity-tagged performance snapshots. The native
gameplay surface owns a `CAMetalLayer`, attaches its drawable to ABI v3 before
boot, and includes a Vita touch-controller overlay plus compact top-left HUD.
The full Vita3K loader/Dynarmic/renderer graph is not yet
linked, so imported games are not playable yet. See
[Docs/DIRECT_GAME_BOOTSTRAP.md](Docs/DIRECT_GAME_BOOTSTRAP.md).

The same ABI retains official PUP structural validation, app-owned extracted VitaFS
generations, firmware partition inventory, and a typed System Software boot
preflight. Synthetic tests reach the authentic `sce_shell.self` container. The
full Vita3K loader/HLE/renderer graph is not linked into the iOS target yet, so
no guest firmware instruction or interactive LiveArea frame is claimed. See
[Docs/FIRMWARE_BOOTSTRAP.md](Docs/FIRMWARE_BOOTSTRAP.md) for the exact checkpoint,
current blocker, and device test flow.

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
