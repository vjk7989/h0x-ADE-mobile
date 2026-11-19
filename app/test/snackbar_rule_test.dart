import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every snackbar goes through showHxSnack: no SnackBar( outside hx.dart', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll('\', '/');
      if (!path.endsWith('.dart') || path.endsWith('lib/widgets/hx.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('SnackBar(') || lines[i].contains('.showSnackBar')) {
          bad.add('$path:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'use showHxSnack: $bad');
  });
}
