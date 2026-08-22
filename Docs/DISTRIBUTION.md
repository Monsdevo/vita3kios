# Distribution constraints

The first performance-capable target is a development-signed or sideloaded
arm64 IPA with a separately enabled JIT path. App Store/TestFlight distribution
is not assumed to grant Dynarmic executable memory.

All shipped native code must be statically linked or embedded and signed in an
iOS-supported framework form. Runtime-downloaded host dylibs/plugins are not
part of the design. Vita executables remain emulated guest data.

Every binary release must identify its exact sources, submodule commits, build
instructions, GPL text, third-party notices and checksums. Certificates,
provisioning profiles, pairing files, firmware, games, licenses and saves are
never distributed by this repository.
