import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../theme/theme_controller.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx_icons.dart';

/// Every desktop theme, each with a live swatch drawn in its own colours,
/// the one on screen ticked, plus System / Light / Dark like the desktop.
class ThemePickerScreen extends ConsumerStatefulWidget {
  const ThemePickerScreen({super.key});

  @override
  ConsumerState<ThemePickerScreen> createState() => _ThemePickerScreenState();
}

class _ThemePickerScreenState extends ConsumerState<ThemePickerScreen> {
  /// Wide layout: the theme shown in the preview pane (tapping a row picks
  /// it; "Use <theme>" applies it). Null: the one in use.
  String? _preview;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx.colors;
    final settings = ref.watch(themeControllerProvider);
    final platform = MediaQuery.platformBrightnessOf(context);
    final active = settings.active(platform);
    final controller = ref.read(themeControllerProvider.notifier);
    final dark = kThemeSpecs.where((t) => !t.isLight).toList();
    final light = kThemeSpecs.where((t) => t.isLight).toList();

    final system = settings.mode == HxThemeMode.system;
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    final previewId = _preview ?? active.id;

    Widget section(String title, List<ThemeSpec> specs, {String? hint}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: HxType.labelXs.copyWith(color: hx.muted)),
              ),
              if (hint != null)
                Text(hint, style: HxType.mono.copyWith(color: hx.muted, fontSize: 11.5)),
            ],
          ),
        ),
        for (final spec in specs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ThemeRow(
              spec: spec,
              selected: spec.id == active.id,
              previewed: wide && spec.id == previewId,
              onTap: wide
                  ? () => setState(() => _preview = spec.id)
                  : () => controller.select(spec.id, platform: platform),
            ),
          ),
      ],
    );

    final listPane = Column(
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
                  // Light first (the desktop's order). System lists both, with
                  // when each is used; Light and Dark list only their own.
                  if (settings.mode != HxThemeMode.dark)
                    section(
                      'LIGHT · ${light.length}',
                      light,
                      hint: system ? 'used when the phone is light' : null,
                    ),
                  if (settings.mode != HxThemeMode.light)
                    section(
                      'DARK · ${dark.length}',
                      dark,
                      hint: system ? 'used when the phone is dark' : null,
                    ),
                ],
              ),
            ),
          ],
        );
    final preview = themeById(previewId);
    return Scaffold(
      backgroundColor: hx.screen,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: listPane,
                  ),
                  VerticalDivider(width: 1, color: hx.hairline),
                  Expanded(
                    child: ThemePreview(
                      spec: preview,
                      inUse: preview.id == active.id,
                      onUse: () => controller.select(preview.id, platform: platform),
                    ),
                  ),
                ],
              )
            : listPane,
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
    this.previewed = false,
  });

  final ThemeSpec spec;
  final bool selected;
  final bool previewed;
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
        color: selected || previewed ? hx.selected : hx.card,
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
                color: selected
                    ? hx.accent
                    : (previewed ? hx.outline : hx.hairline),
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
                        spec.isLight ? '[light]' : '[dark]',
                        // On a selected row the secondary text is foreground.
                        style: HxType.mono.copyWith(
                          color: selected ? hx.foreground : hx.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: hx.accent, shape: BoxShape.circle),
                    child: Center(
                      child: HxIcon('check', size: 16, color: hx.accentForeground),
                    ),
                  ),
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

/// The sample session every preview shows: (text, ANSI colour index or null).
const kPreviewSession = <List<(String, int?)>>[
  [(r'$ claude --continue', null)],
  [('● ', 2), ('Read ', null), ('src/pricing.ts', 6), (' (128 lines)', null)],
  [('● ', 2), ('Edit ', null), ('src/pricing.ts', 6)],
  [('42 -  const cta = "Start now";', 1)],
  [('42 +  const cta = "Start free trial";', 2)],
  [('Allow this edit?', null)],
  [('❯ 1. Yes   2. Always   3. No', null)],
];

/// Where a theme comes from, for the preview's mono line.
String themeSource(String id) =>
    const {'graphite', 'ink', 'moss', 'paper'}.contains(id)
        ? 'built in'
        : 'from $id.json';

/// A theme drawn in its own colours (board settings 10): a card, a terminal
/// with the shared sample session, and the 16 ANSI swatches, plus the button
/// that applies it. Nothing here reads the app's current theme.
class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.spec,
    required this.onUse,
    this.inUse = false,
  });

  final ThemeSpec spec;
  final VoidCallback onUse;

  /// The theme is the one on screen already.
  final bool inUse;

  @override
  Widget build(BuildContext context) {
    final c = HxColors(spec.roles);
    final t = TerminalColors(spec.terminal);
    final kind = spec.isLight ? 'light' : 'dark';
    Widget button(String label, {required bool primary}) => Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary ? c.accent : null,
        borderRadius: BorderRadius.circular(12),
        border: primary ? null : Border.all(color: c.outline),
      ),
      child: Text(
        label,
        style: HxType.weight(HxType.bodyLg, 600).copyWith(
          color: primary ? c.accentForeground : c.foreground,
        ),
      ),
    );
    return ColoredBox(
      color: c.screen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Preview',
                style: HxType.titleSm.copyWith(color: c.foreground),
              ),
            ),
            Text(
              '${spec.label} · $kind · ${themeSource(spec.id)}',
              style: HxType.mono.copyWith(color: c.muted),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ExcludeSemantics(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: c.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'studio-pc',
                              style: HxType.heading.copyWith(color: c.foreground),
                            ),
                            Text(
                              'windows · 3 agents',
                              style: HxType.mono.copyWith(color: c.muted),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: button('Approve', primary: true)),
                                const SizedBox(width: 8),
                                Expanded(child: button('Deny', primary: false)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in kPreviewSession)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    for (final (text, ansi) in line)
                                      TextSpan(
                                        text: text,
                                        style: TextStyle(
                                          color: ansi == null ? t.foreground : t.ansi[ansi],
                                        ),
                                      ),
                                  ],
                                ),
                                style: HxType.mono.copyWith(fontSize: 11.5, height: 1.5),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var row = 0; row < 2; row++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              for (var i = 0; i < 8; i++) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: t.ansi[row * 8 + i],
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: c.hairline),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                enabled: !inUse,
                label: inUse ? '${spec.label}, in use' : 'Use ${spec.label}',
                excludeSemantics: true,
                onTap: inUse ? null : onUse,
                child: Opacity(
                  opacity: inUse ? 0.38 : 1,
                  child: Material(
                    color: c.solid,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: inUse ? null : onUse,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52, minWidth: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        alignment: Alignment.center,
                        child: Text(
                          inUse ? 'In use' : 'Use ${spec.label}',
                          style: HxType.bodyLg.copyWith(color: c.solidForeground),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
