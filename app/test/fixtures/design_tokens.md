# HyperOx mobile — design tokens

Sub-task M0.2a. These tokens are the contract for `app/lib/theme/` and for the golden tests. Every colour here comes from a desktop theme file; the few mobile-only values are derived by a stated rule and checked for contrast below. Screens: `screens/*.svg` (previews in `previews/`).

## 1. Sources

| Theme | Kind | Source |
|---|---|---|
| `paper` | light (HyperOx light default, `DEFAULT_LIGHT`) | h0x-ade-app `src/settings.rs` `PAPER` palette; resolved UI tokens as in `cook/src/base.css` |
| `darkmatter` | dark (mock default dark) | h0x-ade-app `defaults/themes/darkmatter.json` |
| `sodium` | dark | user theme `~/.config/h0x-ade/themes/sodium.json` |
| `voltage` | dark | user theme `~/.config/h0x-ade/themes/voltage.json` |
| `phosphor` | dark | user theme `~/.config/h0x-ade/themes/phosphor.json` (also `cook/src/base.css`) |

Sodium, Voltage and Phosphor are not shipped in `h0x-ade-app/defaults/themes/` yet; they exist only as theme files in the HyperOx home. The values below are copied from those files on 2026-11-18. If the desktop ships them later with other values, the desktop wins and this table is regenerated.

The mocks draw `paper` (light) and `darkmatter` (dark). The other three use the same roles; the app's theme picker offers all five, and "System" picks `paper` / `darkmatter` by the OS appearance.

## 2. Colour roles

Desktop roles keep their desktop names. Rows marked *(mobile)* are derived:

- `screen`: the page behind cards. Light uses `canvas` (`#fafaf9`), dark uses `background`.
- `card`: list and form containers. Light is `#ffffff`. Dark is `mix(background, raised, 0.6)`, so cards read as one step up without the heavy `raised` grey.
- `outline`: the edge of text fields, switches and checkboxes. It is the least `foreground` mixed into `card` that reaches 3:1 against both `card` and `screen` (WCAG 1.4.11).
- `well`: code, keys and fingerprints. Light is `#f3f3f1`. Dark is `background` darkened 35 %.
- `ok`: success and "online". It is ANSI 2 (green) of the theme.
- `selected`: selected row or tab pill. It is `accent` at 10 % (light) or 15 % (dark), the desktop `selected` alpha.
- `hairline`: separators. It is `foreground` at 7 % (dark) or black at 7–9 % (light). Decorative only.
- `scrim`: behind sheets. It is `#0a0a0c` at 40 % (light) or black at 60 % (dark).
- Focus ring on `paper` uses `accent` (`#1f62d0`, 5.4:1), not the desktop grey `ring`, because a touch focus ring must stand out on white.

| Role | paper | darkmatter | sodium | voltage | phosphor |
|---|---|---|---|---|---|
| `background` | `#ffffff` | `#121113` | `#000000` | `#0d0b14` | `#030a05` |
| `foreground` | `#1b1b1e` | `#c1c1c1` | `#e6e6e6` | `#e4e0f0` | `#b6f5c1` |
| `muted` | `#69696a` | `#888888` | `#a3a3a3` | `#a79fc0` | `#7fbf8c` |
| `dim` | `#969698` | `#656465` | `#808080` | `#8880a2` | `#5f9a6c` |
| `raised` | `#f6f6f6` | `#222222` | `#141414` | `#1c1730` | `#0c2014` |
| `popover` | `#ffffff` | `#121113` | `#0a0a0a` | `#151122` | `#07150c` |
| `chrome` | `#f1f1ee` | `#121212` | `#050505` | `#110e1a` | `#05100a` |
| `border` | `#00000017` | `#222222` | `#242424` | `#2a2244` | `#143521` |
| `accent` | `#1f62d0` | `#e78a53` | `#ffd60a` | `#00e5ff` | `#39d353` |
| `accent_foreground` | `#ffffff` | `#121113` | `#000000` | `#06131a` | `#021006` |
| `solid` | `#1b1b1e` | `#e78a53` | `#ffd60a` | `#ff2e63` | `#39d353` |
| `solid_foreground` | `#ffffff` | `#121113` | `#000000` | `#14020a` | `#021006` |
| `ring` | `#5f5f62` | `#e78a53` | `#ffd60a` | `#00e5ff` | `#39d353` |
| `working` | `#9a6700` | `#fbcb97` | `#ffd60a` | `#f2c14e` | `#c6e05a` |
| `blocked` | `#c93c2c` | `#ed5350` | `#ff5c57` | `#ff3b5c` | `#ff5f56` |
| `done` | `#2f6fe4` | `#61a3e6` | `#6cb6ff` | `#3df5a7` | `#4fb8a8` |
| `screen` (mobile) | `#fafaf9` | `#121113` | `#000000` | `#0d0b14` | `#030a05` |
| `card` (mobile) | `#ffffff` | `#1c1b1c` | `#0c0c0c` | `#161225` | `#08170e` |
| `outline` (mobile) | `#8f8f91` | `#686768` | `#5f5f5f` | `#646072` | `#4a6b52` |
| `well` (mobile) | `#f3f3f1` | `#0c0b0c` | `#000000` | `#08070d` | `#020603` |
| `ok` (mobile) | `#1a7f37` | `#62c37a` | `#8ddb6b` | `#3df5a7` | `#39d353` |

### Status vocabulary (same words as the desktop)

| State | Colour role | Tag / text | Used for |
|---|---|---|---|
| online | `ok` | `● online` | machine reachable |
| needs you | `working` | `● needs you`, `[needs you]` | an agent waits for approval or input |
| working | `done` (blue) | `[working]` | agent busy |
| idle / offline / last known | `muted` | `● offline`, `● last known` | nothing to do or not reachable |
| blocked | `blocked` | `● blocked` | host key changed; connection refused |
| account mode | `accent` | `[account]` | reached through the relay with the HyperOx account |
| SSH mode | `done` | `[ssh]` | reached directly over SSH / Tailscale SSH |

Tags are the desktop's CLI brackets: brackets in `dim`, the word in the state colour, JetBrains Mono 12. Colour is never the only signal: every state also has a word, and the host-key state has an icon and its own row.

## 3. Contrast (computed, WCAG 2.2 relative luminance)

Text needs 4.5:1. Icons, field edges and the focus ring need 3:1. ✗ = fails.

| Pair (need) | paper | darkmatter | sodium | voltage | phosphor |
|---|---|---|---|---|---|
| foreground on screen (≥4.5) | 16.45 | 10.46 | 16.83 | 15.09 | 16.03 |
| foreground on card (≥4.5) | 17.18 | 9.54 | 15.67 | 14.14 | 14.76 |
| muted on screen (≥4.5) | 5.25 | 5.31 | 8.33 | 7.78 | 9.27 |
| muted on card (≥4.5) | 5.48 | 4.84 | 7.75 | 7.29 | 8.54 |
| dim on screen (≥3) | 2.83 ✗ | 3.20 | 5.32 | 5.26 | 6.03 |
| accent on screen (text/icon) (≥4.5) | 5.41 | 7.31 | 14.88 | 12.70 | 10.12 |
| solid_foreground on solid (button label) (≥4.5) | 17.18 | 7.31 | 14.88 | 5.58 | 9.84 |
| accent_foreground on accent (≥4.5) | 5.65 | 7.31 | 14.88 | 12.23 | 9.84 |
| working on card (≥4.5) | 4.87 | 11.52 | 13.86 | 10.91 | 12.47 |
| blocked on card (≥4.5) | 5.04 | 4.87 | 6.45 | 5.26 | 6.16 |
| done on card (≥4.5) | 4.65 | 6.45 | 9.10 | 12.91 | 7.68 |
| ok on card (≥4.5) | 5.08 | 7.86 | 11.62 | 12.91 | 9.32 |
| outline on card (field edge, 3:1) (≥3) | 3.23 | 3.05 | 3.06 | 3.01 | 3.09 |
| ring on screen (focus, 3:1) (≥3) | 6.09 | 7.31 | 14.88 | 12.70 | 10.12 |

Rules that follow from the table:

1. **`dim` is never used for information.** On `paper`, `dim` is 2.83:1, so it is only for disabled controls (WCAG-exempt), the dim brackets of a tag (the word carries the meaning) and separators like `·`. Placeholders use `muted`.
2. Secondary text is `muted`. On a `selected` row the secondary text switches to `foreground`: `muted` on darkmatter's selected fill is about 3.9:1.
3. Text inside a red or yellow tinted strip is `foreground`; the state colour goes on the icon and the 1 px edge (`blocked` on its 7 % light tint is 4.39:1).
4. Disabled = 38 % opacity of the whole control plus a reason on screen (banner or helper text). A control is never disabled without a reason.
5. Extra pairs checked in the mocks: white on `working` (light Inbox badge) 4.87; `accent_foreground` on `accent` (dark badge) 7.31; `muted` on the light glass card (`#f6f6f4`) 5.07; `blocked` on its dark tint 4.82.

## 4. Terminal palette

The terminal (M0.2b) draws the theme file's own `background`, `foreground`, `cursor`, `selection` and 16 ANSI colours, unchanged, so it matches the desktop byte for byte. The number after each colour is its contrast against the terminal background.

| Slot | paper | darkmatter | sodium | voltage | phosphor |
|---|---|---|---|---|---|
| background | `#ffffff` | `#121113` | `#000000` | `#0d0b14` | `#030a05` |
| foreground | `#25272c` 14.9 | `#c1c1c1` 10.5 | `#e6e6e6` 16.8 | `#e4e0f0` 15.1 | `#b6f5c1` 16.0 |
| cursor | `#25272c` | `#e78a53` | `#ffd60a` | `#ff2e63` | `#39ff14` |
| selection | `#cfdcf5` | `#523526` | `#4d4000` | `#3a1638` | `#0f3d1e` |
| 0 black | `#25272c` 14.9 | `#383839` 1.6 | `#1a1a1a` 1.2 | `#1c1826` 1.1 | `#0a1f10` 1.2 |
| 1 red | `#c62a2a` 5.6 | `#ed5350` 5.3 | `#ff5c57` 6.9 | `#ff3b5c` 5.6 | `#ff5f56` 6.7 |
| 2 green | `#1a7f37` 5.1 | `#62c37a` 8.6 | `#8ddb6b` 12.5 | `#3df5a7` 13.8 | `#39d353` 10.1 |
| 3 yellow | `#8f5d00` 5.6 | `#fbcb97` 12.6 | `#ffd60a` 14.9 | `#f2c14e` 11.6 | `#c6e05a` 13.5 |
| 4 blue | `#1f62d0` 5.7 | `#61a3e6` 7.1 | `#6cb6ff` 9.8 | `#4cc9f0` 10.2 | `#4fb8a8` 8.3 |
| 5 magenta | `#7a45c8` 6.0 | `#ca7ece` 6.6 | `#d7a6ff` 10.8 | `#ff5fa8` 6.9 | `#8fd694` 11.6 |
| 6 cyan | `#0f6f74` 5.9 | `#5f8787` 4.8 | `#5fd7c7` 12.0 | `#00e5ff` 12.7 | `#2ee6a6` 12.4 |
| 7 white | `#5f6068` 6.3 | `#a7a7a7` 7.8 | `#c8c8c8` 12.6 | `#cfc9e0` 12.2 | `#b6f5c1` 16.0 |
| 8 br.black | `#7b7e87` 4.1 | `#616061` 3.0 | `#767676` 4.6 | `#7d7692` 4.5 | `#5c8f68` 5.3 |
| 9 br.red | `#d1242f` 5.2 | `#ff6a65` 6.7 | `#ff7b72` 8.3 | `#ff6b84` 7.2 | `#ff8a80` 8.8 |
| 10 br.green | `#1f883d` 4.5 | `#79da90` 11.0 | `#a8e88a` 14.6 | `#7dffc5` 15.8 | `#6bff7f` 15.5 |
| 11 br.yellow | `#9a6700` 4.9 | `#ffe2ad` 15.0 | `#ffe566` 16.7 | `#ffd97a` 14.4 | `#e2f587` 16.8 |
| 12 br.blue | `#0969da` 5.2 | `#76bafe` 9.2 | `#8cc8ff` 11.8 | `#86dcff` 12.7 | `#7fd9c9` 12.1 |
| 13 br.magenta | `#8250df` 5.0 | `#e194e5` 8.6 | `#e2bdff` 13.0 | `#ff8fc3` 9.3 | `#b5efb9` 15.3 |
| 14 br.cyan | `#1b7c83` 4.9 | `#749c9c` 6.3 | `#86e6d8` 14.3 | `#6ff3ff` 14.8 | `#74f7c9` 15.1 |
| 15 br.white | `#111214` 18.7 | `#c1c1c1` 10.5 | `#ffffff` 21.0 | `#ffffff` 19.5 | `#e6ffe9` 18.9 |

ANSI 0 (black) and 8 (bright black) are low on dark themes by design, as on the desktop. The terminal follows the theme exactly; it does not apply a minimum-contrast override. Bright black on darkmatter (3.0) is used by shells for hints only.

## 5. Typography

- **Sans:** Geist (OFL), the desktop UI face. Weights 400, 500 and 600.
- **Mono:** JetBrains Mono (OFL), the desktop terminal face, with ligatures off (`calt 0`). It is used for addresses, keys, codes, commands, metadata lines and CLI tags.
- All sizes are in `sp`. Flutter applies `MediaQuery.textScaler`; we never clamp it.
- Android 14+ scales non-linearly: large sizes grow less than small ones. The 200 % column is what the mocks assume.

| Token | Size / line (sp) | Weight | Family | At 200 % (approx.) | Use |
|---|---|---|---|---|---|
| `display` | 30 / 36, −0.02 em | 600 | sans | 52 / 64 | Brand title on sign-in |
| `title-lg` | 24 / 30, −0.01 em | 600 | sans | 40 / 48 | Tablet detail title |
| `title` | 22 / 28 | 600 | sans | 36 / 48 | App bar title |
| `title-sm` | 18–19 / 24 | 600 | sans | 32 / 40 | Sheet title |
| `heading` | 16 / 22 | 600 | sans | 30 / 40 | Card title, machine name (500) |
| `body-lg` | 15 / 22 | 400–500 | sans | 30 / 40 | Button label, tagline, switch label |
| `body` | 14–14.5 / 20–21 | 400 | sans | 28 / 40 | Paragraphs |
| `body-sm` | 13–13.5 / 18–20 | 400 | sans | 26 / 36 | Card body |
| `caption` | 12.5 / 18 | 400 | sans | 24 / 32 | Helper, footnote |
| `mono` | 12 / 16–20 | 400–500 | mono | 24 / 32 | Meta lines, tags, addresses |
| `mono-key` | 11.5 / 20 | 400 | mono | 22 / 32 | Public key (wraps, never truncates) |
| `code` | 26–30 / 32–36, +0.12 em | 600 | mono | 44 / 56 | Approval and link codes |
| `label-xs` | 11.5 / 16, +0.06 em, caps | 500 | mono | 22 / 28 | Section labels (`ACCOUNT`, `SSH`) |

Rules:
1. Minimum size 11.5 sp (caps section labels only); body text ≥ 12.5 sp.
2. No fixed-height text container. Heights are minimums (`minHeight`) and grow with the text. Rows, buttons and banners wrap; nothing is ellipsised except one-line metadata. A metadata line instead wraps line by line at ≥ 1.5× text scale (see `machines › text-200`).
3. Codes and fingerprints never wrap mid-group: 6-digit codes are 3 + 3, link codes are `XXX-XXX`, fingerprints break at fixed 16-character chunks.
4. Numbers in timers and counters use tabular figures (`tnum`).

## 6. Spacing, layout, breakpoints

- **Grid:** 4 dp. The spacing steps are 4, 8, 12, 16, 20, 24, 32, 40 and 48.
- **Phone:** side margin 16. Card padding 16. Gaps: between cards 12, between groups 20–24, field label to box 6, field to field 12.
- **Fixed heights:**
  - status bar 32;
  - app bar 64 (back / actions in 48 × 48);
  - bottom navigation 80;
  - gesture area 24;
  - pinned bottom action bar 88 (button 52, top hairline).
- **Breakpoints (window width):**
  - **compact < 600:** bottom nav and one pane.
  - **medium 600–839:** navigation rail (80) and two panes (list 360 + detail).
  - **expanded ≥ 840:** the same as medium, and the detail gets a max width of 560.
  - Foldables use the hinge as the pane split when it is vertical.
- **Mocks:** phone 360 × 800 dp, tablet / foldable 840 × 900 dp.

## 7. Radii

| Token | dp | Use |
|---|---|---|
| `r-xs` | 6 | checkbox |
| `r-sm` | 10 | chips, icon boxes (40), small buttons, code-digit boxes |
| `r-md` | 12 | text fields, wells, banners' inner strips, icon tiles (44) |
| `r-lg` | 14 | buttons (52), segmented control, banners |
| `r-xl` | 16–18 | cards, list groups, FAB |
| `r-2xl` | 24–26 | glass cards (sign-in), tablet bento tiles |
| `r-sheet` | 28 | bottom sheet top corners |
| `r-full` | 999 | switch, pills, dots |

## 8. Elevation and glass

- Lists and forms are flat: a `card` fill and a 1 px edge (`hairline` dark, black 8 % light). Light cards add a 1 dp black 4 % lip. There are no material shadows on lists.
- The FAB has a 25 % black shadow (blur 8, y +8) and a 1 px white 22 % top highlight.
- **Glass** (sign-in only, from desktop SPEC-v2 §2). It is faked; there is no backdrop blur, which would cost frames on mid-range phones:
  - Dark: `raised` at 55 %, then a white gradient from 7.5 % to 3 %, a 1 px white 10 % edge, a 1 px white 20 % top highlight, and a black 55 % shadow (blur 44, y +12).
  - Light: a white gradient from 86 % to 66 %, a black 7 % edge, a white top highlight, and a black 16 % shadow.
- **Backdrop** (sign-in): a radial wash (`accent` 16 % dark / `foreground` 6 % light) plus the falling-code band.
  - The band is JetBrains Mono 11 at about 9 % opacity, with the head glyph in `accent`.
  - It is masked so it fades top and bottom. It never runs under text without the glass card between.

## 9. Motion

| Token | Duration | Curve | Use |
|---|---|---|---|
| `instant` | 0 ms | — | reduce-motion replacement for everything below |
| `fast` | 120 ms | standard (0.2, 0, 0, 1) | press states, switch thumb, checkbox |
| `base` | 200 ms | standard | tab / segment change, banner in/out (fade + 8 dp slide) |
| `emphasis` | 280 ms | emphasized decel (0.05, 0.7, 0.1, 1) | sheet up, pane change on tablet |
| `exit` | 160 ms | emphasized accel (0.3, 0, 0.8, 0.15) | sheet down, dialogs out |
| `spinner` | 900 ms/turn | linear | all spinners (one style: 28 % arc on a 20 % track) |
| `shimmer` | 1200 ms | linear, loop | skeleton rows |
| `pulse` | 1600 ms | ease-in-out, loop | "Listening for new machines" dot |
| `rain` | 60 ms/row, 24 fps cap | — | sign-in code band. It pauses off-screen and when battery saver is on |

With **reduce motion** (`MediaQuery.disableAnimations` / Android "Remove animations"):
- the code band is static;
- the pulse and shimmer stop (the skeleton shows a flat colour);
- transitions become cross-fades of at most 100 ms.

## 10. Icons

- **Set:** Lucide (ISC), the same set as the desktop. 24 dp grid, stroke 1.75 at 24 (1.5 at ≤ 16), round caps and joins.
- **Duotone accent icons:** a fill layer at `currentColor` 18 % under the line icon (SPEC-v2 §5). They are used in icon tiles (44, `r-md`, `tint` 10 % fill + 22 % edge) and in selected tabs.
- **Sizes:** 20 in buttons and rows, 24 in app bars and navigation, 40 for the biometric prompt.
- **Brand:**
  - The dot-matrix mark is the shipped logo (`logos/h0x-mark-transparent.png`) sampled on a grid: 3.6 dp step and dot r 1.2 on phone; 5 dp step and r 1.7 on tablet.
  - The solid mark (`cook/src/mark.js` path) is used in the navigation rail at 28 dp.
- Provider buttons use the official Google "G" and GitHub marks, under each brand's sign-in guidelines (the mock's G is a simplified stand-in).

## 11. Touch targets

- Every interactive element has a target of at least **48 × 48 dp**. The mock generator asserts this and fails otherwise, and `README.md` lists every target with its size.
- A visual can be smaller than its target (a 20 dp icon in a 48 dp button). Targets never overlap: there are at least 8 dp between the targets of adjacent small actions.
- **Primary actions:** 52 dp tall, full width on phone.
- **Rows:** 56 dp for menu items; 64–72 dp for list rows with two lines.
- Destructive and primary actions are never adjacent without a gap of 12 dp or more.

## 12. Screen reader and focus

**Label rules** (TalkBack and `Semantics`):
1. Every tappable element has a label that says what it does, not what it looks like: "Copy public key", not "Copy icon".
2. List rows are **one** node, read in this order: name, OS, mode, state. For example: "studio-pc, Windows, account, 1 agent needs you". Decorative parts inside (the OS box, the dot, the tag brackets) are excluded.
3. Icon-only buttons name their object when there is more than one on screen ("Rename h0x-gcp", "Copy link command").
4. Codes are read digit by digit with a pause between groups: "Approval code 4 8 2, 9 1 3". Keys and fingerprints are read as their type plus the first 4 characters ("ed25519 key, fingerprint SHA256 4mQe"), with a "Copy" action.
5. Toggles carry state: "Use Tailscale SSH, no key, off". Tabs and segments say "selected". Checkboxes say "selected" / "not selected".
6. Live regions:
   - polite: "Waiting for Google", "Waiting for studio-pc", "Connecting: Log in as dev", "syncing";
   - assertive (announced as alerts): errors, and the host-key warning.
7. Disabled controls stay focusable and read their reason ("Continue with Google, unavailable while offline").
8. No text is baked into images. The brand mark is decorative ("HyperOx" is real text next to it).

**Focus order** (keyboard, switch access, TalkBack linear). It runs top to bottom, start to end, except where noted:
- **Sign in:** Continue with Google → GitHub → email → Continue without an account → Terms → Privacy. Initial focus: Continue with Google. While waiting: Cancel. On error: the error banner (read), then Google.
- **Machines:**
  - App bar (Search → More) → account rows → SSH rows (row → its "Review" strip) → Add machine (FAB) → navigation.
  - The FAB is visually last but is placed after the list on purpose.
  - Tablet: rail → list → detail (title actions → connection → agents → Open inbox → Spaces → Remove).
- **Add machine:**
  - Back → mode segment → content. SSH: Import → Host → User → Port → Tailscale switch → key (Copy, Share) → Connect.
  - On validation failure, focus moves to the first invalid field.
- **Sheets:** focus moves into the sheet (title first) and is trapped until it closes, then returns to the element that opened it. The safe action comes first: "Don't connect" before "Trust new key…", Cancel last.
