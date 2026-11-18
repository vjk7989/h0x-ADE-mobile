#!/usr/bin/env python3
"""Generate app/lib/theme/palettes.g.dart from the desktop themes.

Sources (the desktop wins; regenerate when it changes):
  * graphite, ink, moss, paper: the PRESETS below, copied from
    h0x-ade-app/src/settings.rs (GRAPHITE, INK, MOSS, PAPER).
  * every other theme: tools/themes/<name>.json, byte copies of
    h0x-ade-app/defaults/themes/*.json plus the user's sodium, voltage and
    phosphor files (see design/tokens.md section 1).
UI roles follow h0x-ade-app/src/settings.rs `resolve` (palette -> chrome
colours, then the file's `colors` overrides). The mobile-only roles (screen,
card, outline, well, ok, selected, hairline, scrim) follow design/tokens.md
section 2.

Run from the repo root:  python tools/gen_themes.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT.parent / "app" / "lib" / "theme" / "palettes.g.dart"

DARK_STATUS = (0xE5C07B, 0xF0705F, 0x76A8FF)

# name: (background, foreground, selection, cursor|None, ansi[16], status)
PRESETS = {
    "graphite": (0x17191D, 0xD2D4D9, 0x394454, None,
        [0x45484F, 0xDC8C95, 0xA6BD91, 0xD8BE87, 0x96B2D7, 0xB5A2CE, 0x8CBDC3, 0xD2D4D9,
         0x818793, 0xF0A5AD, 0xBAD5A2, 0xEAD2A1, 0xB0CBEF, 0xCBB7E6, 0xA4D5DB, 0xF0F0F2],
        DARK_STATUS),
    "ink": (0x111720, 0xCDD6E4, 0x344861, None,
        [0x414B5A, 0xE58C9A, 0x89C5AA, 0xD9BE82, 0x91B6EE, 0xB9A0E2, 0x85C4D0, 0xCDD6E4,
         0x7F91A7, 0xF5A5B2, 0xA5DEC3, 0xEDD39C, 0xACCBFA, 0xD0B7F4, 0xA0DCE5, 0xF0F5FC],
        DARK_STATUS),
    "moss": (0x151C19, 0xCDD7CE, 0x354A40, None,
        [0x435248, 0xDF978D, 0xA0C4A2, 0xD4BC8B, 0x99B9CD, 0xBBA4C8, 0x8BBDB5, 0xCDD7CE,
         0x82968A, 0xF1AFA3, 0xB8DAB9, 0xE9D2A5, 0xB1D0E2, 0xD1BDDC, 0xA4D6CA, 0xEFF5EE],
        DARK_STATUS),
    "paper": (0xFFFFFF, 0x25272C, 0xCFDCF5, 0x25272C,
        [0x25272C, 0xC62A2A, 0x1A7F37, 0x8F5D00, 0x1F62D0, 0x7A45C8, 0x0F6F74, 0x5F6068,
         0x7B7E87, 0xD1242F, 0x1F883D, 0x9A6700, 0x0969DA, 0x8250DF, 0x1B7C83, 0x111214],
        (0x9A6700, 0xC93C2C, 0x2F6FE4)),
}


def h(s):
    return int(s.lstrip("#")[:6], 16)


def mix(a, b, t):
    out = 0
    for s in (16, 8, 0):
        x, y = (a >> s) & 255, (b >> s) & 255
        v = x * (1 - t) + y * t
        out |= int(v + 0.5) << s  # Rust f32::round (values are never negative)
    return out


def hx(c):
    return "#%06x" % c


def lum(c):
    def ch(s):
        v = ((c >> s) & 255) / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(16) + 0.7152 * ch(8) + 0.0722 * ch(0)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def is_light(c):  # settings.rs is_light: plain (non-linear) luma > 0.5
    def ch(s):
        return ((c >> s) & 255) / 255
    return 0.2126 * ch(16) + 0.7152 * ch(8) + 0.0722 * ch(0) > 0.5


def alpha(c, a):
    return "#%06x%02x" % (c, int(a * 255 + 0.5))


def resolve(p, overrides):
    bg, fg_t, sel, cur, ansi, status = p
    light = is_light(bg)
    fg = 0x1B1B1E if light else 0xEEEEEF
    working, blocked, done = status or (ansi[3], ansi[1], ansi[4])
    if light:
        warm = 0xE8E8E2
        popover, raised = hx(bg), hx(mix(bg, 0, 0.035))
        hover, selected, border, inp = "#0000000c", "#00000012", "#00000017", "#00000026"
        canvas, chrome = mix(bg, warm, 0.2), mix(bg, warm, 0.6)
    else:
        popover, raised = hx(mix(bg, 0xFFFFFF, 0.06)), hx(mix(bg, 0xFFFFFF, 0.09))
        hover, selected, border, inp = "#ffffff0e", "#ffffff17", "#ffffff18", "#ffffff24"
        canvas, chrome = mix(bg, 0, 0.16), mix(bg, 0, 0.32)
    t = {
        "background": hx(bg), "foreground": hx(fg), "surface": hx(bg),
        "canvas": hx(canvas), "chrome": hx(chrome), "popover": popover,
        "raised": raised, "hover": hover, "selected": selected,
        "border": border, "input": inp,
        "muted": hx(mix(bg, fg, 0.66 if light else 0.6)),
        "dim": hx(mix(bg, fg, 0.46 if light else 0.38)),
        "accent": hx(ansi[4]), "accent_foreground": hx(bg),
        "solid": hx(fg),
        "solid_foreground": hx(0xFFFFFF if light else mix(bg, 0, 0.28)),
        "ring": hx(mix(bg, fg, 0.7)),
        "working": hx(working), "blocked": hx(blocked), "done": hx(done),
    }
    t.update(overrides)
    return t, light


def load_file(path):
    d = json.loads(path.read_text(encoding="utf-8"))
    p = (h(d["background"]), h(d["foreground"]), h(d["selection"]),
         h(d["cursor"]) if d.get("cursor") else None,
         [h(x) for x in d["ansi"]], None)
    assert len(p[4]) == 16, path
    return p, d.get("colors", {})


def label(name):
    return " ".join(w.capitalize() for w in name.split("-"))


def build(name, p, overrides):
    roles, light = resolve(p, overrides)
    bg, fg_t, sel, cur, ansi, _ = p

    def c(k):
        return h(roles[k])

    # mobile roles (design/tokens.md section 2)
    if light:
        surface = c("surface")
        screen = h(overrides["canvas"]) if "canvas" in overrides else mix(surface, 0xE8E8E2, 0.2)
        card = c("popover")
        scrim = "#0a0a0c66"
        hairline = "#00000014"
        well = "#f3f3f1"
        sel_a = 0.10
    else:
        screen = c("background")
        card = mix(c("background"), c("raised"), 0.6)
        scrim = "#00000099"
        hairline = alpha(c("foreground"), 0.07)
        well = hx(mix(c("background"), 0, 0.35))
        sel_a = 0.15
    # outline: least foreground (1% steps) mixed into card with >= 3:1 on card and screen
    outline = c("foreground")
    for i in range(0, 101):
        m = mix(card, c("foreground"), i / 100)
        if contrast(m, card) >= 3 and contrast(m, screen) >= 3:
            outline = m
            break
    roles.update({
        "screen": hx(screen), "card": hx(card), "outline": hx(outline),
        "well": well, "ok": hx(ansi[2]),
        "selected_mobile": alpha(c("accent"), sel_a),
        "hairline": hairline, "scrim": scrim,
    })
    term = {"background": hx(bg), "foreground": hx(fg_t),
            "cursor": hx(cur if cur is not None else fg_t), "selection": hx(sel),
            "ansi": [hx(x) for x in ansi]}
    return {"id": name, "label": label(name), "light": light, "roles": roles, "terminal": term}


ROLE_ORDER = ["background", "foreground", "muted", "dim", "raised", "popover", "chrome",
              "border", "hover", "accent", "accent_foreground", "solid", "solid_foreground",
              "ring", "working", "blocked", "done", "screen", "card", "outline", "well",
              "ok", "selected_mobile", "hairline", "scrim"]


def main():
    themes = [build(n, p, {}) for n, p in PRESETS.items()]
    for f in sorted((ROOT / "themes").glob("*.json")):
        p, o = load_file(f)
        themes.append(build(f.stem, p, o))
    out = [
        "// GENERATED by tools/gen_themes.py. Do not edit.",
        "// Sources: h0x-ade-app src/settings.rs presets (graphite, ink, moss, paper),",
        "// h0x-ade-app defaults/themes/*.json, and the sodium, voltage and phosphor",
        "// user themes (tools/themes/*.json). Mobile-only roles: design/tokens.md s2.",
        "",
        "import 'theme_model.dart';",
        "",
        "final List<ThemeSpec> kThemeSpecs = [",
    ]
    for t in themes:
        out.append("  ThemeSpec(")
        out.append("    id: '%s'," % t["id"])
        out.append("    label: '%s'," % t["label"])
        out.append("    isLight: %s," % str(t["light"]).lower())
        out.append("    roles: {")
        for k in ROLE_ORDER:
            out.append("      '%s': '%s'," % (k, t["roles"][k]))
        out.append("    },")
        tm = t["terminal"]
        out.append("    terminal: TerminalSpec(")
        for k in ("background", "foreground", "cursor", "selection"):
            out.append("      %s: '%s'," % (k, tm[k]))
        out.append("      ansi: [")
        for i in range(0, 16, 4):
            out.append("        " + " ".join("'%s'," % x for x in tm["ansi"][i:i + 4]))
        out.append("      ],")
        out.append("    ),")
        out.append("  ),")
    out.append("];")
    out.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    for t in themes:
        r = {k: h(v) for k, v in t["roles"].items() if len(v) == 7}
        print("%-16s light=%-5s fg/screen=%5.2f muted/card=%5.2f accent/screen=%5.2f outline=%s" % (
            t["id"], t["light"], contrast(r["foreground"], r["screen"]),
            contrast(r["muted"], r["card"]), contrast(r["accent"], r["screen"]),
            t["roles"]["outline"]))


if __name__ == "__main__":
    main()
