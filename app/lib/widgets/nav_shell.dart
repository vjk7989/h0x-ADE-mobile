import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import 'hx_icon_compat.dart';
import '../state/inbox.dart';
import '../theme/motion.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import 'hx.dart';

class _Dest {
  const _Dest(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

const _dests = [
  _Dest('Inbox', '/inbox', Icons.inbox_outlined),
  _Dest('Machines', '/machines', Icons.computer_outlined),
  _Dest('Spaces', '/spaces', Icons.dashboard_outlined),
  _Dest('To-do', '/todo', Icons.checklist),
  _Dest('Settings', '/settings', Icons.settings_outlined),
];

/// The pill sits 12 dp below the top of an item; an item is 80 dp (bar) or 76
/// dp (rail) tall.
const _pillTop = 12.0;
const _barItem = 80.0;
const _railItem = 76.0;

/// The five-item navigation: a bottom bar (80 dp) below 600 dp, a rail
/// (80 dp wide) from 600 dp up (design/tokens.md section 6). The selected
/// pill slides between items in 200 ms; the tab bodies fade through.
class NavShell extends ConsumerWidget {
  const NavShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index {
    final i = _dests.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hx.colors;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final inbox = ref.watch(inboxProvider).value;
    final body = _FadeThrough(index: _index, child: child);
    Widget item(int i, {required bool rail}) => ValueListenableBuilder<InboxState>(
      valueListenable: inbox,
      builder: (context, state, _) => _NavItem(
        dest: _dests[i],
        selected: i == _index,
        rail: rail,
        // The Inbox shows how many agents need the person.
        badge: i == 0 ? state.needsYou : 0,
        onTap: () => context.go(_dests[i].path),
      ),
    );
    final slide = HxMotion.d(context, HxMotion.stateChange);
    if (wide) {
      return Scaffold(
        backgroundColor: c.screen,
        body: Row(
          children: [
            Container(
              width: 80,
              color: c.chrome,
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // The brand mark tops the rail.
                    const HxMark(size: 28),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: _railItem * _dests.length,
                      child: Stack(
                        children: [
                          // The pill slides down and up the rail.
                          AnimatedPositioned(
                            duration: slide,
                            curve: HxMotion.standard,
                            left: 8,
                            width: 64,
                            top: _index * _railItem + _pillTop,
                            height: 32,
                            child: _Pill(color: c.selected),
                          ),
                          Column(
                            children: [
                              for (var i = 0; i < _dests.length; i++) item(i, rail: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.screen,
      body: body,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.chrome,
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: _barItem,
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth / _dests.length;
                return Stack(
                  children: [
                    // The pill slides between the items.
                    AnimatedPositioned(
                      duration: slide,
                      curve: HxMotion.standard,
                      left: _index * w + (w - 64) / 2,
                      width: 64,
                      top: _pillTop,
                      height: 32,
                      child: _Pill(color: c.selected),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _dests.length; i++)
                          Expanded(child: item(i, rail: false)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
  );
}

/// A tab change fades the new body in (200 ms, standard); with reduced motion
/// the fade is at most 100 ms. The old body is not kept: the shell's child is
/// one Navigator, which cannot sit in the tree twice.
class _FadeThrough extends StatefulWidget {
  const _FadeThrough({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_FadeThrough> createState() => _FadeThroughState();
}

class _FadeThroughState extends State<_FadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(_FadeThrough old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _c.duration = HxMotion.d(context, HxMotion.fadeThrough, fade: true);
      _c.forward(from: 0.15);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _c, curve: HxMotion.standard),
    child: widget.child,
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.rail,
    required this.onTap,
    this.badge = 0,
  });

  final _Dest dest;
  final bool selected;
  final bool rail;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduced = HxMotion.reduced(context);
    final fade = reduced ? Duration.zero : HxMotion.stateChange;
    // Selected: accent on dark, foreground on light (the boards).
    final color = selected ? (dark ? c.accent : c.foreground) : c.muted;
    final base = selected ? '${dest.label}, selected' : dest.label;
    // Labels grow with the text size, but stop at 1.3x (tokens section 14).
    final scaler = MediaQuery.textScalerOf(context);
    final labelScale = scaler.scale(12) / 12 > 1.3
        ? const TextScaler.linear(1.3)
        : scaler;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$base, $badge needs you' : base,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        height: rail ? _railItem : _barItem,
        child: HxPressable(
          radius: 16,
          scale: false,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(top: _pillTop),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 64,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // The icon colour cross-fades with the selection.
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: color),
                        duration: fade,
                        curve: HxMotion.standard,
                        builder: (context, v, _) =>
                            Icon(dest.icon, size: 24, color: v ?? color),
                      ),
                      if (badge > 0)
                        Positioned(
                          top: -4,
                          right: 6,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: dark ? c.accent : c.working,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '$badge',
                              textScaler: TextScaler.noScaling,
                              style: HxType.mono.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: dark ? c.accentForeground : Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: fade,
                  curve: HxMotion.standard,
                  builder: (context, v, _) => Text(
                    dest.label,
                    maxLines: 1,
                    textScaler: labelScale,
                    style: HxType.caption.copyWith(
                      color: v ?? color,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontVariations: [
                        FontVariation('wght', selected ? 600 : 500),
                      ],
                    ),
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
