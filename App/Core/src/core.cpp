#include <vita3kios/core.h>

#include <mem/allocator.h>

#include "runtime.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cmath>
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

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
#include <sys/proc.h>
#include <sys/sysctl.h>
#include <unistd.h>
#endif
#endif

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
constexpr std::uint64_t MaximumGameInventoryEntries = 250000;
constexpr std::uint32_t MaximumSfoEntries = 4096;
constexpr std::uint64_t MaximumSfoBytes = 4ULL * 1024ULL * 1024ULL;
constexpr std::uint32_t RequiredSystemPartitionMask =
    V3KIOS_FIRMWARE_PARTITION_OS0 | V3KIOS_FIRMWARE_PARTITION_VS0;
constexpr std::uint32_t SupportedInputMask =
    V3KIOS_INPUT_SELECT | V3KIOS_INPUT_START |
    V3KIOS_INPUT_UP | V3KIOS_INPUT_RIGHT | V3KIOS_INPUT_DOWN | V3KIOS_INPUT_LEFT |
    V3KIOS_INPUT_L | V3KIOS_INPUT_R |
    V3KIOS_INPUT_TRIANGLE | V3KIOS_INPUT_CIRCLE |
    V3KIOS_INPUT_CROSS | V3KIOS_INPUT_SQUARE | V3KIOS_INPUT_PS;

bool IsJITEnabled() {
#if defined(__APPLE__) && TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    kinfo_proc processInfo{};
    std::size_t processInfoSize = sizeof(processInfo);
    if (sysctl(mib, 4, &processInfo, &processInfoSize, nullptr, 0) != 0 ||
        processInfoSize < sizeof(processInfo)) {
        return false;
    }
    return (processInfo.kp_proc.p_flag & P_TRACED) != 0;
#else
    return true;
#endif
}

bool IsDirectGameFirmwareReady(const v3kios_firmware_state_v1 state) {
    return state == V3KIOS_FIRMWARE_DIRECT_GAME_READY ||
           state == V3KIOS_FIRMWARE_SHELL_READY;
}

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

struct GameData {
    v3kios_game_state_v1 state = V3KIOS_GAME_ABSENT;
    v3kios_direct_boot_blocker_v1 blocker = V3KIOS_DIRECT_BOOT_BLOCKER_GAME_NOT_SELECTED;
    std::uint32_t fileCount = 0;
    std::uint64_t totalBytes = 0;
    std::string generationId;
    std::string titleId;
    std::string title;
    std::string version;
    std::string category;
    std::string contentId;
    std::string ebootRelativePath;
    std::string iconRelativePath;
    std::string detail = "No game has been inventoried.";
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
    GameData activeGame;
    GameData probeGame;
    std::string pupVersionText = "Unknown";
    std::string bootDetail;
    std::string directBootDetail;
    v3kios_input_state_v1 inputState{};
    v3kios_display_surface_v1 displaySurface{};
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

bool IsExecutableContainer(const filesystem::path& executablePath) {
    std::ifstream stream{executablePath, std::ios::binary};
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

void FillGameInfo(const GameData& source, v3kios_game_info_v1& destination) {
    destination.state = source.state;
    destination.file_count = source.fileCount;
    destination.total_bytes = source.totalBytes;
    destination.generation_id = source.generationId.c_str();
    destination.title_id = source.titleId.c_str();
    destination.title = source.title.c_str();
    destination.version = source.version.c_str();
    destination.category = source.category.c_str();
    destination.content_id = source.contentId.c_str();
    destination.eboot_relative_path = source.ebootRelativePath.c_str();
    destination.icon_relative_path = source.iconRelativePath.c_str();
    destination.detail = source.detail.c_str();
}

bool IsGameRoot(const filesystem::path& root) {
    std::error_code error;
    return filesystem::is_regular_file(root / "eboot.bin", error) && !error &&
           filesystem::is_regular_file(root / "sce_sys/param.sfo", error) && !error;
}

std::optional<filesystem::path> ResolveGameRoot(const filesystem::path& selectedRoot) {
    std::error_code error;
    if (!filesystem::is_directory(selectedRoot, error) || error) return std::nullopt;
    const auto canonicalRoot = filesystem::weakly_canonical(selectedRoot, error);
    if (error) return std::nullopt;
    if (IsGameRoot(canonicalRoot)) return canonicalRoot;

    std::optional<filesystem::path> candidate;
    filesystem::directory_iterator iterator{canonicalRoot, error};
    const filesystem::directory_iterator end;
    for (; !error && iterator != end; iterator.increment(error)) {
        if (!iterator->is_directory(error) || error) continue;
        if (!IsGameRoot(iterator->path())) continue;
        if (candidate) return std::nullopt;
        candidate = filesystem::weakly_canonical(iterator->path(), error);
        if (error) return std::nullopt;
    }
    return error ? std::nullopt : candidate;
}

bool IsPathInside(const filesystem::path& child, const filesystem::path& parent) {
    std::error_code error;
    const auto relative = filesystem::relative(child, parent, error);
    if (error || relative.empty() || relative.is_absolute()) return false;
    return *relative.begin() != "..";
}

std::optional<std::vector<unsigned char>> ReadBoundedFile(const filesystem::path& path,
                                                          const std::uint64_t maximumBytes) {
    std::error_code error;
    const auto size = filesystem::file_size(path, error);
    if (error || size == 0 || size > maximumBytes ||
        size > static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max()))
        return std::nullopt;
    std::ifstream stream{path, std::ios::binary};
    std::vector<unsigned char> bytes(static_cast<std::size_t>(size));
    if (!stream.read(reinterpret_cast<char*>(bytes.data()),
                     static_cast<std::streamsize>(bytes.size()))) return std::nullopt;
    return bytes;
}

std::optional<std::string> ReadBoundedCString(const std::vector<unsigned char>& bytes,
                                               const std::size_t offset,
                                               const std::size_t end) {
    if (offset >= end || end > bytes.size()) return std::nullopt;
    auto terminator = std::find(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                                bytes.begin() + static_cast<std::ptrdiff_t>(end), 0U);
    if (terminator == bytes.begin() + static_cast<std::ptrdiff_t>(end)) return std::nullopt;
    return std::string{bytes.begin() + static_cast<std::ptrdiff_t>(offset), terminator};
}

std::optional<std::unordered_map<std::string, std::string>> ParseSfo(
    const filesystem::path& path) {
    const auto file = ReadBoundedFile(path, MaximumSfoBytes);
    if (!file || file->size() < 0x14 || (*file)[0] != 0 || (*file)[1] != 'P' ||
        (*file)[2] != 'S' || (*file)[3] != 'F') return std::nullopt;
    const auto* bytes = file->data();
    const std::uint32_t keyTable = ReadLittleEndian<std::uint32_t>(&bytes[0x08]);
    const std::uint32_t dataTable = ReadLittleEndian<std::uint32_t>(&bytes[0x0c]);
    const std::uint32_t entryCount = ReadLittleEndian<std::uint32_t>(&bytes[0x10]);
    const std::uint64_t indexEnd = 0x14ULL + static_cast<std::uint64_t>(entryCount) * 0x10ULL;
    if (entryCount == 0 || entryCount > MaximumSfoEntries || indexEnd > keyTable ||
        keyTable >= dataTable || dataTable > file->size()) return std::nullopt;

    std::unordered_map<std::string, std::string> values;
    for (std::uint32_t index = 0; index < entryCount; ++index) {
        const std::size_t entry = 0x14 + static_cast<std::size_t>(index) * 0x10;
        const std::uint16_t keyOffset = ReadLittleEndian<std::uint16_t>(&bytes[entry]);
        const std::uint16_t format = ReadLittleEndian<std::uint16_t>(&bytes[entry + 2]);
        const std::uint32_t length = ReadLittleEndian<std::uint32_t>(&bytes[entry + 4]);
        const std::uint32_t maximumLength = ReadLittleEndian<std::uint32_t>(&bytes[entry + 8]);
        const std::uint32_t dataOffset = ReadLittleEndian<std::uint32_t>(&bytes[entry + 12]);
        const std::uint64_t keyPosition = static_cast<std::uint64_t>(keyTable) + keyOffset;
        const std::uint64_t valuePosition = static_cast<std::uint64_t>(dataTable) + dataOffset;
        if (keyPosition >= dataTable || length > maximumLength ||
            !IsRangeInside(valuePosition, length, file->size())) return std::nullopt;
        const auto key = ReadBoundedCString(*file, static_cast<std::size_t>(keyPosition), dataTable);
        if (!key) return std::nullopt;
        if (format != 0x0004U && format != 0x0204U) continue;
        if (length == 0 || length > 4096) continue;
        const std::size_t valueEnd = static_cast<std::size_t>(valuePosition + length);
        const auto value = ReadBoundedCString(*file, static_cast<std::size_t>(valuePosition), valueEnd);
        if (value) values[*key] = TrimText(*value);
    }
    return values;
}

bool IsSafeTitleId(const std::string& titleId) {
    return titleId.size() >= 4 && titleId.size() <= 32 &&
           std::all_of(titleId.begin(), titleId.end(), [](const unsigned char value) {
               return std::isalnum(value) != 0 || value == '-' || value == '_';
           });
}

GameData InventoryGame(const filesystem::path& selectedRoot, v3kios_result_v1& result) {
    GameData next;
    result = V3KIOS_RESULT_INVALID_GAME;
    const auto resolvedRoot = ResolveGameRoot(selectedRoot);
    if (!resolvedRoot) {
        next.detail = "Select one extracted game directory containing eboot.bin and sce_sys/param.sfo.";
        return next;
    }
    next.root = *resolvedRoot;
    next.state = V3KIOS_GAME_INVENTORIED;
    next.blocker = V3KIOS_DIRECT_BOOT_BLOCKER_PARAM_SFO_INVALID;
    next.ebootRelativePath = "eboot.bin";
    next.iconRelativePath = filesystem::is_regular_file(next.root / "sce_sys/icon0.png")
        ? "sce_sys/icon0.png" : "";

    const auto sfo = ParseSfo(next.root / "sce_sys/param.sfo");
    if (!sfo) {
        next.detail = "sce_sys/param.sfo is malformed or exceeds the supported preflight limits.";
        return next;
    }
    const auto value = [&sfo](const char* key, const char* fallback = "") {
        const auto iterator = sfo->find(key);
        return iterator == sfo->end() ? std::string{fallback} : iterator->second;
    };
    next.titleId = value("TITLE_ID");
    next.title = value("TITLE", next.titleId.c_str());
    next.version = value("APP_VER", "Unknown");
    next.category = value("CATEGORY", "Unknown");
    next.contentId = value("CONTENT_ID");
    if (!IsSafeTitleId(next.titleId) || next.title.empty()) {
        next.detail = "param.sfo does not contain a valid TITLE_ID and TITLE.";
        return next;
    }

    std::vector<std::pair<std::string, std::uint64_t>> entries;
    std::error_code error;
    filesystem::recursive_directory_iterator iterator{
        next.root, filesystem::directory_options::skip_permission_denied, error};
    const filesystem::recursive_directory_iterator end;
    for (; !error && iterator != end; iterator.increment(error)) {
        if (next.fileCount >= MaximumGameInventoryEntries) {
            next.detail = "The selected game exceeds the supported file-count limit.";
            return next;
        }
        const auto status = iterator->symlink_status(error);
        if (error) break;
        if (filesystem::is_symlink(status)) {
            next.detail = "Game imports may not contain symbolic links.";
            return next;
        }
        if (!filesystem::is_regular_file(status)) continue;
        const auto size = iterator->file_size(error);
        if (error) break;
        if (size > std::numeric_limits<std::uint64_t>::max() - next.totalBytes) {
            next.detail = "The selected game size overflowed the inventory limit.";
            return next;
        }
        const auto relative = filesystem::relative(iterator->path(), next.root, error);
        if (error) break;
        ++next.fileCount;
        next.totalBytes += size;
        entries.emplace_back(relative.generic_string(), size);
    }
    if (error) {
        result = V3KIOS_RESULT_IO_ERROR;
        next.detail = "The selected game could not be read completely.";
        return next;
    }
    std::sort(entries.begin(), entries.end());
    std::uint64_t hash = 14695981039346656037ULL;
    HashBytes(hash, next.titleId);
    HashBytes(hash, next.version);
    for (const auto& [path, size] : entries) {
        HashBytes(hash, path);
        HashInteger(hash, size);
    }
    next.generationId = "game-" + next.titleId + "-" + GenerationId(hash);
    next.blocker = V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_CONTAINER_INVALID;
    if (!IsExecutableContainer(next.root / next.ebootRelativePath)) {
        next.detail = "eboot.bin is not a readable SELF or ELF container.";
        return next;
    }
    next.state = V3KIOS_GAME_BOOT_READY;
    next.blocker = V3KIOS_DIRECT_BOOT_BLOCKER_NONE;
    next.detail = "Extracted game metadata and the eboot SELF container are ready for Direct Game boot.";
    result = V3KIOS_RESULT_OK;
    return next;
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
    context->activeGame = {};
    context->probeGame = {};
    context->dataRoot.clear();
    context->pupVersionText = "Unknown";
    context->bootDetail.clear();
    context->directBootDetail.clear();
    context->inputState = {};
    if (context->displaySurface.metal_layer != nullptr)
        v3kios::runtime::DetachDisplaySurface();
    context->displaySurface = {};
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
                             V3KIOS_CAPABILITY_SYSTEM_SHELL_PREFLIGHT |
                             V3KIOS_CAPABILITY_GAME_INVENTORY |
                             V3KIOS_CAPABILITY_DIRECT_GAME_PREFLIGHT |
                             V3KIOS_CAPABILITY_INPUT_STATE |
                             V3KIOS_CAPABILITY_METRICS_SNAPSHOT |
                             V3KIOS_CAPABILITY_DISPLAY_SURFACE;
    if (v3kios::runtime::IsFullCoreLinked())
        out_info->capabilities |= V3KIOS_CAPABILITY_DIRECT_GAME |
                                  V3KIOS_CAPABILITY_FIRMWARE_PUP_INSTALL;
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

extern "C" v3kios_result_v1 v3kios_core_install_firmware_pup(
    const v3kios_core_handle_t handle, const char* pup_path, const char* vita_fs_root) {
    if (pup_path == nullptr || pup_path[0] == '\0' || vita_fs_root == nullptr ||
        vita_fs_root[0] == '\0') return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    try {
        const filesystem::path pupPath{pup_path};
        const filesystem::path vitaFsRoot{vita_fs_root};
        {
            const std::lock_guard<std::mutex> lock{context->mutex};
            if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED ||
                context->lifecycle == V3KIOS_LIFECYCLE_BOOTING ||
                context->lifecycle == V3KIOS_LIFECYCLE_RUNNING)
                return V3KIOS_RESULT_INVALID_STATE;
            if (!IsPathInside(vitaFsRoot, context->dataRoot))
                return V3KIOS_RESULT_INVALID_FIRMWARE;
            std::error_code error;
            if (!filesystem::is_regular_file(pupPath, error) || error)
                return V3KIOS_RESULT_IO_ERROR;
        }
        if (!v3kios::runtime::IsFullCoreLinked()) return V3KIOS_RESULT_UNSUPPORTED;
        return v3kios::runtime::InstallFirmwarePup(pupPath, vitaFsRoot)
            ? V3KIOS_RESULT_OK : V3KIOS_RESULT_INVALID_FIRMWARE;
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
        const bool directGameReady = partitionsReady && next.fileCount > 0;
        const bool bootModulesReady =
            filesystem::is_regular_file(next.root / "os0/kd/bootimage.skprx") &&
            filesystem::is_regular_file(next.root / "os0/kd/sysmodule.skprx");
        const bool shellReady = !next.shellRelativePath.empty() &&
                                IsExecutableContainer(next.root / next.shellRelativePath);
        if (partitionsReady && bootModulesReady && shellReady) {
            next.state = V3KIOS_FIRMWARE_SHELL_READY;
            next.detail = "Firmware is ready for Direct Game and contains the System Software shell prerequisites.";
        } else if (directGameReady) {
            next.state = V3KIOS_FIRMWARE_DIRECT_GAME_READY;
            if (!bootModulesReady) {
                next.detail = "Firmware is ready for Direct Game. System Software bootimage.skprx or sysmodule.skprx is unavailable.";
            } else if (next.shellRelativePath.empty()) {
                next.detail = "Firmware is ready for Direct Game. No authentic sce_shell.self was found for System Software.";
            } else {
                next.detail = "Firmware is ready for Direct Game. The System Software shell container is not readable.";
            }
        } else if (!partitionsReady) {
            next.detail = "The os0 and vs0 partitions are required for a firmware-backed Direct Game session.";
        } else {
            next.detail = "The firmware partitions do not contain usable Direct Game support files.";
        }
        context->probeInventory = std::move(next);
        if (IsDirectGameFirmwareReady(context->probeInventory.state))
            context->inventory = context->probeInventory;
        context->lifecycle = IsDirectGameFirmwareReady(context->inventory.state)
            ? V3KIOS_LIFECYCLE_FIRMWARE_READY : V3KIOS_LIFECYCLE_INITIALIZED;
        FillInventory(context->probeInventory, *out_inventory);
        return IsDirectGameFirmwareReady(context->probeInventory.state)
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
    if (!IsExecutableContainer(shellPath)) {
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

extern "C" v3kios_result_v1 v3kios_core_inventory_game(
    const v3kios_core_handle_t handle, const char* game_root,
    v3kios_game_info_v1* out_info) {
    if (game_root == nullptr || game_root[0] == '\0' || out_info == nullptr ||
        out_info->struct_size < sizeof(v3kios_game_info_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    try {
        const std::lock_guard<std::mutex> lock{context->mutex};
        if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED ||
            context->lifecycle == V3KIOS_LIFECYCLE_BOOTING ||
            context->lifecycle == V3KIOS_LIFECYCLE_RUNNING)
            return V3KIOS_RESULT_INVALID_STATE;
        v3kios_result_v1 result = V3KIOS_RESULT_INVALID_GAME;
        context->probeGame = InventoryGame(filesystem::path{game_root}, result);
        FillGameInfo(context->probeGame, *out_info);
        return result;
    } catch (...) {
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" v3kios_result_v1 v3kios_core_boot_direct_game(
    const v3kios_core_handle_t handle, const char* game_root, const char* generation_id,
    v3kios_direct_boot_report_v1* out_report) {
    if (game_root == nullptr || game_root[0] == '\0' || generation_id == nullptr ||
        generation_id[0] == '\0' || out_report == nullptr ||
        out_report->struct_size < sizeof(v3kios_direct_boot_report_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    try {
        const std::lock_guard<std::mutex> lock{context->mutex};
        out_report->checkpoint = V3KIOS_DIRECT_BOOT_CHECKPOINT_REQUEST_VALIDATED;
        out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_NONE;
        out_report->generation_id = "";
        out_report->title_id = "";
        if (context->lifecycle == V3KIOS_LIFECYCLE_RUNNING &&
            context->activeGame.generationId == generation_id) {
            out_report->checkpoint = V3KIOS_DIRECT_BOOT_CHECKPOINT_MAIN_THREAD_STARTED;
            out_report->generation_id = context->activeGame.generationId.c_str();
            out_report->title_id = context->activeGame.titleId.c_str();
            context->directBootDetail =
                "The selected Vita3K guest session is already running.";
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_OK;
        }
        if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED ||
            context->lifecycle == V3KIOS_LIFECYCLE_BOOTING ||
            context->lifecycle == V3KIOS_LIFECYCLE_RUNNING) {
            context->directBootDetail = "The core lifecycle is not ready for a Direct Game boot request.";
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_INVALID_STATE;
        }

        v3kios_result_v1 inventoryResult = V3KIOS_RESULT_INVALID_GAME;
        context->probeGame = InventoryGame(filesystem::path{game_root}, inventoryResult);
        out_report->generation_id = context->probeGame.generationId.c_str();
        out_report->title_id = context->probeGame.titleId.c_str();
        if (inventoryResult != V3KIOS_RESULT_OK ||
            context->probeGame.state != V3KIOS_GAME_BOOT_READY) {
            context->directBootDetail = context->probeGame.detail;
            out_report->blocker = context->probeGame.blocker;
            out_report->detail = context->directBootDetail.c_str();
            return inventoryResult == V3KIOS_RESULT_IO_ERROR
                ? inventoryResult : V3KIOS_RESULT_GAME_NOT_READY;
        }
        if (!IsPathInside(context->probeGame.root, context->dataRoot)) {
            context->directBootDetail = "Direct Game boot accepts only app-owned imported game generations.";
            out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_GAME_NOT_SELECTED;
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_INVALID_GAME;
        }
        if (context->probeGame.generationId != generation_id) {
            context->directBootDetail = "The requested game generation does not match the imported content.";
            out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_GENERATION_MISMATCH;
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_INVALID_GAME;
        }
        out_report->checkpoint = V3KIOS_DIRECT_BOOT_CHECKPOINT_GAME_CONTENT_VERIFIED;
        const auto eboot = context->probeGame.root / context->probeGame.ebootRelativePath;
        if (!filesystem::is_regular_file(eboot)) {
            context->directBootDetail = "The imported eboot.bin is missing.";
            out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_MISSING;
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_GAME_NOT_READY;
        }
        if (!IsExecutableContainer(eboot)) {
            context->directBootDetail = "The imported eboot.bin failed its SELF container preflight.";
            out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_CONTAINER_INVALID;
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_INVALID_GAME;
        }
        out_report->checkpoint = V3KIOS_DIRECT_BOOT_CHECKPOINT_EBOOT_CONTAINER_VERIFIED;
        if (!IsJITEnabled()) {
            context->directBootDetail =
                "JIT is not enabled for this process. Enable JIT with StikDebug, then reopen the game.";
            out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_JIT_NOT_ENABLED;
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_GAME_NOT_READY;
        }
        if (context->displaySurface.metal_layer == nullptr ||
            context->displaySurface.drawable_width == 0 ||
            context->displaySurface.drawable_height == 0) {
            context->directBootDetail =
                "The native CAMetalLayer display surface must be attached before Direct Game boot.";
            out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_DISPLAY_SURFACE_MISSING;
            out_report->detail = context->directBootDetail.c_str();
            return V3KIOS_RESULT_GAME_NOT_READY;
        }
        context->activeGame = context->probeGame;
        context->lifecycle = V3KIOS_LIFECYCLE_BOOTING;
        const auto runtimeResult = v3kios::runtime::BootDirectGame(
            context->activeGame.root, context->activeGame.ebootRelativePath,
            context->activeGame.titleId, context->dataRoot, context->inventory.root);
        out_report->checkpoint = runtimeResult.checkpoint;
        out_report->blocker = runtimeResult.blocker;
        context->directBootDetail = runtimeResult.detail;
        out_report->detail = context->directBootDetail.c_str();
        context->lifecycle = runtimeResult.result == V3KIOS_RESULT_OK
            ? V3KIOS_LIFECYCLE_RUNNING
            : (IsDirectGameFirmwareReady(context->inventory.state)
                ? V3KIOS_LIFECYCLE_FIRMWARE_READY : V3KIOS_LIFECYCLE_INITIALIZED);
        return runtimeResult.result;
    } catch (const std::exception& exception) {
        const std::lock_guard<std::mutex> lock{context->mutex};
        context->lifecycle = IsDirectGameFirmwareReady(context->inventory.state)
            ? V3KIOS_LIFECYCLE_FIRMWARE_READY : V3KIOS_LIFECYCLE_INITIALIZED;
        context->directBootDetail =
            std::string{"Vita3K raised an exception during Direct Game boot: "} + exception.what();
        out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_CORE_INITIALIZATION_FAILED;
        out_report->detail = context->directBootDetail.c_str();
        return V3KIOS_RESULT_INTERNAL_ERROR;
    } catch (...) {
        const std::lock_guard<std::mutex> lock{context->mutex};
        context->lifecycle = IsDirectGameFirmwareReady(context->inventory.state)
            ? V3KIOS_LIFECYCLE_FIRMWARE_READY : V3KIOS_LIFECYCLE_INITIALIZED;
        context->directBootDetail =
            "Vita3K raised a non-standard exception during Direct Game boot.";
        out_report->blocker = V3KIOS_DIRECT_BOOT_BLOCKER_CORE_INITIALIZATION_FAILED;
        out_report->detail = context->directBootDetail.c_str();
        return V3KIOS_RESULT_INTERNAL_ERROR;
    }
}

extern "C" int v3kios_core_is_jit_enabled(void) {
    return IsJITEnabled() ? 1 : 0;
}

extern "C" v3kios_result_v1 v3kios_core_set_input_state(
    const v3kios_core_handle_t handle, const v3kios_input_state_v1* input) {
    if (input == nullptr || input->struct_size < sizeof(v3kios_input_state_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    if ((input->buttons & ~SupportedInputMask) != 0 ||
        !std::isfinite(input->left_x) || !std::isfinite(input->left_y) ||
        !std::isfinite(input->right_x) || !std::isfinite(input->right_y) ||
        std::abs(input->left_x) > 1.0F || std::abs(input->left_y) > 1.0F ||
        std::abs(input->right_x) > 1.0F || std::abs(input->right_y) > 1.0F)
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    const std::lock_guard<std::mutex> lock{context->mutex};
    context->inputState = *input;
    if (context->lifecycle == V3KIOS_LIFECYCLE_RUNNING)
        v3kios::runtime::SetInputState(*input);
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_get_metrics(
    const v3kios_core_handle_t handle, v3kios_metrics_v1* out_metrics) {
    if (out_metrics == nullptr || out_metrics->struct_size < sizeof(v3kios_metrics_v1))
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED) return V3KIOS_RESULT_INVALID_STATE;
    v3kios::runtime::GetMetrics(*out_metrics);
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_attach_display_surface(
    const v3kios_core_handle_t handle, const v3kios_display_surface_v1* surface) {
    if (surface == nullptr || surface->struct_size < sizeof(v3kios_display_surface_v1) ||
        surface->metal_layer == nullptr || surface->drawable_width == 0 ||
        surface->drawable_height == 0 || !std::isfinite(surface->scale) ||
        surface->scale <= 0.0F)
        return V3KIOS_RESULT_INVALID_ARGUMENT;
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED)
        return V3KIOS_RESULT_INVALID_STATE;
    context->displaySurface = *surface;
    v3kios::runtime::AttachDisplaySurface(context->displaySurface);
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_detach_display_surface(
    const v3kios_core_handle_t handle) {
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    if (context->lifecycle == V3KIOS_LIFECYCLE_CREATED)
        return V3KIOS_RESULT_INVALID_STATE;
    if (context->displaySurface.metal_layer != nullptr)
        v3kios::runtime::DetachDisplaySurface();
    context->displaySurface = {};
    return V3KIOS_RESULT_OK;
}

extern "C" v3kios_result_v1 v3kios_core_stop_session(const v3kios_core_handle_t handle) {
    auto* context = Resolve(handle);
    if (context == nullptr) return V3KIOS_RESULT_INVALID_HANDLE;
    const std::lock_guard<std::mutex> lock{context->mutex};
    if (context->lifecycle != V3KIOS_LIFECYCLE_RUNNING &&
        context->lifecycle != V3KIOS_LIFECYCLE_BOOTING)
        return V3KIOS_RESULT_INVALID_STATE;
    v3kios::runtime::StopSession();
    context->inputState = {};
    context->lifecycle = IsDirectGameFirmwareReady(context->inventory.state)
        ? V3KIOS_LIFECYCLE_FIRMWARE_READY : V3KIOS_LIFECYCLE_INITIALIZED;
    return V3KIOS_RESULT_OK;
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
    case V3KIOS_RESULT_FIRMWARE_NOT_READY: return "PlayStation Vita firmware is not ready";
    case V3KIOS_RESULT_INVALID_GAME: return "Game validation failed";
    case V3KIOS_RESULT_GAME_NOT_READY: return "Game is not ready for Direct Game boot";
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

extern "C" const char* v3kios_direct_boot_checkpoint_description(
    const v3kios_direct_boot_checkpoint_v1 checkpoint) {
    switch (checkpoint) {
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_NONE: return "Not started";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_REQUEST_VALIDATED: return "Direct Game request validated";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_GAME_CONTENT_VERIFIED: return "Imported game content verified";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_EBOOT_CONTAINER_VERIFIED: return "Game eboot SELF container verified";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_CORE_INITIALIZED: return "Vita3K game runtime initialized";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_MAIN_MODULE_LOADED: return "Game main module loaded";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_MAIN_THREAD_STARTED: return "Game main thread started";
    case V3KIOS_DIRECT_BOOT_CHECKPOINT_FIRST_GUEST_FRAME: return "First guest game frame presented";
    }
    return "Unknown Direct Game checkpoint";
}

extern "C" const char* v3kios_direct_boot_blocker_description(
    const v3kios_direct_boot_blocker_v1 blocker) {
    switch (blocker) {
    case V3KIOS_DIRECT_BOOT_BLOCKER_NONE: return "No blocker";
    case V3KIOS_DIRECT_BOOT_BLOCKER_GAME_NOT_SELECTED: return "No app-owned game generation is selected";
    case V3KIOS_DIRECT_BOOT_BLOCKER_GENERATION_MISMATCH: return "Game generation mismatch";
    case V3KIOS_DIRECT_BOOT_BLOCKER_PARAM_SFO_INVALID: return "Game param.sfo is invalid";
    case V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_MISSING: return "Game eboot.bin is missing";
    case V3KIOS_DIRECT_BOOT_BLOCKER_EBOOT_CONTAINER_INVALID: return "Game eboot SELF container is invalid";
    case V3KIOS_DIRECT_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED: return "Full Vita3K runtime is not linked into the iOS core target";
    case V3KIOS_DIRECT_BOOT_BLOCKER_CORE_INITIALIZATION_FAILED: return "Vita3K game runtime initialization failed";
    case V3KIOS_DIRECT_BOOT_BLOCKER_MODULE_LOAD_FAILED: return "Game main module load failed";
    case V3KIOS_DIRECT_BOOT_BLOCKER_MAIN_THREAD_FAILED: return "Game main thread failed to start";
    case V3KIOS_DIRECT_BOOT_BLOCKER_RENDERER_FAILED: return "Game renderer initialization failed";
    case V3KIOS_DIRECT_BOOT_BLOCKER_DISPLAY_SURFACE_MISSING: return "Native game display surface is not attached";
    case V3KIOS_DIRECT_BOOT_BLOCKER_JIT_NOT_ENABLED: return "JIT is not enabled for this process";
    case V3KIOS_DIRECT_BOOT_BLOCKER_FIRMWARE_NOT_READY: return "PlayStation Vita firmware is not installed";
    }
    return "Unknown Direct Game blocker";
}
