#include <cstddef>
#include <cstdint>
#include <cstring>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <unistd.h>

extern "C" int csops(pid_t, unsigned int, void*, size_t);

// This breakpoint hook runs before any generated instructions are written.
// The debugger helper writes every RX page and acknowledges preparation with
// this marker. A plain debugger attach is insufficient on current iOS.
extern "C" __attribute__((noinline, used, visibility("default")))
void v3kios_jit_prepare_rx(void* address, std::size_t size) {
    asm volatile("" : : "r"(address), "r"(size) : "memory");
}

extern "C" bool v3kios_jit_allocate(std::size_t size, std::uint32_t** writable,
                                     std::uint32_t** executable) {
    *writable = nullptr;
    *executable = nullptr;
    constexpr std::uint32_t CodeSigningDebugged = 0x10000000U;
    std::uint32_t flags = 0;
    if (csops(getpid(), 0, &flags, sizeof(flags)) != 0 ||
        (flags & CodeSigningDebugged) == 0 || size < 8) return false;

    // The original mapping must start RX. Upgrading an RW-backed alias to RX
    // can report success but still fault on the first instruction fetch.
    void* rx = mmap(nullptr, size, PROT_READ | PROT_EXEC,
                    MAP_ANON | MAP_PRIVATE, -1, 0);
    if (rx == MAP_FAILED) return false;
    vm_address_t rw = 0;
    vm_prot_t current = VM_PROT_NONE, maximum = VM_PROT_NONE;
    const auto result = vm_remap(mach_task_self(), &rw, size, 0, VM_FLAGS_ANYWHERE,
        mach_task_self(), reinterpret_cast<vm_address_t>(rx), false,
        &current, &maximum, VM_INHERIT_NONE);
    if (result != KERN_SUCCESS) {
        munmap(rx, size);
        return false;
    }

    v3kios_jit_prepare_rx(rx, size);
    constexpr char Marker[] = "V3KJITOK";
    const bool prepared = std::memcmp(rx, Marker, 8) == 0;
    if (!prepared || mprotect(reinterpret_cast<void*>(rw), size,
                              PROT_READ | PROT_WRITE) != 0) {
        munmap(reinterpret_cast<void*>(rw), size);
        munmap(rx, size);
        return false;
    }
    *writable = reinterpret_cast<std::uint32_t*>(rw);
    *executable = static_cast<std::uint32_t*>(rx);
    return true;
}

extern "C" bool v3kios_jit_memory_available() {
    const long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) return false;
    std::uint32_t* writable = nullptr;
    std::uint32_t* executable = nullptr;
    if (!v3kios_jit_allocate(static_cast<std::size_t>(pageSize),
                              &writable, &executable)) return false;
    // Verify both initial execution and rewriting through the permanent alias.
    constexpr std::uint32_t first[] = {0x52800540U, 0xD65F03C0U}; // return 42
    std::memcpy(writable, first, sizeof(first));
    sys_icache_invalidate(executable, sizeof(first));
    using Probe = std::uint32_t (*)();
    const auto run = reinterpret_cast<Probe>(executable);
    const bool initial = std::memcmp(executable, first, sizeof(first)) == 0 && run() == 42;
    writable[0] = 0x52800560U; // return 43
    sys_icache_invalidate(executable, sizeof(first));
    const bool rewritten = executable[0] == writable[0] && run() == 43;
    munmap(writable, static_cast<std::size_t>(pageSize));
    munmap(executable, static_cast<std::size_t>(pageSize));
    return initial && rewritten;
}
#endif
#endif
