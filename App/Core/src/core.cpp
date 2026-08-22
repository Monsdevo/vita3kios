#include <vita3kios/core.h>

#include <mem/allocator.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <new>
#include <unordered_set>

#ifndef VITA3KIOS_APP_COMMIT
#define VITA3KIOS_APP_COMMIT "unknown"
#endif
#ifndef VITA3KIOS_UPSTREAM_COMMIT
#define VITA3KIOS_UPSTREAM_COMMIT "unknown"
#endif
#ifndef VITA3KIOS_BUILD_PLATFORM
#define VITA3KIOS_BUILD_PLATFORM "unknown"
#endif

namespace {

struct CoreContext {
    std::uint64_t identity;
};

std::atomic<std::uint64_t> nextIdentity{1};
std::mutex contextsMutex;
std::unordered_set<CoreContext*> contexts;

CoreContext* Resolve(const v3kios_core_handle_t handle) {
    if (handle == 0) {
        return nullptr;
    }
    auto* context = reinterpret_cast<CoreContext*>(static_cast<std::uintptr_t>(handle));
    const std::lock_guard<std::mutex> lock{contextsMutex};
    return contexts.find(context) != contexts.end() ? context : nullptr;
}

}  // namespace

extern "C" v3kios_result_v1 v3kios_core_create(v3kios_core_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    }
    *out_handle = 0;
    try {
        auto* context = new CoreContext{nextIdentity.fetch_add(1)};
        {
            const std::lock_guard<std::mutex> lock{contextsMutex};
            contexts.insert(context);
        }
        *out_handle = static_cast<v3kios_core_handle_t>(
            reinterpret_cast<std::uintptr_t>(context));
        return V3KIOS_RESULT_OK;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" v3kios_result_v1 v3kios_core_destroy(const v3kios_core_handle_t handle) {
    if (handle == 0) {
        return V3KIOS_RESULT_INVALID_HANDLE;
    }
    auto* context = reinterpret_cast<CoreContext*>(static_cast<std::uintptr_t>(handle));
    {
        const std::lock_guard<std::mutex> lock{contextsMutex};
        if (contexts.erase(context) != 1) {
            return V3KIOS_RESULT_INVALID_HANDLE;
        }
    }
    delete context;
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_get_info(const v3kios_core_handle_t handle,
                                                    v3kios_core_info_v1* out_info) {
    if (out_info == nullptr || out_info->struct_size < sizeof(v3kios_core_info_v1)) {
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    }
    if (Resolve(handle) == nullptr) {
        return V3KIOS_RESULT_INVALID_HANDLE;
    }
    out_info->abi_version = VITA3KIOS_CORE_ABI_VERSION;
    out_info->capabilities = V3KIOS_CAPABILITY_CORE_ABI |
                             V3KIOS_CAPABILITY_UPSTREAM_ALLOCATOR |
                             V3KIOS_CAPABILITY_JIT_PROBE |
                             V3KIOS_CAPABILITY_MOLTENVK_PROBE;
    out_info->vita3kios_commit = VITA3KIOS_APP_COMMIT;
    out_info->upstream_commit = VITA3KIOS_UPSTREAM_COMMIT;
    out_info->upstream_version = "0.2.1";
    out_info->build_platform = VITA3KIOS_BUILD_PLATFORM;
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_run_bootstrap_self_test(
    const v3kios_core_handle_t handle) {
    if (Resolve(handle) == nullptr) {
        return V3KIOS_RESULT_INVALID_HANDLE;
    }
    try {
        BitmapAllocator allocator{128};
        std::uint32_t firstSize = 8;
        const int firstOffset = allocator.allocate_from(0, firstSize, false);
        std::uint32_t secondSize = 8;
        const int secondOffset = allocator.allocate_from(0, secondSize, false);
        allocator.free(static_cast<std::uint32_t>(firstOffset), firstSize);
        std::uint32_t reusedSize = 8;
        const int reusedOffset = allocator.allocate_from(0, reusedSize, false);
        const bool passed = firstOffset == 0 && secondOffset == 8 && reusedOffset == 0 &&
                            firstSize == 8 && secondSize == 8 && reusedSize == 8;
        return passed ? V3KIOS_RESULT_OK : V3KIOS_RESULT_INTERNAL_ERROR;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" const char* v3kios_result_description(const v3kios_result_v1 result) {
    switch (result) {
    case V3KIOS_RESULT_OK:
        return "Success";
    case V3KIOS_RESULT_INVALID_ARGUMENT:
        return "Invalid argument";
    case V3KIOS_RESULT_INVALID_HANDLE:
        return "Invalid core handle";
    case V3KIOS_RESULT_INVALID_STATE:
        return "Invalid lifecycle state";
    case V3KIOS_RESULT_INTERNAL_ERROR:
        return "Internal core error";
    case V3KIOS_RESULT_UNSUPPORTED:
        return "Capability is not implemented";
    }
    return "Unknown result";
}
