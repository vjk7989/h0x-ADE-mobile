import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double w(String family, {List<ui.FontVariation>? vars}) {
  final ts = TextStyle(fontFamily: family, fontSize: 12, height: 16 / 12, fontVariations: vars);
  final b = ui.ParagraphBuilder(ts.getParagraphStyle());
  b.pushStyle(ts.getTextStyle(textScaler: TextScaler.noScaling));
  b.addText('mmmmmmmmmm');
  final p = b.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  return p.maxIntrinsicWidth / 10;
}

void main() {
  test('diag char widths', () {
    final out = {
      'JetBrainsMono': w('JetBrainsMono'),
      'Geist': w('Geist'),
      'monospace': w('monospace'),
      'JBM wght400': w('JetBrainsMono', vars: [const ui.FontVariation('wght', 400)]),
    };
    expect(out, isEmpty, reason: 'WIDTHS $out');
  });
}
