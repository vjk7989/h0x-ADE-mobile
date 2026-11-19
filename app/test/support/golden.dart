import 'dart:ui' as ui;

import 'package:flutter/rendering.dart'
    show OffsetLayer, RenderObject, debugDisableShadows;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/router.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/widgets/code_rain.dart';
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

/// flutter_test draws every shadow as a hard-edged block, so a soft glass
/// shadow showed up as a slab. Goldens draw the shadows a phone draws.
void _realShadows() {
  final before = debugDisableShadows;
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = before);
}

/// A phone has a status bar (32 dp) and a gesture area (24 dp), tokens
/// section 6. Goldens pretend so, or inset handling is never shown.
void _setInsets(WidgetTester tester, double dpr) {
  final pad = FakeViewPadding(top: 32 * dpr, bottom: 24 * dpr);
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
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
  bool insets = true,
  int frames = 6,
  Map<String, Object> stored = const {},
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = frame.size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  _realShadows();
  if (insets) _setInsets(tester, dpr);
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
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        codeRainAnimateProvider.overrideWithValue(false),
        ...overrides,
      ],
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
    if (frames == 0) await tester.pump();
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// Pumps the real router at [location], so the navigation (bottom bar or
/// rail) is part of the picture. Same theme, insets and text scale as
/// [pumpGolden].
Future<void> pumpShellGolden(
  WidgetTester tester,
  String location, {
  Frame frame = Frame.phone,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  String? themeId,
  double dpr = 1.0,
  bool insets = true,
  Map<String, Object> stored = const {},
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = frame.size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  _realShadows();
  if (insets) _setInsets(tester, dpr);
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
  final container = ProviderContainer(
    overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        codeRainAnimateProvider.overrideWithValue(false),
        ...overrides,
      ],
  );
  addTearDown(container.dispose);
  final GoRouter router = container.read(routerProvider);
  router.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: themeData(spec),
        routerConfig: router,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Frames of an animation as one image, left to right (design/tokens.md
/// section 18 strips). Pumps to each of [times] (cumulative, from now), takes
/// a picture of the app, and lays the pictures out at [scale]. Compare the
/// result with `expectLater(image, matchesGoldenFile(...))`.
Future<ui.Image> strip(
  WidgetTester tester, {
  required List<int> times,
  double scale = 0.5,
  Future<void> Function(int frame)? before,
}) async {
  final frames = <ui.Image>[];
  var at = 0;
  var i = 0;
  for (final ms in times) {
    if (ms > at) await tester.pump(Duration(milliseconds: ms - at));
    at = ms;
    await before?.call(i++);
    RenderObject ro = tester.renderObject(find.byType(MaterialApp));
    while (!ro.isRepaintBoundary) {
      ro = ro.parent!;
    }
    final layer = ro.debugLayer! as OffsetLayer;
    final shot = await tester.runAsync(() => layer.toImage(ro.paintBounds));
    frames.add(shot!);
  }
  final w = frames.first.width * scale;
  final h = frames.first.height * scale;
  const gap = 4.0;
  final out = await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, frames.length * (w + gap), h),
      Paint()..color = const Color(0xFF808080),
    );
    for (var i = 0; i < frames.length; i++) {
      canvas.drawImageRect(
        frames[i],
        Rect.fromLTWH(0, 0, frames[i].width.toDouble(), frames[i].height.toDouble()),
        Rect.fromLTWH(i * (w + gap), 0, w, h),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    return rec.endRecording().toImage((frames.length * (w + gap)).ceil(), h.ceil());
  });
  return out!;
}
