import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'router.dart';
import 'screens/unlock_screen.dart';
import 'theme/theme_controller.dart';
import 'theme/themes.dart';
import 'widgets/intro.dart';
import 'widgets/theme_crossfade.dart';

class HyperOxApp extends ConsumerWidget {
  const HyperOxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'HyperOx',
      theme: themeData(themeById(choice.light)),
      darkTheme: themeData(themeById(choice.dark)),
      themeMode: choice.themeMode,
      // The theme switch is the cross-fade below, not Material's own tween.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeCrossFade(
        child: SplashThemeSync(
          child: IntroGate(child: AppLockScope(child: child!)),
        ),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
