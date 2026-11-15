#!/usr/bin/env python3
"""Generates the pixel-art assets for the Moon flight (assets/space/).

Moon textures and the landing-site elevation profile are derived from NASA data
(CGI Moon Kit, NASA Scientific Visualization Studio, svs.gsfc.nasa.gov/4720):
  lroc_color_poles_1k.jpg - LRO LROC WAC colour mosaic
  ldem_3_8bit.jpg         - LRO LOLA elevation model
Usage: python3 tools/gen_space_assets.py <dir with the two NASA jpgs>
"""
import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "space"
OUT.mkdir(parents=True, exist_ok=True)
NASA = Path(sys.argv[1]) if len(sys.argv) > 1 else None
random.seed(7)

T = (0, 0, 0, 0)
ORANGE = (222, 112, 40, 255)
ORANGE_D = (170, 76, 28, 255)
ORANGE_L = (244, 150, 74, 255)
WHITE = (236, 238, 242, 255)
WHITE_D = (186, 192, 204, 255)
GRAY = (130, 136, 148, 255)
GRAY_D = (78, 84, 96, 255)
DARK = (34, 38, 48, 255)
RED = (200, 40, 40, 255)
GOLD = (214, 170, 48, 255)
GOLD_D = (150, 110, 30, 255)
BLUE = (60, 110, 200, 255)


def img(w, h):
    return Image.new("RGBA", (w, h), T)


def rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def shade_column(d, x0, x1, y0, y1, light, base, dark):
    """Vertical cylinder: light left edge, dark right edge."""
    rect(d, x0, y0, x1, y1, base)
    rect(d, x0, y0, x0, y1, light)
    rect(d, x1, y0, x1, y1, dark)


def save(im, name):
    im.save(OUT / name)
    print("wrote", name, im.size)


# --- Rocket (SLS Block 1 style) ----------------------------------------------

def draw_srb(d, x, y, h):
    # 5 px wide booster, nose cone on top
    shade_column(d, x, x + 4, y + 4, y + h, WHITE, WHITE, WHITE_D)
    rect(d, x + 1, y + 2, x + 3, y + 3, WHITE)
    rect(d, x + 2, y, x + 2, y + 1, WHITE_D)
    for yy in range(y + 12, y + h - 4, 9):  # segment joints
        rect(d, x, yy, x + 4, yy, WHITE_D)
    rect(d, x + 1, y + 16, x + 3, y + 22, RED)  # NASA worm-ish stripe
    rect(d, x, y + h - 2, x + 4, y + h, GRAY_D)  # nozzle skirt


def draw_core(d, x, y, h):
    shade_column(d, x, x + 9, y, y + h, ORANGE_L, ORANGE, ORANGE_D)
    for yy in range(y + 6, y + h, 7):  # foam texture
        d.point((x + 3 + (yy % 3), yy), fill=ORANGE_D)
        d.point((x + 6 - (yy % 2), yy + 3), fill=ORANGE_L)
    rect(d, x + 2, y + 10, x + 7, y + 13, DARK)  # NASA logo block
    rect(d, x + 3, y + 11, x + 6, y + 12, RED)
    rect(d, x, y + h - 3, x + 9, y + h, GRAY_D)
    for i in range(4):  # 4 RS-25 bells
        d.point((x + 1 + i * 2 + (1 if i > 1 else 0), y + h + 1), fill=GRAY)


def draw_upper(d, x, y):
    """ICPS + Orion + LAS tower, 10 px wide."""
    # launch abort system spike
    rect(d, x + 4, y, x + 5, y + 8, WHITE_D)
    rect(d, x + 3, y + 6, x + 6, y + 7, RED)
    # Orion capsule (cone)
    for i in range(6):
        rect(d, x + 4 - i // 1 // 2, y + 9 + i, x + 5 + i // 2, y + 9 + i, WHITE if i < 4 else WHITE_D)
    # service module
    shade_column(d, x + 1, x + 8, y + 15, y + 20, WHITE, WHITE, WHITE_D)
    rect(d, x + 1, y + 18, x + 8, y + 18, GRAY)
    # adapter + ICPS
    shade_column(d, x, x + 9, y + 21, y + 30, WHITE, WHITE_D, GRAY)
    rect(d, x + 2, y + 24, x + 7, y + 25, GRAY_D)


def rocket_full():
    im = img(24, 110)
    d = ImageDraw.Draw(im)
    draw_upper(d, 7, 0)
    draw_core(d, 7, 31, 72)
    draw_srb(d, 1, 46, 58)
    draw_srb(d, 18, 46, 58)
    save(im, "rocket_full.png")


def rocket_no_srb():
    im = img(12, 106)
    d = ImageDraw.Draw(im)
    draw_upper(d, 1, 0)
    draw_core(d, 1, 31, 72)
    save(im, "rocket_core.png")


def srb_single():
    im = img(6, 60)
    draw_srb(ImageDraw.Draw(im), 0, 0, 58)
    save(im, "srb.png")


def core_stage():
    im = img(12, 76)
    draw_core(ImageDraw.Draw(im), 1, 0, 72)
    save(im, "core_stage.png")


def upper_stack():
    im = img(12, 32)
    d = ImageDraw.Draw(im)
    draw_upper(d, 1, 0)
    # without LAS: erase the spike after jettison is a separate sprite
    save(im, "upper_stack.png")
    im2 = im.copy()
    d2 = ImageDraw.Draw(im2)
    rect(d2, 0, 0, 11, 8, T)
    save(im2, "upper_no_las.png")


def orion():
    """Orion spacecraft with its four solar array wings, side view, nose right."""
    im = img(30, 16)
    d = ImageDraw.Draw(im)
    # service module (white cylinder) + engine
    rect(d, 6, 5, 15, 10, WHITE)
    rect(d, 6, 10, 15, 10, WHITE_D)
    rect(d, 3, 6, 5, 9, GRAY)
    # capsule (cone pointing right)
    for i in range(7):
        h = 3 - i // 2
        rect(d, 16 + i, 7 - h, 16 + i, 8 + h, WHITE if i < 5 else WHITE_D)
    rect(d, 16, 4, 16, 11, GRAY_D)  # heat shield
    # solar wings (X-shape seen edge-on: one up, one down)
    for wing_y, step in ((0, 1), (15, -1)):
        for j in range(4):
            rect(d, 9 + j, wing_y + step * j, 12 + j, wing_y + step * j, BLUE)
        rect(d, 9, wing_y, 15, wing_y, (40, 70, 150, 255))
    save(im, "orion.png")


def lander():
    """Lunar lander: gold-foil descent stage, gray ascent stage, 4 legs."""
    im = img(28, 26)
    d = ImageDraw.Draw(im)
    # ascent stage
    rect(d, 9, 2, 18, 9, GRAY)
    rect(d, 9, 2, 18, 2, WHITE_D)
    rect(d, 10, 4, 12, 6, DARK)  # window
    rect(d, 17, 0, 17, 2, WHITE_D)  # antenna
    # descent stage (gold foil)
    rect(d, 7, 10, 20, 16, GOLD)
    for x in range(7, 21, 3):
        rect(d, x, 10, x, 16, GOLD_D)
    rect(d, 7, 16, 20, 16, GOLD_D)
    rect(d, 12, 17, 15, 18, GRAY_D)  # engine bell
    # legs
    for (x0, x1, foot) in ((7, 2, 0), (20, 25, 25)):
        d.line([(x0, 13), (x1, 23)], fill=WHITE_D)
        rect(d, foot, 23, foot + 2, 24, WHITE_D)
    save(im, "lander.png")


def astronaut():
    """4-frame walk cycle, 12x18 per frame, facing right."""
    frames = 4
    im = img(12 * frames, 18)
    d = ImageDraw.Draw(im)
    for f in range(frames):
        o = f * 12
        bob = 1 if f in (1, 3) else 0
        y = bob
        rect(d, o + 3, y + 0, o + 8, y + 5, WHITE)  # helmet
        rect(d, o + 5, y + 2, o + 8, y + 4, GOLD)  # visor
        rect(d, o + 6, y + 2, o + 7, y + 2, (255, 230, 140, 255))
        rect(d, o + 1, y + 6, o + 3, y + 11, WHITE_D)  # backpack (PLSS)
        rect(d, o + 3, y + 6, o + 8, y + 12, WHITE)  # torso
        rect(d, o + 4, y + 8, o + 6, y + 9, RED)  # chest panel
        arm = (-1, 1, 1, -1)[f]
        rect(d, o + 7, y + 7, o + 8, y + 10 + arm, WHITE_D)  # arm
        # legs
        stride = (2, 0, -2, 0)[f]
        rect(d, o + 4 + max(0, -stride) // 2, 13, o + 5, 17, WHITE)
        rect(d, o + 6, 13, o + 7 + max(0, stride) // 2, 17, WHITE_D)
        rect(d, o + 3 - (stride // 2), 17, o + 5 - (stride // 2), 17, GRAY_D)
        rect(d, o + 6 + (stride // 2), 17, o + 8 + (stride // 2), 17, GRAY_D)
    save(im, "astronaut_walk.png")


def cloud():
    im = img(32, 12)
    d = ImageDraw.Draw(im)
    for cx, cy, r in ((8, 7, 4), (15, 5, 5), (22, 7, 4), (12, 8, 3), (26, 8, 3)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)
    rect(d, 4, 10, 29, 11, WHITE_D)
    save(im, "cloud.png")


def tower():
    im = img(14, 120)
    d = ImageDraw.Draw(im)
    for x in (1, 12):
        rect(d, x, 4, x, 119, GRAY)
    for y in range(4, 120, 6):
        rect(d, 1, y, 12, y, GRAY_D)
        d.line([(1, y), (12, y + 6)], fill=GRAY_D)
    rect(d, 0, 0, 13, 3, GRAY_D)
    rect(d, 6, 0, 7, 0, RED)
    save(im, "tower.png")


SAMPLES = {
    "basalt": [(40, 40, 46), (70, 70, 78)],
    "anorthosite": [(200, 200, 196), (232, 232, 226)],
    "regolith": [(120, 116, 110), (150, 146, 138)],
    "core_tube": [(180, 186, 196), (110, 116, 126)],
    "glass": [(230, 120, 30), (255, 170, 60)],
    "seismometer": [(214, 170, 48), (150, 110, 30)],
}


def sample_icons():
    im = img(10 * len(SAMPLES), 10)
    d = ImageDraw.Draw(im)
    for i, (name, (c1, c2)) in enumerate(SAMPLES.items()):
        o = i * 10
        a, b = c1 + (255,), c2 + (255,)
        if name == "core_tube":
            rect(d, o + 4, 0, o + 5, 9, b)
            rect(d, o + 4, 0, o + 5, 1, a)
        elif name == "seismometer":
            rect(d, o + 2, 3, o + 7, 8, a)
            rect(d, o + 2, 8, o + 7, 8, b)
            rect(d, o + 4, 0, o + 5, 2, WHITE_D)
        elif name == "regolith":
            rect(d, o + 2, 2, o + 7, 8, WHITE_D)  # sample bag
            rect(d, o + 3, 4, o + 6, 8, a)
            rect(d, o + 2, 2, o + 7, 2, b)
        else:
            d.ellipse([o + 1, 3, o + 8, 9], fill=a)
            d.point((o + 3, 5), fill=b)
            d.point((o + 6, 6), fill=b)
            d.point((o + 4, 7), fill=b)
    save(im, "samples.png")


# --- Earth (procedural, coloured to match NASA Blue Marble tones) ------------

def value_noise(w, h, cell, seed):
    rnd = random.Random(seed)
    gw, gh = w // cell + 2, h // cell + 2
    grid = [[rnd.random() for _ in range(gw)] for _ in range(gh)]

    def at(x, y):
        gx, gy = x / cell, y / cell
        x0, y0 = int(gx), int(gy)
        fx, fy = gx - x0, gy - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        x1, y1 = (x0 + 1) % gw, y0 + 1
        a = grid[y0][x0 % gw] * (1 - fx) + grid[y0][x1] * fx
        b = grid[y1][x0 % gw] * (1 - fx) + grid[y1][x1] * fx
        return a * (1 - fy) + b * fy
    return at


def earth_globe(size, name):
    im = img(size, size)
    px = im.load()
    n1 = value_noise(size * 2, size, max(4, size // 6), 3)
    n2 = value_noise(size * 2, size, max(2, size // 14), 5)
    cl = value_noise(size * 2, size, max(3, size // 9), 9)
    r = size / 2 - 0.5
    for y in range(size):
        for x in range(size):
            dx, dy = (x - r) / r, (y - r) / r
            d2 = dx * dx + dy * dy
            if d2 > 1:
                continue
            dz = math.sqrt(1 - d2)
            lon = math.atan2(dx, dz)
            lat = math.asin(dy)
            u = (lon / math.pi + 1) * size
            v = (lat / math.pi + 0.5) * (size - 1)
            land = n1(u, v) * 0.7 + n2(u, v) * 0.3
            polar = abs(lat) > 1.25
            if polar:
                c = (236, 242, 248)
            elif land > 0.56:
                c = (74, 120, 52) if land < 0.66 else (150, 128, 78)
            else:
                c = (28, 74, 158) if land < 0.48 else (40, 98, 182)
            if cl(u * 1.3 + 7, v) > 0.66:
                c = (240, 244, 250)
            light = 0.35 + 0.65 * max(0.0, dz * 0.8 - dx * 0.35 + 0.2)
            light = round(min(1.0, light) * 4) / 4  # stepped, pixel style
            c = tuple(int(ch * max(light, 0.25)) for ch in c)
            px[x, y] = c + (255,)
    # thin atmosphere rim
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, size - 1, size - 1], outline=(120, 170, 255, 200))
    save(im, name)


# --- Moon (from NASA LROC colour mosaic + LOLA elevation) -------------------

PALETTE_MOON = [(44, 44, 48), (72, 72, 76), (100, 100, 102), (128, 126, 124),
                (156, 154, 150), (186, 184, 178), (214, 212, 206)]


def quantize_gray(v):
    i = min(len(PALETTE_MOON) - 1, max(0, int(v / 256 * len(PALETTE_MOON))))
    return PALETTE_MOON[i]


def moon_globe(src, size, name, lon0=0.0):
    w, h = src.size
    sp = src.load()
    im = img(size, size)
    px = im.load()
    r = size / 2 - 0.5
    for y in range(size):
        for x in range(size):
            dx, dy = (x - r) / r, (y - r) / r
            d2 = dx * dx + dy * dy
            if d2 > 1:
                continue
            dz = math.sqrt(1 - d2)
            lat = -math.asin(dy)
            lon = math.atan2(dx, dz) + math.radians(lon0)
            u = int(((lon / (2 * math.pi)) + 0.5) % 1.0 * (w - 1))
            v = int((0.5 - lat / math.pi) * (h - 1))
            g = sp[u, v]
            g = g if isinstance(g, int) else sum(g[:3]) / 3
            light = 0.55 + 0.45 * max(0.0, dz * 0.7 - dx * 0.4 + 0.3)
            px[x, y] = quantize_gray(min(255, g * 1.25 * light)) + (255,)
    save(im, name)


def moon_profile(ldem, lat_deg, lon_from, lon_to, samples, name):
    """Elevation profile along a parallel, normalised to 0..1."""
    w, h = ldem.size
    p = ldem.load()
    v = int((0.5 - lat_deg / 180.0) * (h - 1))
    vals = []
    for i in range(samples):
        lon = lon_from + (lon_to - lon_from) * i / (samples - 1)
        u = (lon / 360.0 + 0.5) % 1.0 * (w - 1)
        u0 = int(u)
        f = u - u0
        a, b = p[u0, v], p[(u0 + 1) % w, v]
        vals.append(a * (1 - f) + b * f)
    lo, hi = min(vals), max(vals)
    norm = [round((x - lo) / max(1e-6, hi - lo), 4) for x in vals]
    meta = {
        "source": "NASA LRO LOLA elevation (CGI Moon Kit, SVS 4720), ldem_3_8bit",
        "latitude_deg": lat_deg, "longitude_from_deg": lon_from, "longitude_to_deg": lon_to,
        "heights": norm,
    }
    (OUT / name).write_text(json.dumps(meta))
    print("wrote", name, len(norm), "samples")


def main():
    # Rocket, pad, clouds, Earth and Moon now come from the author's assets
    # (assets/sls, assets/earth.png, assets/moon.png); only these are generated.
    lander()
    astronaut()
    sample_icons()
    if NASA:
        ldem = Image.open(NASA / "moon_ldem.jpg").convert("L")
        # Apollo 11 landing site, Sea of Tranquility: 0.67 N, 23.47 E
        moon_profile(ldem, 0.67, 18.0, 29.0, 160, "moon_profile_tranquility.json")


if __name__ == "__main__":
    main()
