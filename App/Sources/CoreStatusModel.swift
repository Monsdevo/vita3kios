import Foundation
import Observation

@Observable
final class CoreStatusModel {
    private var handle: v3kios_core_handle_t = 0

    private(set) var abiVersion: UInt32 = 0
    private(set) var capabilities: UInt64 = 0
    private(set) var vita3kiosCommit = "Unavailable"
    private(set) var upstreamCommit = "Unavailable"
    private(set) var upstreamVersion = "Unavailable"
    private(set) var platform = "Unavailable"
    private(set) var allocatorTestPassed = false
    private(set) var reportWritten = false
    private(set) var error: String?

    init() {
        refresh()
    }

    deinit {
        if handle != 0 {
            _ = v3kios_core_destroy(handle)
        }
    }

    func refresh() {
        error = nil
        if handle == 0 {
            let createResult = v3kios_core_create(&handle)
            guard createResult.rawValue == 0 else {
                error = description(for: createResult)
                return
            }
        }

        var info = v3kios_core_info_v1()
        info.struct_size = UInt32(MemoryLayout<v3kios_core_info_v1>.size)
        let infoResult = v3kios_core_get_info(handle, &info)
        guard infoResult.rawValue == 0 else {
            error = description(for: infoResult)
            return
        }

        abiVersion = info.abi_version
        capabilities = info.capabilities
        vita3kiosCommit = string(info.vita3kios_commit)
        upstreamCommit = string(info.upstream_commit)
        upstreamVersion = string(info.upstream_version)
        platform = string(info.build_platform)
        allocatorTestPassed = v3kios_core_run_bootstrap_self_test(handle).rawValue == 0
        writeReadinessReport()
    }

    func has(_ bit: UInt64) -> Bool {
        (capabilities & bit) != 0
    }

    private func string(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "Unavailable" }
        return String(cString: pointer)
    }

    private func description(for result: v3kios_result_v1) -> String {
        guard let text = v3kios_result_description(result) else {
            return "Unknown core error"
        }
        return String(cString: text)
    }

    private func writeReadinessReport() {
        let passed = abiVersion == UInt32(VITA3KIOS_CORE_ABI_VERSION) &&
            has(CoreCapability.abi) &&
            has(CoreCapability.upstreamAllocator) &&
            allocatorTestPassed
        let report: [String: Any] = [
            "schemaVersion": 1,
            "milestone": "M3",
            "status": passed ? "passed-core-link-and-query" : "failed",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "abiVersion": abiVersion,
            "capabilities": capabilities,
            "vita3kiosCommit": vita3kiosCommit,
            "upstreamCommit": upstreamCommit,
            "upstreamVersion": upstreamVersion,
            "platform": platform,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "allocatorSelfTestPassed": allocatorTestPassed,
        ]

        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: report,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(
                to: documents.appendingPathComponent("m3-core-report.json"),
                options: .atomic
            )
            reportWritten = true
        } catch {
            reportWritten = false
        }
    }
}

enum CoreCapability {
    static let abi: UInt64 = 1 << 0
    static let upstreamAllocator: UInt64 = 1 << 1
    static let jitProbe: UInt64 = 1 << 2
    static let moltenVKProbe: UInt64 = 1 << 3
    static let directGame: UInt64 = 1 << 4
    static let systemSoftware: UInt64 = 1 << 5
}
