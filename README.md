# Hinge

English · [日本語](README.ja.md)

<img src="docs/icon-preview.png" width="96" alt="The Hinge icon">

Close your MacBook a little and the desktop stays where it was. The panel
swings toward you, but what is drawn on it is redrawn so the display reads as
standing still in the room, upright at the angle you calibrated.

## How it works

The lid angle comes from the internal HID sensor on Apple silicon MacBooks
(usage page `0x20`, usage `0x8A`), polled at 60 Hz. ScreenCaptureKit streams
the desktop, with Hinge's own windows excluded. Each frame is drawn through a
projective transform built from three things: the hinge, the panel angle, and
where your eye is.

The hinge is the bottom edge, so that edge never moves and always spans the
full width. Everything above it is placed where your eye would have to look to
still see the upright display. The top of the panel has come closer to you, so
a given real width covers fewer points up there, and the image is drawn
narrower toward the top. The top of the virtual display falls past the panel
edge and is cut off, the way it would be in the room.

Calibration assumes you are looking straight down the panel's normal, through
the middle of the screen. Under that assumption the calibrated angle drops out
of the transform, and the only free parameter left is how far away you sit.

That distance is derived rather than guessed. Closing the lid a little leaves
the virtual display short of the panel's top edge, and the gap has to be
covered by stretching the image. Requiring that stretch to stay under 1% at
every angle puts a floor under the distance:

```
D ≥ h(½+ε)·sinΔ / (1+ε−cosΔ)
```

The worst case sits at Δ = √(2ε) ≈ 8°, which gives 3.6 screen heights. On a
15-inch MacBook that is about 72 cm, roughly where a person actually sits.

Blur starts at the top edge and creeps down as the lid closes. Two copies of
the same frame are stacked, sharp and blurred, and a gradient mask on the
blurred one moves the boundary.

## Build

```
./make_app.sh
```

This produces `Hinge.app`: a Swift Package Manager binary wrapped in a bundle
and ad-hoc signed. There is no Xcode project.

## Run

```
open Hinge.app
```

Hinge needs Screen Recording permission. The first launch explains where to
grant it, in System Settings under Privacy & Security, and then you reopen it.

An ad-hoc signature changes hash on every build, which invalidates the
permission while still showing as enabled. `make_app.sh` clears the stale
grant, so allow Hinge again after each rebuild.

Hinge runs in the background. The settings window opens from the Dock icon or
the menu bar item, and closing it leaves the app running. Quit from the button
in settings or with Command-Q. A second copy will not start; it hands over to
the one already running.

The overlay only appears once the desktop tilts, so the menu bar and Dock stay
usable at normal lid angles.

## Settings

- **Flat above** — the lid angle at and above which the desktop fills the
  screen. One button sets it to wherever the lid is right now.
- **Perspective** — 100% is the derived viewing distance. Lower backs away from
  it and softens the correction. It never moves closer.
- **Max blur** and **Shadow** — how far each goes at the end of the travel.
- **Open Hinge at login**.

## Checking it without taking over the screen

```
.build/release/Hinge --selfcheck   # the transform, angle by angle
.build/release/Hinge --probe       # live lid angle and permission state
```

`--selfcheck` asserts the things that are easy to break by accident: the bottom
edge stays exactly full width at every angle, the image narrows toward the top,
no black band ever appears, and the stretch stays near 1%.

## Requirements

- An Apple silicon MacBook with a lid angle sensor
- macOS 14 or later

The design notes are in [docs/spec.md](docs/spec.md).
