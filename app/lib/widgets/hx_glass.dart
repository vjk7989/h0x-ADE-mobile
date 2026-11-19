import 'package:material_ui/material_ui.dart';

import '../theme/themes.dart';

/// Fake glass for the sign-in and unlock cards (design/tokens.md section 8,
/// the desktop's SPEC-v2). No `BackdropFilter`: a blur would cost frames on a
/// mid-range phone, so the glass is layers.
///
/// - Dark: `raised` at 55 %, a white gradient from 7.5 % to 3 %, a 1 px white
///   10 % edge, a 1 px white 20 % top highlight, a black 55 % shadow.
/// - Light: a white gradient from 86 % to 66 %, a black 7 % edge, a white top
///   highlight, a black 16 % shadow.
class HxGlass extends StatelessWidget {
  const HxGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    final decoration = dark
        ? BoxDecoration(
            color: c.raised.withValues(alpha: 0.55),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFFFFFFF).withValues(alpha: 0.075),
                const Color(0xFFFFFFFF).withValues(alpha: 0.03),
              ],
            ),
            borderRadius: r,
            border: Border.all(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.55),
                blurRadius: 44,
                offset: const Offset(0, 12),
              ),
            ],
          )
        : BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFFFFFFF).withValues(alpha: 0.86),
                const Color(0xFFFFFFFF).withValues(alpha: 0.66),
              ],
            ),
            borderRadius: r,
            border: Border.all(
              color: const Color(0xFF000000).withValues(alpha: 0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.16),
                blurRadius: 44,
                offset: const Offset(0, 18),
              ),
            ],
          );
    return DecoratedBox(
      decoration: decoration,
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          // The top highlight, inset by the radius so it does not touch the corners.
          Positioned(
            top: 0,
            left: radius,
            right: radius,
            height: 1,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF).withValues(alpha: dark ? 0.20 : 1),
            ),
          ),
        ],
      ),
    );
  }
}
