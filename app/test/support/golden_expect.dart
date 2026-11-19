import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y.dart';

/// Compares [finder] with `test/goldens/<name>.png`. A golden that has not
/// been generated yet is skipped (they are made on ubuntu by the app-goldens
/// workflow, then committed); `flutter test --update-goldens` writes them.
Future<void> expectGolden(Finder finder, String name) async {
  final file = File('test/goldens/$name.png');
  if (!autoUpdateGoldenFiles && !file.existsSync()) {
    debugPrint('golden $name.png not generated yet: run app-goldens');
    return;
  }
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
}

/// The accessibility guidelines at 3x pixels: text contrast is measured from
/// the rendered pixels, and at 1x the anti-aliasing of 11 to 12 sp text gives
/// readings far below the real contrast.
Future<void> expectAccessibleCrisp(WidgetTester tester) async {
  final size = tester.view.physicalSize;
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = size * 3;
  await tester.pumpAndSettle();
  await expectAccessible(tester);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

/// A widget test with semantics on, switched off again at its end.
void testWithSemantics(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}
