import Foundation
import Observation
import QuartzCore

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
    @ObservationIgnored private var directBootRequestGeneration: String?
    @ObservationIgnored private var firstGuestFrameReported = false

    private(set) var abiVersion: UInt32 = 0
    private(set) var capabilities: UInt64 = 0
    private(set) var vita3kiosCommit = "Unavailable"
    private(set) var upstreamCommit = "Unavailable"
    private(set) var upstreamVersion = "Unavailable"
    private(set) var platform = "Unavailable"
    private(set) var allocatorTestPassed = false
    private(set) var reportWritten = false
    private(set) var jitEnabled = false
    private(set) var firmwareBusy = false
    private(set) var firmwareReady = false
    private(set) var systemSoftwareReady = false
    private(set) var firmwareVersion = "Not installed"
    private(set) var firmwareGeneration = ""
    private(set) var firmwarePartitions: UInt32 = 0
    private(set) var firmwareFileCount: UInt32 = 0
    private(set) var firmwareBytes: UInt64 = 0
    private(set) var shellPath = ""
    private(set) var firmwareDetail = "Firmware is optional for Direct Game compatibility and required for System Software research."
    private(set) var games: [GameLibraryItem] = []
    private(set) var gameImportBusy = false
    private(set) var gameLibraryBusy = false
    private(set) var activeGame: GameLibraryItem?
    private(set) var directBootCheckpoint = "Not started"
    private(set) var directBootBlocker = "No boot attempt"
    private(set) var directBootDetail = ""
    private(set) var metrics = PerformanceMetrics()
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
        refreshJITStatus()
        initializeIfNeeded()
        restoreFirmwareIfPresent()
        restoreGames()
        writeReadinessReport()
    }

    func refreshJITStatus() {
        jitEnabled = v3kios_core_is_jit_enabled() != 0
    }

    func inspectFirmwarePUP(_ url: URL) {
        guard core.value != 0 else { return }
        firmwareBusy = true
        error = nil
        do {
            let supportRoot = try Self.applicationSupportRoot()
            let coreHandle = core.value
            Task {
                do {
                    let snapshot = try await Task.detached(priority: .userInitiated) {
                        try Self.installAndInventoryFirmwarePUP(
                            source: url,
                            supportRoot: supportRoot,
                            handle: coreHandle
                        )
                    }.value
                    apply(snapshot)
                } catch {
                    self.error = error.localizedDescription
                    if !firmwareReady {
                        firmwareDetail = "The official firmware PUP could not be installed."
                    }
                }
                firmwareBusy = false
            }
        } catch {
            self.error = error.localizedDescription
            firmwareDetail = "The official firmware PUP could not be installed."
            firmwareBusy = false
        }
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

    func importExtractedGame(_ url: URL) {
        guard core.value != 0 else { return }
        gameImportBusy = true
        error = nil
        do {
            let supportRoot = try Self.applicationSupportRoot()
            let coreHandle = core.value
            Task {
                do {
                    let item = try await Task.detached(priority: .userInitiated) {
                        try Self.copyAndInventoryGame(
                            source: url,
                            supportRoot: supportRoot,
                            handle: coreHandle
                        )
                    }.value
                    games.removeAll { $0.generation == item.generation }
                    games.append(item)
                    games.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                } catch {
                    self.error = error.localizedDescription
                }
                gameImportBusy = false
            }
        } catch {
            self.error = error.localizedDescription
            gameImportBusy = false
        }
    }

    func bootDirectGame(_ game: GameLibraryItem) {
        guard directBootRequestGeneration != game.generation,
              activeGame?.generation != game.generation else { return }
        guard let container = gameContainerURL(for: game) else {
            error = "The imported game container is unavailable."
            return
        }
        refreshJITStatus()
        guard jitEnabled else {
            activeGame = game
            directBootCheckpoint = "Game eboot SELF container verified"
            directBootBlocker = "JIT is not enabled for this process"
            directBootDetail = "Enable JIT with StikDebug, then reopen the game."
            error = "JIT must be enabled before starting a game."
            writeDirectGameReport(result: V3KIOS_RESULT_GAME_NOT_READY)
            return
        }
        directBootRequestGeneration = game.generation
        firstGuestFrameReported = false
        activeGame = game
        defer { directBootRequestGeneration = nil }
        var report = v3kios_direct_boot_report_v1()
        report.struct_size = UInt32(MemoryLayout<v3kios_direct_boot_report_v1>.size)
        let result = container.path.withCString { root in
            game.generation.withCString { generation in
                v3kios_core_boot_direct_game(core.value, root, generation, &report)
            }
        }
        directBootCheckpoint = string(v3kios_direct_boot_checkpoint_description(report.checkpoint))
        directBootBlocker = string(v3kios_direct_boot_blocker_description(report.blocker))
        directBootDetail = string(report.detail)
        if result.rawValue != 0 && result != V3KIOS_RESULT_UNSUPPORTED {
            error = description(for: result)
        } else {
            error = nil
        }
        writeDirectGameReport(result: result)
    }

    func endDirectGameSession() {
        directBootRequestGeneration = nil
        firstGuestFrameReported = false
        _ = v3kios_core_stop_session(core.value)
        var neutral = v3kios_input_state_v1()
        neutral.struct_size = UInt32(MemoryLayout<v3kios_input_state_v1>.size)
        _ = v3kios_core_set_input_state(core.value, &neutral)
        activeGame = nil
        metrics = PerformanceMetrics()
    }

    func submitInput(_ input: ControllerInputSnapshot) {
        var state = v3kios_input_state_v1()
        state.struct_size = UInt32(MemoryLayout<v3kios_input_state_v1>.size)
        state.buttons = input.buttons
        state.left_x = input.leftX
        state.left_y = input.leftY
        state.right_x = input.rightX
        state.right_y = input.rightY
        _ = v3kios_core_set_input_state(core.value, &state)
    }

    func refreshMetrics() {
        var snapshot = v3kios_metrics_v1()
        snapshot.struct_size = UInt32(MemoryLayout<v3kios_metrics_v1>.size)
        guard v3kios_core_get_metrics(core.value, &snapshot).rawValue == 0 else {
            metrics = PerformanceMetrics()
            return
        }
        metrics = PerformanceMetrics(
            validityMask: snapshot.validity_mask,
            guestFPS: snapshot.guest_fps,
            frameTimeMS: snapshot.frame_time_ms,
            hostCPUPercent: snapshot.host_cpu_percent,
            hostMemoryBytes: snapshot.host_memory_bytes
        )
        if activeGame != nil,
           snapshot.validity_mask & MetricValidity.guestFPS != 0,
           snapshot.guest_fps > 0 {
            directBootCheckpoint = "First guest game frame presented"
            directBootBlocker = "No blocker"
            directBootDetail = "The Vita3K guest is presenting frames through the iOS Metal surface."
            if !firstGuestFrameReported {
                firstGuestFrameReported = true
                writeDirectGameReport(result: V3KIOS_RESULT_OK)
            }
        }
    }

    func attachDisplaySurface(_ layer: CAMetalLayer, drawableSize: CGSize, scale: CGFloat) -> Bool {
        guard drawableSize.width > 0, drawableSize.height > 0,
              drawableSize.width <= CGFloat(UInt32.max),
              drawableSize.height <= CGFloat(UInt32.max), scale > 0 else { return false }
        var surface = v3kios_display_surface_v1()
        surface.struct_size = UInt32(MemoryLayout<v3kios_display_surface_v1>.size)
        surface.metal_layer = Unmanaged.passUnretained(layer).toOpaque()
        surface.drawable_width = UInt32(drawableSize.width.rounded())
        surface.drawable_height = UInt32(drawableSize.height.rounded())
        surface.scale = Float(scale)
        let result = v3kios_core_attach_display_surface(core.value, &surface)
        guard result.rawValue == 0 else {
            error = description(for: result)
            return false
        }
        return true
    }

    func detachDisplaySurface() {
        _ = v3kios_core_detach_display_surface(core.value)
    }

    func gameIconURL(for game: GameLibraryItem) -> URL? {
        guard !game.iconRelativePath.isEmpty,
              let container = gameContainerURL(for: game),
              let root = Self.resolveGameRoot(container) else { return nil }
        return root.appendingPathComponent(game.iconRelativePath)
    }

    func bootSystemSoftware() {
        guard systemSoftwareReady, !firmwareGeneration.isEmpty else {
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

    private func restoreGames() {
        gameLibraryBusy = true
        do {
            let supportRoot = try Self.applicationSupportRoot()
            let coreHandle = core.value
            Task {
                do {
                    games = try await Task.detached(priority: .utility) {
                        let generations = supportRoot.appendingPathComponent(
                            "Games/Generations",
                            isDirectory: true
                        )
                        try FileManager.default.createDirectory(
                            at: generations,
                            withIntermediateDirectories: true
                        )
                        let candidates = try FileManager.default.contentsOfDirectory(
                            at: generations,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]
                        )
                        return candidates.compactMap { candidate in
                            let snapshot = Self.inventoryGame(path: candidate.path, handle: coreHandle)
                            return snapshot.ready
                                ? Self.makeGameItem(
                                    snapshot: snapshot,
                                    container: candidate,
                                    supportRoot: supportRoot
                                )
                                : nil
                        }.sorted {
                            $0.title.localizedStandardCompare($1.title) == .orderedAscending
                        }
                    }.value
                } catch {
                    games = []
                }
                gameLibraryBusy = false
            }
        } catch {
            games = []
            gameLibraryBusy = false
        }
    }

    private func gameContainerURL(for game: GameLibraryItem) -> URL? {
        guard let supportRoot = try? Self.applicationSupportRoot() else { return nil }
        let generationContainer = supportRoot
            .appendingPathComponent("Games/Generations", isDirectory: true)
            .appendingPathComponent(game.generation, isDirectory: true)
        if FileManager.default.fileExists(atPath: generationContainer.path) {
            return generationContainer
        }
        let recordedContainer = supportRoot.appendingPathComponent(
            game.containerRelativePath,
            isDirectory: true
        )
        return FileManager.default.fileExists(atPath: recordedContainer.path)
            ? recordedContainer : nil
    }

    private func apply(_ snapshot: FirmwareInventorySnapshot) {
        firmwareReady = snapshot.ready
        systemSoftwareReady = snapshot.systemSoftwareReady
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

    private func writeDirectGameReport(result: v3kios_result_v1) {
        guard let game = activeGame else { return }
        let report: [String: Any] = [
            "schemaVersion": 1,
            "mode": "direct-game",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "result": description(for: result),
            "titleID": game.titleID,
            "title": game.title,
            "version": game.version,
            "generation": game.generation,
            "checkpoint": directBootCheckpoint,
            "blocker": directBootBlocker,
            "detail": directBootDetail,
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
                to: documents.appendingPathComponent("direct-game-boot-report.json"),
                options: .atomic
            )
        } catch {
            // Diagnostics must not change session behavior.
        }
    }

    private func writeSystemSoftwareReport() {
        let report: [String: Any] = [
            "schemaVersion": 1,
            "mode": "system-software",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "firmwareReady": firmwareReady,
            "systemSoftwareReady": systemSoftwareReady,
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

    nonisolated private static func copyAndInventoryGame(
        source: URL,
        supportRoot: URL,
        handle: v3kios_core_handle_t
    ) throws -> GameLibraryItem {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let gamesRoot = supportRoot.appendingPathComponent("Games", isDirectory: true)
        let generationsRoot = gamesRoot.appendingPathComponent("Generations", isDirectory: true)
        try fileManager.createDirectory(at: generationsRoot, withIntermediateDirectories: true)
        let staging = gamesRoot.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.copyItem(at: source, to: staging)
            let staged = inventoryGame(path: staging.path, handle: handle)
            guard staged.ready else {
                throw GameImportError.notReady(staged.detail)
            }
            let destination = generationsRoot.appendingPathComponent(staged.generation, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
            let installed = inventoryGame(path: destination.path, handle: handle)
            guard installed.ready else {
                throw GameImportError.notReady(installed.detail)
            }
            return makeGameItem(snapshot: installed, container: destination, supportRoot: supportRoot)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    nonisolated private static func inventoryGame(
        path: String,
        handle: v3kios_core_handle_t
    ) -> GameInventorySnapshot {
        var info = v3kios_game_info_v1()
        info.struct_size = UInt32(MemoryLayout<v3kios_game_info_v1>.size)
        let result = path.withCString {
            v3kios_core_inventory_game(handle, $0, &info)
        }
        return GameInventorySnapshot(
            ready: info.state == V3KIOS_GAME_BOOT_READY,
            generation: copyString(info.generation_id),
            titleID: copyString(info.title_id),
            title: copyString(info.title),
            version: copyString(info.version),
            category: copyString(info.category),
            contentID: copyString(info.content_id),
            ebootRelativePath: copyString(info.eboot_relative_path),
            iconRelativePath: copyString(info.icon_relative_path),
            fileCount: info.file_count,
            totalBytes: info.total_bytes,
            detail: copyString(info.detail),
            resultDescription: copyString(v3kios_result_description(result))
        )
    }

    nonisolated private static func makeGameItem(
        snapshot: GameInventorySnapshot,
        container: URL,
        supportRoot: URL
    ) -> GameLibraryItem {
        let relative = container.path.replacingOccurrences(
            of: supportRoot.path + "/",
            with: "",
            options: [.anchored]
        )
        return GameLibraryItem(
            generation: snapshot.generation,
            titleID: snapshot.titleID,
            title: snapshot.title,
            version: snapshot.version,
            category: snapshot.category,
            contentID: snapshot.contentID,
            containerRelativePath: relative,
            ebootRelativePath: snapshot.ebootRelativePath,
            iconRelativePath: snapshot.iconRelativePath,
            fileCount: snapshot.fileCount,
            totalBytes: snapshot.totalBytes
        )
    }

    nonisolated private static func resolveGameRoot(_ container: URL) -> URL? {
        let fileManager = FileManager.default
        let isRoot = fileManager.fileExists(atPath: container.appendingPathComponent("eboot.bin").path) &&
            fileManager.fileExists(atPath: container.appendingPathComponent("sce_sys/param.sfo").path)
        if isRoot { return container }
        guard let children = try? fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let candidates = children.filter { child in
            fileManager.fileExists(atPath: child.appendingPathComponent("eboot.bin").path) &&
                fileManager.fileExists(atPath: child.appendingPathComponent("sce_sys/param.sfo").path)
        }
        return candidates.count == 1 ? candidates[0] : nil
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

    nonisolated private static func installAndInventoryFirmwarePUP(
        source: URL,
        supportRoot: URL,
        handle: v3kios_core_handle_t
    ) throws -> FirmwareInventorySnapshot {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        var info = v3kios_pup_info_v1()
        info.struct_size = UInt32(MemoryLayout<v3kios_pup_info_v1>.size)
        let preflight = source.path.withCString {
            v3kios_core_inspect_firmware_pup(handle, $0, &info)
        }
        guard preflight.rawValue == 0 else {
            throw FirmwareImportError.failed(copyString(v3kios_result_description(preflight)))
        }

        let fileManager = FileManager.default
        let firmwareRoot = supportRoot.appendingPathComponent("Firmware", isDirectory: true)
        let generationsRoot = firmwareRoot.appendingPathComponent("Generations", isDirectory: true)
        try fileManager.createDirectory(at: generationsRoot, withIntermediateDirectories: true)
        let staging = firmwareRoot.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let installResult = source.path.withCString { pupPath in
                staging.path.withCString { vitaFsPath in
                    v3kios_core_install_firmware_pup(handle, pupPath, vitaFsPath)
                }
            }
            guard installResult.rawValue == 0 else {
                throw FirmwareImportError.failed(copyString(v3kios_result_description(installResult)))
            }
            let staged = inventory(path: staging.path, handle: handle)
            guard staged.ready else {
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
            ready: inventory.state == V3KIOS_FIRMWARE_DIRECT_GAME_READY ||
                inventory.state == V3KIOS_FIRMWARE_SHELL_READY,
            systemSoftwareReady: inventory.state == V3KIOS_FIRMWARE_SHELL_READY,
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
            "jitEnabledAtReportTime": jitEnabled,
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
    static let gameInventory: UInt64 = 1 << 9
    static let directGamePreflight: UInt64 = 1 << 10
    static let inputState: UInt64 = 1 << 11
    static let metricsSnapshot: UInt64 = 1 << 12
    static let displaySurface: UInt64 = 1 << 13
    static let firmwarePUPInstall: UInt64 = 1 << 14
}

struct GameLibraryItem: Identifiable, Hashable, Sendable {
    var id: String { generation }
    let generation: String
    let titleID: String
    let title: String
    let version: String
    let category: String
    let contentID: String
    let containerRelativePath: String
    let ebootRelativePath: String
    let iconRelativePath: String
    let fileCount: UInt32
    let totalBytes: UInt64
}

struct ControllerInputSnapshot: Equatable, Sendable {
    var buttons: UInt32 = 0
    var leftX: Float = 0
    var leftY: Float = 0
    var rightX: Float = 0
    var rightY: Float = 0
}

struct PerformanceMetrics: Equatable, Sendable {
    var validityMask: UInt32 = 0
    var guestFPS: Float = 0
    var frameTimeMS: Float = 0
    var hostCPUPercent: Float = 0
    var hostMemoryBytes: UInt64 = 0

    func has(_ bit: UInt32) -> Bool {
        (validityMask & bit) != 0
    }
}

enum MetricValidity {
    static let guestFPS: UInt32 = 1 << 0
    static let frameTime: UInt32 = 1 << 1
    static let hostCPU: UInt32 = 1 << 2
    static let hostMemory: UInt32 = 1 << 3
}

enum VitaInputButton {
    static let select: UInt32 = 1 << 0
    static let start: UInt32 = 1 << 3
    static let up: UInt32 = 1 << 4
    static let right: UInt32 = 1 << 5
    static let down: UInt32 = 1 << 6
    static let left: UInt32 = 1 << 7
    static let l: UInt32 = 1 << 8
    static let r: UInt32 = 1 << 9
    static let triangle: UInt32 = 1 << 12
    static let circle: UInt32 = 1 << 13
    static let cross: UInt32 = 1 << 14
    static let square: UInt32 = 1 << 15
    static let ps: UInt32 = 1 << 16
}

private struct FirmwareInventorySnapshot: Sendable {
    let ready: Bool
    let systemSoftwareReady: Bool
    let version: String
    let generation: String
    let partitionMask: UInt32
    let fileCount: UInt32
    let totalBytes: UInt64
    let shellPath: String
    let detail: String
    let resultDescription: String
}

private struct GameInventorySnapshot: Sendable {
    let ready: Bool
    let generation: String
    let titleID: String
    let title: String
    let version: String
    let category: String
    let contentID: String
    let ebootRelativePath: String
    let iconRelativePath: String
    let fileCount: UInt32
    let totalBytes: UInt64
    let detail: String
    let resultDescription: String
}

private enum FirmwareImportError: LocalizedError {
    case notReady(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .notReady(detail):
            return detail
        case let .failed(detail):
            return detail
        }
    }
}

private enum GameImportError: LocalizedError {
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case let .notReady(detail):
            return detail
        }
    }
}
