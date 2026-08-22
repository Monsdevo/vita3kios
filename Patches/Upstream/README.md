# Upstream compatibility patches

These patches are applied transiently by the project build scripts. The pinned
`External/Vita3K` submodule must be clean before and after each build.

## `0001-xcode-27-remove-legacy-ld64.patch`

Vita3K added `-ld64` in 2024 to select Xcode's classic linker. Xcode 27 removed
that linker implementation, so AppleClang 21 interprets the obsolete token as a
request for a library named `d64` and fails the final link.

The patch also lets the wrapper supply `macdeployqt` arguments. The wrapper
adds Homebrew's split QtPdf/QtVirtualKeyboard search paths and disables
`macdeployqt`'s internal signing. It also skips Vita3K's in-place ad-hoc signing.
The wrapper copies the generated bundle to `/private/tmp` without filesystem
metadata, signs that temporary copy, performs strict verification, and removes
the staging directory. This is needed when the workspace lives on a macOS File
Provider-managed Desktop folder, which can immediately recreate Finder metadata.

The macOS baseline script applies the patch only for Xcode 27 or newer and
reverses it on exit. It is a host-toolchain compatibility patch, not an iOS
emulation change.

## `0002-cmake-link-imported-boost-filesystem.patch`

Vita3K's utility target links the legacy `${Boost_LIBRARIES}` variable. With
the pinned Boost 1.89 CMake package and Vita3K's repeated `get_boost()` calls,
that compatibility variable can be empty even though the imported
`Boost::filesystem` target and its arm64 static archive are valid. The result
is a final-link failure containing unresolved Boost.Filesystem symbols.

The patch links the imported target directly. The macOS baseline wrapper also
forces the pinned custom Boost distribution and its release runtime variant so
dependency selection does not depend on packages installed on the host. The
patch is applied transiently and reversed on every exit.
