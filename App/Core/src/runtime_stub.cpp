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

DirectBootResult BootDirectGame(const std::filesystem::path&,
                                const std::filesystem::path&,
                                const std::string&) {
    return {
        .result = V3KIOS_RESULT_UNSUPPORTED,
        .checkpoint = V3KIOS_DIRECT_BOOT_CHECKPOINT_EBOOT_CONTAINER_VERIFIED,
        .blocker = V3KIOS_DIRECT_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED,
        .detail =
            "The game is ready, but the full Vita3K loader, Dynarmic CPU, and renderer are not linked into the iOS core target yet.",
    };
}

void SetInputState(const v3kios_input_state_v1&) {
}

void GetMetrics(v3kios_metrics_v1& metrics) {
    metrics.validity_mask = 0;
    metrics.guest_fps = 0.0F;
    metrics.frame_time_ms = 0.0F;
    metrics.host_cpu_percent = 0.0F;
    metrics.host_memory_bytes = 0;
}

void AttachDisplaySurface(const v3kios_display_surface_v1&) {
}

void DetachDisplaySurface() {
}

void StopSession() {
}

}  // namespace v3kios::runtime
