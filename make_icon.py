"""Draws Hinge's app icon and packs it into Resources/AppIcon.icns.

The mark is the app's own effect: a panel drawn narrower at the top, standing
on the hinge line that never moves.
"""
import pathlib
import subprocess
from PIL import Image, ImageDraw

S = 4  # supersample factor, for clean edges
SIZE = 1024 * S

BG_TOP, BG_BOTTOM = (30, 31, 34), (12, 12, 14)
PANEL = (242, 242, 240)
GHOST = (72, 74, 80)
HINGE = (242, 179, 61)


def draw() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Vertical gradient, clipped to the rounded square.
    gradient = Image.new("RGBA", (SIZE, SIZE))
    pen = ImageDraw.Draw(gradient)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        pen.line([(0, y), (SIZE, y)],
                 fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([64 * S, 64 * S, 960 * S, 960 * S],
                                           radius=205 * S, fill=255)
    img.paste(gradient, (0, 0), mask)

    pen = ImageDraw.Draw(img)
    hinge = (380 * S, 688 * S)
    deck_end = (780 * S, 688 * S)
    # The lid, leaning back past upright the way an open laptop sits.
    lid_end = (276 * S, 302 * S)

    # The angle between the two, which is the app's whole input.
    radius = 168 * S
    pen.arc([hinge[0] - radius, hinge[1] - radius, hinge[0] + radius, hinge[1] + radius],
            start=255, end=360, fill=HINGE + (255,), width=22 * S)

    pen.line([hinge, deck_end], fill=PANEL + (255,), width=48 * S, joint="curve")
    pen.line([hinge, lid_end], fill=PANEL + (255,), width=48 * S, joint="curve")
    for point in (hinge, deck_end, lid_end):
        r = 24 * S
        pen.ellipse([point[0] - r, point[1] - r, point[0] + r, point[1] + r],
                    fill=PANEL + (255,))

    # The hinge pin.
    r = 15 * S
    pen.ellipse([hinge[0] - r, hinge[1] - r, hinge[0] + r, hinge[1] + r], fill=HINGE + (255,))

    return img.resize((1024, 1024), Image.LANCZOS)


def main() -> None:
    root = pathlib.Path(__file__).parent
    icon = draw()
    iconset = root / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(iconset / f"icon_{size}x{size}@2x.png")

    resources = root / "Resources"
    resources.mkdir(exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")],
                   check=True)
    icon.save(root / "docs" / "icon-preview.png")
    print(f"wrote {resources / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
