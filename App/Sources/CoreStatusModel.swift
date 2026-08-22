import Foundation
import Observation

private final class CoreHandleStorage {
    var value: v3kios_core_handle_t = 0

    deinit {
        if value != 0 {
            _ = v3kios_core_shutdown(value)
            _ = v3kios_core_destroy(value)
        }
    }
}

@Observable
@MainActor
final class CoreStatusModel {
    @ObservationIgnored private let core = CoreHandleStorage()

    private(set) var abiVersion: UInt32 = 0
    private(set) var capabilities: UInt64 = 0
    private(set) var vita3kiosCommit = "Unavailable"
    private(set) var upstreamCommit = "Unavailable"
    private(set) var upstreamVersion = "Unavailable"
    private(set) var platform = "Unavailable"
    private(set) var allocatorTestPassed = false
    private(set) var reportWritten = false
    private(set) var firmwareBusy = false
    private(set) var firmwareReady = false
    private(set) var firmwareVersion = "Not installed"
    private(set) var firmwareGeneration = ""
    private(set) var firmwarePartitions: UInt32 = 0
    private(set) var firmwareFileCount: UInt32 = 0
    private(set) var firmwareBytes: UInt64 = 0
    private(set) var shellPath = ""
    private(set) var firmwareDetail = "Import an official firmware PUP for validation or an extracted VitaFS for the current boot experiment."
    private(set) var bootCheckpoint = "Not started"
    private(set) var bootBlocker = "No boot attempt"
    private(set) var bootDetail = ""
    private(set) var error: String?

    init() {
        refresh()
    }

    func refresh() {
        error = nil
        if core.value == 0 {
            let createResult = v3kios_core_create(&core.value)
            guard createResult.rawValue == 0 else {
                error = description(for: createResult)
                return
            }
        }

        var info = v3kios_core_info_v1()
        info.struct_size = UInt32(MemoryLayout<v3kios_core_info_v1>.size)
        let infoResult = v3kios_core_get_info(core.value, &info)
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
        allocatorTestPassed = v3kios_core_run_bootstrap_self_test(core.value).rawValue == 0
        initializeIfNeeded()
        restoreFirmwareIfPresent()
        writeReadinessReport()
    }

    func inspectFirmwarePUP(_ url: URL) {
        guard core.value != 0 else { return }
        firmwareBusy = true
        error = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            firmwareBusy = false
        }

        var info = v3kios_pup_info_v1()
        info.struct_size = UInt32(MemoryLayout<v3kios_pup_info_v1>.size)
        let result = url.path.withCString {
            v3kios_core_inspect_firmware_pup(core.value, $0, &info)
        }
        guard result.rawValue == 0 else {
            error = description(for: result)
            firmwareDetail = "The selected file did not pass the firmware PUP preflight."
            return
        }

        firmwareVersion = string(info.version_text)
        firmwareDetail = "Official PUP container validated: \(info.record_count) records, \(ByteCountFormatter.string(fromByteCount: Int64(info.file_size), countStyle: .file)). The iOS partition extractor is the next core integration gate."
    }

    func importExtractedVitaFS(_ url: URL) {
        guard core.value != 0 else { return }
        firmwareBusy = true
        error = nil
        do {
            let supportRoot = try Self.applicationSupportRoot()
            let coreHandle = core.value
            Task {
                do {
                    let snapshot = try await Task.detached(priority: .userInitiated) {
                        try Self.copyAndInventoryVitaFS(
                            source: url,
                            supportRoot: supportRoot,
                            handle: coreHandle
                        )
                    }.value
                    apply(snapshot)
                } catch {
                    self.error = error.localizedDescription
                    if !firmwareReady {
                        firmwareDetail = "The extracted VitaFS import did not complete."
                    }
                }
                firmwareBusy = false
            }
        } catch {
            self.error = error.localizedDescription
            if !firmwareReady {
                firmwareDetail = "The extracted VitaFS import did not complete."
            }
            firmwareBusy = false
        }
    }

    func bootSystemSoftware() {
        guard firmwareReady, !firmwareGeneration.isEmpty else {
            error = "A shell-ready firmware generation must be imported first."
            return
        }
        var report = v3kios_system_boot_report_v1()
        report.struct_size = UInt32(MemoryLayout<v3kios_system_boot_report_v1>.size)
        let result = firmwareGeneration.withCString {
            v3kios_core_boot_system_software(core.value, $0, &report)
        }
        bootCheckpoint = string(v3kios_boot_checkpoint_description(report.checkpoint))
        bootBlocker = string(v3kios_boot_blocker_description(report.blocker))
        bootDetail = string(report.detail)
        if result.rawValue != 0 && result != V3KIOS_RESULT_UNSUPPORTED {
            error = description(for: result)
        }
        writeSystemSoftwareReport()
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

    private func initializeIfNeeded() {
        do {
            let root = try Self.applicationSupportRoot()
            let result = root.path.withCString { v3kios_core_initialize(core.value, $0) }
            if result.rawValue != 0 && result != V3KIOS_RESULT_INVALID_STATE {
                error = description(for: result)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restoreFirmwareIfPresent() {
        guard !firmwareReady else { return }
        do {
            let generations = try Self.applicationSupportRoot()
                .appendingPathComponent("Firmware/Generations", isDirectory: true)
            let candidates = try FileManager.default.contentsOfDirectory(
                at: generations,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let newest = candidates.max { left, right in
                let leftDate = try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rightDate = try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (leftDate ?? .distantPast) < (rightDate ?? .distantPast)
            }
            if let newest {
                apply(Self.inventory(path: newest.path, handle: core.value))
                error = nil
            }
        } catch {
            // No installed generation is a normal first-launch state.
        }
    }

    private func apply(_ snapshot: FirmwareInventorySnapshot) {
        firmwareReady = snapshot.ready
        firmwareVersion = snapshot.version
        firmwareGeneration = snapshot.generation
        firmwarePartitions = snapshot.partitionMask
        firmwareFileCount = snapshot.fileCount
        firmwareBytes = snapshot.totalBytes
        shellPath = snapshot.shellPath
        firmwareDetail = snapshot.detail
        error = snapshot.ready ? nil : snapshot.resultDescription
        writeSystemSoftwareReport()
    }

    private static func applicationSupportRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("vita3kios", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSystemSoftwareReport() {
        let report: [String: Any] = [
            "schemaVersion": 1,
            "mode": "system-software",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "firmwareReady": firmwareReady,
            "firmwareVersion": firmwareVersion,
            "firmwareGeneration": firmwareGeneration,
            "partitionMask": firmwarePartitions,
            "fileCount": firmwareFileCount,
            "totalBytes": firmwareBytes,
            "shellRelativePath": shellPath,
            "checkpoint": bootCheckpoint,
            "blocker": bootBlocker,
            "detail": bootDetail,
            "vita3kiosCommit": vita3kiosCommit,
            "upstreamCommit": upstreamCommit,
            "platform": platform,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(
                to: documents.appendingPathComponent("system-software-preflight-report.json"),
                options: .atomic
            )
        } catch {
            // A report write failure must not invalidate an otherwise usable firmware generation.
        }
    }

    nonisolated private static func copyAndInventoryVitaFS(
        source: URL,
        supportRoot: URL,
        handle: v3kios_core_handle_t
    ) throws -> FirmwareInventorySnapshot {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let firmwareRoot = supportRoot.appendingPathComponent("Firmware", isDirectory: true)
        let generationsRoot = firmwareRoot.appendingPathComponent("Generations", isDirectory: true)
        try fileManager.createDirectory(at: generationsRoot, withIntermediateDirectories: true)
        let staging = firmwareRoot.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.copyItem(at: source, to: staging)
            let staged = inventory(path: staging.path, handle: handle)
            guard staged.ready else {
                try? fileManager.removeItem(at: staging)
                throw FirmwareImportError.notReady(staged.detail)
            }
            let destination = generationsRoot.appendingPathComponent(staged.generation, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
            return inventory(path: destination.path, handle: handle)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    nonisolated private static func inventory(
        path: String,
        handle: v3kios_core_handle_t
    ) -> FirmwareInventorySnapshot {
        var inventory = v3kios_firmware_inventory_v1()
        inventory.struct_size = UInt32(MemoryLayout<v3kios_firmware_inventory_v1>.size)
        let result = path.withCString {
            v3kios_core_inventory_firmware(handle, $0, &inventory)
        }
        return FirmwareInventorySnapshot(
            ready: inventory.state == V3KIOS_FIRMWARE_SHELL_READY,
            version: copyString(inventory.version_text),
            generation: copyString(inventory.generation_id),
            partitionMask: inventory.partition_mask,
            fileCount: inventory.file_count,
            totalBytes: inventory.total_bytes,
            shellPath: copyString(inventory.shell_relative_path),
            detail: copyString(inventory.detail),
            resultDescription: copyString(v3kios_result_description(result))
        )
    }

    nonisolated private static func copyString(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "Unavailable" }
        return String(cString: pointer)
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
    static let firmwarePUPPreflight: UInt64 = 1 << 6
    static let firmwareInventory: UInt64 = 1 << 7
    static let systemShellPreflight: UInt64 = 1 << 8
}

private struct FirmwareInventorySnapshot: Sendable {
    let ready: Bool
    let version: String
    let generation: String
    let partitionMask: UInt32
    let fileCount: UInt32
    let totalBytes: UInt64
    let shellPath: String
    let detail: String
    let resultDescription: String
}

private enum FirmwareImportError: LocalizedError {
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case let .notReady(detail):
            return detail
        }
    }
}
