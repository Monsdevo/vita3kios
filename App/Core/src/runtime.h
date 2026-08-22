#pragma once

#include <vita3kios/core.h>

#include <filesystem>
#include <string>

namespace v3kios::runtime {

struct SystemBootResult {
    v3kios_result_v1 result;
    v3kios_boot_checkpoint_v1 checkpoint;
    v3kios_boot_blocker_v1 blocker;
    std::string detail;
};

struct DirectBootResult {
    v3kios_result_v1 result;
    v3kios_direct_boot_checkpoint_v1 checkpoint;
    v3kios_direct_boot_blocker_v1 blocker;
    std::string detail;
};

bool IsFullCoreLinked();
SystemBootResult BootSystemSoftware(const std::filesystem::path& vitaFsRoot,
                                    const std::filesystem::path& shellRelativePath);
DirectBootResult BootDirectGame(const std::filesystem::path& gameRoot,
                                const std::filesystem::path& ebootRelativePath,
                                const std::string& titleId);
void SetInputState(const v3kios_input_state_v1& input);
void GetMetrics(v3kios_metrics_v1& metrics);
void AttachDisplaySurface(const v3kios_display_surface_v1& surface);
void DetachDisplaySurface();
void StopSession();

}  // namespace v3kios::runtime
