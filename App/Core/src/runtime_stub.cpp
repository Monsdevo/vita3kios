#include "runtime.h"

namespace v3kios::runtime {

bool IsFullCoreLinked() {
    return false;
}

SystemBootResult BootSystemSoftware(const std::filesystem::path&,
                                    const std::filesystem::path&) {
    return {
        .result = V3KIOS_RESULT_UNSUPPORTED,
        .checkpoint = V3KIOS_BOOT_CHECKPOINT_SHELL_CONTAINER_VERIFIED,
        .blocker = V3KIOS_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED,
        .detail =
            "Authentic firmware is ready, but the full Vita3K loader, HLE kernel, renderer, and service graph are not linked into the iOS core target yet.",
    };
}

}  // namespace v3kios::runtime
