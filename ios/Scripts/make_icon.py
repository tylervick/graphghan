"""The app icon (spec §7): moss sky, a gold moon, three charcoal standing stones on the hill band,
with the weave. This script is the only definition of that geometry -- it began as a copy of the
PWA icon's, and the PWA went away with the browser viewer (#78)."""

import argparse

from PIL import Image, ImageDraw

MOSS, MOSS_DEEP, CREAM, GOLD, CHARCOAL = (
    (30, 77, 58),
    (22, 59, 45),
    (244, 245, 240),
    (217, 162, 27),
    (43, 47, 51),
)


def make_icon(size: int) -> Image.Image:
    s = size / 100  # one percent
    img = Image.new("RGB", (size, size), MOSS)
    # the weave: hairlines at 135°, 2.8% pitch, 5% cream
    weave = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    wd = ImageDraw.Draw(weave)
    pitch = int(2.8 * s * 2**0.5)
    for x in range(-size, size, max(1, pitch)):
        wd.line([(x, size), (x + size, 0)], fill=(*CREAM, 13), width=max(1, int(0.6 * s)))
    img.paste(Image.alpha_composite(img.convert("RGBA"), weave).convert("RGB"))
    d = ImageDraw.Draw(img)
    # a 16-unit grid: hill band from 12 units down, the moon at (12.75, 4.25) with radius 1.75,
    # three stones standing on the horizon
    u = size / 16
    d.rectangle([0, 12 * u, size, size], fill=MOSS_DEEP)
    d.ellipse([11 * u, 2.5 * u, 14.5 * u, 6 * u], fill=GOLD)
    for x0, h in ((3.5, 5), (6.5, 7), (9.5, 5.5)):
        d.rectangle([x0 * u, (12 - h) * u, (x0 + 1.8) * u, 12 * u], fill=CHARCOAL)
    return img


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    make_icon(a.size).save(a.out)
    print("wrote", a.out)
