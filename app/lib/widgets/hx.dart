import 'package:material_ui/material_ui.dart';

import '../theme/themes.dart';
import '../theme/type.dart';

enum HxButtonKind { primary, secondary, outline, danger }

/// A 52 dp button (design/tokens.md section 11): one semantics node, label
/// read as given, disabled at 38 % opacity.
class HxButton extends StatelessWidget {
  const HxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = HxButtonKind.secondary,
    this.semanticsLabel,
    this.minHeight = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final HxButtonKind kind;
  final String? semanticsLabel;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
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
      label: semanticsLabel ?? label,
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
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: fg),
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

enum HxBannerKind { error, info }

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
    final tone = kind == HxBannerKind.error ? c.blocked : c.working;
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $message',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withAlpha(kind == HxBannerKind.error ? 18 : 8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              kind == HxBannerKind.error
                  ? Icons.error_outline
                  : Icons.info_outline,
              color: tone,
              size: 20,
            ),
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

/// The dot-matrix H mark, drawn as a grid of dots (decorative).
class HxMark extends StatelessWidget {
  const HxMark({super.key, this.size = 72});

  final double size;

  static const _rows = [
    '1000001',
    '1000001',
    '1000001',
    '1111111',
    '1000001',
    '1000001',
    '1000001',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size),
        painter: _MarkPainter(c.foreground, c.accent),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.dot, this.accent);

  final Color dot;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 7;
    for (var y = 0; y < 7; y++) {
      for (var x = 0; x < 7; x++) {
        if (HxMark._rows[y][x] != '1') continue;
        canvas.drawCircle(
          Offset(step * (x + 0.5), step * (y + 0.5)),
          step * 0.3,
          Paint()..color = y == 3 ? accent : dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.dot != dot || old.accent != accent;
}
