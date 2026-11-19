import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the splash theme is sent at start-up and on a brightness change', (t) async {
    final calls = <Object?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('hyperox/splash'),
      (c) async {
        if (c.method == 'setTheme') calls.add((c.arguments as Map)['light']);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('hyperox/splash'),
        null,
      ),
    );
    Widget app(ThemeMode m) => MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: m,
      home: const SplashThemeSync(child: SizedBox()),
    );
    await t.pumpWidget(app(ThemeMode.light));
    await t.pumpWidget(app(ThemeMode.light));
    expect(calls, [true], reason: 'once, at start-up');
    await t.pumpWidget(app(ThemeMode.dark));
    await t.pumpAndSettle();
    expect(calls, [true, false]);
  });
}
