import 'package:xterm/xterm.dart';

import 'theme_model.dart';

/// The terminal view's colours for a theme: the theme file's own palette,
/// unchanged (no minimum-contrast override), as design/tokens.md section 4.
TerminalTheme terminalThemeFor(TerminalColors t) => TerminalTheme(
  cursor: t.cursor,
  selection: t.selection,
  foreground: t.foreground,
  background: t.background,
  black: t.ansi[0],
  red: t.ansi[1],
  green: t.ansi[2],
  yellow: t.ansi[3],
  blue: t.ansi[4],
  magenta: t.ansi[5],
  cyan: t.ansi[6],
  white: t.ansi[7],
  brightBlack: t.ansi[8],
  brightRed: t.ansi[9],
  brightGreen: t.ansi[10],
  brightYellow: t.ansi[11],
  brightBlue: t.ansi[12],
  brightMagenta: t.ansi[13],
  brightCyan: t.ansi[14],
  brightWhite: t.ansi[15],
  searchHitBackground: t.ansi[3],
  searchHitBackgroundCurrent: t.ansi[2],
  searchHitForeground: t.background,
);
