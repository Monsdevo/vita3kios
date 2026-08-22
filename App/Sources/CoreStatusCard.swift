import SwiftUI

struct CoreStatusCard: View {
    @Bindable var core: CoreStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Core Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    core.refresh()
                }
                .labelStyle(.iconOnly)
            }

            if let error = core.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                LabeledContent("Core ABI", value: "v\(core.abiVersion)")
                LabeledContent("Vita3K", value: core.upstreamVersion)
                LabeledContent("Platform", value: core.platform)
                LabeledContent("Upstream commit", value: short(core.upstreamCommit))
                LabeledContent("Allocator self-test", value: core.allocatorTestPassed ? "Passed" : "Failed")
                    .foregroundStyle(core.allocatorTestPassed ? Color.primary : Color.red)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func short(_ value: String) -> String {
        String(value.prefix(12))
    }
}
