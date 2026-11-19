import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/ssh_gateway.dart';
import 'data/ssh_gateway_stub.dart';
import 'theme/theme_controller.dart';

// INTERIM: StubSshGateway until lib/conn/ssh compiles; then RealSshGateway
// (lib/data/ssh_gateway_real.dart) replaces it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sshGatewayProvider.overrideWithValue(const StubSshGateway()),
      ],
      child: const HyperOxApp(),
    ),
  );
}
