import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../auth/app_lock.dart';
import '../auth/auth_service.dart';
import '../session_state.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/hx.dart';

/// Covers the app while it is locked, and re-locks it after [kLockAfter]
/// in the background.
class AppLockScope extends ConsumerStatefulWidget {
  const AppLockScope({super.key, required this.child, this.clock = DateTime.now});

  final Widget child;
  final DateTime Function() clock;

  @override
  ConsumerState<AppLockScope> createState() => _AppLockScopeState();
}

class _AppLockScopeState extends ConsumerState<AppLockScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused) lock.onBackground(widget.clock());
    if (state == AppLifecycleState.resumed) lock.onForeground(widget.clock());
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider).locked;
    return Stack(
      children: [
        widget.child,
        if (locked) const Positioned.fill(child: UnlockScreen()),
      ],
    );
  }
}

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  @override
  void initState() {
    super.initState();
    // Ask as soon as the lock shows; the buttons below repeat the prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final signedIn = ref.watch(signedInProvider);
    final lock = ref.read(appLockProvider.notifier);
    return Scaffold(
      backgroundColor: c.screen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: HxMark(size: 72)),
                  const SizedBox(height: 12),
                  Text('HyperOx', style: HxType.display, textAlign: TextAlign.center),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: HxType.body.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: 32),
                  HxCard(
                    child: Column(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Unlock with fingerprint',
                          excludeSemantics: true,
                          onTap: lock.unlock,
                          child: InkResponse(
                            onTap: lock.unlock,
                            radius: 48,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: c.selected,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.fingerprint, size: 40, color: c.accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Touch the sensor to unlock', style: HxType.body),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: HxButton(
                                label: 'Use PIN',
                                onPressed: lock.unlock,
                              ),
                            ),
                            if (signedIn) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: HxButton(
                                  label: 'Sign out',
                                  onPressed: () async {
                                    await ref
                                        .read(authControllerProvider.notifier)
                                        .signOut();
                                    await lock.setEnabled(false);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Unlock is asked after 5 minutes away. Change it in Settings.',
                    textAlign: TextAlign.center,
                    style: HxType.caption.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
