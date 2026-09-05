cmake_minimum_required(VERSION 3.25)

project(vita3kios LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

get_filename_component(VITA3KIOS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(VITA3KIOS_UPSTREAM_ROOT "${VITA3KIOS_ROOT}/External/Vita3K")
option(VITA3KIOS_FULL_CORE "Link the complete Vita3K Direct Game runtime" OFF)

set(VITA3KIOS_RUNTIME_SOURCE Core/src/runtime_stub.cpp)
if(VITA3KIOS_FULL_CORE)
    set(VITA3KIOS_FULL_CORE_ARCHIVE "${VITA3KIOS_ROOT}/Build/Core/libVita3KFullCore.a")
    set(VITA3KIOS_DEPENDENCY_PREFIX
        "${VITA3KIOS_ROOT}/Build/Dependencies/vcpkg/installed/arm64-ios-vita3k")
    if(NOT EXISTS "${VITA3KIOS_FULL_CORE_ARCHIVE}")
        message(FATAL_ERROR "Full Vita3K iOS core is missing; run Scripts/build-vita3k-ios-core.sh")
    endif()
    set(VITA3KIOS_RUNTIME_SOURCE Core/src/runtime_vita3k.cpp)
endif()

execute_process(
    COMMAND git -C "${VITA3KIOS_ROOT}" rev-parse HEAD
    OUTPUT_VARIABLE VITA3KIOS_APP_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
execute_process(
    COMMAND git -C "${VITA3KIOS_UPSTREAM_ROOT}" rev-parse HEAD
    OUTPUT_VARIABLE VITA3KIOS_UPSTREAM_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)

set(VITA3KIOS_SOURCE_ROOT "${VITA3KIOS_UPSTREAM_ROOT}")
if(VITA3KIOS_FULL_CORE)
    set(VITA3KIOS_MATERIALIZED_SOURCE "/tmp/vita3kios-vita3k-source-${VITA3KIOS_UPSTREAM_COMMIT}")
    if(EXISTS "${VITA3KIOS_MATERIALIZED_SOURCE}/vita3k/interface.cpp")
        set(VITA3KIOS_SOURCE_ROOT "${VITA3KIOS_MATERIALIZED_SOURCE}")
    endif()
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    if(CMAKE_OSX_SYSROOT MATCHES "iphonesimulator")
        set(VITA3KIOS_BUILD_PLATFORM "iphonesimulator-arm64")
    else()
        set(VITA3KIOS_BUILD_PLATFORM "iphoneos-arm64")
    endif()
else()
    set(VITA3KIOS_BUILD_PLATFORM "macos-host")
endif()

add_library(Vita3KCore STATIC
    Core/src/core.cpp
    Core/src/jit_memory_ios.cpp
    ${VITA3KIOS_RUNTIME_SOURCE}
    "${VITA3KIOS_SOURCE_ROOT}/vita3k/mem/src/allocator.cpp"
)
set_target_properties(Vita3KCore PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
    XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD "c++20"
)
target_include_directories(Vita3KCore
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/Core/include"
    PRIVATE "${VITA3KIOS_SOURCE_ROOT}/vita3k/mem/include"
)
if(VITA3KIOS_FULL_CORE)
    file(GLOB VITA3KIOS_UPSTREAM_COMPONENT_INCLUDES
        "${VITA3KIOS_SOURCE_ROOT}/vita3k/*/include")
    target_include_directories(Vita3KCore PRIVATE
        "${VITA3KIOS_SOURCE_ROOT}/vita3k"
        ${VITA3KIOS_UPSTREAM_COMPONENT_INCLUDES}
        "${VITA3KIOS_SOURCE_ROOT}/external/sdl/include"
        "${VITA3KIOS_SOURCE_ROOT}/external/fmt/include"
        "${VITA3KIOS_SOURCE_ROOT}/external/spdlog/include"
        "${VITA3KIOS_DEPENDENCY_PREFIX}/include"
    )
    target_link_libraries(Vita3KCore PUBLIC "${VITA3KIOS_FULL_CORE_ARCHIVE}")
    target_compile_definitions(Vita3KCore PRIVATE VITA3KIOS_FULL_CORE=1)
    set_source_files_properties(Core/src/runtime_vita3k.cpp
        PROPERTIES COMPILE_OPTIONS "-Wno-error")
endif()
target_compile_definitions(Vita3KCore PRIVATE
    VITA3KIOS_APP_COMMIT="${VITA3KIOS_APP_COMMIT}"
    VITA3KIOS_UPSTREAM_COMMIT="${VITA3KIOS_UPSTREAM_COMMIT}"
    VITA3KIOS_BUILD_PLATFORM="${VITA3KIOS_BUILD_PLATFORM}"
)
target_compile_options(Vita3KCore PRIVATE -Wall -Wextra -Wpedantic -Werror)
set_source_files_properties(
    "${VITA3KIOS_SOURCE_ROOT}/vita3k/mem/src/allocator.cpp"
    PROPERTIES COMPILE_OPTIONS "-Wno-error=sign-compare;-Wno-error=shorten-64-to-32"
)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(Swift)

    set(VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER "org.vita3kios.app" CACHE STRING
        "Local self-signed product bundle identifier")
    set(VITA3KIOS_DEVELOPMENT_TEAM "" CACHE STRING
        "Local Apple development team; never commit a personal value")

    add_executable(vita3kios MACOSX_BUNDLE
        Sources/vita3kiosApp.swift
        Sources/CoreStatusModel.swift
        Sources/DesignSystem.swift
        Sources/GameDisplayView.swift
        Sources/GameplayView.swift
        Sources/RootView.swift
        Sources/CoreStatusCard.swift
        Sources/SettingsView.swift
    )
    target_link_libraries(vita3kios PRIVATE Vita3KCore "-lc++")
    if(VITA3KIOS_FULL_CORE)
        target_link_libraries(vita3kios PRIVATE
            "-ObjC"
            "-framework Accelerate"
            "-framework AudioToolbox"
            "-framework AVFoundation"
            "-framework CoreAudio"
            "-framework CoreBluetooth"
            "-framework CoreFoundation"
            "-framework CoreGraphics"
            "-framework CoreHaptics"
            "-framework CoreMedia"
            "-framework CoreMotion"
            "-framework CoreVideo"
            "-framework Foundation"
            "-framework GameController"
            "-framework IOSurface"
            "-framework Metal"
            "-framework QuartzCore"
            "-framework Security"
            "-framework UIKit"
            "-framework VideoToolbox"
            "-liconv" "-lsqlite3" "-lz")
        add_custom_command(TARGET vita3kios POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E copy_directory
                "${VITA3KIOS_SOURCE_ROOT}/vita3k/shaders-builtin"
                "$<TARGET_FILE_DIR:vita3kios>/shaders-builtin"
            COMMENT "Bundling Vita3K built-in renderer shaders")
    endif()
    target_include_directories(vita3kios PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/Core/include")
    set_target_properties(vita3kios PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist.in"
        OUTPUT_NAME "vita3kios"
        XCODE_ATTRIBUTE_CLANG_ENABLE_MODULES YES
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
        XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION 1
        XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING YES
        XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
        XCODE_ATTRIBUTE_MARKETING_VERSION "0.1.0"
        XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER}"
        XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
        XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER
            "${CMAKE_CURRENT_SOURCE_DIR}/vita3kios-Bridging-Header.h"
        XCODE_ATTRIBUTE_SWIFT_STRICT_CONCURRENCY complete
        XCODE_ATTRIBUTE_SWIFT_VERSION 6.0
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    )
    if(VITA3KIOS_DEVELOPMENT_TEAM)
        set_target_properties(vita3kios PROPERTIES
            XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${VITA3KIOS_DEVELOPMENT_TEAM}"
        )
    endif()
else()
    enable_testing()
    add_executable(Vita3KCoreTests CoreTests/core_tests.cpp)
    target_link_libraries(Vita3KCoreTests PRIVATE Vita3KCore)
    add_test(NAME Vita3KCoreTests COMMAND Vita3KCoreTests)
endif()
