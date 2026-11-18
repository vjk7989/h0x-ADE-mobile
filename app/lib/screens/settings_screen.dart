import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Stub until the Settings screen is built; only the Theme entry exists.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListTile(
        title: const Text('Theme'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/theme'),
      ),
    ),
  );
}
