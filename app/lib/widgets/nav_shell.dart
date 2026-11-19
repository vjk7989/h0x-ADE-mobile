import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/themes.dart';
import '../theme/type.dart';

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

/// The five-item navigation: a bottom bar (80 dp) below 600 dp, a rail
/// (80 dp wide) from 600 dp up (design/tokens.md section 6).
class NavShell extends StatelessWidget {
  const NavShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index {
    final i = _dests.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    Widget item(int i, {required bool rail}) => _NavItem(
      dest: _dests[i],
      selected: i == _index,
      rail: rail,
      onTap: () => context.go(_dests[i].path),
    );
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
                    for (var i = 0; i < _dests.length; i++) item(i, rail: true),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.screen,
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.chrome,
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 80,
            child: Row(
              children: [
                for (var i = 0; i < _dests.length; i++)
                  Expanded(child: item(i, rail: false)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.rail,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final bool rail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final color = selected ? c.accent : c.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '${dest.label}, selected' : dest.label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64, minWidth: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? c.selected : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(dest.icon, size: 24, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                dest.label,
                maxLines: 1,
                style: HxType.caption.copyWith(color: color, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
