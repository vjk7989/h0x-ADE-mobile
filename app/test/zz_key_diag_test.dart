import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/state/key_input.dart';
import 'package:hyperox/widgets/key_bar.dart';
import 'package:material_ui/material_ui.dart' hide Key;

import 'support/golden.dart';

void main() {
  testWidgets('diag key hold', (t) async {
    await pumpGolden(
      t,
      Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            KeyBar(modifiers: Modifiers(), onKeys: (_) {}),
            const SizedBox(height: 24),
            KeyBar(modifiers: Modifiers(), onKeys: (_) {}),
          ],
        ),
      ),
      brightness: Brightness.dark,
    );
    final g = await t.startGesture(t.getCenter(find.text('Esc').at(1)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final out = <String>[];
    for (final e in find.ancestor(of: find.text('Esc').at(1), matching: find.byType(AnimatedContainer)).evaluate()) {
      final w = e.widget as AnimatedContainer;
      out.add('${(w.decoration as BoxDecoration?)?.color} ${w.transform}');
    }
    for (final e in find.ancestor(of: find.text('Esc').at(0), matching: find.byType(AnimatedContainer)).evaluate()) {
      final w = e.widget as AnimatedContainer;
      out.add('first ${(w.decoration as BoxDecoration?)?.color}');
    }
    await g.cancel();
    expect(out, isEmpty, reason: 'KEYDIAG $out');
  });
}
