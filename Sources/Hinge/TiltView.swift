import AppKit
import QuartzCore

/// Draws the captured desktop as a plane that stands still while the panel moves.
///
/// Two copies of the same frame sit in a transformed container: a sharp one and
/// a blurred one masked by a vertical gradient. Moving that gradient down is
/// what makes the blur creep in from the top edge.
final class TiltView: NSView {
    private let plane = CALayer()
    private let sharp = CALayer()
    private let blurred = CALayer()
    private let blurMask = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Core Image filters on a layer are opt-in for layer-backed views.
        layerUsesCoreImageFilters = true
        layer?.backgroundColor = NSColor.black.cgColor

        // The hinge: this edge never moves, so anchor the transform there.
        plane.anchorPoint = CGPoint(x: 0.5, y: 0)
        plane.masksToBounds = false
        plane.shadowColor = NSColor.black.cgColor
        plane.shadowOffset = CGSize(width: 0, height: -24)
        plane.shadowRadius = 48

        for layer in [sharp, blurred] {
            layer.contentsGravity = .resize
            layer.anchorPoint = CGPoint(x: 0, y: 0)
            plane.addSublayer(layer)
        }
        blurMask.colors = [NSColor.white.cgColor, NSColor.clear.cgColor]
        blurMask.anchorPoint = CGPoint(x: 0, y: 0)
        blurred.mask = blurMask

        layer?.addSublayer(plane)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        withoutAnimation {
            plane.bounds = bounds
            plane.position = CGPoint(x: bounds.midX, y: bounds.minY)
            for layer in [sharp, blurred, blurMask] {
                layer.bounds = bounds
                layer.position = .zero
            }
            // An explicit path keeps the shadow visible under a blur filter.
            plane.shadowPath = CGPath(rect: bounds, transform: nil)
        }
    }

    func show(_ surface: IOSurfaceRef) {
        withoutAnimation {
            sharp.contents = surface
            blurred.contents = surface
        }
    }

    func apply(tiltDegrees: Double, settings: Settings) {
        withoutAnimation {
            plane.transform = Tilt.transform(tiltDegrees: tiltDegrees,
                                             perspective: settings.perspective,
                                             screenHeight: bounds.height)
            plane.shadowOpacity = Float(Tilt.clamp01(settings.shadow))

            // ponytail: full-screen CIGaussianBlur every frame; move to a Metal
            // pass if this ever shows up as a frame-time problem.
            let radius = Tilt.blurRadius(tiltDegrees: tiltDegrees, maxBlur: settings.blur)
            blurred.isHidden = radius < 0.5
            guard !blurred.isHidden else { return }
            blurred.filters = [CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": radius])]
                .compactMap { $0 }
            // Opaque at the top edge, fading out at the frontier as it descends.
            blurMask.startPoint = CGPoint(x: 0.5, y: 1)
            blurMask.endPoint = CGPoint(x: 0.5, y: Tilt.blurFrontier(tiltDegrees: tiltDegrees))
        }
    }

    /// Layer property changes animate by default, which would lag the sensor.
    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
