import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/add_machine_screen.dart';
import 'screens/agent_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/machines_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/theme_picker_screen.dart';
import 'screens/spaces_screen.dart';
import 'screens/todo_screen.dart';
import 'session_state.dart';
import 'widgets/nav_shell.dart';

/// Where a user goes, given who they are. Returns null to stay.
///
/// - not signed in and no SSH machine: the sign-in screen (the only places
///   open to them are sign-in, Add machine (the "continue without an
///   account" path) and the theme picker);
/// - an account or at least one SSH machine: the Inbox.
String? redirectFor({
  required String location,
  required bool signedIn,
  required int sshMachines,
}) {
  final known = signedIn || sshMachines > 0;
  if (location == '/') return known ? '/inbox' : '/sign-in';
  if (known) return location == '/sign-in' ? '/inbox' : null;
  const open = {'/sign-in', '/machines/add', '/settings/theme'};
  return open.contains(location) ? null : '/sign-in';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<bool>(signedInProvider, (_, _) => refresh.value++);
  ref.listen<int>(sshMachineCountProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      location: state.uri.path,
      signedIn: ref.read(signedInProvider),
      sshMachines: ref.read(sshMachineCountProvider),
    ),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      // Full-screen routes, outside the navigation.
      GoRoute(
        path: '/machines/add',
        builder: (_, _) => const AddMachineScreen(),
      ),
      GoRoute(
        path: '/settings/theme',
        builder: (_, _) => const ThemePickerScreen(),
      ),
      GoRoute(
        path: '/agent/:machine/:terminal',
        builder: (_, state) => AgentScreen(
          machineId: state.pathParameters['machine']!,
          terminal: state.pathParameters['terminal']!,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            NavShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/inbox', builder: (_, _) => const InboxScreen()),
          GoRoute(
            path: '/machines',
            builder: (_, _) => const MachinesScreen(),
          ),
          GoRoute(path: '/spaces', builder: (_, _) => const SpacesScreen()),
          GoRoute(path: '/todo', builder: (_, _) => const TodoScreen()),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
