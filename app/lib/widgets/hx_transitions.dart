import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/motion.dart';

/// Rows register a [GlobalKey] by id, so the container transform can find a
/// row's rect, and on the way back the row's CURRENT place (the list may have
/// scrolled or changed meanwhile).
class HxRowRegistry {
  HxRowRegistry._();

  static final _keys = <String, GlobalKey>{};

  static GlobalKey keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// The row's rect in the screen, or null when it is not on screen.
  static Rect? rectOf(String id) {
    final box = _keys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// What the router gets as `extra` when it opens [id] from its row.
  static HxOrigin? originOf(
    String id, {
    required double radius,
    required Color color,
  }) {
    final r = rectOf(id);
    return r == null
        ? null
        : HxOrigin(id: id, rect: r, radius: radius, color: color);
  }
}

class HxOrigin {
  const HxOrigin({
    required this.id,
    required this.rect,
    required this.radius,
    required this.color,
  });

  final String id;
  final Rect rect;
  final double radius;
  final Color color;
}

/// X-axis shared axis: the incoming page slides 30 dp and fades in, the
/// outgoing one slides -30 dp and fades out (300 ms, emphasized). With reduced
/// motion: a fade of at most 100 ms. Predictive back drives the same
/// animation backwards (the route's controller follows the gesture).
class HxSharedAxisPage<T> extends CustomTransitionPage<T> {
  HxSharedAxisPage({super.key, required super.child, super.name})
    : super(
        transitionDuration: HxMotion.sharedAxis,
        reverseTransitionDuration: HxMotion.sharedAxis,
        transitionsBuilder: sharedAxis,
      );

  static Widget sharedAxis(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
  ) {
    final reduced = HxMotion.reduced(context);
    const quick = Interval(0, 1 / 3);
    final inn = CurvedAnimation(
      parent: animation,
      curve: reduced ? quick : HxMotion.emphasizedDecel,
      reverseCurve: reduced ? quick : HxMotion.emphasizedAccel,
    );
    final out = CurvedAnimation(
      parent: secondary,
      curve: reduced ? quick : HxMotion.emphasizedAccel,
      reverseCurve: reduced ? quick : HxMotion.emphasizedDecel,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([inn, out]),
      builder: (context, _) {
        final dx = reduced ? 0.0 : 30 * (1 - inn.value) - 30 * out.value;
        return Opacity(
          opacity: (inn.value * (1 - out.value)).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

/// Container transform: the tapped row's rect grows to the full screen while
/// its card colour hands over to the page (350 ms, emphasized). Back shrinks
/// it to the row's current rect; if the row is gone it is a shared axis.
class HxContainerPage<T> extends CustomTransitionPage<T> {
  HxContainerPage({
    super.key,
    required super.child,
    super.name,
    required HxOrigin origin,
  }) : super(
         transitionDuration: HxMotion.container,
         reverseTransitionDuration: HxMotion.container,
         transitionsBuilder: (context, animation, secondary, child) =>
             container(context, animation, secondary, child, origin),
       );

  static Widget container(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
    HxOrigin origin,
  ) {
    if (HxMotion.reduced(context)) {
      return HxSharedAxisPage.sharedAxis(context, animation, secondary, child);
    }
    final size = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final reversing = animation.status == AnimationStatus.reverse;
        final now = HxRowRegistry.rectOf(origin.id);
        if (reversing && now == null) {
          return HxSharedAxisPage.sharedAxis(
            context,
            animation,
            secondary,
            child,
          );
        }
        // The rect grows from the row toward the screen, radius to 0. The
        // card fill covers the row's content over the first 35 % (the row
        // fades out), and the page fades in inside the rect from 35 %. Back
        // runs it the other way: the fill leaves over the last 30 %, so the
        // row's own content is back and there is never an empty card.
        final v = animation.value;
        // A gentler curve than the page's: the rect is seen between the row and
        // the screen (at 70 ms it is about a fifth of the way).
        final t = const Cubic(0.4, 0, 0.2, 1).transform(v);
        final rect = Rect.lerp(now ?? origin.rect, Offset.zero & size, t)!;
        final fill = (v / (reversing ? 0.3 : 0.35)).clamp(0.0, 1.0);
        final page = ((v - 0.35) / 0.65).clamp(0.0, 1.0);
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(origin.radius * (1 - t)),
                child: ColoredBox(
                  color: origin.color.withValues(alpha: fill),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: Opacity(opacity: page, child: child),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
