import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var core: CoreStatusModel

    var body: some View {
        NavigationStack {
            List {
                Section("Boot") {
                    Label("Direct Game", systemImage: "play.fill")
                    Label("System Software", systemImage: "rectangle.inset.filled")
                }

                Section("Firmware") {
                    LabeledContent("Version", value: core.firmwareVersion)
                    LabeledContent("System modules", value: core.firmwareReady ? "Installed" : "Not installed")
                    LabeledContent("PUP validation", value: availability(CoreCapability.firmwarePUPPreflight))
                    LabeledContent("PUP installation", value: availability(CoreCapability.firmwarePUPInstall))
                    LabeledContent("Partition inventory", value: availability(CoreCapability.firmwareInventory))
                    LabeledContent("Shell preflight", value: availability(CoreCapability.systemShellPreflight))
                }

                Section("Core") {
                    LabeledContent("ABI version", value: "\(core.abiVersion)")
                    LabeledContent("Architecture", value: core.platform)
                    LabeledContent("Direct Game", value: availability(CoreCapability.directGame))
                    LabeledContent("System Software", value: availability(CoreCapability.systemSoftware))
                    LabeledContent("Game inventory", value: availability(CoreCapability.gameInventory))
                    LabeledContent("Direct Game preflight", value: availability(CoreCapability.directGamePreflight))
                    LabeledContent("Native display surface", value: availability(CoreCapability.displaySurface))
                }

                Section("Interface") {
                    LabeledContent("Design", value: "Apple Native")
                    LabeledContent("Accent", value: "PlayStation-inspired")
                    LabeledContent("Touch controls", value: availability(CoreCapability.inputState))
                    LabeledContent("Performance HUD", value: "Top-left · Compact")
                }

                Section {
                    Text("Detailed global, boot-mode, and per-title controls will appear only when their core capabilities become functional.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func availability(_ bit: UInt64) -> String {
        core.has(bit) ? "Available" : "Not implemented"
    }
}
