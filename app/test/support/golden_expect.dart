import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
