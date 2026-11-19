import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The guidelines every screen must pass: tap targets of at least 48 dp,
/// every tappable labelled, and text contrast.
///
/// Flutter's own `textContrastGuideline` is not used for contrast: it
/// compares the two most common pixel colours of a text's box, and for thin
/// small text (14 sp, weight 400) the second most common colour is an
/// anti-aliasing shade, so it reports 1.3 to 4 for text that is 5.25 by the
/// theme. [expectTextContrast] computes the real ratio of the text colour
/// against the fill behind it instead.
Future<void> expectAccessible(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
  final failures = textContrastFailures(tester);
  expect(failures, isEmpty, reason: failures.join('\n'));
}

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The fill behind [element]: translucent fills are blended over what lies
/// beneath them, up to the first opaque one. Null when [element] sits under
/// an `Opacity` below 1 (a disabled control, exempt from WCAG contrast).
Color? backgroundBehind(Element element) {
  final layers = <Color>[];
  var exempt = false;
  var opaque = false;
  element.visitAncestorElements((e) {
    final w = e.widget;
    if (w is Opacity && w.opacity < 1) {
      exempt = true;
      return false;
    }
    // A disabled control (semantics enabled: false) is WCAG-exempt. Keep
    // walking past the first opaque fill to find it.
    if (w is Semantics && w.properties.enabled == false) {
      exempt = true;
      return false;
    }
    if (opaque) return true;
    Color? fill;
    if (w is DecoratedBox) {
      final d = w.decoration;
      if (d is BoxDecoration) fill = d.color;
    } else if (w is ColoredBox) {
      fill = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      fill = w.color ?? Theme.of(e).colorScheme.surface;
    }
    if (fill != null && fill.a > 0) {
      layers.add(fill);
      if (fill.a >= 1) opaque = true;
    }
    return true;
  });
  if (exempt) return null;
  final start = layers.indexWhere((c) => c.a >= 1);
  var bg = start >= 0 ? layers[start] : const Color(0xFFFFFFFF);
  final over = start >= 0 ? layers.sublist(0, start) : layers;
  for (final c in over.reversed) {
    bg = Color.alphaBlend(c, bg);
  }
  return bg;
}

/// Every visible text whose colour has less contrast than WCAG AA requires
/// (4.5, or 3 for large text) against the fill behind it.
List<String> textContrastFailures(WidgetTester tester) {
  final out = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final rt = element.widget as RichText;
    final bg = backgroundBehind(element);
    if (bg == null) continue;
    final base = DefaultTextStyle.of(element).style;
    void check(InlineSpan span, TextStyle inherited) {
      final style = span.style == null
          ? inherited
          : inherited.merge(span.style);
      if (span is TextSpan) {
        final text = span.text ?? '';
        final color = style.color;
        // The dim brackets of a CLI tag are decorative; the word between
        // them carries the meaning (design/tokens.md rule 1).
        final decorative = text == '[' || text == ']';
        if (text.trim().isNotEmpty && color != null && !decorative) {
          final fg = Color.alphaBlend(color, bg);
          final size = style.fontSize ?? 14;
          final bold = (style.fontWeight?.value ?? 400) >= 700;
          // Icons (an Icon is a one-glyph RichText) need 3:1, like large text.
          final isIcon = element.findAncestorWidgetOfExactType<Icon>() != null;
          final need = isIcon || size >= 24 || (size >= 18.66 && bold)
              ? 3.0
              : 4.5;
          final ratio = contrastRatio(fg, bg);
          if (ratio < need) {
            out.add(
              '"$text" ${size}sp: ${ratio.toStringAsFixed(2)} < $need',
            );
          }
        }
        for (final c in span.children ?? const <InlineSpan>[]) {
          check(c, style);
        }
      }
    }

    check(rt.text, base);
  }
  return out;
}
