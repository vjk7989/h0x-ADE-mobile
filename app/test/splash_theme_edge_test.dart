import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:material_ui/material_ui.dart';

const _channel = MethodChannel('hyperox/splash');

/// Records every call on the splash channel; [fail] makes the host throw.
List<MethodCall> _mock(WidgetTester t, {Object? fail}) {
  final calls = <MethodCall>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (c) async {
    calls.add(c);
    if (fail != null) throw fail;
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

List<Object?> _lights(List<MethodCall> calls) =>
    [for (final c in calls) (c.arguments as Map)['light']];

Widget _app(ThemeMode m, {ThemeData? light}) => MaterialApp(
  theme: light ?? ThemeData.light(),
  darkTheme: ThemeData.dark(),
  themeMode: m,
  themeAnimationDuration: Duration.zero,
  home: const SplashThemeSync(child: SizedBox()),
);

void main() {
  testWidgets('the call is setTheme with only a light flag', (t) async {
    final calls = _mock(t);
    await t.pumpWidget(_app(ThemeMode.dark));
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setTheme');
    expect(calls.single.arguments, {'light': false});
  });

  testWidgets('system mode follows the system brightness, both ways', (t) async {
    final calls = _mock(t);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpWidget(_app(ThemeMode.system));
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.pump();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pump();
    expect(_lights(calls), [true, false, true]);
  });

  testWidgets('an app mode that differs from the system is what is sent', (t) async {
    final calls = _mock(t);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.pumpWidget(_app(ThemeMode.light));
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pump();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.pump();
    expect(_lights(calls), [true], reason: 'app Light: the system flips do not matter');
  });

  testWidgets('another theme of the same brightness sends nothing new', (t) async {
    final calls = _mock(t);
    await t.pumpWidget(_app(ThemeMode.light));
    await t.pumpWidget(
      _app(
        ThemeMode.light,
        light: ThemeData.light().copyWith(scaffoldBackgroundColor: const Color(0xFFEEEEEE)),
      ),
    );
    expect(_lights(calls), [true]);
  });

  testWidgets('quick flips within frames are all sent, in order', (t) async {
    final calls = _mock(t);
    await t.pumpWidget(_app(ThemeMode.light));
    await t.pumpWidget(_app(ThemeMode.dark));
    await t.pumpWidget(_app(ThemeMode.light));
    await t.pumpWidget(_app(ThemeMode.dark));
    expect(_lights(calls), [true, false, true, false]);
  });

  testWidgets('a host that throws does not break the app, and later changes still go', (t) async {
    final calls = _mock(t, fail: PlatformException(code: 'nope'));
    await t.pumpWidget(_app(ThemeMode.light));
    await t.pump();
    expect(t.takeException(), isNull);
    await t.pumpWidget(_app(ThemeMode.dark));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(_lights(calls), [true, false]);
  });

  testWidgets('no host at all (desktop, below API 31) is fine', (t) async {
    // No mock handler: MissingPluginException is swallowed.
    await t.pumpWidget(_app(ThemeMode.dark));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(SplashThemeSync), findsOneWidget);
  });

  testWidgets('a rebuild with the same mode sends nothing', (t) async {
    final calls = _mock(t);
    for (var i = 0; i < 5; i++) {
      await t.pumpWidget(_app(ThemeMode.dark));
    }
    expect(_lights(calls), [false]);
  });
}
