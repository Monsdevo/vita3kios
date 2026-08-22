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

bool IsFullCoreLinked();
SystemBootResult BootSystemSoftware(const std::filesystem::path& vitaFsRoot,
                                    const std::filesystem::path& shellRelativePath);

}  // namespace v3kios::runtime
