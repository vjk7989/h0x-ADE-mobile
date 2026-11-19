import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `debugNeedsPaint` and friends are late fields that only asserts set: read
/// outside an assert they throw in profile and release builds.
void main() {
  test('no debug* render getters outside asserts in lib', () {
    final back = String.fromCharCode(92);
    final bad = <String>[];
    final pattern = RegExp(r'\.debug(NeedsPaint|NeedsLayout|Layer|Semantics|DoingPaint)\b');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(back, '/');
      if (!path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i]) && !lines[i].contains('assert(') && !lines[i].contains('kDebugMode')) {
          bad.add('$path:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'debug-only getters: $bad');
  });
}
