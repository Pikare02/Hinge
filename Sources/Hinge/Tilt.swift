import QuartzCore

/// Keeps a virtual display standing still in the room while the physical panel
/// swings toward the viewer.
///
/// The lid hinges at the bottom edge, so that edge never moves. Everything
/// above it is drawn where the eye would have to look to still see the upright
/// display. Because the top of the panel has come closer to the eye, a given
/// real width covers fewer panel points up there, so the drawn image narrows
/// toward the top. The top of the virtual display falls past the panel edge and
/// is simply cut off, which is what happens in the room too.
///
/// Derivation, with the hinge at the origin, y up, z toward the eye, the eye at
/// (0, E, D) and the panel rotated by Δ:
///   a panel point u sits at (u·cosΔ, u·sinΔ), and the ray from the eye through
///   it meets the virtual plane z = 0 at height E + t(u·cosΔ − E), t = D/(D − u·sinΔ).
/// Solving that for u and writing C = D·cosΔ − E·sinΔ (the eye's distance from
/// the tilted panel) gives the homography this file applies:
///   x' = x / w,  y' = y·(D/C) / w,  w = 1 + y·sinΔ/C
enum Tilt {
    /// Visual tilt is clamped so the panel never swings past a readable angle.
    static let maxTiltDegrees = 32.0
    /// Degrees of panel swing per degree of lid movement below the flat angle.
    static let defaultGain = 0.6
    /// Where the eye sits, as a fraction of the screen height above the hinge.
    static let eyeHeightFraction = 0.5

    /// At or above `flatAngle` the desktop sits flat; closing the lid tilts it.
    static func tiltDegrees(lidAngle: Double, flatAngle: Double, gain: Double = defaultGain) -> Double {
        let raw = max(0, flatAngle - lidAngle) * gain
        return min(raw, maxTiltDegrees)
    }

    /// 0 when flat, 1 at full tilt. Drives everything that fades in with the tilt.
    static func progress(tiltDegrees: Double) -> Double {
        clamp01(tiltDegrees / maxTiltDegrees)
    }

    /// How far the eye sits from the hinge. The slider moves it between a
    /// distant viewer, where the correction is subtle, and a near one.
    static func eyeDistance(perspective: Double, screenHeight: Double) -> Double {
        screenHeight * (6.0 - clamp01(perspective) * 4.5)
    }

    /// The virtual display does not always reach the top of the tilted panel.
    /// Stretching it upward by this much, about the hinge, keeps the panel
    /// covered instead of leaving a black band. It stays within a few percent,
    /// and it is deliberately vertical only: widening it would push the bottom
    /// edge past the sides of the screen, and that edge must not move.
    static func overscan(tiltDegrees: Double, perspective: Double, screenHeight h: Double) -> Double {
        let (d, c, sinT) = geometry(tiltDegrees: tiltDegrees, perspective: perspective, screenHeight: h)
        return max(1, c / (d - h * sinT))
    }

    private static func geometry(tiltDegrees: Double, perspective: Double, screenHeight h: Double)
        -> (d: Double, c: Double, sinT: Double) {
        let t = tiltDegrees * .pi / 180
        let d = eyeDistance(perspective: perspective, screenHeight: h)
        let e = h * eyeHeightFraction
        return (d, d * cos(t) - e * sin(t), sin(t))
    }

    static func transform(tiltDegrees: Double, perspective: Double, screenHeight h: Double) -> CATransform3D {
        let (d, c, sinT) = geometry(tiltDegrees: tiltDegrees, perspective: perspective, screenHeight: h)
        let s = overscan(tiltDegrees: tiltDegrees, perspective: perspective, screenHeight: h)
        var t = CATransform3DIdentity
        t.m22 = s * d / c
        t.m24 = s * sinT / c
        return t
    }

    /// Where the blur has reached, as a fraction of the height: 1 is the top
    /// edge, 0 the bottom. The blur creeps down from the top as the lid closes.
    static func blurFrontier(tiltDegrees: Double) -> Double {
        1 - progress(tiltDegrees: tiltDegrees)
    }

    /// Blur follows the tilt, so a flat desktop stays sharp and the slider only
    /// sets how far the blur goes at full tilt.
    static func blurRadius(tiltDegrees: Double, maxBlur: Double) -> Double {
        progress(tiltDegrees: tiltDegrees) * clamp01(maxBlur) * 24
    }

    /// Low-pass filter that takes the jitter out of the raw sensor reading.
    static func smooth(previous: Double, target: Double, factor: Double = 0.25) -> Double {
        previous + (target - previous) * factor
    }

    static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    // MARK: - Self check

    /// Where content at height `y` lands on the panel, and how wide it is drawn.
    private static func project(_ y: Double, _ m: CATransform3D) -> (y: Double, widthScale: Double) {
        let w = 1 + y * m.m24
        return (y * m.m22 / w, m.m11 / w)
    }

    static func selfCheck() {
        let h = 1118.0

        // Above the flat angle nothing happens, however far the lid opens.
        assert(tiltDegrees(lidAngle: 90, flatAngle: 90) == 0, "the flat angle must be flat")
        assert(tiltDegrees(lidAngle: 130, flatAngle: 90) == 0, "opening past flat must stay flat")
        assert(tiltDegrees(lidAngle: 70, flatAngle: 90) > 0, "closing must tilt")
        assert(tiltDegrees(lidAngle: 0, flatAngle: 90) == maxTiltDegrees, "tilt must clamp")
        var previous = 0.0
        for lid in stride(from: 90.0, through: 20.0, by: -1) {
            let t = tiltDegrees(lidAngle: lid, flatAngle: 90)
            assert(t >= previous, "tilt must grow monotonically as the lid closes")
            previous = t
        }

        // Flat leaves the desktop untouched.
        let flat = transform(tiltDegrees: 0, perspective: 0.5, screenHeight: h)
        assert(flat.m11 == 1 && flat.m22 == 1 && flat.m24 == 0, "a flat desktop must be drawn as-is")

        for perspective in [0.0, 0.5, 1.0] {
            for tilt in stride(from: 0.0, through: maxTiltDegrees, by: 1) {
                let m = transform(tiltDegrees: tilt, perspective: perspective, screenHeight: h)
                let bottom = project(0, m)
                let top = project(h, m)

                // The hinge is fixed: the bottom edge never moves or resizes.
                assert(abs(bottom.y) < 1e-9, "the bottom edge must stay on the hinge")
                assert(bottom.widthScale == 1,
                       "the bottom edge must stay exactly full width at tilt \(tilt)")

                // Higher up the panel is nearer the eye, so it must be drawn narrower.
                assert(top.widthScale <= bottom.widthScale + 1e-12,
                       "the drawn image must narrow toward the top at tilt \(tilt)")
                if tilt > 1 {
                    assert(top.widthScale < bottom.widthScale,
                           "a tilted panel must narrow toward the top at tilt \(tilt)")
                }

                // No black band: content must reach the top edge of the panel.
                assert(top.y >= h - 1e-6, "content must cover the panel at tilt \(tilt)")

                // The correction stays a correction, not a zoom.
                let scale = overscan(tiltDegrees: tilt, perspective: perspective, screenHeight: h)
                assert(scale >= 1 && scale < 1.1, "overscan must stay small, got \(scale)")
            }
        }

        // Blur starts at the top and works down, and is off when flat.
        assert(blurFrontier(tiltDegrees: 0) == 1, "a flat desktop must be sharp all the way up")
        assert(blurFrontier(tiltDegrees: maxTiltDegrees) == 0, "full tilt must blur to the bottom")
        assert(blurFrontier(tiltDegrees: maxTiltDegrees / 2) < blurFrontier(tiltDegrees: 1),
               "the blur must descend as the lid closes")
        assert(blurRadius(tiltDegrees: 0, maxBlur: 1) == 0, "a flat desktop must stay sharp")
        assert(blurRadius(tiltDegrees: maxTiltDegrees, maxBlur: 0) == 0, "a zeroed slider must stay sharp")

        var v = 0.0
        for _ in 0..<200 { v = smooth(previous: v, target: 90) }
        assert(abs(v - 90) < 0.01, "smoothing must converge on the target")
        assert(clamp01(-1) == 0 && clamp01(2) == 1, "clamp01 must bound both ends")
        print("Tilt.selfCheck passed")
    }
}
