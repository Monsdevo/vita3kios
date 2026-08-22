#include <vita3kios/core.h>

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
    assert((info.capabilities & V3KIOS_CAPABILITY_SYSTEM_SOFTWARE) == 0);
    assert(v3kios_core_run_bootstrap_self_test(handle) == V3KIOS_RESULT_OK);

    v3kios_firmware_inventory_v1 inventory{};
    inventory.struct_size = sizeof(inventory);
    assert(v3kios_core_inventory_firmware(handle, "/missing", &inventory) ==
           V3KIOS_RESULT_INVALID_STATE);

    const auto fixtureRoot = MakeFixtureRoot();
    const auto vitaRoot = MakeSyntheticVitaFs(fixtureRoot);
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

    assert(v3kios_core_shutdown(handle) == V3KIOS_RESULT_OK);
    assert(v3kios_core_shutdown(handle) == V3KIOS_RESULT_INVALID_STATE);
    assert(v3kios_core_destroy(handle) == V3KIOS_RESULT_OK);
    assert(v3kios_core_destroy(handle) == V3KIOS_RESULT_INVALID_HANDLE);
    filesystem::remove_all(fixtureRoot);
    return 0;
}
