import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:material_ui/material_ui.dart' hide Icon;

import 'hx_icon_compat.dart';
import 'hx_icons.dart';
import '../theme/themes.dart';
import '../theme/type.dart';

enum HxButtonKind { primary, secondary, outline, danger }

/// A 52 dp button (design/tokens.md section 11): one semantics node, label
/// read as given, disabled at 38 % opacity.
class HxButton extends StatefulWidget {
  const HxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.lucide,
    this.leading,
    this.kind = HxButtonKind.secondary,
    this.semanticsLabel,
    this.minHeight = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// A Lucide icon by name (see hx_icons.dart); wins over [icon].
  final String? lucide;

  /// A custom leading widget (a brand mark); wins over both.
  final Widget? leading;
  final HxButtonKind kind;
  final String? semanticsLabel;
  final double minHeight;

  @override
  State<HxButton> createState() => _HxButtonState();
}

class _HxButtonState extends State<HxButton> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final onPressed = widget.onPressed;
    final icon = widget.icon;
    final lucide = widget.lucide;
    final leading = widget.leading;
    final kind = widget.kind;
    final minHeight = widget.minHeight;
    final c = context.hx.colors;
    // A keyboard focus ring: 2 dp accent, only when the keyboard drives.
    final ring = _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final (bg, fg, edge) = switch (kind) {
      HxButtonKind.primary => (c.solid, c.solidForeground, c.solid),
      HxButtonKind.secondary => (c.card, c.foreground, c.hairline),
      HxButtonKind.outline => (c.screen, c.foreground, c.outline),
      HxButtonKind.danger => (c.screen, c.blocked, c.blocked),
    };
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: edge),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            onFocusChange: (f) => setState(() => _focused = f),
            child: Container(
              foregroundDecoration: ring
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.accent, width: 2),
                    )
                  : null,
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (leading != null || lucide != null || icon != null) ...[
                      leading ??
                          (lucide != null
                              ? HxIcon(lucide, size: 20, color: fg)
                              : Icon(icon, size: 20, color: fg)),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: HxType.bodyLg.copyWith(color: fg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A list or form container: card fill and a hairline edge, no shadow.
class HxCard extends StatelessWidget {
  const HxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.hairline),
      ),
      // Ink in rows below needs a Material; the card draws its own fill.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

enum HxBannerKind { error, info, offline, warn }

/// A strip announced to the screen reader as it appears. Text stays
/// `foreground`; the state colour is on the icon and the edge (tokens rule 3).
class HxBanner extends StatelessWidget {
  const HxBanner({
    super.key,
    required this.title,
    required this.message,
    this.kind = HxBannerKind.error,
  });

  final String title;
  final String message;
  final HxBannerKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final tone = switch (kind) {
      HxBannerKind.error => c.blocked,
      HxBannerKind.info || HxBannerKind.warn => c.working,
      HxBannerKind.offline => c.muted,
    };
    final icon = switch (kind) {
      HxBannerKind.error => 'alert',
      HxBannerKind.info => 'info',
      HxBannerKind.offline => 'wifi-off',
      HxBannerKind.warn => 'triangle',
    };
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $message',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withAlpha(kind == HxBannerKind.error ? 18 : 3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HxIcon(icon, color: tone, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HxType.bodyLg.copyWith(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(message, style: HxType.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `[word]` as the desktop's CLI tags: brackets in `dim`, word in [color].
class HxTag extends StatelessWidget {
  const HxTag(this.word, {super.key, required this.color});

  final String word;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dim = context.hx.colors.dim;
    return Text.rich(
      TextSpan(
        style: HxType.mono,
        children: [
          TextSpan(text: '[', style: TextStyle(color: dim)),
          TextSpan(text: word, style: TextStyle(color: color)),
          TextSpan(text: ']', style: TextStyle(color: dim)),
        ],
      ),
    );
  }
}

/// The dot-matrix HyperOx mark: the shipped logo sampled on a 21 x 25 grid
/// (design/tokens.md section 8). [size] is the width; the height is
/// width x 25/21. One colour: `accent` on dark themes, `foreground` on light.
class HxMark extends StatelessWidget {
  const HxMark({super.key, this.size = 74});

  final double size;

  static const _rows = [
    '000001110000000000011',
    '000011110000000001111',
    '001111010000000011101',
    '011100010000001110001',
    '111000110000011100011',
    '110011110000011000111',
    '110111010000011001101',
    '110110010000011001001',
    '110110010000011001001',
    '110110010000011001001',
    '110110011111111001001',
    '110110011000111001001',
    '110110011000111001001',
    '110110011000111001001',
    '110110011111111001001',
    '110110011111111001001',
    '110110010000011001001',
    '110110010000011001001',
    '110110010000011001001',
    '110011110000011001111',
    '110001110000011000111',
    '110001110000011000111',
    '110111100000011011110',
    '111110000000011111000',
    '111100000000011110000',
  ];

  /// The dot grid, for tools/gen_icons.py's test: the launcher icon must be
  /// this grid.
  @visibleForTesting
  static List<String> get rows => _rows;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size * 25 / 21),
        painter: _MarkPainter(dark ? c.accent : c.foreground),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.tint);

  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 21;
    final paint = Paint()..color = tint;
    for (var y = 0; y < HxMark._rows.length; y++) {
      final row = HxMark._rows[y];
      for (var x = 0; x < 21; x++) {
        if (row[x] != '1') continue;
        canvas.drawCircle(
          Offset(step * (x + 0.5), step * (y + 0.5)),
          step / 3,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.tint != tint;
}
