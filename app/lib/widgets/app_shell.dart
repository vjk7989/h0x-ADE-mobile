import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../state/inbox.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import 'hx.dart';

/// The five destinations, in the same order everywhere (tokens section 14).
enum NavDest {
  inbox('Inbox', '/inbox', Icons.inbox_outlined),
  machines('Machines', '/machines', Icons.computer_outlined),
  spaces('Spaces', '/spaces', Icons.dashboard_outlined),
  todo('To-do', '/todo', Icons.checklist),
  settings('Settings', '/settings', Icons.settings_outlined);

  const NavDest(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

/// Width from which the bottom bar becomes a rail (tokens section 6).
const kRailBreakpoint = 600.0;

/// A screen body with the navigation around it: a bottom bar on a phone, a
/// rail from 600 dp. [onNavigate] defaults to the router.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.selected, required this.body, this.onNavigate});

  final NavDest selected;
  final Widget body;
  final void Function(NavDest dest)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hx.colors;
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    void go(NavDest d) => onNavigate != null ? onNavigate!(d) : context.go(d.path);
    final inbox = ref.watch(inboxProvider).value;
    return ValueListenableBuilder<InboxState>(
      valueListenable: inbox,
      builder: (context, state, _) {
        final needs = state.needsYou;
        final items = [
          for (final d in NavDest.values)
            _NavItem(
              dest: d,
              selected: d == selected,
              badge: d == NavDest.inbox ? needs : 0,
              onTap: () => go(d),
              rail: wide,
            ),
        ];
        return Scaffold(
          backgroundColor: c.screen,
          body: SafeArea(
            bottom: false,
            child: wide
                ? Row(
                    children: [
                      Container(
                        width: 80,
                        decoration: BoxDecoration(
                          color: c.screen,
                          border: Border(right: BorderSide(color: c.hairline)),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            const HxMark(size: 32),
                            const SizedBox(height: 16),
                            ...items,
                          ],
                        ),
                      ),
                      Expanded(child: body),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: body),
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: c.screen,
                          border: Border(top: BorderSide(color: c.hairline)),
                        ),
                        child: Row(children: [for (final i in items) Expanded(child: i)]),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.badge,
    required this.onTap,
    required this.rail,
  });

  final NavDest dest;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final color = selected ? c.foreground : c.muted;
    // Labels stop growing at 1.3x so five still fit; the screen reader gets
    // the full label either way.
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final label = badge > 0 ? '${dest.label}, $badge needs you' : dest.label;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: rail ? 76 : 80,
          width: rail ? 80 : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected ? c.selected : null,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(dest.icon, size: 22, color: color),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: 8,
                      top: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: c.working,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          textScaler: TextScaler.noScaling,
                          style: HxType.mono.copyWith(fontSize: 10, color: c.screen),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dest.label,
                textScaler: scale,
                maxLines: 1,
                style: HxType.caption.copyWith(
                  fontSize: 11.5,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A screen title block: title, a mono sub-line, and trailing actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(title, style: HxType.title)),
                  if (subtitle != null)
                    Text(subtitle!, style: HxType.mono.copyWith(color: c.muted)),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A 48 x 48 icon button with a screen-reader label.
class HxIconButton extends StatelessWidget {
  const HxIconButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: 22),
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
      );
}
