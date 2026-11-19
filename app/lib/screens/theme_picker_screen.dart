import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../theme/theme_controller.dart';
import '../theme/themes.dart';
import '../theme/type.dart';

/// Every desktop theme, each with a live swatch drawn in its own colours,
/// the one on screen ticked, plus System / Light / Dark like the desktop.
class ThemePickerScreen extends ConsumerWidget {
  const ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx.colors;
    final settings = ref.watch(themeControllerProvider);
    final platform = MediaQuery.platformBrightnessOf(context);
    final active = settings.active(platform);
    final controller = ref.read(themeControllerProvider.notifier);
    final dark = kThemeSpecs.where((t) => !t.isLight).toList();
    final light = kThemeSpecs.where((t) => t.isLight).toList();

    Widget section(String title, List<ThemeSpec> specs) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Semantics(
            header: true,
            child: Text(title, style: HxType.labelXs.copyWith(color: hx.muted)),
          ),
        ),
        for (final spec in specs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ThemeRow(
              spec: spec,
              selected: spec.id == active.id,
              onTap: () => controller.select(spec.id, platform: platform),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: hx.screen,
      body: SafeArea(
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    header: true,
                    child: Text('Theme', style: HxType.title),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _ModeSegments(
                    mode: settings.mode,
                    onChanged: controller.setMode,
                  ),
                  section('DARK THEMES', dark),
                  section('LIGHT THEMES', light),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSegments extends StatelessWidget {
  const _ModeSegments({required this.mode, required this.onChanged});

  final HxThemeMode mode;
  final ValueChanged<HxThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx.colors;
    const labels = {
      HxThemeMode.system: 'System',
      HxThemeMode.light: 'Light',
      HxThemeMode.dark: 'Dark',
    };
    return Container(
      decoration: BoxDecoration(
        color: hx.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hx.hairline),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final m in HxThemeMode.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: m == mode,
                label: '${labels[m]} mode${m == mode ? ', selected' : ''}',
                excludeSemantics: true,
                onTap: () => onChanged(m),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(m),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: m == mode ? hx.selected : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      labels[m]!,
                      style: HxType.bodyLg.copyWith(
                        color: m == mode ? hx.accent : hx.foreground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final ThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx.colors;
    final kind = spec.isLight ? 'light' : 'dark';
    return Semantics(
      button: true,
      selected: selected,
      label: '${spec.label}, $kind theme${selected ? ', selected' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: hx.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? hx.accent : hx.hairline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                ThemeSwatch(spec: spec),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spec.label, style: HxType.heading),
                      Text(
                        spec.isLight ? 'Light' : 'Dark',
                        style: HxType.caption.copyWith(color: hx.muted),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check, color: hx.accent, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 72 x 48 preview in the theme's own colours: its terminal background,
/// accent and foreground bars, and ANSI red to cyan.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({super.key, required this.spec});

  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    final c = HxColors(spec.roles);
    final t = TerminalColors(spec.terminal);
    Widget bar(Color color, double w) => Container(
      width: w,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.5),
      ),
    );
    return Container(
      width: 72,
      height: 48,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              bar(c.accent, 18),
              const SizedBox(width: 4),
              bar(t.foreground, 26),
            ],
          ),
          Row(
            children: [
              for (var i = 1; i <= 6; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: t.ansi[i],
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
