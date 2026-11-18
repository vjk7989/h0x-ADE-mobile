import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'router.dart';

void main() {
  runApp(const ProviderScope(child: HyperOxApp()));
}

class HyperOxApp extends ConsumerWidget {
  const HyperOxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'HyperOx',
      routerConfig: ref.watch(routerProvider),
    );
  }
}
