#ifndef VITA3KIOS_CORE_H
#define VITA3KIOS_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VITA3KIOS_CORE_ABI_VERSION 1U

typedef uint64_t v3kios_core_handle_t;

typedef enum v3kios_result_v1 {
    V3KIOS_RESULT_OK = 0,
    V3KIOS_RESULT_INVALID_ARGUMENT = 1,
    V3KIOS_RESULT_INVALID_HANDLE = 2,
    V3KIOS_RESULT_INVALID_STATE = 3,
    V3KIOS_RESULT_INTERNAL_ERROR = 4,
    V3KIOS_RESULT_UNSUPPORTED = 5
} v3kios_result_v1;

typedef enum v3kios_capability_v1 {
    V3KIOS_CAPABILITY_CORE_ABI = 1ULL << 0,
    V3KIOS_CAPABILITY_UPSTREAM_ALLOCATOR = 1ULL << 1,
    V3KIOS_CAPABILITY_JIT_PROBE = 1ULL << 2,
    V3KIOS_CAPABILITY_MOLTENVK_PROBE = 1ULL << 3,
    V3KIOS_CAPABILITY_DIRECT_GAME = 1ULL << 4,
    V3KIOS_CAPABILITY_SYSTEM_SOFTWARE = 1ULL << 5
} v3kios_capability_v1;

typedef struct v3kios_core_info_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t capabilities;
    const char* vita3kios_commit;
    const char* upstream_commit;
    const char* upstream_version;
    const char* build_platform;
} v3kios_core_info_v1;

/*
 * Handles are opaque, owned by the caller, and must be destroyed exactly once.
 * Functions are thread-safe at this bootstrap gate. Returned strings are
 * immutable process-lifetime data. No C++ type or exception crosses this ABI.
 */
v3kios_result_v1 v3kios_core_create(v3kios_core_handle_t* out_handle);
v3kios_result_v1 v3kios_core_destroy(v3kios_core_handle_t handle);
v3kios_result_v1 v3kios_core_get_info(v3kios_core_handle_t handle,
                                      v3kios_core_info_v1* out_info);
v3kios_result_v1 v3kios_core_run_bootstrap_self_test(v3kios_core_handle_t handle);
const char* v3kios_result_description(v3kios_result_v1 result);

#ifdef __cplusplus
}
#endif

#endif
