import SwiftUI

enum PlayStationAccent {
    static let blue = Color(red: 0.00, green: 0.44, blue: 0.80)
    static let red = Color(red: 0.83, green: 0.15, blue: 0.22)
    static let green = Color(red: 0.00, green: 0.65, blue: 0.32)
    static let pink = Color(red: 0.93, green: 0.30, blue: 0.58)
}

struct AccentGlyphs: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "xmark")
                .foregroundStyle(PlayStationAccent.blue)
            Image(systemName: "circle")
                .foregroundStyle(PlayStationAccent.red)
            Image(systemName: "triangle")
                .foregroundStyle(PlayStationAccent.green)
            Image(systemName: "square")
                .foregroundStyle(PlayStationAccent.pink)
        }
        .font(.caption2.weight(.semibold))
        .accessibilityHidden(true)
    }
}

struct ReadinessCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Label(ready ? "Ready" : "Pending", systemImage: ready ? "checkmark.circle.fill" : "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(ready ? .green : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
