#include <vita3kios/core.h>

#include <cassert>

int main() {
    v3kios_core_handle_t handle = 0;
    assert(v3kios_core_create(nullptr) == V3KIOS_RESULT_INVALID_ARGUMENT);
    assert(v3kios_core_create(&handle) == V3KIOS_RESULT_OK);
    assert(handle != 0);

    v3kios_core_info_v1 info{};
    info.struct_size = sizeof(info);
    assert(v3kios_core_get_info(handle, &info) == V3KIOS_RESULT_OK);
    assert(info.abi_version == VITA3KIOS_CORE_ABI_VERSION);
    assert((info.capabilities & V3KIOS_CAPABILITY_UPSTREAM_ALLOCATOR) != 0);
    assert(v3kios_core_run_bootstrap_self_test(handle) == V3KIOS_RESULT_OK);
    assert(v3kios_core_destroy(handle) == V3KIOS_RESULT_OK);
    assert(v3kios_core_destroy(handle) == V3KIOS_RESULT_INVALID_HANDLE);
    return 0;
}
