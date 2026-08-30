import Combine
import SwiftUI
import UIKit

struct GameplayView: View {
    @Bindable var core: CoreStatusModel
    let game: GameLibraryItem
    let close: () -> Void

    @State private var input = ControllerInputSnapshot()
    @State private var didRequestBoot = false
    private let metricsTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                GameDisplayView { layer, drawableSize, scale in
                    guard !didRequestBoot, core.attachDisplaySurface(
                        layer,
                        drawableSize: drawableSize,
                        scale: scale
                    ) else { return }
                    didRequestBoot = true
                    core.bootDirectGame(game)
                } surfaceDetached: {
                    core.detachDisplaySurface()
                }
                    .aspectRatio(960.0 / 544.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if core.directBootCheckpoint != "First guest game frame presented" {
                    bootStatus
                }

                VitaTouchController(input: $input)
                    .padding(.horizontal, max(12, geometry.safeAreaInsets.leading + 8))
                    .padding(.bottom, max(10, geometry.safeAreaInsets.bottom + 4))

                PerformanceHUD(metrics: core.metrics)
                    .padding(.leading, max(10, geometry.safeAreaInsets.leading + 8))
                    .padding(.top, max(10, geometry.safeAreaInsets.top + 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.trailing, max(10, geometry.safeAreaInsets.trailing + 8))
                .padding(.top, max(10, geometry.safeAreaInsets.top + 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityLabel("Close Game")
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear {
            requestOrientation(.landscape)
        }
        .onChange(of: input) { _, value in
            core.submitInput(value)
        }
        .onReceive(metricsTimer) { _ in
            core.refreshMetrics()
        }
        .onDisappear {
            core.submitInput(ControllerInputSnapshot())
            core.endDirectGameSession()
            requestOrientation(.portrait)
        }
    }

    private func requestOrientation(_ orientations: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        }
    }

    private var bootStatus: some View {
        VStack(spacing: 7) {
            Text(game.title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(core.directBootCheckpoint)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            if !core.directBootDetail.isEmpty {
                Text(core.directBootDetail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 80)
        .allowsHitTesting(false)
    }
}

private struct PerformanceHUD: View {
    let metrics: PerformanceMetrics

    var body: some View {
        HStack(spacing: 8) {
            Text(metric(metrics.has(MetricValidity.guestFPS), metrics.guestFPS, suffix: " FPS"))
            Text(metric(metrics.has(MetricValidity.frameTime), metrics.frameTimeMS, suffix: " ms"))
            if metrics.has(MetricValidity.hostCPU) {
                Text(String(format: "%.0f%% CPU", metrics.hostCPUPercent))
            }
            if metrics.has(MetricValidity.hostMemory) {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(metrics.hostMemoryBytes), countStyle: .memory)) MEM")
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.62), in: Capsule())
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    private func metric(_ valid: Bool, _ value: Float, suffix: String) -> String {
        valid ? String(format: "%.1f%@", value, suffix) : "—\(suffix)"
    }
}

private struct VitaTouchController: View {
    @Binding var input: ControllerInputSnapshot

    var body: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                VStack(spacing: 10) {
                    ShoulderTouchButton(label: "L") {
                        setButton(VitaInputButton.l, pressed: $0)
                    }
                    DPad { button, pressed in setButton(button, pressed: pressed) }
                    VirtualStick { x, y in
                        input.leftX = x
                        input.leftY = y
                    }
                }

                Spacer()

                HStack(spacing: 18) {
                    SmallTouchButton(label: "SELECT") {
                        setButton(VitaInputButton.select, pressed: $0)
                    }
                    PSButton {
                        setButton(VitaInputButton.ps, pressed: $0)
                    }
                    SmallTouchButton(label: "START") {
                        setButton(VitaInputButton.start, pressed: $0)
                    }
                }
                .padding(.bottom, 8)

                Spacer()

                VStack(spacing: 10) {
                    ShoulderTouchButton(label: "R") {
                        setButton(VitaInputButton.r, pressed: $0)
                    }
                    FaceButtons { button, pressed in setButton(button, pressed: pressed) }
                    VirtualStick { x, y in
                        input.rightX = x
                        input.rightY = y
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func setButton(_ button: UInt32, pressed: Bool) {
        if pressed {
            input.buttons |= button
        } else {
            input.buttons &= ~button
        }
    }
}

private struct ShoulderTouchButton: View {
    let label: String
    let changed: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .frame(width: 72, height: 30)
            .foregroundStyle(.white.opacity(0.8))
            .background(.black.opacity(pressed ? 0.72 : 0.42), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(pressed ? 0.7 : 0.3), lineWidth: 1))
            .scaleEffect(pressed ? 0.94 : 1)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        changed(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        changed(false)
                    }
            )
            .accessibilityLabel("\(label) Shoulder Button")
    }
}

private struct PSButton: View {
    let changed: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text("PS")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .frame(width: 27, height: 27)
            .background(.black.opacity(pressed ? 0.72 : 0.42), in: Circle())
            .overlay(Circle().stroke(PlayStationAccent.blue.opacity(0.75), lineWidth: 1))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        changed(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        changed(false)
                    }
            )
            .accessibilityLabel("PS Button")
    }
}

private struct DPad: View {
    let changed: (UInt32, Bool) -> Void

    var body: some View {
        ZStack {
            TouchButton(symbol: "chevron.up", color: .white.opacity(0.72)) {
                changed(VitaInputButton.up, $0)
            }
            .offset(y: -34)
            TouchButton(symbol: "chevron.down", color: .white.opacity(0.72)) {
                changed(VitaInputButton.down, $0)
            }
            .offset(y: 34)
            TouchButton(symbol: "chevron.left", color: .white.opacity(0.72)) {
                changed(VitaInputButton.left, $0)
            }
            .offset(x: -34)
            TouchButton(symbol: "chevron.right", color: .white.opacity(0.72)) {
                changed(VitaInputButton.right, $0)
            }
            .offset(x: 34)
        }
        .frame(width: 108, height: 108)
    }
}

private struct FaceButtons: View {
    let changed: (UInt32, Bool) -> Void

    var body: some View {
        ZStack {
            TouchButton(symbol: "triangle", color: PlayStationAccent.green) {
                changed(VitaInputButton.triangle, $0)
            }
            .offset(y: -34)
            TouchButton(symbol: "xmark", color: PlayStationAccent.blue) {
                changed(VitaInputButton.cross, $0)
            }
            .offset(y: 34)
            TouchButton(symbol: "square", color: PlayStationAccent.pink) {
                changed(VitaInputButton.square, $0)
            }
            .offset(x: -34)
            TouchButton(symbol: "circle", color: PlayStationAccent.red) {
                changed(VitaInputButton.circle, $0)
            }
            .offset(x: 34)
        }
        .frame(width: 108, height: 108)
    }
}

private struct TouchButton: View {
    let label: String?
    let symbol: String?
    let color: Color
    let changed: (Bool) -> Void
    @State private var pressed = false

    init(label: String, color: Color, changed: @escaping (Bool) -> Void) {
        self.label = label
        symbol = nil
        self.color = color
        self.changed = changed
    }

    init(symbol: String, color: Color, changed: @escaping (Bool) -> Void) {
        label = nil
        self.symbol = symbol
        self.color = color
        self.changed = changed
    }

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
            } else {
                Text(label ?? "")
            }
        }
        .font(.caption.bold())
        .frame(width: 42, height: 42)
        .foregroundStyle(color)
        .background(.black.opacity(pressed ? 0.72 : 0.42), in: Circle())
        .overlay(Circle().stroke(.white.opacity(pressed ? 0.7 : 0.3), lineWidth: 1))
        .scaleEffect(pressed ? 0.92 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    changed(true)
                }
                .onEnded { _ in
                    pressed = false
                    changed(false)
                }
        )
    }
}

private struct SmallTouchButton: View {
    let label: String
    let changed: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .frame(width: 48, height: 25)
            .background(.black.opacity(pressed ? 0.72 : 0.42), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        changed(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        changed(false)
                    }
            )
    }
}

private struct VirtualStick: View {
    let changed: (Float, Float) -> Void
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            Circle()
                .fill(.black.opacity(0.34))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .overlay {
                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: radius, height: radius)
                        .offset(offset)
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = value.location.x - proxy.size.width / 2
                            let dy = value.location.y - proxy.size.height / 2
                            let distance = max(1, hypot(dx, dy))
                            let maximum = radius * 0.58
                            let scale = min(1, maximum / distance)
                            offset = CGSize(width: dx * scale, height: dy * scale)
                            changed(Float(offset.width / maximum), Float(offset.height / maximum))
                        }
                        .onEnded { _ in
                            offset = .zero
                            changed(0, 0)
                        }
                )
        }
        .frame(width: 82, height: 82)
        .accessibilityLabel("Analog Stick")
    }
}
