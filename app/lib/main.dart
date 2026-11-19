import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'widgets/intro.dart';
import 'data/ssh_gateway.dart';
import 'data/ssh_gateway_real.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  HxIntro.clock.start();
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sshGatewayProvider.overrideWithValue(RealSshGateway()),
      ],
      child: const HyperOxApp(),
    ),
  );
}
