import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock frame sizes in dp (design/tokens.md section 6).
enum Frame {
  phone(Size(360, 800)),
  tablet(Size(840, 900));

  const Frame(this.size);
  final Size size;
}

/// Pumps [child] in a [frame] at [textScale] with a HyperOx theme: [themeId],
/// or `paper` (light) / `darkmatter` (dark) by [brightness]. Device pixel
/// ratio is 1, so a golden is 1 px per dp ([dpr] 3 is for the accessibility checks). Goldens are generated on ubuntu
/// only (the app-goldens workflow).
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  Frame frame = Frame.phone,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  String? themeId,
  double dpr = 1.0,
  bool settle = true,
  Map<String, Object> stored = const {},
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = frame.size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final spec = themeById(
    themeId ??
        (brightness == Brightness.light
            ? kDefaultLightTheme
            : kDefaultDarkTheme),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), ...overrides],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeData(spec),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: child,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A live terminal animates for ever (cursor): frames by hand.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
