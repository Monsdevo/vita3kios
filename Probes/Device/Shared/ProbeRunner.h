#pragma once

#include <string>

namespace Vita3KiOS::Probes {

// Implemented independently by each device-probe target. The Metal probe
// receives a CAMetalLayer; non-rendering probes may ignore the opaque pointer.
[[nodiscard]] std::string RunProbe(void* presentationLayer);

}  // namespace Vita3KiOS::Probes
