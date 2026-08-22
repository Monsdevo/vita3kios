import SwiftUI

struct RootView: View {
    @Bindable var core: CoreStatusModel
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    readiness
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
                    detail: "Official user-supplied firmware is required.",
                    symbol: "internaldrive",
                    color: PlayStationAccent.red,
                    ready: false
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
