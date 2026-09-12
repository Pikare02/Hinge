# Hinge design notes

A macOS app that reads the MacBook lid angle sensor and redraws the captured
desktop as though it were pinned in space, still standing at the angle where
the lid was fully open.

## Pieces

| File | Role |
| --- | --- |
| `LidAngleSensor.swift` | Reads feature report 1 from the HID sensor (usage page 0x20 / usage 0x8A) and returns the angle in degrees |
| `ScreenCapture.swift` | A ScreenCaptureKit stream that excludes this app and delivers IOSurface frames |
| `Tilt.swift` | The pure mapping from angle to transform. Free of AppKit, so it can check itself |
| `TiltView.swift` | Draws the plane. A sharp copy and a blurred copy, with a gradient mask moving the boundary |
| `SettingsView.swift` | The independent settings window: angle readout, flat angle, sliders, quit button |
| `LoginItem.swift` | The open-at-login toggle, backed by `SMAppService` |
| `Settings.swift` | Persists each value in `UserDefaults` |
| `AppController.swift` | Wiring, permission checks, windows, menu bar item, single-instance guard |
| `make_icon.py` | Draws the icon and writes `Resources/AppIcon.icns` |

## Data flow

The sensor is read once per displayed frame, on a display link, on the main
thread. A timer of its own drifts against the refresh and lands halfway through
a frame, which costs up to another frame before the panel shows the angle; the
read is under a millisecond, so it sits where the drawing already is.

The reading passes through a low-pass filter with a 25 ms time constant,
written against elapsed time rather than frames so a display of any rate
behaves the same. The filter is not there for jitter: the sensor reports whole
degrees and holds them without a flicker. It is there to round off the
one-degree steps as the lid crosses them, and every millisecond past that is
the panel arriving late.

Capture is a separate stream handing over IOSurfaces at 60 fps, which go
straight into the layer's `contents`. Both reach the layer on the main thread
with implicit animation turned off.

## From angle to tilt

At or above the flat angle (90 degrees by default) the tilt is zero. Below it
the panel swings by **exactly as much as the lid moved**. Scaling that down by
some factor would break the very illusion it is meant to hold up. The ceiling
follows from the flat angle: min(flat − 20, 55) degrees. Sensors differ between
machines, so the flat angle is not hard-coded; a slider (45 to 135 degrees) and
a button that adopts the current lid angle both set it, and it is saved.

## The display that stays put

The lid hinges at its bottom edge, so that edge never moves. Everything above
it is redrawn by asking where the eye would have to look to still see the
upright display. The top of the panel has come closer to the eye, so a given
real width covers fewer panel points up there. Drawing the image **narrower
toward the top** is what makes the width look unchanged from the front. The top
of the virtual display falls past the panel edge and is cut off.

The derivation, with the hinge at the origin, y up, z toward the eye, the eye
at (0, E, D) and the panel swung by Δ:

- a panel point u sits at (u·cosΔ, u·sinΔ), and the ray from the eye through it
  meets the virtual plane z = 0 at height E + t(u·cosΔ − E), where
  t = D/(D − u·sinΔ);
- solving that for u, and writing C = D·cosΔ − E·sinΔ for the eye's distance
  from the tilted panel, gives the projective transform the code applies:

```
x' = x / w        y' = y·(D/C) / w        w = 1 + y·sinΔ/C
```

The eye height E is half the screen height. Pressing the button that sets the
flat angle is taken to mean the line of sight runs down the panel's normal,
through the middle of the screen. Under that assumption the flat angle itself
drops out of the transform, and the only degree of freedom left is the viewing
distance D.

## Why the viewing distance is not a taste setting

D is derived. Closing the lid a little leaves the virtual display short of the
panel's top edge, and the gap has to be covered by stretching the image
vertically. Requiring that stretch to stay under 1% at every angle

```
D ≥ h(½+ε)·sinΔ / (1+ε−cosΔ)
```

puts a floor under D. The worst case sits at Δ = √(2ε) ≈ 8 degrees and gives
3.6 screen heights, about 72 cm on a 15-inch MacBook, roughly where a person
actually sits. The slider only moves away from that value, never closer, since
closer is where the stretch starts to show.

The stretch is vertical only. Widening would push the bottom edge past the
sides of the screen, and the bottom edge must not move.

## Blur descending

The blur starts at the top edge and creeps down as the lid closes. The same
frame is stacked twice, sharp and blurred, with a vertical gradient mask on the
blurred copy whose boundary drops with the tilt. The radius follows the tilt
too, so the slider is a ceiling on how far the blur goes, not a constant.

## Windows and staying resident

- **Overlay** — full screen, borderless, screen saver level. `ignoresMouseEvents`
  is set, so it never takes a click.
- **Settings** — an ordinary independent window. Closing it does not quit the
  app (`applicationShouldTerminateAfterLastWindowClosed` is false); the Dock
  icon or the menu bar item opens it again. Quitting for real is the button in
  settings, or Command-Q.
- The settings window is lifted above the overlay only while the overlay is up.
  The rest of the time it behaves like any other window.

A second instance would capture the first one's overlay, filling the screen
with nested copies of itself, so launching again hands over to the instance
already running and quits.

## When the overlay appears

While flat, the overlay is pixel-for-pixel the screen behind it, so it is not
shown until there is a tilt. That leaves the menu bar and the Dock usable at
normal angles. To stop it flickering at the boundary, it appears above 1 degree
of tilt and disappears below 0.2.

## Permission

Screen Recording is required. `CGPreflightScreenCaptureAccess()` is checked
before anything covers the screen; if it has not been granted, the app explains
where to grant it and quits. Reading the sensor needs no permission.

An ad-hoc signature changes hash on every build, which invalidates the existing
grant while it still shows as enabled. `make_app.sh` clears the stale record
with `tccutil reset` after signing, so the next launch asks properly.

## Checks

- `Hinge --selfcheck` — the angle mapping, the fixed bottom edge, narrowing
  toward the top, no black band at any angle, the stretch staying near 1%, and
  the blur descending
- `Hinge --probe` — the live lid angle and the permission state

## Known limits

- A full-screen `CIGaussianBlur` runs every frame. If frame time ever becomes a
  problem, move it to a Metal pass (there is a `ponytail:` comment at the spot).
- The main display only.
