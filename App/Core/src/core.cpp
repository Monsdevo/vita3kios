#include <vita3kios/core.h>

#include <mem/allocator.h>

#include "runtime.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

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
namespace filesystem = std::filesystem;

constexpr std::size_t PupHeaderSize = 0x80;
constexpr std::size_t PupRecordSize = 0x20;
constexpr std::uint32_t MaximumPupRecords = 4096;
constexpr std::uint64_t MaximumInventoryEntries = 500000;
constexpr std::uint32_t RequiredSystemPartitionMask =
    V3KIOS_FIRMWARE_PARTITION_OS0 | V3KIOS_FIRMWARE_PARTITION_VS0;

struct InventoryData {
    v3kios_firmware_state_v1 state = V3KIOS_FIRMWARE_ABSENT;
    std::uint32_t partitionMask = 0;
    std::uint32_t fileCount = 0;
    std::uint64_t totalBytes = 0;
    std::string generationId;
    std::string versionText = "Unknown";
    std::string shellRelativePath;
    std::string detail = "No firmware has been inventoried.";
    filesystem::path root;
};

struct CoreContext {
    explicit CoreContext(const std::uint64_t newIdentity) : identity(newIdentity) {}
    std::uint64_t identity;
    std::mutex mutex;
    v3kios_lifecycle_state_v1 lifecycle = V3KIOS_LIFECYCLE_CREATED;
    filesystem::path dataRoot;
    InventoryData inventory;
    InventoryData probeInventory;
    std::string pupVersionText = "Unknown";
    std::string bootDetail;
};

std::atomic<std::uint64_t> nextIdentity{1};
std::mutex contextsMutex;
std::unordered_set<CoreContext*> contexts;

CoreContext* Resolve(const v3kios_core_handle_t handle) {
    if (handle == 0) return nullptr;
    auto* context = reinterpret_cast<CoreContext*>(static_cast<std::uintptr_t>(handle));
    const std::lock_guard<std::mutex> lock{contextsMutex};
    return contexts.find(context) != contexts.end() ? context : nullptr;
}

template <typename T>
T ReadLittleEndian(const unsigned char* bytes) {
    T result = 0;
    for (std::size_t index = 0; index < sizeof(T); ++index)
        result |= static_cast<T>(bytes[index]) << (index * 8U);
    return result;
}

bool IsRangeInside(const std::uint64_t offset, const std::uint64_t length,
                   const std::uint64_t fileSize) {
    return offset <= fileSize && length <= fileSize - offset;
}

bool ReadAt(std::ifstream& stream, const std::uint64_t offset,
            unsigned char* destination, const std::size_t length) {
    if (offset > static_cast<std::uint64_t>(std::numeric_limits<std::streamoff>::max()))
        return false;
    stream.clear();
    stream.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!stream.good()) return false;
    stream.read(reinterpret_cast<char*>(destination), static_cast<std::streamsize>(length));
    return stream.gcount() == static_cast<std::streamsize>(length);
}

std::string TrimText(std::string text) {
    while (!text.empty() &&
           (text.back() == '\0' || std::isspace(static_cast<unsigned char>(text.back())) != 0))
        text.pop_back();
    const auto first = std::find_if_not(text.begin(), text.end(), [](const char value) {
        return std::isspace(static_cast<unsigned char>(value)) != 0;
    });
    text.erase(text.begin(), first);
    text.erase(std::remove_if(text.begin(), text.end(), [](const unsigned char value) {
        return value < 0x20U || value > 0x7eU;
    }), text.end());
    if (text.size() > 64) text.resize(64);
    return text.empty() ? "Unknown" : text;
}

std::string Lowercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](const unsigned char value) {
        return static_cast<char>(std::tolower(value));
    });
    return value;
}

void HashBytes(std::uint64_t& hash, const std::string_view bytes) {
    constexpr std::uint64_t FnvPrime = 1099511628211ULL;
    for (const unsigned char byte : bytes) {
        hash ^= byte;
        hash *= FnvPrime;
    }
}

void HashInteger(std::uint64_t& hash, const std::uint64_t value) {
    std::array<unsigned char, sizeof(value)> bytes{};
    for (std::size_t index = 0; index < bytes.size(); ++index)
        bytes[index] = static_cast<unsigned char>((value >> (index * 8U)) & 0xffU);
    HashBytes(hash, {reinterpret_cast<const char*>(bytes.data()), bytes.size()});
}

std::string GenerationId(const std::uint64_t hash) {
    std::ostringstream text;
    text << "inventory-v1-" << std::hex << std::setfill('0') << std::setw(16) << hash;
    return text.str();
}

bool HasPartitionLayout(const filesystem::path& root) {
    std::error_code error;
    return filesystem::is_directory(root / "vs0", error) ||
           filesystem::is_directory(root / "os0", error);
}

std::optional<filesystem::path> ResolveVitaFsRoot(const filesystem::path& selectedRoot) {
    std::error_code error;
    if (!filesystem::is_directory(selectedRoot, error) || error) return std::nullopt;
    const auto canonicalRoot = filesystem::weakly_canonical(selectedRoot, error);
    if (error) return std::nullopt;
    if (HasPartitionLayout(canonicalRoot)) return canonicalRoot;
    if (HasPartitionLayout(canonicalRoot / "vita")) return canonicalRoot / "vita";
    return std::nullopt;
}

bool IsShellContainer(const filesystem::path& shellPath) {
    std::ifstream stream{shellPath, std::ios::binary};
    std::array<unsigned char, 4> magic{};
    if (!stream.read(reinterpret_cast<char*>(magic.data()),
                     static_cast<std::streamsize>(magic.size()))) return false;
    const bool sce = magic[0] == 'S' && magic[1] == 'C' && magic[2] == 'E' && magic[3] == 0;
    const bool elf = magic[0] == 0x7fU && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
    return sce || elf;
}

void FillInventory(const InventoryData& source, v3kios_firmware_inventory_v1& destination) {
    destination.state = source.state;
    destination.partition_mask = source.partitionMask;
    destination.file_count = source.fileCount;
    destination.total_bytes = source.totalBytes;
    destination.generation_id = source.generationId.c_str();
    destination.version_text = source.versionText.c_str();
    destination.shell_relative_path = source.shellRelativePath.c_str();
    destination.detail = source.detail.c_str();
}
}  // namespace

extern "C" v3kios_result_v1 v3kios_core_create(v3kios_core_handle_t* out_handle) {
    if (out_handle == nullptr) return V3KIOS_RESULT_INVALID_ARGUMENT;
    *out_handle = 0;
    try {
        auto* context = new CoreContext{nextIdentity.fetch_add(1)};
        {
            const std::lock_guard<std::mutex> lock{contextsMutex};
            contexts.insert(context);
        }
        *out_handle = static_cast<v3kios_core_handle_t>(reinterpret_cast<std::uintptr_t>(context));
        return V3KIOS_RESULT_OK;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" v3kios_result_v1 v3kios_core_destroy(const v3kios_core_handle_t handle) {
    if (handle == 0) return V3KIOS_RESULT_INVALID_HANDLE;
    auto* context = reinterpret_cast<CoreContext*>(static_cast<std::uintptr_t>(handle));
    {
        const std::lock_guard<std::mutex> lock{contextsMutex};
        if (contexts.erase(context) != 1) return V3KIOS_RESULT_INVALID_HANDLE;
    }
    delete context;
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_initialize(const v3kios_core_handle_t handle,
                                                       const char* data_root) {
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    if (data_root == nullptr || data_root[0] == '\0') return V3KIOS_RESULT_INVALID_ARGUMENT;
    try {
        const std::lock_guard<std::mutex> lock{context->mutex};
        if (context->lifecycle != V3KIOS_LIFECYCLE_CREATED) return V3KIOS_RESULT_INVALID_STATE;
        std::error_code error;
        const filesystem::path requestedRoot{data_root};
        filesystem::create_directories(requestedRoot, error);
        if (error || !filesystem::is_directory(requestedRoot, error)) return V3KIOS_RESULT_IO_ERROR;
        context->dataRoot = filesystem::weakly_canonical(requestedRoot, error);
        if (error) return V3KIOS_RESULT_IO_ERROR;
        context->lifecycle = V3KIOS_LIFECYCLE_INITIALIZED;
        return V3KIOS_RESULT_OK;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" v3kios_result_v1 v3kios_core_shutdown(const v3kios_core_handle_t handle) {
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED) return V3KIOS_RESULT_INVALID_STATE;
    context->inventory = {};
    context->probeInventory = {};
    context->dataRoot.clear();
    context->pupVersionText = "Unknown";
    context->bootDetail.clear();
    context->lifecycle = V3KIOS_LIFECYCLE_CREATED;
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_get_info(const v3kios_core_handle_t handle,
                                                    v3kios_core_info_v1* out_info) {
    if (out_info == nullptr || out_info->struct_size < sizeof(v3kios_core_info_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    if (Resolve(handle) == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    out_info->abi_version = VITA3KIOS_CORE_ABI_VERSION;
    out_info->capabilities = V3KIOS_CAPABILITY_CORE_ABI |
                             V3KIOS_CAPABILITY_UPSTREAM_ALLOCATOR |
                             V3KIOS_CAPABILITY_JIT_PROBE |
                             V3KIOS_CAPABILITY_MOLTENVK_PROBE |
                             V3KIOS_CAPABILITY_FIRMWARE_PUP_PREFLIGHT |
                             V3KIOS_CAPABILITY_FIRMWARE_INVENTORY |
                             V3KIOS_CAPABILITY_SYSTEM_SHELL_PREFLIGHT;
    if (v3kios::runtime::IsFullCoreLinked())
        out_info->capabilities |= V3KIOS_CAPABILITY_SYSTEM_SOFTWARE;
    out_info->vita3kios_commit = VITA3KIOS_APP_COMMIT;
    out_info->upstream_commit = VITA3KIOS_UPSTREAM_COMMIT;
    out_info->upstream_version = "0.2.1";
    out_info->build_platform = VITA3KIOS_BUILD_PLATFORM;
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_get_lifecycle_state(
    const v3kios_core_handle_t handle, v3kios_lifecycle_state_v1* out_state) {
    if (out_state == nullptr) return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    *out_state = context->lifecycle;
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_run_bootstrap_self_test(
    const v3kios_core_handle_t handle) {
    if (Resolve(handle) == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
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

extern "C" v3kios_result_v1 v3kios_core_inspect_firmware_pup(
    const v3kios_core_handle_t handle, const char* pup_path, v3kios_pup_info_v1* out_info) {
    if (pup_path == nullptr || pup_path[0] == '\0' || out_info == nullptr ||
        out_info->struct_size < sizeof(v3kios_pup_info_v1)) return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    try {
        const std::lock_guard<std::mutex> lock{context->mutex};
        if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED ||
            context->lifecycle == V3KIOS_LIFECYCLE_BOOTING ||
            context->lifecycle == V3KIOS_LIFECYCLE_RUNNING) return V3KIOS_RESULT_INVALID_STATE;
        std::error_code error;
        const filesystem::path pupPath{pup_path};
        if (!filesystem::is_regular_file(pupPath, error) || error) return V3KIOS_RESULT_IO_ERROR;
        const std::uint64_t fileSize = filesystem::file_size(pupPath, error);
        if (error || fileSize < PupHeaderSize) return V3KIOS_RESULT_INVALID_FIRMWARE;
        std::ifstream stream{pupPath, std::ios::binary};
        std::array<unsigned char, PupHeaderSize> header{};
        if (!ReadAt(stream, 0, header.data(), header.size()) ||
            std::memcmp(header.data(), "SCEUF", 5) != 0) return V3KIOS_RESULT_INVALID_FIRMWARE;
        const std::uint32_t recordCount = ReadLittleEndian<std::uint32_t>(&header[0x18]);
        const std::uint32_t pupVersion = ReadLittleEndian<std::uint32_t>(&header[0x08]);
        const std::uint32_t firmwareVersion = ReadLittleEndian<std::uint32_t>(&header[0x10]);
        const std::uint32_t buildNumber = ReadLittleEndian<std::uint32_t>(&header[0x14]);
        if (recordCount == 0 || recordCount > MaximumPupRecords ||
            recordCount > (fileSize - PupHeaderSize) / PupRecordSize)
            return V3KIOS_RESULT_INVALID_FIRMWARE;
        const std::uint64_t recordTableEnd = PupHeaderSize +
            static_cast<std::uint64_t>(recordCount) * PupRecordSize;
        context->pupVersionText = "Unknown";
        bool foundVersionRecord = false;
        for (std::uint32_t index = 0; index < recordCount; ++index) {
            std::array<unsigned char, PupRecordSize> record{};
            const std::uint64_t recordOffset = PupHeaderSize +
                static_cast<std::uint64_t>(index) * PupRecordSize;
            if (!ReadAt(stream, recordOffset, record.data(), record.size()))
                return V3KIOS_RESULT_INVALID_FIRMWARE;
            const std::uint64_t type = ReadLittleEndian<std::uint64_t>(&record[0]);
            const std::uint64_t offset = ReadLittleEndian<std::uint64_t>(&record[8]);
            const std::uint64_t length = ReadLittleEndian<std::uint64_t>(&record[16]);
            if (!IsRangeInside(offset, length, fileSize) || offset < recordTableEnd)
                return V3KIOS_RESULT_INVALID_FIRMWARE;
            if (type == 0x100U) {
                if (length == 0 || length > 4096) return V3KIOS_RESULT_INVALID_FIRMWARE;
                foundVersionRecord = true;
                const auto textLength = static_cast<std::size_t>(std::min<std::uint64_t>(length, 256));
                std::string version(textLength, '\0');
                if (textLength != 0 &&
                    !ReadAt(stream, offset, reinterpret_cast<unsigned char*>(version.data()), textLength))
                    return V3KIOS_RESULT_INVALID_FIRMWARE;
                context->pupVersionText = TrimText(std::move(version));
            }
        }
        if (!foundVersionRecord) return V3KIOS_RESULT_INVALID_FIRMWARE;
        out_info->record_count = recordCount;
        out_info->pup_version = pupVersion;
        out_info->firmware_version = firmwareVersion;
        out_info->build_number = buildNumber;
        out_info->file_size = fileSize;
        out_info->version_text = context->pupVersionText.c_str();
        return V3KIOS_RESULT_OK;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" v3kios_result_v1 v3kios_core_inventory_firmware(
    const v3kios_core_handle_t handle, const char* vita_fs_root,
    v3kios_firmware_inventory_v1* out_inventory) {
    if (vita_fs_root == nullptr || vita_fs_root[0] == '\0' || out_inventory == nullptr ||
        out_inventory->struct_size < sizeof(v3kios_firmware_inventory_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    try {
        const std::lock_guard<std::mutex> lock{context->mutex};
        if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED ||
            context->lifecycle == V3KIOS_LIFECYCLE_BOOTING ||
            context->lifecycle == V3KIOS_LIFECYCLE_RUNNING) return V3KIOS_RESULT_INVALID_STATE;
        const auto resolvedRoot = ResolveVitaFsRoot(filesystem::path{vita_fs_root});
        if (!resolvedRoot) return V3KIOS_RESULT_INVALID_FIRMWARE;

        InventoryData next;
        next.state = V3KIOS_FIRMWARE_INVENTORIED;
        next.root = *resolvedRoot;
        next.detail = "Firmware partitions were inventoried, but the system shell is not ready.";
        std::uint64_t hash = 14695981039346656037ULL;
        std::vector<std::pair<std::string, std::uint64_t>> inventoryEntries;
        const std::array<std::pair<const char*, std::uint32_t>, 4> partitions{{
            {"os0", V3KIOS_FIRMWARE_PARTITION_OS0},
            {"pd0", V3KIOS_FIRMWARE_PARTITION_PD0},
            {"sa0", V3KIOS_FIRMWARE_PARTITION_SA0},
            {"vs0", V3KIOS_FIRMWARE_PARTITION_VS0},
        }};

        for (const auto& [name, mask] : partitions) {
            std::error_code error;
            const auto partitionRoot = next.root / name;
            if (!filesystem::is_directory(partitionRoot, error) || error) continue;
            next.partitionMask |= mask;
            filesystem::recursive_directory_iterator iterator{
                partitionRoot, filesystem::directory_options::skip_permission_denied, error};
            const filesystem::recursive_directory_iterator end;
            for (; !error && iterator != end; iterator.increment(error)) {
                if (next.fileCount >= MaximumInventoryEntries)
                    return V3KIOS_RESULT_INVALID_FIRMWARE;
                const auto symlinkStatus = iterator->symlink_status(error);
                if (error) break;
                if (filesystem::is_symlink(symlinkStatus)) return V3KIOS_RESULT_INVALID_FIRMWARE;
                if (!filesystem::is_regular_file(symlinkStatus)) continue;
                const auto size = iterator->file_size(error);
                if (error) break;
                if (size > std::numeric_limits<std::uint64_t>::max() - next.totalBytes)
                    return V3KIOS_RESULT_INVALID_FIRMWARE;
                ++next.fileCount;
                next.totalBytes += size;
                const auto relative = filesystem::relative(iterator->path(), next.root, error);
                if (error) break;
                const std::string relativeText = relative.generic_string();
                inventoryEntries.emplace_back(relativeText, size);
                if (Lowercase(iterator->path().filename().string()) == "sce_shell.self") {
                    const std::string preferred = "vs0/vsh/shell/sce_shell.self";
                    if (next.shellRelativePath.empty() || Lowercase(relativeText) == preferred)
                        next.shellRelativePath = relativeText;
                }
                const std::string lowerRelative = Lowercase(relativeText);
                if (next.versionText == "Unknown" &&
                    (lowerRelative == "vs0/vsh/etc/version.txt" ||
                     lowerRelative == "vs0/version.txt")) {
                    std::ifstream versionStream{iterator->path(), std::ios::binary};
                    std::string version(256, '\0');
                    versionStream.read(version.data(), static_cast<std::streamsize>(version.size()));
                    version.resize(static_cast<std::size_t>(versionStream.gcount()));
                    next.versionText = TrimText(std::move(version));
                }
            }
            if (error) return V3KIOS_RESULT_IO_ERROR;
        }

        std::sort(inventoryEntries.begin(), inventoryEntries.end());
        for (const auto& [relativePath, size] : inventoryEntries) {
            HashBytes(hash, relativePath);
            HashInteger(hash, size);
        }
        HashInteger(hash, next.partitionMask);
        HashBytes(hash, next.versionText);
        next.generationId = GenerationId(hash);
        const bool partitionsReady =
            (next.partitionMask & RequiredSystemPartitionMask) == RequiredSystemPartitionMask;
        const bool bootModulesReady =
            filesystem::is_regular_file(next.root / "os0/kd/bootimage.skprx") &&
            filesystem::is_regular_file(next.root / "os0/kd/sysmodule.skprx");
        const bool shellReady = !next.shellRelativePath.empty() &&
                                IsShellContainer(next.root / next.shellRelativePath);
        if (partitionsReady && bootModulesReady && shellReady) {
            next.state = V3KIOS_FIRMWARE_SHELL_READY;
            next.detail = "Required partitions, boot modules, and the authentic SceShell container are present.";
        } else if (!partitionsReady) {
            next.detail = "The os0 and vs0 partitions are required for System Software boot.";
        } else if (!bootModulesReady) {
            next.detail = "Required os0 bootimage.skprx or sysmodule.skprx is missing.";
        } else if (next.shellRelativePath.empty()) {
            next.detail = "No authentic sce_shell.self executable was found under vs0.";
        } else {
            next.detail = "The located sce_shell.self is not a readable SELF or ELF container.";
        }
        context->probeInventory = std::move(next);
        if (context->probeInventory.state == V3KIOS_FIRMWARE_SHELL_READY)
            context->inventory = context->probeInventory;
        context->lifecycle = context->inventory.state == V3KIOS_FIRMWARE_SHELL_READY
            ? V3KIOS_LIFECYCLE_FIRMWARE_READY : V3KIOS_LIFECYCLE_INITIALIZED;
        FillInventory(context->probeInventory, *out_inventory);
        return context->probeInventory.state == V3KIOS_FIRMWARE_SHELL_READY
            ? V3KIOS_RESULT_OK : V3KIOS_RESULT_FIRMWARE_NOT_READY;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" v3kios_result_v1 v3kios_core_boot_system_software(
    const v3kios_core_handle_t handle, const char* generation_id,
    v3kios_system_boot_report_v1* out_report) {
    if (generation_id == nullptr || generation_id[0] == '\0' || out_report == nullptr ||
        out_report->struct_size < sizeof(v3kios_system_boot_report_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    out_report->checkpoint = V3KIOS_BOOT_CHECKPOINT_REQUEST_VALIDATED;
    out_report->blocker = V3KIOS_BOOT_BLOCKER_NONE;
    out_report->generation_id = context->inventory.generationId.c_str();
    out_report->shell_relative_path = context->inventory.shellRelativePath.c_str();
    if (context->inventory.state != V3KIOS_FIRMWARE_SHELL_READY) {
        context->bootDetail = "A shell-ready firmware generation must be selected first.";
        out_report->blocker = V3KIOS_BOOT_BLOCKER_FIRMWARE_NOT_SELECTED;
        out_report->detail = context->bootDetail.c_str();
        return V3KIOS_RESULT_FIRMWARE_NOT_READY;
    }
    if (context->inventory.generationId != generation_id) {
        context->bootDetail = "The requested firmware generation does not match the active inventory.";
        out_report->blocker = V3KIOS_BOOT_BLOCKER_GENERATION_MISMATCH;
        out_report->detail = context->bootDetail.c_str();
        return V3KIOS_RESULT_INVALID_FIRMWARE;
    }
    out_report->checkpoint = V3KIOS_BOOT_CHECKPOINT_FIRMWARE_SELECTED;
    if ((context->inventory.partitionMask & RequiredSystemPartitionMask) !=
        RequiredSystemPartitionMask) {
        context->bootDetail = "The selected firmware no longer contains required partitions.";
        out_report->blocker = V3KIOS_BOOT_BLOCKER_REQUIRED_PARTITION_MISSING;
        out_report->detail = context->bootDetail.c_str();
        return V3KIOS_RESULT_FIRMWARE_NOT_READY;
    }
    out_report->checkpoint = V3KIOS_BOOT_CHECKPOINT_PARTITIONS_VERIFIED;
    const auto shellPath = context->inventory.root / context->inventory.shellRelativePath;
    if (!filesystem::is_regular_file(shellPath)) {
        context->bootDetail = "The inventoried SceShell executable is no longer present.";
        out_report->blocker = V3KIOS_BOOT_BLOCKER_SHELL_EXECUTABLE_MISSING;
        out_report->detail = context->bootDetail.c_str();
        return V3KIOS_RESULT_FIRMWARE_NOT_READY;
    }
    out_report->checkpoint = V3KIOS_BOOT_CHECKPOINT_SHELL_EXECUTABLE_LOCATED;
    if (!IsShellContainer(shellPath)) {
        context->bootDetail = "The SceShell executable failed its SELF container preflight.";
        out_report->blocker = V3KIOS_BOOT_BLOCKER_SHELL_CONTAINER_INVALID;
        out_report->detail = context->bootDetail.c_str();
        return V3KIOS_RESULT_INVALID_FIRMWARE;
    }
    const auto runtimeResult = v3kios::runtime::BootSystemSoftware(
        context->inventory.root, context->inventory.shellRelativePath);
    out_report->checkpoint = runtimeResult.checkpoint;
    out_report->blocker = runtimeResult.blocker;
    context->bootDetail = runtimeResult.detail;
    out_report->detail = context->bootDetail.c_str();
    return runtimeResult.result;
}

extern "C" const char* v3kios_result_description(const v3kios_result_v1 result) {
    switch (result) {
    case V3KIOS_RESULT_OK: return "Success";
    case V3KIOS_RESULT_INVALID_ARGUMENT: return "Invalid argument";
    case V3KIOS_RESULT_INVALID_HANDLE: return "Invalid core handle";
    case V3KIOS_RESULT_INVALID_STATE: return "Invalid lifecycle state";
    case V3KIOS_RESULT_INTERNAL_ERROR: return "Internal core error";
    case V3KIOS_RESULT_UNSUPPORTED: return "Capability is not implemented";
    case V3KIOS_RESULT_IO_ERROR: return "Filesystem operation failed";
    case V3KIOS_RESULT_INVALID_FIRMWARE: return "Firmware validation failed";
    case V3KIOS_RESULT_FIRMWARE_NOT_READY: return "Firmware is not ready for System Software boot";
    }
    return "Unknown result";
}

extern "C" const char* v3kios_boot_checkpoint_description(
    const v3kios_boot_checkpoint_v1 checkpoint) {
    switch (checkpoint) {
    case V3KIOS_BOOT_CHECKPOINT_NONE: return "Not started";
    case V3KIOS_BOOT_CHECKPOINT_REQUEST_VALIDATED: return "Boot request validated";
    case V3KIOS_BOOT_CHECKPOINT_FIRMWARE_SELECTED: return "Firmware generation selected";
    case V3KIOS_BOOT_CHECKPOINT_PARTITIONS_VERIFIED: return "Firmware partitions verified";
    case V3KIOS_BOOT_CHECKPOINT_SHELL_EXECUTABLE_LOCATED: return "SceShell executable located";
    case V3KIOS_BOOT_CHECKPOINT_SHELL_CONTAINER_VERIFIED: return "SceShell SELF container verified";
    case V3KIOS_BOOT_CHECKPOINT_CORE_INITIALIZED: return "Vita3K core initialized";
    case V3KIOS_BOOT_CHECKPOINT_MAIN_MODULE_LOADED: return "SceShell main module loaded";
    case V3KIOS_BOOT_CHECKPOINT_MAIN_THREAD_STARTED: return "SceShell main thread started";
    case V3KIOS_BOOT_CHECKPOINT_FIRST_GUEST_FRAME: return "First guest SceShell frame presented";
    }
    return "Unknown checkpoint";
}

extern "C" const char* v3kios_boot_blocker_description(const v3kios_boot_blocker_v1 blocker) {
    switch (blocker) {
    case V3KIOS_BOOT_BLOCKER_NONE: return "No blocker";
    case V3KIOS_BOOT_BLOCKER_FIRMWARE_NOT_SELECTED: return "No shell-ready firmware is selected";
    case V3KIOS_BOOT_BLOCKER_GENERATION_MISMATCH: return "Firmware generation mismatch";
    case V3KIOS_BOOT_BLOCKER_REQUIRED_PARTITION_MISSING: return "Required firmware partition is missing";
    case V3KIOS_BOOT_BLOCKER_SHELL_EXECUTABLE_MISSING: return "SceShell executable is missing";
    case V3KIOS_BOOT_BLOCKER_SHELL_CONTAINER_INVALID: return "SceShell SELF container is invalid";
    case V3KIOS_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED: return "Full Vita3K runtime is not linked into the iOS core target";
    case V3KIOS_BOOT_BLOCKER_CORE_INITIALIZATION_FAILED: return "Vita3K core initialization failed";
    case V3KIOS_BOOT_BLOCKER_MODULE_LOAD_FAILED: return "SceShell module load failed";
    case V3KIOS_BOOT_BLOCKER_MAIN_THREAD_FAILED: return "SceShell main thread failed to start";
    }
    return "Unknown blocker";
}
