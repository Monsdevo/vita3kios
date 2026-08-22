import QuartzCore
import SwiftUI
import UIKit

final class VitaMetalSurfaceView: UIView {
    var surfaceChanged: ((CAMetalLayer, CGSize, CGFloat) -> Void)?
    var surfaceDetached: (() -> Void)?
    private var lastReportedDrawableSize = CGSize.zero

    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        metalLayer.framebufferOnly = true
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.contentsScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )
        reportSurfaceIfNeeded()
    }

    func reportSurfaceIfNeeded(force: Bool = false) {
        guard metalLayer.drawableSize.width > 0, metalLayer.drawableSize.height > 0 else { return }
        guard force || metalLayer.drawableSize != lastReportedDrawableSize else { return }
        lastReportedDrawableSize = metalLayer.drawableSize
        surfaceChanged?(metalLayer, metalLayer.drawableSize, metalLayer.contentsScale)
    }
}

struct GameDisplayView: UIViewRepresentable {
    let surfaceChanged: (CAMetalLayer, CGSize, CGFloat) -> Void
    let surfaceDetached: () -> Void

    func makeUIView(context: Context) -> VitaMetalSurfaceView {
        let view = VitaMetalSurfaceView()
        view.surfaceChanged = surfaceChanged
        view.surfaceDetached = surfaceDetached
        return view
    }

    func updateUIView(_ uiView: VitaMetalSurfaceView, context: Context) {
        uiView.surfaceChanged = surfaceChanged
        uiView.surfaceDetached = surfaceDetached
        uiView.setNeedsLayout()
        uiView.reportSurfaceIfNeeded(force: true)
    }

    static func dismantleUIView(_ uiView: VitaMetalSurfaceView, coordinator: ()) {
        uiView.surfaceDetached?()
        uiView.surfaceChanged = nil
        uiView.surfaceDetached = nil
    }
}
