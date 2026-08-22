#include <vita3kios/core.h>

#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace {

namespace filesystem = std::filesystem;

template <typename T>
void WriteLittleEndian(std::vector<unsigned char>& bytes, const std::size_t offset, T value) {
    for (std::size_t index = 0; index < sizeof(T); ++index) {
        bytes[offset + index] = static_cast<unsigned char>((value >> (index * 8U)) & 0xffU);
    }
}

void WriteFile(const filesystem::path& path, const std::vector<unsigned char>& bytes) {
    filesystem::create_directories(path.parent_path());
    std::ofstream stream{path, std::ios::binary};
    stream.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    assert(stream.good());
}

filesystem::path MakeFixtureRoot() {
    const auto unique = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto root = filesystem::temp_directory_path() /
                      ("vita3kios-core-tests-" + std::to_string(unique));
    filesystem::create_directories(root);
    return root;
}

filesystem::path MakeSyntheticPup(const filesystem::path& root) {
    constexpr std::size_t headerSize = 0x80;
    constexpr std::size_t recordSize = 0x20;
    const std::string version = "3.74\n";
    std::vector<unsigned char> bytes(headerSize + recordSize + version.size(), 0);
    std::copy_n(reinterpret_cast<const unsigned char*>("SCEUF"), 5, bytes.begin());
    WriteLittleEndian<std::uint32_t>(bytes, 0x08, 1);
    WriteLittleEndian<std::uint32_t>(bytes, 0x10, 0x03740000);
    WriteLittleEndian<std::uint32_t>(bytes, 0x14, 1234);
    WriteLittleEndian<std::uint32_t>(bytes, 0x18, 1);
    WriteLittleEndian<std::uint64_t>(bytes, headerSize, 0x100);
    WriteLittleEndian<std::uint64_t>(bytes, headerSize + 8, headerSize + recordSize);
    WriteLittleEndian<std::uint64_t>(bytes, headerSize + 16, version.size());
    std::copy(version.begin(), version.end(), bytes.begin() + headerSize + recordSize);
    const auto path = root / "synthetic.PUP";
    WriteFile(path, bytes);
    return path;
}

filesystem::path MakeOutOfRangePup(const filesystem::path& root) {
    constexpr std::size_t headerSize = 0x80;
    constexpr std::size_t recordSize = 0x20;
    std::vector<unsigned char> bytes(headerSize + recordSize, 0);
    std::copy_n(reinterpret_cast<const unsigned char*>("SCEUF"), 5, bytes.begin());
    WriteLittleEndian<std::uint32_t>(bytes, 0x18, 1);
    WriteLittleEndian<std::uint64_t>(bytes, headerSize, 0x100);
    WriteLittleEndian<std::uint64_t>(bytes, headerSize + 8, bytes.size() + 1);
    WriteLittleEndian<std::uint64_t>(bytes, headerSize + 16, 32);
    const auto path = root / "out-of-range.PUP";
    WriteFile(path, bytes);
    return path;
}

filesystem::path MakeSyntheticVitaFs(const filesystem::path& root) {
    const auto vita = root / "vita";
    const std::vector<unsigned char> container{'S', 'C', 'E', 0, 1, 2, 3, 4};
    WriteFile(vita / "os0/kd/bootimage.skprx", container);
    WriteFile(vita / "os0/kd/sysmodule.skprx", container);
    WriteFile(vita / "vs0/vsh/shell/sce_shell.self", container);
    WriteFile(vita / "vs0/vsh/etc/version.txt", {'3', '.', '7', '4', '\n'});
    filesystem::create_directories(vita / "sa0");
    filesystem::create_directories(vita / "pd0");
    return vita;
}

filesystem::path MakeSyntheticGame(const filesystem::path& root) {
    const auto game = root / "Games/Generations/synthetic-game";
    const std::array<std::pair<std::string, std::string>, 5> fields{{
        {"TITLE_ID", "TEST00001"},
        {"TITLE", "Synthetic Vita Homebrew"},
        {"APP_VER", "01.00"},
        {"CATEGORY", "gd"},
        {"CONTENT_ID", "TEST-CONTENT-ID"},
    }};
    constexpr std::size_t headerSize = 0x14;
    constexpr std::size_t entrySize = 0x10;
    std::string keys;
    std::string values;
    std::array<std::uint16_t, fields.size()> keyOffsets{};
    std::array<std::uint32_t, fields.size()> valueOffsets{};
    for (std::size_t index = 0; index < fields.size(); ++index) {
        keyOffsets[index] = static_cast<std::uint16_t>(keys.size());
        valueOffsets[index] = static_cast<std::uint32_t>(values.size());
        keys += fields[index].first;
        keys.push_back('\0');
        values += fields[index].second;
        values.push_back('\0');
    }
    const std::size_t keyTable = headerSize + entrySize * fields.size();
    const std::size_t dataTable = (keyTable + keys.size() + 3U) & ~3U;
    std::vector<unsigned char> sfo(dataTable + values.size(), 0);
    sfo[0] = 0;
    sfo[1] = 'P';
    sfo[2] = 'S';
    sfo[3] = 'F';
    WriteLittleEndian<std::uint32_t>(sfo, 0x04, 0x00000101);
    WriteLittleEndian<std::uint32_t>(sfo, 0x08, keyTable);
    WriteLittleEndian<std::uint32_t>(sfo, 0x0c, dataTable);
    WriteLittleEndian<std::uint32_t>(sfo, 0x10, fields.size());
    for (std::size_t index = 0; index < fields.size(); ++index) {
        const std::size_t entry = headerSize + entrySize * index;
        const auto length = static_cast<std::uint32_t>(fields[index].second.size() + 1);
        WriteLittleEndian<std::uint16_t>(sfo, entry, keyOffsets[index]);
        WriteLittleEndian<std::uint16_t>(sfo, entry + 2, 0x0204);
        WriteLittleEndian<std::uint32_t>(sfo, entry + 4, length);
        WriteLittleEndian<std::uint32_t>(sfo, entry + 8, length);
        WriteLittleEndian<std::uint32_t>(sfo, entry + 12, valueOffsets[index]);
    }
    std::copy(keys.begin(), keys.end(), sfo.begin() + static_cast<std::ptrdiff_t>(keyTable));
    std::copy(values.begin(), values.end(), sfo.begin() + static_cast<std::ptrdiff_t>(dataTable));
    WriteFile(game / "sce_sys/param.sfo", sfo);
    WriteFile(game / "sce_sys/icon0.png", {0x89, 'P', 'N', 'G'});
    WriteFile(game / "eboot.bin", {'S', 'C', 'E', 0, 1, 2, 3, 4});
    return game;
}

}  // namespace

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
    assert((info.capabilities & V3KIOS_CAPABILITY_FIRMWARE_INVENTORY) != 0);
    assert((info.capabilities & V3KIOS_CAPABILITY_GAME_INVENTORY) != 0);
    assert((info.capabilities & V3KIOS_CAPABILITY_DIRECT_GAME_PREFLIGHT) != 0);
    assert((info.capabilities & V3KIOS_CAPABILITY_DIRECT_GAME) == 0);
    assert((info.capabilities & V3KIOS_CAPABILITY_SYSTEM_SOFTWARE) == 0);
    assert(v3kios_core_run_bootstrap_self_test(handle) == V3KIOS_RESULT_OK);

    v3kios_firmware_inventory_v1 inventory{};
    inventory.struct_size = sizeof(inventory);
    assert(v3kios_core_inventory_firmware(handle, "/missing", &inventory) ==
           V3KIOS_RESULT_INVALID_STATE);

    const auto fixtureRoot = MakeFixtureRoot();
    const auto vitaRoot = MakeSyntheticVitaFs(fixtureRoot);
    const auto gameRoot = MakeSyntheticGame(fixtureRoot / "data");
    assert(v3kios_core_initialize(handle, (fixtureRoot / "data").c_str()) == V3KIOS_RESULT_OK);
    assert(v3kios_core_initialize(handle, (fixtureRoot / "data").c_str()) ==
           V3KIOS_RESULT_INVALID_STATE);

    v3kios_pup_info_v1 pupInfo{};
    pupInfo.struct_size = sizeof(pupInfo);
    const auto pupPath = MakeSyntheticPup(fixtureRoot);
    assert(v3kios_core_inspect_firmware_pup(handle, pupPath.c_str(), &pupInfo) ==
           V3KIOS_RESULT_OK);
    assert(pupInfo.record_count == 1);
    assert(std::string{pupInfo.version_text} == "3.74");
    const auto invalidPupPath = MakeOutOfRangePup(fixtureRoot);
    assert(v3kios_core_inspect_firmware_pup(handle, invalidPupPath.c_str(), &pupInfo) ==
           V3KIOS_RESULT_INVALID_FIRMWARE);

    assert(v3kios_core_inventory_firmware(handle, vitaRoot.c_str(), &inventory) ==
           V3KIOS_RESULT_OK);
    assert(inventory.state == V3KIOS_FIRMWARE_SHELL_READY);
    assert(inventory.partition_mask == 0x0fU);
    assert(std::string{inventory.version_text} == "3.74");
    assert(std::string{inventory.shell_relative_path} == "vs0/vsh/shell/sce_shell.self");
    const std::string generationId{inventory.generation_id};

    const auto incompleteRoot = fixtureRoot / "incomplete";
    filesystem::create_directories(incompleteRoot / "vs0");
    assert(v3kios_core_inventory_firmware(handle, incompleteRoot.c_str(), &inventory) ==
           V3KIOS_RESULT_FIRMWARE_NOT_READY);
    assert(inventory.state == V3KIOS_FIRMWARE_INVENTORIED);

    v3kios_system_boot_report_v1 bootReport{};
    bootReport.struct_size = sizeof(bootReport);
    assert(v3kios_core_boot_system_software(handle, "wrong-generation", &bootReport) ==
           V3KIOS_RESULT_INVALID_FIRMWARE);
    assert(bootReport.blocker == V3KIOS_BOOT_BLOCKER_GENERATION_MISMATCH);
    assert(v3kios_core_boot_system_software(handle, generationId.c_str(), &bootReport) ==
           V3KIOS_RESULT_UNSUPPORTED);
    assert(bootReport.checkpoint == V3KIOS_BOOT_CHECKPOINT_SHELL_CONTAINER_VERIFIED);
    assert(bootReport.blocker == V3KIOS_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED);

    v3kios_game_info_v1 gameInfo{};
    gameInfo.struct_size = sizeof(gameInfo);
    assert(v3kios_core_inventory_game(handle, gameRoot.c_str(), &gameInfo) ==
           V3KIOS_RESULT_OK);
    assert(gameInfo.state == V3KIOS_GAME_BOOT_READY);
    assert(std::string{gameInfo.title_id} == "TEST00001");
    assert(std::string{gameInfo.title} == "Synthetic Vita Homebrew");
    assert(std::string{gameInfo.eboot_relative_path} == "eboot.bin");
    const std::string gameGeneration{gameInfo.generation_id};

    v3kios_direct_boot_report_v1 directReport{};
    directReport.struct_size = sizeof(directReport);
    assert(v3kios_core_boot_direct_game(handle, (fixtureRoot / "missing-game").c_str(),
                                        "missing", &directReport) ==
           V3KIOS_RESULT_GAME_NOT_READY);
    assert(directReport.blocker == V3KIOS_DIRECT_BOOT_BLOCKER_GAME_NOT_SELECTED);
    assert(v3kios_core_boot_direct_game(handle, gameRoot.c_str(), "wrong", &directReport) ==
           V3KIOS_RESULT_INVALID_GAME);
    assert(directReport.blocker == V3KIOS_DIRECT_BOOT_BLOCKER_GENERATION_MISMATCH);
    assert(v3kios_core_boot_direct_game(handle, gameRoot.c_str(), gameGeneration.c_str(),
                                        &directReport) == V3KIOS_RESULT_GAME_NOT_READY);
    assert(directReport.checkpoint == V3KIOS_DIRECT_BOOT_CHECKPOINT_EBOOT_CONTAINER_VERIFIED);
    assert(directReport.blocker == V3KIOS_DIRECT_BOOT_BLOCKER_DISPLAY_SURFACE_MISSING);
    v3kios_display_surface_v1 display{};
    display.struct_size = sizeof(display);
    display.metal_layer = reinterpret_cast<void*>(static_cast<std::uintptr_t>(1));
    display.drawable_width = 1920;
    display.drawable_height = 1088;
    display.scale = 2.0F;
    assert(v3kios_core_attach_display_surface(handle, &display) == V3KIOS_RESULT_OK);
    assert(v3kios_core_boot_direct_game(handle, gameRoot.c_str(), gameGeneration.c_str(),
                                        &directReport) == V3KIOS_RESULT_UNSUPPORTED);
    assert(directReport.checkpoint == V3KIOS_DIRECT_BOOT_CHECKPOINT_EBOOT_CONTAINER_VERIFIED);
    assert(directReport.blocker == V3KIOS_DIRECT_BOOT_BLOCKER_UPSTREAM_CORE_NOT_LINKED);

    v3kios_input_state_v1 input{};
    input.struct_size = sizeof(input);
    input.left_x = 2.0F;
    assert(v3kios_core_set_input_state(handle, &input) == V3KIOS_RESULT_INVALID_ARGUMENT);
    input.left_x = 0.5F;
    input.buttons = 1U << 31;
    assert(v3kios_core_set_input_state(handle, &input) == V3KIOS_RESULT_INVALID_ARGUMENT);
    input.buttons = V3KIOS_INPUT_L | V3KIOS_INPUT_CROSS | V3KIOS_INPUT_PS;
    assert(v3kios_core_set_input_state(handle, &input) == V3KIOS_RESULT_OK);
    v3kios_metrics_v1 metrics{};
    metrics.struct_size = sizeof(metrics);
    assert(v3kios_core_get_metrics(handle, &metrics) == V3KIOS_RESULT_OK);
    assert(metrics.validity_mask == 0);
    assert(v3kios_core_stop_session(handle) == V3KIOS_RESULT_INVALID_STATE);
    assert(v3kios_core_detach_display_surface(handle) == V3KIOS_RESULT_OK);

    assert(v3kios_core_shutdown(handle) == V3KIOS_RESULT_OK);
    assert(v3kios_core_shutdown(handle) == V3KIOS_RESULT_INVALID_STATE);
    assert(v3kios_core_destroy(handle) == V3KIOS_RESULT_OK);
    assert(v3kios_core_destroy(handle) == V3KIOS_RESULT_INVALID_HANDLE);
    filesystem::remove_all(fixtureRoot);
    return 0;
}
