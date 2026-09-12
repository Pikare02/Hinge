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
    /// Where the eye sits, as a fraction of the screen height above the hinge.
    /// Calibration assumes the viewer is looking straight down the panel's
    /// normal, through the middle of the screen.
    static let eyeHeightFraction = 0.5

    /// Viewing distance, in screen heights, chosen so the illusion is as strong
    /// as it can be without cheating. Closing the lid a little leaves the
    /// virtual display short of the panel's top edge, and the gap has to be
    /// covered by stretching the image; requiring that stretch to stay under 1%
    /// puts a floor under the distance. Solving
    ///   D ≥ h(½+ε)·sinΔ / (1+ε−cosΔ)
    /// over every angle gives its worst case at Δ = √(2ε) ≈ 8°, and a distance
    /// of 3.6 screen heights. On a 15-inch MacBook that is about 72 cm, which
    /// is roughly where a person actually sits.
    static let honestEyeDistanceInHeights = 3.6

    /// The lid can only close so far before the eye would end up behind the
    /// panel, and the panel angle itself caps how much travel is left.
    static func maxTiltDegrees(flatAngle: Double) -> Double {
        min(max(flatAngle - 20, 0), 55)
    }

    /// The panel swings by exactly as much as the lid moves: anything else
    /// would break the illusion it is meant to hold up.
    static func tiltDegrees(lidAngle: Double, flatAngle: Double) -> Double {
        min(max(0, flatAngle - lidAngle), maxTiltDegrees(flatAngle: flatAngle))
    }

    /// 0 when flat, 1 at the end of the travel. Drives everything that fades in.
    static func progress(tiltDegrees: Double, flatAngle: Double) -> Double {
        let limit = maxTiltDegrees(flatAngle: flatAngle)
        return limit > 0 ? clamp01(tiltDegrees / limit) : 0
    }

    /// The automatic distance at full strength; the slider only backs away from
    /// it, which softens the correction. It never moves closer, because closer
    /// is where the stretch starts showing.
    static func eyeDistance(perspective: Double, screenHeight: Double) -> Double {
        screenHeight * honestEyeDistanceInHeights * (2.0 - clamp01(perspective))
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
    static func blurFrontier(tiltDegrees: Double, flatAngle: Double) -> Double {
        1 - progress(tiltDegrees: tiltDegrees, flatAngle: flatAngle)
    }

    /// Blur follows the tilt, so a flat desktop stays sharp and the slider only
    /// sets how far the blur goes at full tilt.
    static func blurRadius(tiltDegrees: Double, flatAngle: Double, maxBlur: Double) -> Double {
        progress(tiltDegrees: tiltDegrees, flatAngle: flatAngle) * clamp01(maxBlur) * 24
    }

    /// How long the smoothing takes to close most of a gap. The sensor reports
    /// whole degrees and holds them without a flicker, so the filter is only
    /// rounding off the one-degree steps as the lid crosses them. Every
    /// millisecond past that is the panel arriving late.
    static let smoothingTime = 0.025

    /// Low-pass filter on the raw reading, written against elapsed time rather
    /// than frames so the panel behaves the same on a display of any rate.
    static func smooth(previous: Double, target: Double, dt: Double,
                       tau: Double = smoothingTime) -> Double {
        guard dt > 0, tau > 0 else { return target }
        return previous + (target - previous) * (1 - exp(-dt / tau))
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
        let flatAngles = [60.0, 75.0, 90.0, 110.0, 135.0]

        for flat in flatAngles {
            let limit = maxTiltDegrees(flatAngle: flat)
            assert(limit > 0, "there must be travel to use at flat angle \(flat)")
            assert(tiltDegrees(lidAngle: flat, flatAngle: flat) == 0, "the flat angle must be flat")
            assert(tiltDegrees(lidAngle: flat + 40, flatAngle: flat) == 0, "opening past flat must stay flat")
            // The panel swings by exactly what the lid gave up.
            assert(tiltDegrees(lidAngle: flat - 10, flatAngle: flat) == min(10, limit),
                   "the swing must match the lid movement at flat angle \(flat)")
            assert(tiltDegrees(lidAngle: 0, flatAngle: flat) == limit, "tilt must clamp")
            var previous = 0.0
            for lid in stride(from: flat, through: 0, by: -1) {
                let t = tiltDegrees(lidAngle: lid, flatAngle: flat)
                assert(t >= previous, "tilt must grow monotonically as the lid closes")
                previous = t
            }
        }

        // Flat leaves the desktop untouched.
        let flatTransform = transform(tiltDegrees: 0, perspective: 0.5, screenHeight: h)
        assert(flatTransform.m11 == 1 && flatTransform.m22 == 1 && flatTransform.m24 == 0,
               "a flat desktop must be drawn as-is")

        for flat in flatAngles {
            let limit = maxTiltDegrees(flatAngle: flat)
            for perspective in [0.0, 0.5, 1.0] {
                for tilt in stride(from: 0.0, through: limit, by: 1) {
                    let m = transform(tiltDegrees: tilt, perspective: perspective, screenHeight: h)
                    let bottom = project(0, m)
                    let top = project(h, m)

                    // The hinge is fixed: the bottom edge never moves or resizes.
                    assert(abs(bottom.y) < 1e-9, "the bottom edge must stay on the hinge")
                    assert(bottom.widthScale == 1,
                           "the bottom edge must stay exactly full width at tilt \(tilt)")

                    // Higher up the panel is nearer the eye, so it is drawn narrower.
                    if tilt > 1 {
                        assert(top.widthScale < bottom.widthScale,
                               "a tilted panel must narrow toward the top at tilt \(tilt)")
                    }

                    // No black band: content must reach the top edge of the panel.
                    assert(top.y >= h - 1e-6, "content must cover the panel at tilt \(tilt)")

                    // The eye must stay in front of the panel, and the stretch
                    // must stay the small correction it is meant to be.
                    let scale = overscan(tiltDegrees: tilt, perspective: perspective, screenHeight: h)
                    assert(scale >= 1, "the stretch must never shrink the image")
                    assert(scale < 1.011, "the stretch must stay near 1%, got \(scale) at tilt \(tilt)")
                }
            }
        }

        // Blur starts at the top and works down, and is off when flat.
        assert(blurFrontier(tiltDegrees: 0, flatAngle: 90) == 1, "a flat desktop must be sharp all the way up")
        assert(blurFrontier(tiltDegrees: maxTiltDegrees(flatAngle: 90), flatAngle: 90) == 0,
               "the end of the travel must blur to the bottom")
        assert(blurFrontier(tiltDegrees: 20, flatAngle: 90) < blurFrontier(tiltDegrees: 5, flatAngle: 90),
               "the blur must descend as the lid closes")
        assert(blurRadius(tiltDegrees: 0, flatAngle: 90, maxBlur: 1) == 0, "a flat desktop must stay sharp")
        assert(blurRadius(tiltDegrees: 30, flatAngle: 90, maxBlur: 0) == 0, "a zeroed slider must stay sharp")

        // Smoothing converges, never overshoots, and lands in the same place
        // whatever rate it is stepped at: twice the frames, half the step.
        var v = 0.0
        for _ in 0..<200 { v = smooth(previous: v, target: 90, dt: 1.0 / 60) }
        assert(abs(v - 90) < 0.01, "smoothing must converge on the target")
        assert(v <= 90, "smoothing must not overshoot the target")
        var slow = 0.0, fast = 0.0
        for _ in 0..<6 { slow = smooth(previous: slow, target: 90, dt: 1.0 / 60) }
        for _ in 0..<12 { fast = smooth(previous: fast, target: 90, dt: 1.0 / 120) }
        assert(abs(slow - fast) < 0.01, "the same elapsed time must give the same angle at any frame rate")
        assert(smooth(previous: 0, target: 90, dt: 0) == 90, "a first reading must be taken as-is")
        // What the filter costs: most of a one-degree step is gone within a
        // couple of frames, which is what keeps it from feeling delayed.
        let step = smooth(previous: 0, target: 1, dt: 2.0 / 60)
        assert(step > 0.7, "a one-degree step must be most of the way home in two frames, got \(step)")
        assert(clamp01(-1) == 0 && clamp01(2) == 1, "clamp01 must bound both ends")
        print("Tilt.selfCheck passed")
    }
}
