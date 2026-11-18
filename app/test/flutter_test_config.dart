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
  await testMain();
}
