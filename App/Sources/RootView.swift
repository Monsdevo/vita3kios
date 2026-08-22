import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var core: CoreStatusModel
    @State private var showingSettings = false
    @State private var showingPUPImporter = false
    @State private var showingVitaFSImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    readiness
                    firmware
                    library
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
                Button("Import", systemImage: "plus") {}
                    .disabled(true)
            }

            ContentUnavailableView {
                Label("No Games", systemImage: "rectangle.stack")
            } description: {
                Text("Game import becomes available after the core boot gate passes.")
            } actions: {
                Button("Import Game", systemImage: "square.and.arrow.down") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
