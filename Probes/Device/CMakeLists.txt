cmake_minimum_required(VERSION 3.25)

project(Vita3KiOSDeviceProbes LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "Device probes must be cross-compiled with CMAKE_SYSTEM_NAME=iOS")
endif()
if(CMAKE_OSX_SYSROOT MATCHES "iphonesimulator")
    message(FATAL_ERROR "The Phase 2A probes are physical-device iphoneos targets, not simulator targets")
endif()
if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    message(FATAL_ERROR "Device probes require exactly CMAKE_OSX_ARCHITECTURES=arm64")
endif()

option(VITA3KIOS_ENABLE_JIT_PROBE "Generate the A32 Dynarmic JIT probe" OFF)
option(VITA3KIOS_ENABLE_MOLTENVK_PROBE "Generate the MoltenVK CAMetalLayer probe" OFF)
set(VITA3KIOS_PREPARED_DYNARMIC_DIR "" CACHE PATH "Prepared, patched Dynarmic source")
set(VITA3KIOS_MOLTENVK_ROOT "" CACHE PATH "Extracted MoltenVK runtime root")
set(VITA3KIOS_PROBE_BUNDLE_PREFIX "org.vita3kios.probes" CACHE STRING "Non-product probe bundle prefix")
set(VITA3KIOS_DEVELOPMENT_TEAM "" CACHE STRING "Local Apple development team; never commit a personal value")

if(NOT VITA3KIOS_ENABLE_JIT_PROBE AND NOT VITA3KIOS_ENABLE_MOLTENVK_PROBE)
    message(FATAL_ERROR "Enable at least one device probe target")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

get_filename_component(VITA3KIOS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(VITA3KIOS_SHARED_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/Shared/ProbeApp.mm")
set(VITA3KIOS_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist.in")

execute_process(
    COMMAND git -C "${VITA3KIOS_ROOT}" rev-parse HEAD
    OUTPUT_VARIABLE VITA3KIOS_APP_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
execute_process(
    COMMAND git -C "${VITA3KIOS_ROOT}/External/Vita3K" rev-parse HEAD
    OUTPUT_VARIABLE VITA3KIOS_UPSTREAM_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)

function(vita3kios_configure_probe TARGET DISPLAY_NAME BUNDLE_SUFFIX)
    set_target_properties(${TARGET} PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "${VITA3KIOS_INFO_PLIST}"
        OUTPUT_NAME "${DISPLAY_NAME}"
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
        XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION 1
        XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
        XCODE_ATTRIBUTE_MARKETING_VERSION "0.1"
        XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${VITA3KIOS_PROBE_BUNDLE_PREFIX}.${BUNDLE_SUFFIX}"
        XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS iphoneos
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    )
    if(VITA3KIOS_DEVELOPMENT_TEAM)
        set_target_properties(${TARGET} PROPERTIES
            XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${VITA3KIOS_DEVELOPMENT_TEAM}"
        )
    endif()
    target_include_directories(${TARGET} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/Shared")
    target_compile_features(${TARGET} PRIVATE cxx_std_20)
    target_compile_options(${TARGET} PRIVATE
        "$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Wall>"
        "$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Wextra>"
        "$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Wpedantic>"
        "$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Werror>"
    )
    target_compile_definitions(${TARGET} PRIVATE
        VITA3KIOS_APP_COMMIT="${VITA3KIOS_APP_COMMIT}"
        VITA3KIOS_UPSTREAM_COMMIT="${VITA3KIOS_UPSTREAM_COMMIT}"
    )
    target_link_libraries(${TARGET} PRIVATE
        "-framework CoreGraphics"
        "-framework Foundation"
        "-framework QuartzCore"
        "-framework UIKit"
    )
endfunction()

if(VITA3KIOS_ENABLE_JIT_PROBE)
    if(NOT EXISTS "${VITA3KIOS_PREPARED_DYNARMIC_DIR}/CMakeLists.txt")
        message(FATAL_ERROR "Prepared Dynarmic source is missing; run Scripts/prepare-device-probes.sh")
    endif()

    if(POLICY CMP0167)
        cmake_policy(SET CMP0167 OLD)
    endif()
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(DYNARMIC_ENABLE_NO_EXECUTE_SUPPORT ON CACHE BOOL "" FORCE)
    set(DYNARMIC_FRONTENDS A32 CACHE STRING "" FORCE)
    set(DYNARMIC_TESTS OFF CACHE BOOL "" FORCE)
    set(DYNARMIC_TESTS_USE_UNICORN OFF CACHE BOOL "" FORCE)
    set(DYNARMIC_USE_BUNDLED_EXTERNALS ON CACHE BOOL "" FORCE)
    set(DYNARMIC_USE_LLVM OFF CACHE BOOL "" FORCE)
    set(DYNARMIC_USE_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
    set(DYNARMIC_WARNINGS_AS_ERRORS OFF CACHE BOOL "" FORCE)
    set(FMT_OS OFF CACHE BOOL "" FORCE)
    set(Boost_NO_BOOST_CMAKE ON CACHE BOOL "" FORCE)
    set(Boost_NO_SYSTEM_PATHS ON CACHE BOOL "" FORCE)
    set(BOOST_ROOT "${VITA3KIOS_ROOT}/External/Vita3K/external/boost" CACHE PATH "" FORCE)
    set(Boost_INCLUDE_DIR "${VITA3KIOS_ROOT}/External/Vita3K/external/boost" CACHE PATH "" FORCE)

    add_subdirectory("${VITA3KIOS_PREPARED_DYNARMIC_DIR}" dynarmic EXCLUDE_FROM_ALL)

    # fmt 10.1.0's consteval parser is rejected by AppleClang 21 even for
    # fmt's own valid format strings. Keep constexpr validation without
    # forcing immediate evaluation until the pinned dependency is updated.
    target_compile_definitions(fmt PUBLIC FMT_CONSTEVAL=constexpr)

    add_executable(Vita3KiOSJITProbe MACOSX_BUNDLE
        "${VITA3KIOS_SHARED_SOURCE}"
        JIT/JITProbeRunner.mm
    )
    vita3kios_configure_probe(Vita3KiOSJITProbe "vita3kios JIT Probe" jit)
    target_compile_definitions(Vita3KiOSJITProbe PRIVATE VITA3KIOS_PROBE_USES_METAL=0)
    target_link_libraries(Vita3KiOSJITProbe PRIVATE dynarmic)
endif()

if(VITA3KIOS_ENABLE_MOLTENVK_PROBE)
    set(VITA3KIOS_MOLTENVK_ARCHIVE
        "${VITA3KIOS_MOLTENVK_ROOT}/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a")
    if(NOT EXISTS "${VITA3KIOS_MOLTENVK_ARCHIVE}" OR
       NOT EXISTS "${VITA3KIOS_MOLTENVK_ROOT}/include/vulkan/vulkan.h")
        message(FATAL_ERROR "Pinned MoltenVK iOS package is missing; run Scripts/fetch-device-probe-deps.sh")
    endif()

    add_library(Vita3KiOSMoltenVK STATIC IMPORTED GLOBAL)
    set_target_properties(Vita3KiOSMoltenVK PROPERTIES
        IMPORTED_LOCATION "${VITA3KIOS_MOLTENVK_ARCHIVE}"
        INTERFACE_INCLUDE_DIRECTORIES "${VITA3KIOS_MOLTENVK_ROOT}/include"
    )

    add_executable(Vita3KiOSMoltenVKProbe MACOSX_BUNDLE
        "${VITA3KIOS_SHARED_SOURCE}"
        MoltenVK/MoltenVKProbeRunner.mm
    )
    set(VITA3KIOS_TRIANGLE_VERTEX_SHADER
        "${VITA3KIOS_ROOT}/External/Vita3K/vita3k/shaders-builtin/overlay/overlay.vert.spv")
    set(VITA3KIOS_TRIANGLE_FRAGMENT_SHADER
        "${VITA3KIOS_ROOT}/External/Vita3K/vita3k/shaders-builtin/overlay/overlay.frag.spv")
    set_source_files_properties(
        "${VITA3KIOS_TRIANGLE_VERTEX_SHADER}"
        "${VITA3KIOS_TRIANGLE_FRAGMENT_SHADER}"
        PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/ProbeShaders"
    )
    target_sources(Vita3KiOSMoltenVKProbe PRIVATE
        "${VITA3KIOS_TRIANGLE_VERTEX_SHADER}"
        "${VITA3KIOS_TRIANGLE_FRAGMENT_SHADER}"
    )
    vita3kios_configure_probe(Vita3KiOSMoltenVKProbe "vita3kios MoltenVK Probe" moltenvk)
    target_compile_definitions(Vita3KiOSMoltenVKProbe PRIVATE
        VITA3KIOS_PROBE_USES_METAL=1
        VK_ENABLE_BETA_EXTENSIONS=1
        VK_USE_PLATFORM_METAL_EXT=1
    )
    target_link_libraries(Vita3KiOSMoltenVKProbe PRIVATE
        Vita3KiOSMoltenVK
        "-framework IOSurface"
        "-framework Metal"
    )
    target_link_options(Vita3KiOSMoltenVKProbe PRIVATE "-ObjC")
endif()
