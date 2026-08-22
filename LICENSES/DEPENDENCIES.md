# Dependency and license inventory

Snapshot: Vita3K `496939b602703951277263c7b3e60a9ae36879c1`, 2026-08-22.

The exact 41 recursive Git entries (the Vita3K superproject plus 40 upstream
submodules), origins and detected license files are in
`Docs/Audits/VITA3K_SUBMODULES.tsv`. The table below is an initial human audit;
it is not a substitute for release-time legal review or a complete SBOM.

| Component/group | Detected license | iOS disposition |
|---|---|---|
| Vita3K | GPL-2.0; many source headers say v2-or-later | Core; source obligations apply |
| LibAtrac9 | MIT | Keep |
| SPIRV-Cross | Apache-2.0 | Keep |
| VulkanMemoryAllocator-Hpp | CC0-1.0 | Keep |
| Vulkan-Headers | Apache-2.0 OR MIT, file-dependent | Keep |
| Vulkan Memory Allocator | MIT | Keep |
| Boost subset | BSL-1.0 | Keep; static |
| Capstone | BSD-3-Clause plus LLVM-licensed files | Keep only required ARM support |
| concurrentqueue | BSD-2-Clause; embedded exceptions noted upstream | Keep |
| cubeb and Rust backends | ISC | Re-evaluate; likely replace host audio on iOS |
| sanitizers-cmake | MIT | Build-only |
| googletest | BSD-3-Clause | Test-only |
| dirent | MIT | Windows-only/remove from iOS graph |
| dlmalloc | Public domain/CC0 statement in README | Core memory; verify source notices |
| Dynarmic | 0BSD/ISC-style permission text | Critical JIT dependency |
| FFmpeg core | LGPL-2.1; actual enabled codecs/config must be audited | Keep subset; static-link compliance review |
| fmt | MIT | Keep |
| glslang | Multiple permissive licenses; see upstream manifest | Keep required targets only |
| libadrenotools/linkernsbypass | BSD-2-Clause | Android-only/remove from iOS graph |
| libfat16 | MIT | Keep for firmware partitions |
| nativefiledialog-extended | Zlib | Desktop-only/remove from iOS graph |
| printf | MIT | Keep if linked |
| psvpfstools family | No complete root license file detected | **Release blocker: manual provenance/license audit** |
| libb64 | Public-domain dedication | Transitive psvpfstools |
| bundled zlib | Zlib | Transitive psvpfstools |
| pugixml | MIT | Keep |
| SDL | Zlib | Keep initially; native replacement evaluated per subsystem |
| spdlog | MIT | Keep |
| stb | MIT OR Public Domain | Keep selected files |
| substitute | LGPL-2.1-or-later; some files LGPL-3/public domain | Platform use must be traced; likely exclude on iOS |
| Tracy | BSD-3-Clause | Developer build only |
| vita-toolchain / psp2rela | MIT | Build/input tooling; runtime need to be verified |
| xxHash | BSD-2-Clause | Keep |
| yaml-cpp | MIT | Keep |

## Vendored non-submodule sources

The upstream Git tree also vendors `CppCommon`, `GPUOpen`, `cli11`, `ddspp`,
`glad` and `miniz`; Dynarmic and other submodules vendor further components.
Their per-file licenses must be included by the future automated SBOM scan.

## Package/build inputs outside submodules

- vcpkg manifest: Boost filesystem/ICL/program-options/system/variant, curl,
  OpenSSL and zlib; baseline `77df67cfff9c12ccfdb52284e07c87c75092f723`.
- Qt 6.11.1 for the macOS-only upstream baseline; not part of the iOS UI plan.
- MoltenVK 1.4.1 macOS tar is hash-pinned upstream.
- FFmpeg prebuilt artifact is not hash-pinned upstream and must be checksummed.
- Discord Game SDK is proprietary and disabled in vita3kios builds.

## Open release blockers

1. Produce a full source SBOM that includes vendored trees and build downloads.
2. Resolve psvpfstools/libzrif/psvpfsparser license provenance.
3. Record the exact FFmpeg configuration and static-link compliance material.
4. Copy all required license/notice texts into the packaged distribution.
