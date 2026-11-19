import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;

import '../theme/motion.dart';
import '../theme/themes.dart';
import 'hx.dart';

/// Pull distance (dp) at which a release refreshes.
const double kRefreshThreshold = 80;

/// The pull-to-refresh of the lists: a 28 dp mini of the brand mark whose dots
/// light in the intro's diagonal order as the list is pulled (0 to 80 dp).
/// Past the threshold a release turns it into a spinner until [onRefresh]
/// completes, then it snaps back (200 ms). A light tap at the threshold. With
/// reduced motion there is no dot fill, only the spinner.
///
/// The list inside must be a vertical scrollable that can always scroll; it
/// overscrolls like a spring here, which is what is measured.
class HxRefresh extends StatefulWidget {
  const HxRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<HxRefresh> createState() => _HxRefreshState();
}

class _HxRefreshState extends State<HxRefresh> {
  double _pull = 0;
  var _armed = false;
  var _refreshing = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (_refreshing) return false;
    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      final dragging = n is ScrollUpdateNotification
          ? n.dragDetails != null
          : (n as OverscrollNotification).dragDetails != null;
      final pull = (-n.metrics.pixels).clamp(0.0, 160.0);
      if (pull != _pull) setState(() => _pull = pull);
      if (pull >= kRefreshThreshold && !_armed && dragging) {
        _armed = true;
        HapticFeedback.lightImpact();
      } else if (pull < kRefreshThreshold && dragging) {
        // Only a finger lowers it again; the spring back after a release must
        // not disarm the refresh.
        _armed = false;
      }
    } else if (n is ScrollEndNotification) {
      final go = _armed;
      _armed = false;
      if (go) {
        _run();
      } else if (_pull != 0) {
        setState(() => _pull = 0);
      }
    }
    return false;
  }

  Future<void> _run() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _pull = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final reduced = HxMotion.reduced(context);
    final p = (_pull / kRefreshThreshold).clamp(0.0, 1.0);
    final show = _refreshing || _pull > 0;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          overscroll: false,
        ),
        child: Stack(
          children: [
            // The list moves down while it refreshes, to show the spinner.
            AnimatedPadding(
              duration: HxMotion.d(context, HxMotion.stateChange, fade: true),
              curve: HxMotion.standard,
              padding: EdgeInsets.only(top: _refreshing ? 56 : 0),
              child: widget.child,
            ),
            if (show)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                height: 40,
                child: IgnorePointer(
                  child: Center(
                    child: _refreshing || reduced
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: c.accent,
                              value: _refreshing ? null : p,
                            ),
                          )
                        : Opacity(
                            opacity: 0.3 + 0.7 * p,
                            child: CustomPaint(
                              size: const Size(28, 28 * 25 / 21),
                              painter: _MarkPullPainter(p, c.accent, c.muted),
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

/// The mark's dots, lit in the intro's diagonal order up to [progress].
class _MarkPullPainter extends CustomPainter {
  _MarkPullPainter(this.progress, this.lit, this.dim);

  final double progress;
  final Color lit;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = HxMark.rows;
    final step = size.width / 21;
    final last = 20 + 24;
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < 21; c++) {
        if (rows[r][c] != '1') continue;
        final on = (c + r) / last <= progress;
        canvas.drawCircle(
          Offset((c + 0.5) * step, (r + 0.5) * step),
          step * 0.36,
          Paint()..color = on ? lit : dim.withValues(alpha: 0.35),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPullPainter old) =>
      old.progress != progress || old.lit != lit || old.dim != dim;
}
