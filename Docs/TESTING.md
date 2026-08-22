# Testing

The firmware transaction and System Software raw-boot preflight are documented
in [FIRMWARE_BOOTSTRAP.md](FIRMWARE_BOOTSTRAP.md). Automated tests use only
synthetic content; they do not establish firmware compatibility.

Every result must record both the vita3kios commit and pinned Vita3K commit,
toolchain, build configuration and—when relevant—device model and iOS version.

Test layers will be introduced in this order:

1. Upstream macOS configure/build/test baseline.
2. Isolated iPhoneOS Dynarmic JIT probe.
3. Isolated CAMetalLayer + MoltenVK probe.
4. C ABI lifecycle and parser/import unit tests.
5. Open-source homebrew boot/render/audio/input tests.
6. User-provided legal retail and firmware system-software tests.

Simulator results never replace physical-device evidence for JIT, GPU,
performance, thermal behavior, signing or memory pressure.

## Current macOS baseline

The Phase 1 host baseline is exercised with:

```sh
Scripts/test-upstream-macos.sh
Scripts/smoke-upstream-macos.sh
```

At the pinned upstream commit, CTest owns two suites: `mem` and `module`. Both
passed on the recorded arm64 run. The GUI smoke stages an ad-hoc-signed bundle
with isolated portable storage and requires the `[apply_theme_entry]` marker;
it does not use the user's normal Vita3K directory. Exact toolchain and results
are recorded in `Docs/Audits/UPSTREAM_BASELINE.md`.
