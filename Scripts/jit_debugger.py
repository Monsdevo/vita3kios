"""LLDB page preparation for the iOS Dynarmic dual-mapped code cache.

Import before attaching to the application. Keep the debugger connected
while running: every new CPU code cache needs its own page preparation.
"""

import time
import os
import subprocess
import lldb


def prepare_rx(frame, breakpoint_location, internal_dict):
    process = frame.GetThread().GetProcess()
    address = frame.FindRegister("x0").GetValueAsUnsigned()
    size = frame.FindRegister("x1").GetValueAsUnsigned()
    if not address or size < 8 or size > 128 * 1024 * 1024:
        print("Rejected invalid JIT page preparation request.")
        return True
    error = lldb.SBError()
    # Bulk writes avoid one remote round trip per 16 KiB page. Acknowledge only
    # after the entire range has been written successfully by debugserver.
    chunk = bytes(min(size, 1024 * 1024))
    for offset in range(0, size, len(chunk)):
        data = chunk[:min(len(chunk), size - offset)]
        count = process.WriteMemory(address + offset, data, error)
        if not error.Success() or count != len(data):
            print("JIT page preparation failed: %s" % error)
            return True
    count = process.WriteMemory(address, b"V3KJITOK", error)
    if not error.Success() or count != 8:
        print("JIT page acknowledgement failed: %s" % error)
        return True
    print("Prepared %d bytes of JIT code memory." % size)
    return False


def run_after_attach(debugger, command, result, internal_dict):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        target = debugger.GetSelectedTarget()
        process = target.GetProcess()
        state = process.GetState()
        if state == lldb.eStateStopped:
            breakpoint = target.BreakpointCreateByName("v3kios_jit_prepare_rx")
            breakpoint.SetScriptCallbackFunction(__name__ + ".prepare_rx")
            debugger.SetAsync(True)
            error = process.Continue()
            if error.Success():
                result.AppendMessage("Running with the vita3kios JIT page helper.")
                device = os.environ.get("VITA3KIOS_JIT_DEVICE")
                bundle = os.environ.get("VITA3KIOS_JIT_BUNDLE")
                if device and bundle:
                    try:
                        launch = subprocess.run([
                            "xcrun", "devicectl", "--timeout", "20", "device",
                            "process", "launch", "--device", device, "--payload-url",
                            "vita3kios://boot-first-game", bundle,
                        ], capture_output=True, text=True, timeout=25)
                        if launch.returncode != 0:
                            result.SetError("Game activation failed: " + launch.stderr)
                    except subprocess.TimeoutExpired:
                        result.SetError("Timed out activating the first imported game.")
            else:
                result.SetError(str(error))
            return
        if state in (lldb.eStateExited, lldb.eStateCrashed, lldb.eStateDetached):
            result.SetError("The app exited before debugger setup completed.")
            return
        time.sleep(0.2)
    result.SetError("Timed out waiting for the stopped application.")


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f " + __name__ + ".run_after_attach vita3kios-run"
    )
