import 'package:material_ui/material_ui.dart';

/// `#rrggbb` or `#rrggbbaa` (the desktop theme files' notation) to a [Color].
Color parseHex(String s) {
  final v = int.parse(s.substring(1), radix: 16);
  if (s.length == 7) return Color(0xFF000000 | v);
  return Color(((v & 0xFF) << 24) | (v >> 8));
}

/// A theme's terminal colours: exactly the desktop theme file's own.
class TerminalSpec {
  const TerminalSpec({
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.ansi,
  });

  final String background;
  final String foreground;
  final String cursor;
  final String selection;

  /// The 16 ANSI colours, 0 black .. 15 bright white.
  final List<String> ansi;
}

/// One theme as generated from the desktop (palettes.g.dart): hex strings,
/// so the test can compare them with design/tokens.md byte for byte.
class ThemeSpec {
  const ThemeSpec({
    required this.id,
    required this.label,
    required this.isLight,
    required this.roles,
    required this.terminal,
  });

  final String id;
  final String label;
  final bool isLight;

  /// Role name (desktop snake_case, plus the mobile roles) to hex.
  final Map<String, String> roles;
  final TerminalSpec terminal;
}

/// The colour roles screens use, from design/tokens.md section 2.
class HxColors {
  HxColors(Map<String, String> r)
    : background = parseHex(r['background']!),
      foreground = parseHex(r['foreground']!),
      muted = parseHex(r['muted']!),
      dim = parseHex(r['dim']!),
      raised = parseHex(r['raised']!),
      popover = parseHex(r['popover']!),
      chrome = parseHex(r['chrome']!),
      border = parseHex(r['border']!),
      accent = parseHex(r['accent']!),
      accentForeground = parseHex(r['accent_foreground']!),
      solid = parseHex(r['solid']!),
      solidForeground = parseHex(r['solid_foreground']!),
      ring = parseHex(r['ring']!),
      working = parseHex(r['working']!),
      blocked = parseHex(r['blocked']!),
      done = parseHex(r['done']!),
      screen = parseHex(r['screen']!),
      card = parseHex(r['card']!),
      outline = parseHex(r['outline']!),
      well = parseHex(r['well']!),
      ok = parseHex(r['ok']!),
      selected = parseHex(r['selected_mobile']!),
      hairline = parseHex(r['hairline']!),
      scrim = parseHex(r['scrim']!);

  final Color background;
  final Color foreground;
  final Color muted;
  final Color dim;
  final Color raised;
  final Color popover;
  final Color chrome;
  final Color border;
  final Color accent;
  final Color accentForeground;
  final Color solid;
  final Color solidForeground;
  final Color ring;
  final Color working;
  final Color blocked;
  final Color done;
  final Color screen;
  final Color card;
  final Color outline;
  final Color well;
  final Color ok;
  final Color selected;
  final Color hairline;
  final Color scrim;
}

/// The terminal palette as colours (background, foreground, cursor,
/// selection, 16 ANSI).
class TerminalColors {
  TerminalColors(TerminalSpec s)
    : background = parseHex(s.background),
      foreground = parseHex(s.foreground),
      cursor = parseHex(s.cursor),
      selection = parseHex(s.selection),
      ansi = [for (final c in s.ansi) parseHex(c)];

  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final List<Color> ansi;
}
