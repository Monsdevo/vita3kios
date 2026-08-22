#include "../Shared/ProbeRunner.h"

#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <exception>
#include <iomanip>
#include <locale>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

#include <dynarmic/interface/A32/a32.h>

#ifndef VITA3KIOS_APP_COMMIT
#define VITA3KIOS_APP_COMMIT "unknown"
#endif
#ifndef VITA3KIOS_UPSTREAM_COMMIT
#define VITA3KIOS_UPSTREAM_COMMIT "unknown"
#endif

namespace Vita3KiOS::Probes {
namespace {

using SteadyClock = std::chrono::steady_clock;

constexpr std::size_t kRequiredIterations = 20;
constexpr std::size_t kGuestMemorySize = 0x1000;
constexpr std::size_t kCodeCacheSize = 8 * 1024 * 1024;
constexpr std::uint32_t kUserModeCpsr = 0x000001D0;

enum class CaseStatus {
    Passed,
    Failed,
    Skipped,
};

struct TestOutcome {
    bool passed = false;
    std::string actual;
    std::string detail;
};

struct CaseResult {
    std::string name;
    std::string expected;
    std::string actual;
    std::string detail;
    CaseStatus status = CaseStatus::Failed;
    std::uint64_t duration_us = 0;
};

struct IterationResult {
    std::size_t index = 0;
    bool passed = false;
    std::uint64_t duration_us = 0;
    std::vector<CaseResult> cases;
};

std::uint64_t ElapsedMicroseconds(const SteadyClock::time_point start) {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(SteadyClock::now() - start).count());
}

std::string Hex32(const std::uint32_t value) {
    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream << "0x" << std::hex << std::uppercase << std::setw(8) << std::setfill('0') << value;
    return stream.str();
}

std::string PosixError(const std::string_view operation, const int error_number) {
    const std::error_code error{error_number, std::generic_category()};
    return std::string{operation} + " failed: errno=" + std::to_string(error_number) + " (" + error.message() + ")";
}

void AppendJsonString(std::ostringstream& stream, const std::string_view value) {
    stream << '"';
    for (const unsigned char character : value) {
        switch (character) {
        case '"':
            stream << "\\\"";
            break;
        case '\\':
            stream << "\\\\";
            break;
        case '\b':
            stream << "\\b";
            break;
        case '\f':
            stream << "\\f";
            break;
        case '\n':
            stream << "\\n";
            break;
        case '\r':
            stream << "\\r";
            break;
        case '\t':
            stream << "\\t";
            break;
        default:
            if (character < 0x20) {
                stream << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                       << static_cast<unsigned int>(character) << std::dec;
            } else {
                stream << static_cast<char>(character);
            }
            break;
        }
    }
    stream << '"';
}

const char* StatusName(const CaseStatus status) {
    switch (status) {
    case CaseStatus::Passed:
        return "pass";
    case CaseStatus::Failed:
        return "fail";
    case CaseStatus::Skipped:
        return "skip";
    }
    return "fail";
}

template <typename Function>
CaseResult RunCase(std::string name, std::string expected, Function&& function) {
    CaseResult result;
    result.name = std::move(name);
    result.expected = std::move(expected);

    const auto start = SteadyClock::now();
    try {
        TestOutcome outcome = std::forward<Function>(function)();
        result.actual = std::move(outcome.actual);
        result.detail = std::move(outcome.detail);
        result.status = outcome.passed ? CaseStatus::Passed : CaseStatus::Failed;
    } catch (const std::exception& exception) {
        result.actual = "exception";
        result.detail = exception.what();
        result.status = CaseStatus::Failed;
    } catch (...) {
        result.actual = "unknown exception";
        result.detail = "The case raised a non-standard exception.";
        result.status = CaseStatus::Failed;
    }
    result.duration_us = ElapsedMicroseconds(start);
    return result;
}

CaseResult SkippedCase(std::string name, std::string expected, std::string detail) {
    CaseResult result;
    result.name = std::move(name);
    result.expected = std::move(expected);
    result.actual = "not executed";
    result.detail = std::move(detail);
    result.status = CaseStatus::Skipped;
    return result;
}

enum class CallbackFault {
    None,
    CodeReadOutOfBounds,
    DataReadOutOfBounds,
    DataWriteOutOfBounds,
    InterpreterFallback,
    UnexpectedSvc,
    GuestException,
};

const char* CallbackFaultName(const CallbackFault fault) {
    switch (fault) {
    case CallbackFault::None:
        return "none";
    case CallbackFault::CodeReadOutOfBounds:
        return "code-read-out-of-bounds";
    case CallbackFault::DataReadOutOfBounds:
        return "data-read-out-of-bounds";
    case CallbackFault::DataWriteOutOfBounds:
        return "data-write-out-of-bounds";
    case CallbackFault::InterpreterFallback:
        return "interpreter-fallback";
    case CallbackFault::UnexpectedSvc:
        return "unexpected-svc";
    case CallbackFault::GuestException:
        return "guest-exception";
    }
    return "unknown";
}

class A32TestEnvironment final : public Dynarmic::A32::UserCallbacks {
public:
    A32TestEnvironment()
        : memory_(kGuestMemorySize, 0) {}

    bool WriteHost32(const std::uint32_t address, const std::uint32_t value) {
        if (!RangeIsValid(address, sizeof(value))) {
            SetFault(CallbackFault::DataWriteOutOfBounds);
            return false;
        }
        StoreLittleEndian(address, value, sizeof(value));
        return true;
    }

    std::uint32_t ReadHost32(const std::uint32_t address) const {
        if (!RangeIsValid(address, sizeof(std::uint32_t))) {
            return 0;
        }
        return static_cast<std::uint32_t>(LoadLittleEndian(address, sizeof(std::uint32_t)));
    }

    void SetTicks(const std::uint64_t ticks) {
        ticks_left_ = ticks;
    }

    std::uint64_t DataReadCount() const {
        return data_read_count_;
    }

    std::uint64_t DataWriteCount() const {
        return data_write_count_;
    }

    bool HasFault() const {
        return fault_ != CallbackFault::None;
    }

    const char* FaultName() const {
        return CallbackFaultName(fault_);
    }

    std::optional<std::uint32_t> MemoryReadCode(const std::uint32_t address) override {
        if (!RangeIsValid(address, sizeof(std::uint32_t))) {
            SetFault(CallbackFault::CodeReadOutOfBounds);
            return std::nullopt;
        }
        return static_cast<std::uint32_t>(LoadLittleEndian(address, sizeof(std::uint32_t)));
    }

    std::uint8_t MemoryRead8(const std::uint32_t address) override {
        ++data_read_count_;
        return static_cast<std::uint8_t>(ReadData(address, sizeof(std::uint8_t)));
    }

    std::uint16_t MemoryRead16(const std::uint32_t address) override {
        ++data_read_count_;
        return static_cast<std::uint16_t>(ReadData(address, sizeof(std::uint16_t)));
    }

    std::uint32_t MemoryRead32(const std::uint32_t address) override {
        ++data_read_count_;
        return static_cast<std::uint32_t>(ReadData(address, sizeof(std::uint32_t)));
    }

    std::uint64_t MemoryRead64(const std::uint32_t address) override {
        ++data_read_count_;
        return ReadData(address, sizeof(std::uint64_t));
    }

    void MemoryWrite8(const std::uint32_t address, const std::uint8_t value) override {
        WriteData(address, value, sizeof(value));
    }

    void MemoryWrite16(const std::uint32_t address, const std::uint16_t value) override {
        WriteData(address, value, sizeof(value));
    }

    void MemoryWrite32(const std::uint32_t address, const std::uint32_t value) override {
        WriteData(address, value, sizeof(value));
    }

    void MemoryWrite64(const std::uint32_t address, const std::uint64_t value) override {
        WriteData(address, value, sizeof(value));
    }

    void InterpreterFallback(std::uint32_t, std::size_t) override {
        SetFault(CallbackFault::InterpreterFallback);
    }

    void CallSVC(std::uint32_t) override {
        SetFault(CallbackFault::UnexpectedSvc);
    }

    void ExceptionRaised(std::uint32_t, Dynarmic::A32::Exception) override {
        SetFault(CallbackFault::GuestException);
    }

    void AddTicks(const std::uint64_t ticks) override {
        ticks_left_ = ticks >= ticks_left_ ? 0 : ticks_left_ - ticks;
    }

    std::uint64_t GetTicksRemaining() override {
        return ticks_left_;
    }

private:
    bool RangeIsValid(const std::uint32_t address, const std::size_t width) const {
        return static_cast<std::uint64_t>(address) + width <= memory_.size();
    }

    std::uint64_t LoadLittleEndian(const std::uint32_t address, const std::size_t width) const {
        std::uint64_t value = 0;
        for (std::size_t offset = 0; offset < width; ++offset) {
            value |= static_cast<std::uint64_t>(memory_[address + offset]) << (offset * 8);
        }
        return value;
    }

    void StoreLittleEndian(const std::uint32_t address, const std::uint64_t value, const std::size_t width) {
        for (std::size_t offset = 0; offset < width; ++offset) {
            memory_[address + offset] = static_cast<std::uint8_t>(value >> (offset * 8));
        }
    }

    std::uint64_t ReadData(const std::uint32_t address, const std::size_t width) {
        if (!RangeIsValid(address, width)) {
            SetFault(CallbackFault::DataReadOutOfBounds);
            return 0;
        }
        return LoadLittleEndian(address, width);
    }

    void WriteData(const std::uint32_t address, const std::uint64_t value, const std::size_t width) {
        ++data_write_count_;
        if (!RangeIsValid(address, width)) {
            SetFault(CallbackFault::DataWriteOutOfBounds);
            return;
        }
        StoreLittleEndian(address, value, width);
    }

    void SetFault(const CallbackFault fault) {
        if (fault_ == CallbackFault::None) {
            fault_ = fault;
        }
    }

    std::vector<std::uint8_t> memory_;
    std::uint64_t ticks_left_ = 0;
    std::uint64_t data_read_count_ = 0;
    std::uint64_t data_write_count_ = 0;
    CallbackFault fault_ = CallbackFault::None;
};

Dynarmic::A32::UserConfig MakeConfig(A32TestEnvironment& environment) {
    Dynarmic::A32::UserConfig config{};
    config.callbacks = &environment;
    config.arch_version = Dynarmic::A32::ArchVersion::v7;
    config.optimizations &= ~Dynarmic::OptimizationFlag::FastDispatch;
    config.enable_cycle_counting = true;
    config.always_little_endian = true;
    config.page_table = nullptr;
    config.fastmem_pointer = std::nullopt;
    config.code_cache_size = kCodeCacheSize;
    return config;
}

TestOutcome RawWriteExecutePreflight() {
#if defined(__APPLE__) && TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    class Mapping final {
    public:
        Mapping(void* address, const std::size_t size)
            : address_(address), size_(size) {}

        ~Mapping() {
            if (address_ != nullptr) {
                ::munmap(address_, size_);
            }
        }

        void* Get() const {
            return address_;
        }

    private:
        void* address_ = nullptr;
        std::size_t size_ = 0;
    };

    const long system_page_size = ::sysconf(_SC_PAGESIZE);
    if (system_page_size <= 0) {
        const int error_number = errno;
        return {false, "page-size unavailable", PosixError("sysconf(_SC_PAGESIZE)", error_number)};
    }
    const auto page_size = static_cast<std::size_t>(system_page_size);

    void* raw_mapping = ::mmap(nullptr, page_size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (raw_mapping == MAP_FAILED) {
        const int error_number = errno;
        return {false, "mmap-rx failed", PosixError("mmap(PROT_READ|PROT_EXEC)", error_number)};
    }
    Mapping mapping{raw_mapping, page_size};

    if (::mprotect(mapping.Get(), page_size, PROT_READ | PROT_WRITE) != 0) {
        const int error_number = errno;
        return {false, "mprotect-rw failed", PosixError("mprotect(PROT_READ|PROT_WRITE)", error_number)};
    }

    constexpr std::uint32_t mov_w0_42 = 0x52800540;
    constexpr std::uint32_t mov_w0_43 = 0x52800560;
    constexpr std::uint32_t ret = 0xD65F03C0;
    const std::array first_program{mov_w0_42, ret};
    std::memcpy(mapping.Get(), first_program.data(), sizeof(first_program));
    ::sys_icache_invalidate(mapping.Get(), sizeof(first_program));

    if (::mprotect(mapping.Get(), page_size, PROT_READ | PROT_EXEC) != 0) {
        const int error_number = errno;
        return {false, "mprotect-rx-42 failed", PosixError("mprotect(PROT_READ|PROT_EXEC)", error_number)};
    }

    using GeneratedFunction = std::uint32_t (*)();
    const auto generated_function = reinterpret_cast<GeneratedFunction>(mapping.Get());
    const std::uint32_t first_result = generated_function();
    if (first_result != 42) {
        return {false, "first=" + std::to_string(first_result), "Generated AArch64 code did not return 42."};
    }

    if (::mprotect(mapping.Get(), page_size, PROT_READ | PROT_WRITE) != 0) {
        const int error_number = errno;
        return {false, "mprotect-rw-rewrite failed", PosixError("mprotect(PROT_READ|PROT_WRITE)", error_number)};
    }

    const std::array second_program{mov_w0_43, ret};
    std::memcpy(mapping.Get(), second_program.data(), sizeof(second_program));
    ::sys_icache_invalidate(mapping.Get(), sizeof(second_program));

    if (::mprotect(mapping.Get(), page_size, PROT_READ | PROT_EXEC) != 0) {
        const int error_number = errno;
        return {false, "mprotect-rx-43 failed", PosixError("mprotect(PROT_READ|PROT_EXEC)", error_number)};
    }

    const std::uint32_t second_result = generated_function();
    const bool passed = second_result == 43;
    return {
        passed,
        "first=" + std::to_string(first_result) + ", second=" + std::to_string(second_result),
        passed ? "RX->RW->RX and sys_icache_invalidate succeeded twice."
               : "Rewritten AArch64 code did not return 43.",
    };
#else
    return {
        false,
        "unsupported platform",
        "The JIT gate must run in an arm64 iPhoneOS process, not macOS or iOS Simulator.",
    };
#endif
}

TestOutcome ArmArithmeticAndFlags() {
    A32TestEnvironment environment;
    environment.WriteHost32(0x00, 0xE3A00005);  // mov r0, #5
    environment.WriteHost32(0x04, 0xE3A0100D);  // mov r1, #13
    environment.WriteHost32(0x08, 0xE0912000);  // adds r2, r1, r0
    environment.WriteHost32(0x0C, 0xE0503001);  // subs r3, r0, r1
    environment.WriteHost32(0x10, 0xEAFFFFFE);  // b .

    Dynarmic::A32::Jit jit{MakeConfig(environment)};
    jit.Regs() = {};
    jit.SetCpsr(kUserModeCpsr);
    environment.SetTicks(4);
    jit.Run();

    const std::uint32_t nzcv = jit.Cpsr() & 0xF0000000U;
    const bool passed = !environment.HasFault() && jit.Regs()[2] == 18 &&
                        jit.Regs()[3] == 0xFFFFFFF8U && nzcv == 0x80000000U;
    return {
        passed,
        "r2=" + std::to_string(jit.Regs()[2]) + ", r3=" + Hex32(jit.Regs()[3]) + ", nzcv=" + Hex32(nzcv),
        std::string{"callback_fault="} + environment.FaultName(),
    };
}

std::pair<bool, std::string> RunConditionalBranchPath(const std::uint32_t r0, const std::uint32_t expected_r1) {
    A32TestEnvironment environment;
    environment.WriteHost32(0x00, 0xE3500000);  // cmp r0, #0
    environment.WriteHost32(0x04, 0x1A000001);  // bne 0x10
    environment.WriteHost32(0x08, 0xE3A0102A);  // mov r1, #42
    environment.WriteHost32(0x0C, 0xEA000000);  // b 0x14
    environment.WriteHost32(0x10, 0xE3A01063);  // mov r1, #99
    environment.WriteHost32(0x14, 0xEAFFFFFE);  // b .

    Dynarmic::A32::Jit jit{MakeConfig(environment)};
    jit.Regs() = {};
    jit.Regs()[0] = r0;
    jit.SetCpsr(kUserModeCpsr);
    environment.SetTicks(3);
    jit.Run();

    const bool passed = !environment.HasFault() && jit.Regs()[1] == expected_r1;
    return {
        passed,
        "r0=" + std::to_string(r0) + " -> r1=" + std::to_string(jit.Regs()[1]) +
            " (fault=" + environment.FaultName() + ")",
    };
}

TestOutcome ArmConditionalBranch() {
    const auto [not_taken_passed, not_taken_actual] = RunConditionalBranchPath(0, 42);
    const auto [taken_passed, taken_actual] = RunConditionalBranchPath(1, 99);
    return {
        not_taken_passed && taken_passed,
        not_taken_actual + "; " + taken_actual,
        "BNE was tested in both not-taken and taken directions.",
    };
}

TestOutcome CallbackMemoryReadWrite() {
    constexpr std::uint32_t source_address = 0x100;
    constexpr std::uint32_t destination_address = 0x200;
    constexpr std::uint32_t value = 0x11223344;

    A32TestEnvironment environment;
    environment.WriteHost32(0x00, 0xE5904000);  // ldr r4, [r0]
    environment.WriteHost32(0x04, 0xE5814000);  // str r4, [r1]
    environment.WriteHost32(0x08, 0xEAFFFFFE);  // b .
    environment.WriteHost32(source_address, value);

    Dynarmic::A32::Jit jit{MakeConfig(environment)};
    jit.Regs() = {};
    jit.Regs()[0] = source_address;
    jit.Regs()[1] = destination_address;
    jit.SetCpsr(kUserModeCpsr);
    environment.SetTicks(2);
    jit.Run();

    const std::uint32_t stored_value = environment.ReadHost32(destination_address);
    const bool callbacks_were_used = environment.DataReadCount() > 0 && environment.DataWriteCount() > 0;
    const bool passed = !environment.HasFault() && callbacks_were_used &&
                        jit.Regs()[4] == value && stored_value == value;
    return {
        passed,
        "r4=" + Hex32(jit.Regs()[4]) + ", memory[0x200]=" + Hex32(stored_value) +
            ", reads=" + std::to_string(environment.DataReadCount()) +
            ", writes=" + std::to_string(environment.DataWriteCount()),
        std::string{"callback_fault="} + environment.FaultName(),
    };
}

TestOutcome GuestCodeInvalidation() {
    A32TestEnvironment environment;
    environment.WriteHost32(0x00, 0xE3A00005);  // mov r0, #5
    environment.WriteHost32(0x04, 0xE3A0100D);  // mov r1, #13
    environment.WriteHost32(0x08, 0xE0812000);  // add r2, r1, r0
    environment.WriteHost32(0x0C, 0xEAFFFFFE);  // b .

    Dynarmic::A32::Jit jit{MakeConfig(environment)};
    jit.Regs() = {};
    jit.SetCpsr(kUserModeCpsr);
    environment.SetTicks(4);
    jit.Run();
    const std::uint32_t before = jit.Regs()[2];

    environment.WriteHost32(0x04, 0xE3A01007);  // mov r1, #7
    jit.InvalidateCacheRange(0x04, sizeof(std::uint32_t));
    jit.Regs()[15] = 0;
    environment.SetTicks(4);
    jit.Run();
    jit.Run();
    const std::uint32_t after = jit.Regs()[2];

    const bool passed = !environment.HasFault() && before == 18 && after == 12;
    return {
        passed,
        "before=" + std::to_string(before) + ", after=" + std::to_string(after),
        std::string{"callback_fault="} + environment.FaultName(),
    };
}

TestOutcome ClearCacheReemit() {
    A32TestEnvironment environment;
    environment.WriteHost32(0x00, 0xE3A00009);  // mov r0, #9
    environment.WriteHost32(0x04, 0xEAFFFFFE);  // b .

    Dynarmic::A32::Jit jit{MakeConfig(environment)};
    jit.Regs() = {};
    jit.SetCpsr(kUserModeCpsr);
    environment.SetTicks(1);
    jit.Run();
    const std::uint32_t before = jit.Regs()[0];

    environment.WriteHost32(0x00, 0xE3A00015);  // mov r0, #21
    jit.ClearCache();
    jit.Regs()[15] = 0;
    environment.SetTicks(1);
    jit.Run();
    const std::uint32_t after = jit.Regs()[0];

    const bool passed = !environment.HasFault() && before == 9 && after == 21;
    return {
        passed,
        "before=" + std::to_string(before) + ", after=" + std::to_string(after),
        std::string{"callback_fault="} + environment.FaultName(),
    };
}

IterationResult RunIteration(const std::size_t index) {
    IterationResult iteration;
    iteration.index = index;
    const auto start = SteadyClock::now();

    iteration.cases.push_back(RunCase(
        "raw_wx_icache_42_to_43",
        "RX->RW write 42 -> icache flush -> RX execute; rewrite 43 -> flush -> execute",
        RawWriteExecutePreflight));

    if (iteration.cases.back().status == CaseStatus::Passed) {
        iteration.cases.push_back(RunCase(
            "arm_arithmetic_flags",
            "r2=18, r3=0xFFFFFFF8, NZCV=0x80000000",
            ArmArithmeticAndFlags));
        iteration.cases.push_back(RunCase(
            "arm_conditional_branch",
            "r0=0 selects r1=42; r0=1 selects r1=99",
            ArmConditionalBranch));
        iteration.cases.push_back(RunCase(
            "callback_memory_read_write",
            "LDR/STR callbacks copy 0x11223344 from 0x100 to 0x200",
            CallbackMemoryReadWrite));
        iteration.cases.push_back(RunCase(
            "guest_code_invalidation",
            "InvalidateCacheRange changes result from 18 to 12",
            GuestCodeInvalidation));
        iteration.cases.push_back(RunCase(
            "clear_cache_reemit",
            "ClearCache retranslates changed code and changes r0 from 9 to 21",
            ClearCacheReemit));
    } else {
        const std::string reason = "Skipped because executable-memory preflight failed: " + iteration.cases.back().detail;
        iteration.cases.push_back(SkippedCase("arm_arithmetic_flags", "r2=18, r3=0xFFFFFFF8, NZCV=0x80000000", reason));
        iteration.cases.push_back(SkippedCase("arm_conditional_branch", "r0=0 selects r1=42; r0=1 selects r1=99", reason));
        iteration.cases.push_back(SkippedCase("callback_memory_read_write", "LDR/STR callbacks copy 0x11223344 from 0x100 to 0x200", reason));
        iteration.cases.push_back(SkippedCase("guest_code_invalidation", "InvalidateCacheRange changes result from 18 to 12", reason));
        iteration.cases.push_back(SkippedCase("clear_cache_reemit", "ClearCache retranslates changed code and changes r0 from 9 to 21", reason));
    }

    iteration.passed = true;
    for (const CaseResult& result : iteration.cases) {
        iteration.passed = iteration.passed && result.status == CaseStatus::Passed;
    }
    iteration.duration_us = ElapsedMicroseconds(start);
    return iteration;
}

std::string BuildJsonReport(const void* presentation_layer) {
    const auto suite_start = SteadyClock::now();
    std::vector<IterationResult> iterations;
    iterations.reserve(kRequiredIterations);
    for (std::size_t index = 1; index <= kRequiredIterations; ++index) {
        iterations.push_back(RunIteration(index));
    }

    std::size_t passed_cases = 0;
    std::size_t failed_cases = 0;
    std::size_t skipped_cases = 0;
    std::size_t passed_iterations = 0;
    for (const IterationResult& iteration : iterations) {
        if (iteration.passed) {
            ++passed_iterations;
        }
        for (const CaseResult& result : iteration.cases) {
            switch (result.status) {
            case CaseStatus::Passed:
                ++passed_cases;
                break;
            case CaseStatus::Failed:
                ++failed_cases;
                break;
            case CaseStatus::Skipped:
                ++skipped_cases;
                break;
            }
        }
    }
    const bool passed = passed_iterations == kRequiredIterations && failed_cases == 0 && skipped_cases == 0;
    const std::uint64_t suite_duration_us = ElapsedMicroseconds(suite_start);

    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream << '{';
    stream << "\"schema_version\":1,";
    stream << "\"probe\":\"dynarmic-jit\",";
    stream << "\"platform\":\"iphoneos-arm64\",";
    stream << "\"app_commit\":";
    AppendJsonString(stream, VITA3KIOS_APP_COMMIT);
    stream << ",\"upstream_commit\":";
    AppendJsonString(stream, VITA3KIOS_UPSTREAM_COMMIT);
    stream << ',';
    stream << "\"presentation_layer_present\":" << (presentation_layer != nullptr ? "true" : "false") << ',';
    stream << "\"passed\":" << (passed ? "true" : "false") << ',';
    stream << "\"required_iterations\":" << kRequiredIterations << ',';
    stream << "\"completed_iterations\":" << iterations.size() << ',';
    stream << "\"duration_us\":" << suite_duration_us << ',';
    stream << "\"summary\":{";
    stream << "\"passed_iterations\":" << passed_iterations << ',';
    stream << "\"passed_cases\":" << passed_cases << ',';
    stream << "\"failed_cases\":" << failed_cases << ',';
    stream << "\"skipped_cases\":" << skipped_cases;
    stream << "},";
    stream << "\"iterations\":[";

    for (std::size_t iteration_index = 0; iteration_index < iterations.size(); ++iteration_index) {
        if (iteration_index != 0) {
            stream << ',';
        }
        const IterationResult& iteration = iterations[iteration_index];
        stream << '{';
        stream << "\"index\":" << iteration.index << ',';
        stream << "\"passed\":" << (iteration.passed ? "true" : "false") << ',';
        stream << "\"duration_us\":" << iteration.duration_us << ',';
        stream << "\"cases\":[";
        for (std::size_t case_index = 0; case_index < iteration.cases.size(); ++case_index) {
            if (case_index != 0) {
                stream << ',';
            }
            const CaseResult& result = iteration.cases[case_index];
            stream << '{';
            stream << "\"name\":";
            AppendJsonString(stream, result.name);
            stream << ",\"status\":";
            AppendJsonString(stream, StatusName(result.status));
            stream << ",\"expected\":";
            AppendJsonString(stream, result.expected);
            stream << ",\"actual\":";
            AppendJsonString(stream, result.actual);
            stream << ",\"detail\":";
            AppendJsonString(stream, result.detail);
            stream << ",\"duration_us\":" << result.duration_us;
            stream << '}';
        }
        stream << "]}";
    }
    stream << "]}";
    return stream.str();
}

std::string EmergencyJsonReport(const std::string_view error) {
    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream << "{\"schema_version\":1,\"probe\":\"dynarmic-jit\",\"passed\":false,\"fatal_error\":";
    AppendJsonString(stream, error);
    stream << '}';
    return stream.str();
}

}  // namespace

std::string RunProbe(void* presentationLayer) {
    try {
        return BuildJsonReport(presentationLayer);
    } catch (const std::exception& exception) {
        return EmergencyJsonReport(exception.what());
    } catch (...) {
        return EmergencyJsonReport("The JIT probe raised a non-standard exception.");
    }
}

}  // namespace Vita3KiOS::Probes
