import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Loads the real fonts, so goldens show text instead of boxes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFont('Geist', 'assets/fonts/Geist.ttf');
  await _loadFont('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  await _loadMaterialIcons();
  await testMain();
}

/// The icon font lives in the Flutter SDK, not in the test bundle; without
/// it every icon in a golden is a box. Looked up next to the tester binary.
Future<void> _loadMaterialIcons() async {
  final roots = <String>[
    ?Platform.environment['FLUTTER_ROOT'],
    // .../bin/cache/artifacts/engine/<platform>/flutter_tester
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent
        .path,
  ];
  for (final root in roots) {
    final font = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (font.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(font.readAsBytes().then(ByteData.sublistView));
      await loader.load();
      return;
    }
  }
}
