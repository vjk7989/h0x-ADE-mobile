#!/usr/bin/env python3
"""Generate the Android app icon from HxMark's dot grid.

One source of truth: the `_rows` literal in app/lib/widgets/hx.dart. Writes,
under app/android/app/src/main/res/ and design/store/:

  drawable/ic_launcher_foreground.xml   vector, 108 dp viewport, accent dots
  drawable/ic_launcher_monochrome.xml   the same geometry, white (themed icon)
  values/ic_launcher_background.xml     the #121113 background colour
  mipmap-anydpi-v26/ic_launcher.xml     adaptive icon (+ monochrome)
  mipmap-anydpi-v26/ic_launcher_round.xml
  mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png and ic_launcher_round.png
  design/store/icon-512.png             the Play listing icon

Run from the repo root:  python tools/gen_icons.py
CI check:                python tools/gen_icons.py --check   (exit 1 on drift)

Geometry. The grid is 21 x 25 dots. The adaptive icon canvas is 108 dp and
only a 66 dp circle (radius 33) is safe on every mask, so the step is the
largest one at which the farthest dot, with its radius, lies inside that
circle: 2.06 dp (the mark is not symmetric, and its bottom-left dot is the
farthest from the centre). Dot radius is 0.36 of the step: icons need
heavier dots than the in-app mark (1/3).
"""
import argparse
import math
import pathlib
import re
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
HX = ROOT / "app" / "lib" / "widgets" / "hx.dart"
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
STORE = ROOT / "design" / "store"

ACCENT = "#e78a53"
BACKGROUND = "#121113"
VIEWPORT = 108.0
SAFE_RADIUS = 33.0
DOT_FRACTION = 0.36
COLS = 21
ROWS = 25


def load_rows():
    text = HX.read_text(encoding="utf-8")
    body = re.search(r"static const _rows = \[(.*?)\];", text, re.S).group(1)
    rows = re.findall(r"'([01]{21})'", body)
    assert len(rows) == ROWS, f"expected {ROWS} rows, found {len(rows)}"
    return rows


def dots(rows):
    """(col - 10, row - 12) of every dot: the offset from the grid centre in steps."""
    return [
        (c - (COLS - 1) / 2, r - (ROWS - 1) / 2)
        for r, row in enumerate(rows)
        for c, ch in enumerate(row)
        if ch == "1"
    ]


def step_for(rows):
    far = max(math.hypot(x, y) for x, y in dots(rows))
    # (far + fraction) * step <= SAFE_RADIUS, rounded down to 0.01
    return math.floor(SAFE_RADIUS / (far + DOT_FRACTION) * 100) / 100


def num(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def path_data(rows, step):
    r = step * DOT_FRACTION
    parts = []
    for x, y in dots(rows):
        cx = VIEWPORT / 2 + x * step
        cy = VIEWPORT / 2 + y * step
        # a circle as two arcs: M left a r r 0 1 0 2r 0 a r r 0 1 0 -2r 0
        parts.append(
            f"M{num(cx - r)} {num(cy)}a{num(r)} {num(r)} 0 1 0 {num(2 * r)} 0"
            f"a{num(r)} {num(r)} 0 1 0 {num(-2 * r)} 0"
        )
    return "".join(parts)


def vector_xml(rows, step, fill):
    return (
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        f'  <path\n      android:fillColor="{fill}"\n'
        f'      android:pathData="{path_data(rows, step)}"/>\n'
        "</vector>\n"
    )


ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
"""

BACKGROUND_XML = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="ic_launcher_background">{BACKGROUND}</color>
</resources>
"""


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def render(rows, step, size, shape):
    """The mark on #121113. shape: 'square' (rounded), 'round', or 'full'.

    A legacy icon shows the whole bitmap, where the adaptive icon shows only
    its central 72 dp of 108: so the scale is size / 72 dp.
    """
    k = 4
    big = size * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bg = hex_rgb(BACKGROUND) + (255,)
    if shape == "round":
        d.ellipse((0, 0, big - 1, big - 1), fill=bg)
    elif shape == "square":
        d.rounded_rectangle((0, 0, big - 1, big - 1), radius=int(big * 0.22), fill=bg)
    else:
        d.rectangle((0, 0, big, big), fill=bg)
    px = big / 72.0
    r = step * DOT_FRACTION * px
    fill = hex_rgb(ACCENT) + (255,)
    for x, y in dots(rows):
        cx = big / 2 + x * step * px
        cy = big / 2 + y * step * px
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
    return img.resize((size, size), Image.LANCZOS)


def generate(out_res, out_store):
    rows = load_rows()
    step = step_for(rows)
    files = {}
    files["drawable/ic_launcher_foreground.xml"] = vector_xml(rows, step, ACCENT)
    files["drawable/ic_launcher_monochrome.xml"] = vector_xml(rows, step, "#ffffff")
    files["values/ic_launcher_background.xml"] = BACKGROUND_XML
    files["mipmap-anydpi-v26/ic_launcher.xml"] = ADAPTIVE
    files["mipmap-anydpi-v26/ic_launcher_round.xml"] = ADAPTIVE
    for name, text in files.items():
        p = out_res / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8", newline="\n")
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        for stem, shape in (("ic_launcher", "square"), ("ic_launcher_round", "round")):
            p = out_res / f"mipmap-{density}" / f"{stem}.png"
            p.parent.mkdir(parents=True, exist_ok=True)
            render(rows, step, size, shape).save(p, optimize=True)
    out_store.mkdir(parents=True, exist_ok=True)
    render(rows, step, 512, "full").save(out_store / "icon-512.png", optimize=True)
    return step


def same(a, b):
    if a.suffix == ".png":
        ia, ib = Image.open(a).convert("RGBA"), Image.open(b).convert("RGBA")
        return ia.size == ib.size and ia.tobytes() == ib.tobytes()
    return a.read_bytes() == b.read_bytes()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 if the committed icons differ")
    args = ap.parse_args()
    if not args.check:
        step = generate(RES, STORE)
        print(f"icons written (step {step} dp)")
        return 0
    with tempfile.TemporaryDirectory() as tmp:
        t = pathlib.Path(tmp)
        generate(t / "res", t / "store")
        bad = []
        for gen in sorted((t / "res").rglob("*")) + sorted((t / "store").rglob("*")):
            if not gen.is_file():
                continue
            base, root = (t / "res", RES) if (t / "res") in gen.parents else (t / "store", STORE)
            have = root / gen.relative_to(base)
            if not have.exists() or not same(gen, have):
                bad.append(str(have.relative_to(ROOT)))
        if bad:
            print("icons are out of date:\n  " + "\n  ".join(bad))
            return 1
        print("icons are up to date")
        return 0


if __name__ == "__main__":
    sys.exit(main())
