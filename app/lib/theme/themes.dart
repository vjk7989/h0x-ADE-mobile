import 'package:material_ui/material_ui.dart';

import 'palettes.g.dart';
import 'theme_model.dart';

export 'palettes.g.dart' show kThemeSpecs;
export 'theme_model.dart';

/// The mock's defaults: `paper` (light) and `darkmatter` (dark).
const String kDefaultLightTheme = 'paper';
const String kDefaultDarkTheme = 'darkmatter';

ThemeSpec themeById(String id) => kThemeSpecs.firstWhere(
  (t) => t.id == id,
  orElse: () => throw ArgumentError('unknown theme "$id"'),
);

bool isThemeId(String id) => kThemeSpecs.any((t) => t.id == id);

/// Colours and terminal palette of the active theme, read with
/// `context.hx`.
class HxTheme extends ThemeExtension<HxTheme> {
  HxTheme(this.spec)
    : colors = HxColors(spec.roles),
      terminal = TerminalColors(spec.terminal);

  final ThemeSpec spec;
  final HxColors colors;
  final TerminalColors terminal;

  @override
  HxTheme copyWith() => this;

  @override
  HxTheme lerp(ThemeExtension<HxTheme>? other, double t) =>
      other is HxTheme && t >= 0.5 ? other : this;
}

extension HxContext on BuildContext {
  HxTheme get hx => Theme.of(this).extension<HxTheme>()!;
}

Color _onColor(Color c) =>
    c.computeLuminance() > 0.4 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

final Map<String, ThemeData> _cache = {};

/// The [ThemeData] of one theme (cached: building it is cheap but screens
/// ask on every build).
ThemeData themeData(ThemeSpec spec) => _cache.putIfAbsent(spec.id, () {
  final c = HxColors(spec.roles);
  final scheme = ColorScheme(
    brightness: spec.isLight ? Brightness.light : Brightness.dark,
    primary: c.accent,
    onPrimary: c.accentForeground,
    secondary: c.solid,
    onSecondary: c.solidForeground,
    error: c.blocked,
    onError: _onColor(c.blocked),
    surface: c.screen,
    onSurface: c.foreground,
    outline: c.outline,
    outlineVariant: c.hairline,
    scrim: c.scrim,
  );
  final base = ThemeData(colorScheme: scheme, fontFamily: 'Geist');
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: c.foreground,
      displayColor: c.foreground,
    ),
    dividerColor: c.hairline,
    extensions: [HxTheme(spec)],
  );
});
