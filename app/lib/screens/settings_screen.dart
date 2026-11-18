import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/app_lock.dart';

/// Stub until the Settings screen is built: Theme and the app lock only.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBiometrics = ref.watch(biometricsAvailableProvider).value ?? false;
    final lock = ref.watch(appLockProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text('Theme'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/theme'),
            ),
            // Hidden when the device has no fingerprint or face enrolled.
            if (hasBiometrics)
              SwitchListTile(
                title: const Text('Biometric lock'),
                subtitle: const Text('Ask after 5 minutes in the background'),
                value: lock.enabled,
                onChanged: (on) =>
                    ref.read(appLockProvider.notifier).setEnabled(on),
              ),
          ],
        ),
      ),
    );
  }
}
