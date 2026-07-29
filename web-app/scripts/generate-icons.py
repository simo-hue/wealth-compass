#!/usr/bin/env python3
"""
Regenerate every site icon from the shipping App Store icon.

Run by hand, from web-app/, whenever apple/ gets a new app icon:

    python3 scripts/generate-icons.py

Requires Pillow (`pip install Pillow`). It is deliberately not a build step and
not a package.json dependency: the source art changes once a year at most, and
the outputs are committed.

This exists because the site drifted. The landing page shipped with a purple
compass favicon left over from the previous site while the App Store listing
showed the gold-on-navy icon below — two different logos for one product, and
nothing in the build could notice. Deriving all of them from the one file the
apps actually ship makes that drift impossible.

The source is a square iOS icon, so its rounded corners are painted onto opaque
black (iOS masks the square itself). Pasted straight onto the page that reads as
black notches, so the corners are cut back to transparency here:

  1. Threshold the near-black pixels.
  2. Flood-fill from the four corners, so only the *exterior* black is taken —
     an interior shadow that happens to be as dark stays opaque.
  3. Crop to what is left, and paint the cut-away area in the rim colour before
     writing the alpha. Pillow does not premultiply on resize, so transparent
     pixels still contribute their RGB to the downscaled edge; leaving them
     black would draw a dark hairline around the mark at nav size.

Touch and PWA icons are written opaque instead — iOS and Android apply their own
mask, and a transparent corner underneath it renders black.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent.parent / "apple/WealthCompass/Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
PUBLIC = HERE.parent / "public"

# Anything at or below this total RGB is the black the icon was composited onto.
# The darkest pixel inside the tile sums to ~60, so there is room either way.
BLACK = 24


def tile(source: Path) -> tuple[Image.Image, tuple[int, int, int]]:
    """The icon cropped to its artwork, corners transparent. Also its rim colour."""
    im = source.convert("RGB")
    w, h = im.size
    px = im.load()

    black = Image.new("L", (w, h), 0)
    bp = black.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r + g + b <= BLACK:
                bp[x, y] = 255
    for seed in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        ImageDraw.floodfill(black, seed, 128, thresh=0)

    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            if bp[x, y] == 128:
                ap[x, y] = 0

    box = alpha.getbbox()
    if box is None:
        raise SystemExit(f"{source}: the whole image read as black")

    rim = []
    for t in range(box[0] + 20, box[2] - 20, 5):
        rim += [px[t, box[1] + 3], px[t, box[3] - 4]]
    for t in range(box[1] + 20, box[3] - 20, 5):
        rim += [px[box[0] + 3, t], px[box[2] - 4, t]]
    colour = tuple(sum(c[i] for c in rim) // len(rim) for i in range(3))

    base = Image.composite(im, Image.new("RGB", (w, h), colour), alpha)
    base.putalpha(alpha)
    return base.crop(box), colour


def write(art: Image.Image, colour, name: str, size: int, opaque: bool) -> None:
    out = art.resize((size, size), Image.LANCZOS)
    if opaque:
        flat = Image.new("RGB", (size, size), colour)
        flat.paste(out, (0, 0), out)
        out = flat
    # The art is a handful of navy, gold and green ramps, so a 256-entry palette
    # is indistinguishable from truecolour at every size written here — checked
    # pixel-doubled at 28px and at full 512. It is 4-5x smaller, which matters on
    # a page that loads no third-party bytes and should not spend 25 kB on a mark
    # that renders 28px wide.
    out = out.quantize(colors=256, method=Image.FASTOCTREE)
    path = PUBLIC / name
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, optimize=True)
    print(f"  {name:<22} {size}x{size}  {path.stat().st_size / 1024:.1f} kB")


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"missing source icon: {SOURCE}")
    art, colour = tile(Image.open(SOURCE))
    print(f"cropped to {art.size[0]}x{art.size[1]}, rim {colour}")

    # The mark in the nav and the footer. It lives under images/ with the other
    # asset the markup references; the files at the root of public/ are the ones
    # a browser or an OS asks for by a fixed name. 128 covers a 32px slot on a 3x
    # screen, which is more than either placement uses.
    write(art, colour, "images/logo.png", 128, opaque=False)
    write(art, colour, "favicon.png", 64, opaque=False)
    # Masked by the OS, so these must not be transparent behind the mask.
    write(art, colour, "apple-touch-icon.png", 180, opaque=True)
    write(art, colour, "pwa-192x192.png", 192, opaque=True)
    write(art, colour, "pwa-512x512.png", 512, opaque=True)

    # Only for the browsers and crawlers that still ask for /favicon.ico by name;
    # everything current takes the PNG above. Three entries, no 64 — Pillow stores
    # each one PNG-compressed, so a fourth would be 8 kB for a size nothing picks.
    ico = PUBLIC / "favicon.ico"
    art.resize((48, 48), Image.LANCZOS).save(ico, sizes=[(16, 16), (32, 32), (48, 48)])
    print(f"  {'favicon.ico':<22} 16..48    {ico.stat().st_size / 1024:.1f} kB")


if __name__ == "__main__":
    sys.exit(main())
