#ifndef VITA3KIOS_CORE_H
#define VITA3KIOS_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VITA3KIOS_CORE_ABI_VERSION 5U

typedef uint64_t v3kios_core_handle_t;

typedef enum v3kios_result_v1 {
    V3KIOS_RESULT_OK = 0,
    V3KIOS_RESULT_INVALID_ARGUMENT = 1,
    V3KIOS_RESULT_INVALID_HANDLE = 2,
    V3KIOS_RESULT_INVALID_STATE = 3,
    V3KIOS_RESULT_INTERNAL_ERROR = 4,
    V3KIOS_RESULT_UNSUPPORTED = 5,
    V3KIOS_RESULT_IO_ERROR = 6,
    V3KIOS_RESULT_INVALID_FIRMWARE = 7,
    V3KIOS_RESULT_FIRMWARE_NOT_READY = 8,
    V3KIOS_RESULT_INVALID_GAME = 9,
    V3KIOS_RESULT_GAME_NOT_READY = 10
} v3kios_result_v1;

typedef enum v3kios_capability_v1 {
    V3KIOS_CAPABILITY_CORE_ABI = 1ULL << 0,
    V3KIOS_CAPABILITY_UPSTREAM_ALLOCATOR = 1ULL << 1,
    V3KIOS_CAPABILITY_JIT_PROBE = 1ULL << 2,
    V3KIOS_CAPABILITY_MOLTENVK_PROBE = 1ULL << 3,
    V3KIOS_CAPABILITY_DIRECT_GAME = 1ULL << 4,
    V3KIOS_CAPABILITY_SYSTEM_SOFTWARE = 1ULL << 5,
    V3KIOS_CAPABILITY_FIRMWARE_PUP_PREFLIGHT = 1ULL << 6,
    V3KIOS_CAPABILITY_FIRMWARE_INVENTORY = 1ULL << 7,
    V3KIOS_CAPABILITY_SYSTEM_SHELL_PREFLIGHT = 1ULL << 8,
    V3KIOS_CAPABILITY_GAME_INVENTORY = 1ULL << 9,
    V3KIOS_CAPABILITY_DIRECT_GAME_PREFLIGHT = 1ULL << 10,
    V3KIOS_CAPABILITY_INPUT_STATE = 1ULL << 11,
    V3KIOS_CAPABILITY_METRICS_SNAPSHOT = 1ULL << 12,
    V3KIOS_CAPABILITY_DISPLAY_SURFACE = 1ULL << 13,
    V3KIOS_CAPABILITY_FIRMWARE_PUP_INSTALL = 1ULL << 14
} v3kios_capability_v1;

typedef enum v3kios_lifecycle_state_v1 {
    V3KIOS_LIFECYCLE_CREATED = 0,
    V3KIOS_LIFECYCLE_INITIALIZED = 1,
    V3KIOS_LIFECYCLE_FIRMWARE_READY = 2,
    V3KIOS_LIFECYCLE_BOOTING = 3,
    V3KIOS_LIFECYCLE_RUNNING = 4,
    V3KIOS_LIFECYCLE_FAILED = 5
} v3kios_lifecycle_state_v1;

typedef enum v3kios_firmware_state_v1 {
    V3KIOS_FIRMWARE_ABSENT = 0,
    V3KIOS_FIRMWARE_PUP_VALIDATED = 1,
    V3KIOS_FIRMWARE_INVENTORIED = 2,
    V3KIOS_FIRMWARE_DIRECT_GAME_READY = 3,
    V3KIOS_FIRMWARE_SHELL_READY = 4
} v3kios_firmware_state_v1;

typedef enum v3kios_firmware_partition_v1 {
    V3KIOS_FIRMWARE_PARTITION_OS0 = 1U << 0,
    V3KIOS_FIRMWARE_PARTITION_PD0 = 1U << 1,
    V3KIOS_FIRMWARE_PARTITION_SA0 = 1U << 2,
    V3KIOS_FIRMWARE_PARTITION_VS0 = 1U << 3
} v3kios_firmware_partition_v1;

typedef enum v3kios_game_state_v1 {
    V3KIOS_GAME_ABSENT = 0,
    V3KIOS_GAME_INVENTORIED = 1,
    V3KIOS_GAME_BOOT_READY = 2
} v3kios_game_state_v1;

typedef enum v3kios_direct_boot_checkpoint_v1 {
    V3KIOS_DIRECT_BOOT_CHECKPOINT_NONE = 0,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_REQUEST_VALIDATED = 1,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_GAME_CONTENT_VERIFIED = 2,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_EBOOT_CONTAINER_VERIFIED = 3,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_CORE_INITIALIZED = 4,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_MAIN_MODULE_LOADED = 5,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_MAIN_THREAD_STARTED = 6,
    V3KIOS_DIRECT_BOOT_CHECKPOINT_FIRST_GUEST_FRAME = 7
} v3kios_direct_boot_checkpoint_v1;

typedef enum v3kios_direct_boot_blocker_v1 {
    V3KIOS_DIRECT_BOOT_BLOCKER_NONE = 0,
    V3KIOS_DIRECT_BOOT_BLOCKER_GAME_NOT_SELECTED = 1,
    V3KIOS_DIRECT_BOOT_BLOCKER_GENERATION_MISMATCH = 2,
    V3KIOS_DIRECT_BOOT_BLOCKER_PARAM_SFO_INVALID = 3,
    V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_MISSING = 4,
    V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_CONTAINER_INVALID = 5,
    V3KIOS_DIRECT_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED = 6,
    V3KIOS_DIRECT_BOOT_BLOCKER_CORE_INITIALIZATION_FAILED = 7,
    V3KIOS_DIRECT_BOOT_BLOCKER_MODULE_LOAD_FAILED = 8,
    V3KIOS_DIRECT_BOOT_BLOCKER_MAIN_THREAD_FAILED = 9,
    V3KIOS_DIRECT_BOOT_BLOCKER_RENDERER_FAILED = 10,
    V3KIOS_DIRECT_BOOT_BLOCKER_DISPLAY_SURFACE_MISSING = 11,
    V3KIOS_DIRECT_BOOT_BLOCKER_JIT_NOT_ENABLED = 12,
    V3KIOS_DIRECT_BOOT_BLOCKER_FIRMWARE_NOT_READY = 13,
    V3KIOS_DIRECT_BOOT_BLOCKER_UNSUPPORTED_DUMP = 14
} v3kios_direct_boot_blocker_v1;

typedef enum v3kios_input_button_v1 {
    V3KIOS_INPUT_SELECT = 1U << 0,
    V3KIOS_INPUT_START = 1U << 3,
    V3KIOS_INPUT_UP = 1U << 4,
    V3KIOS_INPUT_RIGHT = 1U << 5,
    V3KIOS_INPUT_DOWN = 1U << 6,
    V3KIOS_INPUT_LEFT = 1U << 7,
    V3KIOS_INPUT_L = 1U << 8,
    V3KIOS_INPUT_R = 1U << 9,
    V3KIOS_INPUT_TRIANGLE = 1U << 12,
    V3KIOS_INPUT_CIRCLE = 1U << 13,
    V3KIOS_INPUT_CROSS = 1U << 14,
    V3KIOS_INPUT_SQUARE = 1U << 15,
    V3KIOS_INPUT_PS = 1U << 16
} v3kios_input_button_v1;

typedef enum v3kios_metric_validity_v1 {
    V3KIOS_METRIC_GUEST_FPS = 1U << 0,
    V3KIOS_METRIC_FRAME_TIME = 1U << 1,
    V3KIOS_METRIC_HOST_CPU = 1U << 2,
    V3KIOS_METRIC_HOST_MEMORY = 1U << 3
} v3kios_metric_validity_v1;

typedef enum v3kios_boot_checkpoint_v1 {
    V3KIOS_BOOT_CHECKPOINT_NONE = 0,
    V3KIOS_BOOT_CHECKPOINT_REQUEST_VALIDATED = 1,
    V3KIOS_BOOT_CHECKPOINT_FIRMWARE_SELECTED = 2,
    V3KIOS_BOOT_CHECKPOINT_PARTITIONS_VERIFIED = 3,
    V3KIOS_BOOT_CHECKPOINT_SHELL_EXECUTABLE_LOCATED = 4,
    V3KIOS_BOOT_CHECKPOINT_SHELL_CONTAINER_VERIFIED = 5,
    V3KIOS_BOOT_CHECKPOINT_CORE_INITIALIZED = 6,
    V3KIOS_BOOT_CHECKPOINT_MAIN_MODULE_LOADED = 7,
    V3KIOS_BOOT_CHECKPOINT_MAIN_THREAD_STARTED = 8,
    V3KIOS_BOOT_CHECKPOINT_FIRST_GUEST_FRAME = 9
} v3kios_boot_checkpoint_v1;

typedef enum v3kios_boot_blocker_v1 {
    V3KIOS_BOOT_BLOCKER_NONE = 0,
    V3KIOS_BOOT_BLOCKER_FIRMWARE_NOT_SELECTED = 1,
    V3KIOS_BOOT_BLOCKER_GENERATION_MISMATCH = 2,
    V3KIOS_BOOT_BLOCKER_REQUIRED_PARTITION_MISSING = 3,
    V3KIOS_BOOT_BLOCKER_SHELL_EXECUTABLE_MISSING = 4,
    V3KIOS_BOOT_BLOCKER_SHELL_CONTAINER_INVALID = 5,
    V3KIOS_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED = 6,
    V3KIOS_BOOT_BLOCKER_CORE_INITIALIZATION_FAILED = 7,
    V3KIOS_BOOT_BLOCKER_MODULE_LOAD_FAILED = 8,
    V3KIOS_BOOT_BLOCKER_MAIN_THREAD_FAILED = 9
} v3kios_boot_blocker_v1;

typedef struct v3kios_core_info_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t capabilities;
    const char* vita3kios_commit;
    const char* upstream_commit;
    const char* upstream_version;
    const char* build_platform;
} v3kios_core_info_v1;

typedef struct v3kios_pup_info_v1 {
    uint32_t struct_size;
    uint32_t record_count;
    uint32_t pup_version;
    uint32_t firmware_version;
    uint32_t build_number;
    uint64_t file_size;
    const char* version_text;
} v3kios_pup_info_v1;

typedef struct v3kios_firmware_inventory_v1 {
    uint32_t struct_size;
    v3kios_firmware_state_v1 state;
    uint32_t partition_mask;
    uint32_t file_count;
    uint64_t total_bytes;
    const char* generation_id;
    const char* version_text;
    const char* shell_relative_path;
    const char* detail;
} v3kios_firmware_inventory_v1;

typedef struct v3kios_system_boot_report_v1 {
    uint32_t struct_size;
    v3kios_boot_checkpoint_v1 checkpoint;
    v3kios_boot_blocker_v1 blocker;
    const char* generation_id;
    const char* shell_relative_path;
    const char* detail;
} v3kios_system_boot_report_v1;

typedef struct v3kios_game_info_v1 {
    uint32_t struct_size;
    v3kios_game_state_v1 state;
    uint32_t file_count;
    uint64_t total_bytes;
    const char* generation_id;
    const char* title_id;
    const char* title;
    const char* version;
    const char* category;
    const char* content_id;
    const char* eboot_relative_path;
    const char* icon_relative_path;
    const char* detail;
} v3kios_game_info_v1;

typedef struct v3kios_direct_boot_report_v1 {
    uint32_t struct_size;
    v3kios_direct_boot_checkpoint_v1 checkpoint;
    v3kios_direct_boot_blocker_v1 blocker;
    const char* generation_id;
    const char* title_id;
    const char* detail;
} v3kios_direct_boot_report_v1;

typedef struct v3kios_input_state_v1 {
    uint32_t struct_size;
    uint32_t buttons;
    float left_x;
    float left_y;
    float right_x;
    float right_y;
} v3kios_input_state_v1;

typedef struct v3kios_metrics_v1 {
    uint32_t struct_size;
    uint32_t validity_mask;
    float guest_fps;
    float frame_time_ms;
    float host_cpu_percent;
    uint64_t host_memory_bytes;
} v3kios_metrics_v1;

typedef struct v3kios_display_surface_v1 {
    uint32_t struct_size;
    void* metal_layer;
    uint32_t drawable_width;
    uint32_t drawable_height;
    float scale;
} v3kios_display_surface_v1;

/*
 * Handles are opaque, owned by the caller, and must be destroyed exactly once.
 * Functions are thread-safe at this bootstrap gate. Returned strings are
 * immutable until the next mutating call on the same handle. Callers must copy
 * returned text before another call or destroy. No C++ type or exception crosses
 * this ABI.
 */
v3kios_result_v1 v3kios_core_create(v3kios_core_handle_t* out_handle);
v3kios_result_v1 v3kios_core_destroy(v3kios_core_handle_t handle);
v3kios_result_v1 v3kios_core_initialize(v3kios_core_handle_t handle,
                                        const char* data_root);
v3kios_result_v1 v3kios_core_shutdown(v3kios_core_handle_t handle);
v3kios_result_v1 v3kios_core_get_info(v3kios_core_handle_t handle,
                                      v3kios_core_info_v1* out_info);
v3kios_result_v1 v3kios_core_get_lifecycle_state(
    v3kios_core_handle_t handle,
    v3kios_lifecycle_state_v1* out_state);
v3kios_result_v1 v3kios_core_run_bootstrap_self_test(v3kios_core_handle_t handle);
v3kios_result_v1 v3kios_core_inspect_firmware_pup(
    v3kios_core_handle_t handle,
    const char* pup_path,
    v3kios_pup_info_v1* out_info);
v3kios_result_v1 v3kios_core_install_firmware_pup(
    v3kios_core_handle_t handle,
    const char* pup_path,
    const char* vita_fs_root);
v3kios_result_v1 v3kios_core_inventory_firmware(
    v3kios_core_handle_t handle,
    const char* vita_fs_root,
    v3kios_firmware_inventory_v1* out_inventory);
v3kios_result_v1 v3kios_core_boot_system_software(
    v3kios_core_handle_t handle,
    const char* generation_id,
    v3kios_system_boot_report_v1* out_report);
v3kios_result_v1 v3kios_core_inventory_game(
    v3kios_core_handle_t handle,
    const char* game_root,
    v3kios_game_info_v1* out_info);
v3kios_result_v1 v3kios_core_boot_direct_game(
    v3kios_core_handle_t handle,
    const char* game_root,
    const char* generation_id,
    v3kios_direct_boot_report_v1* out_report);
v3kios_result_v1 v3kios_core_set_input_state(
    v3kios_core_handle_t handle,
    const v3kios_input_state_v1* input);
v3kios_result_v1 v3kios_core_get_metrics(
    v3kios_core_handle_t handle,
    v3kios_metrics_v1* out_metrics);
v3kios_result_v1 v3kios_core_attach_display_surface(
    v3kios_core_handle_t handle,
    const v3kios_display_surface_v1* surface);
v3kios_result_v1 v3kios_core_detach_display_surface(v3kios_core_handle_t handle);
v3kios_result_v1 v3kios_core_stop_session(v3kios_core_handle_t handle);
int v3kios_core_is_jit_enabled(void);
const char* v3kios_result_description(v3kios_result_v1 result);
const char* v3kios_boot_checkpoint_description(v3kios_boot_checkpoint_v1 checkpoint);
const char* v3kios_boot_blocker_description(v3kios_boot_blocker_v1 blocker);
const char* v3kios_direct_boot_checkpoint_description(
    v3kios_direct_boot_checkpoint_v1 checkpoint);
const char* v3kios_direct_boot_blocker_description(
    v3kios_direct_boot_blocker_v1 blocker);

#ifdef __cplusplus
}
#endif

#endif
