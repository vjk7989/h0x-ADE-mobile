import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:material_ui/material_ui.dart' hide Icon;

import 'hx_icon_compat.dart';
import 'hx_icons.dart';
import '../theme/motion.dart';
import '../theme/themes.dart';
import '../theme/type.dart';

enum HxButtonKind { primary, secondary, outline, danger }

/// The press, focus and state layer every pressable control shares
/// (design/tokens.md section 18): a state layer (hover 8 %, pressed 12 %,
/// focused 12 % of [layer]), a 90 ms press scale to 0.97 (none when motion is
/// reduced, or when [scale] is false: rows use the state layer only), and a
/// 2 dp focus ring, offset 2 dp, that follows the control's radius and shows
/// only when the keyboard or a switch drives focus.
class HxPressable extends StatefulWidget {
  const HxPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.radius = 14,
    this.scale = true,
    this.fill,
    this.side,
    this.layer,
    this.onPressedChanged,
    this.focusRingForTesting = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool scale;

  /// The control's own fill and edge, drawn under the ink.
  final Color? fill;
  final BorderSide? side;

  /// The state layer colour (default: `foreground`).
  final Color? layer;

  /// Called when the finger goes down and when it leaves.
  final ValueChanged<bool>? onPressedChanged;

  /// Tests draw the keyboard-focus look without owning the focus.
  @visibleForTesting
  final bool focusRingForTesting;

  @override
  State<HxPressable> createState() => _HxPressableState();
}

class _HxPressableState extends State<HxPressable> {
  var _down = false;
  var _focused = false;
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final reduced = HxMotion.reduced(context);
    final layer = widget.layer ?? c.foreground;
    final r = BorderRadius.circular(widget.radius);
    final ring = widget.focusRingForTesting ||
        (_focused &&
            FocusManager.instance.highlightMode == FocusHighlightMode.traditional);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ringColor = dark ? c.ring : c.accent;
    // The state layer: pressed 12 %, keyboard-focused 12 %, hovered 8 %.
    final keyboard =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final layerColor = _down
        ? layer.withValues(alpha: HxMotion.pressedLayer)
        : (_focused && keyboard) || widget.focusRingForTesting
        ? layer.withValues(alpha: HxMotion.focusedLayer)
        : _hover
        ? layer.withValues(alpha: HxMotion.hoverLayer)
        : const Color(0x00000000);
    Widget control = Material(
      color: widget.fill ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: widget.side ?? BorderSide.none,
      ),
      child: InkWell(
        borderRadius: r,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        // The state layer is drawn below, by us, so it is the same on every
        // platform and shows in goldens; the ink keeps only its splash.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        onHover: (h) => setState(() => _hover = h),
        onHighlightChanged: (v) {
          setState(() => _down = v);
          widget.onPressedChanged?.call(v);
        },
        onFocusChange: (f) => setState(() => _focused = f),
        child: Stack(
          // Pass the constraints through: the control keeps its width.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: HxMotion.d(context, HxMotion.press, fade: true),
                  curve: HxMotion.standard,
                  decoration: BoxDecoration(
                    color: layerColor,
                    borderRadius: r,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (ring) {
      control = Stack(
        clipBehavior: Clip.none,
        children: [
          control,
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius + 4),
                  border: Border.all(color: ringColor, width: 2),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!widget.scale || reduced) return control;
    return AnimatedScale(
      scale: _down ? HxMotion.pressScale : 1,
      duration: HxMotion.press,
      curve: HxMotion.standard,
      child: control,
    );
  }
}

/// A 52 dp button (design/tokens.md section 11): one semantics node, label
/// read as given, disabled at 38 % opacity. Press, focus and state layer come
/// from [HxPressable].
class HxButton extends StatelessWidget {
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
    this.focusRingForTesting = false,
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

  /// Tests draw the keyboard-focus look without owning the focus.
  @visibleForTesting
  final bool focusRingForTesting;

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
        child: HxPressable(
          onTap: onPressed,
          fill: bg,
          side: BorderSide(color: edge),
          layer: fg,
          focusRingForTesting: focusRingForTesting,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null || lucide != null || icon != null) ...[
                    leading ??
                        (lucide != null
                            ? HxIcon(lucide!, size: 20, color: fg)
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
class HxBanner extends StatefulWidget {
  const HxBanner({
    super.key,
    required this.title,
    required this.message,
    this.kind = HxBannerKind.error,
    this.trailing,
    this.ghost = false,
  });

  /// A copy shown while a removed banner fades out: no grow-in, no ghost of
  /// its own.
  final bool ghost;

  final String title;
  final String message;
  final HxBannerKind kind;

  /// Something at the end of the strip (a countdown ring, for example).
  final Widget? trailing;

  @override
  State<HxBanner> createState() => _HxBannerState();
}

class _HxBannerState extends State<HxBanner> {
  OverlayState? _overlay;
  Rect? _rect;
  var _watching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overlay = Overlay.maybeOf(context);
  }

  /// Keeps the banner's last place on screen, for its exit.
  void _remember() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      _rect = box.localToGlobal(Offset.zero) & box.size;
    }
    _watching = false;
  }

  @override
  void dispose() {
    // The banner is already out of the tree: a copy of it fades out and
    // collapses in the overlay over 160 ms (emphasized accel).
    final overlay = _overlay;
    final rect = _rect;
    if (!widget.ghost && overlay != null && overlay.mounted && rect != null) {
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => _BannerGhost(
          rect: rect,
          onDone: () => entry.remove(),
          child: HxBanner(
            title: widget.title,
            message: widget.message,
            kind: widget.kind,
            trailing: widget.trailing,
            ghost: true,
          ),
        ),
      );
      overlay.insert(entry);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _remember());
    }
    final title = widget.title;
    final message = widget.message;
    final kind = widget.kind;
    final trailing = widget.trailing;
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
    // It grows in with a fade and an 8 dp slide down (200 ms, emphasized
    // decel), clipped while it grows; with reduced motion it is simply there.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: widget.ghost ? 1 : 0, end: 1),
      duration: HxMotion.d(context, HxMotion.stateChange, fade: true),
      curve: HxMotion.emphasizedDecel,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: ClipRect(
          child: Align(
            heightFactor: t.clamp(0.0, 1.0),
            alignment: Alignment.topCenter,
            child: Transform.translate(offset: Offset(0, -8 * (1 - t)), child: child),
          ),
        ),
      ),
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
            // The text reads as one label; the trailing widget keeps its own.
            Expanded(
              child: Semantics(
                liveRegion: true,
                container: true,
                label: '$title. $message',
                excludeSemantics: true,
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
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }
}

/// A removed banner, drawn over where it was: it fades out and collapses
/// (160 ms, emphasized accel), then removes itself.
class _BannerGhost extends StatefulWidget {
  const _BannerGhost({required this.rect, required this.onDone, required this.child});

  final Rect rect;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_BannerGhost> createState() => _BannerGhostState();
}

class _BannerGhostState extends State<_BannerGhost> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    // Reduced motion: gone at once.
    if (HxMotion.reduced(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      return;
    }
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: widget.rect,
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = HxMotion.emphasizedAccel.transform(_c.value);
          return Opacity(
            opacity: 1 - t,
            child: ClipRect(
              child: Align(heightFactor: 1 - t, alignment: Alignment.topCenter, child: child),
            ),
          );
        },
        child: widget.child,
      ),
    ),
  );
}

/// The accent, moved toward white or black until it reads at 4.5:1 on
/// [fill] (the inverse snackbar: `foreground` is the fill, so on a light
/// theme it is dark and the accent is lightened, as the board's #8ab4ff).
Color accentOnInverse(Color accent, Color fill) {
  if (_contrast(accent, fill) >= 4.5) return accent;
  final toward = fill.computeLuminance() < 0.4
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  for (var i = 1; i <= 20; i++) {
    final c = Color.lerp(accent, toward, i / 20)!;
    if (_contrast(c, fill) >= 4.5) return c;
  }
  return toward;
}

/// The one snackbar of the app: floating and inverse (`foreground` fill,
/// `screen` text), 16 dp side margins, radius 12, 56 dp tall, [bottom] dp
/// above the bottom (12 above the navigation; the agent screen lifts it above
/// compose and the key bar). It comes in over 200 ms (emphasized decel) and
/// leaves over 160 ms (emphasized accel). The action is the accent moved
/// until it reads at 4.5:1.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showHxSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
  double bottom = 12,
}) {
  final c = context.hx.colors;
  final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return m.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.foreground,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(message, style: HxType.body.copyWith(color: c.screen, fontSize: 13.5)),
        ),
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: accentOnInverse(c.accent, c.foreground),
              onPressed: onAction ?? () {},
            ),
      persist: false,
      duration: duration,
    ),
    snackBarAnimationStyle: AnimationStyle(
      duration: HxMotion.d(context, HxMotion.stateChange, fade: true),
      reverseDuration: HxMotion.d(context, const Duration(milliseconds: 160), fade: true),
      curve: HxMotion.emphasizedDecel,
      reverseCurve: HxMotion.emphasizedAccel,
    ),
  );
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

  /// The dot grid. tools/gen_icons.py builds the launcher icon from it, a test
  /// keeps the two equal, and the intro draws it.
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
