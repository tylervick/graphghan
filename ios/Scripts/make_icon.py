"""The app icon (spec §7): moss sky with the weave, a gold moon, the hill band, and a crocheted
chain along the horizon. Geometry is in fractions of the side so the PWA icon can share it later."""

import argparse

from PIL import Image, ImageDraw

MOSS, MOSS_DEEP, CREAM, GOLD = (30, 77, 58), (22, 59, 45), (244, 245, 240), (217, 162, 27)


def polyline(draw, points, fill, width):
    """A stroked path with round joins and caps (Pillow's line() has neither)."""
    draw.line(points, fill=fill, width=width, joint="curve")
    r = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


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
    # hill band from 62% down, then the moon
    d.rectangle([0, 62 * s, size, size], fill=MOSS_DEEP)
    d.ellipse([(74 - 9) * s, (30 - 9) * s, (74 + 9) * s, (30 + 9) * s], fill=GOLD)
    # eight chevrons along the horizon, tips leading (the chain travels right), halo in the hill color
    n, step, y = 8, 9.5, 62
    x0 = 50 - step * (n - 1) / 2
    for i in range(n):
        cx = x0 + step * i
        pts = [((cx + 9.5) * s, (y - 8.5) * s), ((cx - 3.5) * s, y * s), ((cx + 9.5) * s, (y + 8.5) * s)]
        polyline(d, pts, MOSS_DEEP, int(10 * s))
        polyline(d, pts, CREAM, int(6 * s))
    return img


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    make_icon(a.size).save(a.out)
    print("wrote", a.out)
