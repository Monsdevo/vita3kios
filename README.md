# vita3kios

An experimental, open-source PlayStation Vita emulator for iPhone and iPad,
built by porting the Vita3K core into an Apple-native application.

> [!IMPORTANT]
> vita3kios is in early feasibility development. There is no installable IPA
> and no playable public build yet. Do not download applications claiming to
> be an official vita3kios release from third-party websites.

## Project status

Phase 1 and milestone M0 are complete. The pinned Vita3K source builds and
passes its selected tests from a clean macOS arm64 checkout.

Phase 2A is in progress. Independent iPhoneOS arm64 probes for Dynarmic JIT and
MoltenVK now compile successfully, but they have not completed the signed
physical-device runtime gates. M1 and M2 therefore remain open.

See [ROADMAP.txt](ROADMAP.txt) for the authoritative plan, acceptance gates,
and current progress.

## Planned features

- Native SwiftUI interface designed for iPhone and iPad
- Game and application import through the iOS document picker
- **Direct Game Mode** for launching an installed Vita title directly
- **System Software Mode** for booting the authentic SceShell/LiveArea
  environment from user-supplied official firmware
- Detailed global, boot-mode, and per-title settings profiles
- Searchable Basic, Advanced, and Developer settings views
- Small, configurable top-right performance HUD in both boot modes
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

The repository currently provides the reproducible macOS upstream baseline and
the Phase 2A device probes. It does not yet provide the product Xcode project.

```sh
git clone --recursive https://github.com/Monsdevo/vita3kios.git
cd vita3kios
Scripts/bootstrap.sh
Scripts/build-device-probes.sh jit
Scripts/build-device-probes.sh moltenvk
```

Detailed instructions are in [Docs/BUILDING.md](Docs/BUILDING.md) and
[Docs/DEVICE_PROBES.md](Docs/DEVICE_PROBES.md).

## Installation and usage

Installation instructions will be published with the first verified alpha.
Until then, no IPA should be treated as an official vita3kios build.

Future releases are expected to use a sideloaded build and an explicitly
documented JIT-enablement flow. Users will supply their own legally obtained
firmware and dumped applications; neither is included with the project.

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
