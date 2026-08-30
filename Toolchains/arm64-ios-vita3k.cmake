set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_ARCHITECTURES arm64)
set(VCPKG_OSX_DEPLOYMENT_TARGET 17.4)
set(VCPKG_BUILD_TYPE release)

# Xcode beta exposes pipe2 in the iOS 27 SDK while curl's feature probe sees the
# declaration without its deployment guard. Keep the availability diagnostic as
# a warning so curl can retain its runtime fallback on iOS 17.
set(VCPKG_C_FLAGS "-Wno-error=unguarded-availability-new")
set(VCPKG_CXX_FLAGS "-Wno-error=unguarded-availability-new")
