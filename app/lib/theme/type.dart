import 'package:material_ui/material_ui.dart';

/// The type scale of design/tokens.md section 5. Sizes are sp: Flutter
/// applies the text scale, nothing here clamps it. Geist and JetBrains Mono
/// are variable fonts, so the weight is set as a font variation.
class HxType {
  HxType._();

  static FontWeight _w(int w) => FontWeight.values[(w ~/ 100) - 1];

  static TextStyle _sans(
    double size,
    double line,
    int weight, {
    double tracking = 0,
  }) => TextStyle(
    fontFamily: 'Geist',
    fontSize: size,
    height: line / size,
    fontWeight: _w(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    letterSpacing: tracking * size,
  );

  static TextStyle _mono(
    double size,
    double line,
    int weight, {
    double tracking = 0,
  }) => TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    height: line / size,
    fontWeight: _w(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    letterSpacing: tracking * size,
    fontFeatures: const [FontFeature.disable('calt')],
  );

  static final display = _sans(30, 36, 600, tracking: -0.02);
  static final titleLg = _sans(24, 30, 600, tracking: -0.01);
  static final title = _sans(22, 28, 600);
  static final titleSm = _sans(18, 24, 600);
  static final heading = _sans(16, 22, 600);
  static final bodyLg = _sans(15, 22, 500);
  static final body = _sans(14, 20, 400);
  static final bodySm = _sans(13, 18, 400);
  static final caption = _sans(12.5, 18, 400);
  static final mono = _mono(12, 18, 400);
  static final monoKey = _mono(11.5, 20, 400);
  static final code = _mono(28, 34, 600, tracking: 0.12);
  static final labelXs = _mono(11.5, 16, 500, tracking: 0.06);
}
