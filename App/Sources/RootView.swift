import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var core: CoreStatusModel
    @State private var showingSettings = false
    @State private var showingPUPImporter = false
    @State private var showingVitaFSImporter = false
    @State private var showingGameImporter = false
    @State private var presentedGame: GameLibraryItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    readiness
                    library
                    firmware
                    CoreStatusCard(core: core)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(core: core)
            }
            .fileImporter(
                isPresented: $showingPUPImporter,
                allowedContentTypes: [UTType(filenameExtension: "pup") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    core.inspectFirmwarePUP(url)
                }
            }
            .fileImporter(
                isPresented: $showingVitaFSImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    core.importExtractedVitaFS(url)
                }
            }
            .fileImporter(
                isPresented: $showingGameImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    core.importExtractedGame(url)
                }
            }
            .fullScreenCover(item: $presentedGame, onDismiss: {
                core.endDirectGameSession()
            }) { game in
                GameplayView(core: core, game: game) {
                    core.endDirectGameSession()
                    presentedGame = nil
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("vita3kios")
                    .font(.title2.bold())
                Text("PlayStation Vita emulation for iPhone and iPad")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AccentGlyphs()
        }
        .padding(.top, 8)
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Readiness")
                .font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ReadinessCard(
                    title: "Firmware",
                    detail: core.firmwareReady ? "SceShell files are ready." : "Official user-supplied firmware is required.",
                    symbol: "internaldrive",
                    color: PlayStationAccent.red,
                    ready: core.firmwareReady
                )
                ReadinessCard(
                    title: "JIT",
                    detail: "Signed physical-device verification is required.",
                    symbol: "bolt.fill",
                    color: PlayStationAccent.green,
                    ready: false
                )
                ReadinessCard(
                    title: "Renderer",
                    detail: "MoltenVK device verification is required.",
                    symbol: "square.3.layers.3d",
                    color: PlayStationAccent.pink,
                    ready: false
                )
            }
        }
    }

    private var firmware: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("System Software")
                        .font(.title3.bold())
                    Text(core.firmwareVersion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: core.firmwareReady ? "checkmark.seal.fill" : "internaldrive")
                    .font(.title2)
                    .foregroundStyle(core.firmwareReady ? PlayStationAccent.green : PlayStationAccent.red)
                    .accessibilityHidden(true)
            }

            Text(core.firmwareDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if core.firmwareFileCount > 0 {
                LabeledContent("Inventory", value: "\(core.firmwareFileCount) files · \(ByteCountFormatter.string(fromByteCount: Int64(core.firmwareBytes), countStyle: .file))")
                    .font(.subheadline)
                LabeledContent("Shell", value: core.shellPath)
                    .font(.caption)
            }

            if let error = core.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack {
                Menu("Import Firmware", systemImage: "square.and.arrow.down") {
                    Button("Validate Official PUP", systemImage: "checkmark.shield") {
                        showingPUPImporter = true
                    }
                    Button("Import Extracted VitaFS", systemImage: "folder") {
                        showingVitaFSImporter = true
                    }
                }
                .buttonStyle(.bordered)

                Button("Boot System Software", systemImage: "play.fill") {
                    core.bootSystemSoftware()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!core.firmwareReady || core.firmwareBusy)
            }

            if core.bootCheckpoint != "Not started" {
                VStack(alignment: .leading, spacing: 5) {
                    Label(core.bootCheckpoint, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.semibold))
                    Text(core.bootBlocker)
                        .font(.caption)
                    if !core.bootDetail.isEmpty {
                        Text(core.bootDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if core.firmwareBusy {
                ProgressView()
                    .padding(16)
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Games")
                    .font(.title3.bold())
                Spacer()
                Button("Import", systemImage: "plus") {
                    showingGameImporter = true
                }
                    .disabled(core.gameImportBusy || core.gameLibraryBusy)
            }

            GameImportRequirementsCard()

            if core.games.isEmpty {
                ContentUnavailableView {
                    Label("No Games", systemImage: "rectangle.stack")
                } description: {
                    Text("Import a legally dumped extracted game folder containing eboot.bin and sce_sys/param.sfo.")
                } actions: {
                    Button("Import Extracted Game", systemImage: "square.and.arrow.down") {
                        showingGameImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(core.gameImportBusy || core.gameLibraryBusy)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(core.games) { game in
                        GameLibraryRow(core: core, game: game) {
                            presentedGame = game
                        }
                    }
                }
            }

            if core.gameLibraryBusy || core.gameImportBusy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(core.gameLibraryBusy ? "Loading game library…" : "Importing and validating game…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = core.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct GameImportRequirementsCard: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Accepted now: extracted game folder", systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))

                Text("Select the game root itself, or a parent folder containing exactly one game root.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("GAME_FOLDER/\n  eboot.bin\n  sce_sys/\n    param.sfo\n    icon0.png  (optional)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Label("Not accepted yet: VPK, ZIP, PKG, updates, or DLC", systemImage: "shippingbox")
                    .font(.footnote)

                Text("This build imports metadata and verifies the eboot container. It does not execute Vita guest code yet because the full Vita3K runtime is not linked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        } label: {
            Label("Game Import Requirements", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GameLibraryRow: View {
    let core: CoreStatusModel
    let game: GameLibraryItem
    let play: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            GameIcon(url: core.gameIconURL(for: game))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(game.titleID) · Version \(game.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: Int64(game.totalBytes), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button("Play", systemImage: "play.fill", action: play)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct GameIcon: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(PlayStationAccent.blue)
            }
        }
        .frame(width: 58, height: 58)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
