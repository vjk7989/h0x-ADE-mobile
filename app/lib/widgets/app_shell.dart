import 'package:material_ui/material_ui.dart';

import '../theme/themes.dart';
import '../theme/type.dart';

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

/// A screen's body on the app background. The navigation (bottom bar or
/// rail) comes from the router's shell route, not from here.
class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.hx.colors.screen,
        body: SafeArea(bottom: false, child: body),
      );
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
