import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/hx.dart';
import 'package:material_ui/material_ui.dart' hide Key;

import 'support/golden.dart';

void main() {
  testWidgets('diag press grid', (t) async {
    await pumpGolden(
      t,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final l in ['a', 'b', 'c', 'd'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    children: [
                      Expanded(child: HxButton(key: ValueKey('$l-rest'), label: l, onPressed: () {})),
                      const SizedBox(width: 12),
                      Expanded(child: HxButton(key: ValueKey('$l-down'), label: l, onPressed: () {})),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    double scale(String k) => t
        .widget<AnimatedScale>(
          find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(AnimatedScale)),
        )
        .scale;
    final out = <String, double>{};
    final g1 = await t.startGesture(t.getCenter(find.byKey(const ValueKey('a-down'))), pointer: 1);
    await t.pump(const Duration(milliseconds: 300));
    out['one: a-down'] = scale('a-down');
    final g2 = await t.startGesture(t.getCenter(find.byKey(const ValueKey('b-down'))), pointer: 2);
    await t.pump(const Duration(milliseconds: 300));
    out['two: a-down'] = scale('a-down');
    out['two: b-down'] = scale('b-down');
    final g3 = await t.startGesture(t.getCenter(find.byKey(const ValueKey('c-down'))), pointer: 3);
    await t.pump(const Duration(milliseconds: 300));
    out['three: c-down'] = scale('c-down');
    await g1.cancel();
    await g2.cancel();
    await g3.cancel();
    expect(out, isEmpty, reason: 'SCALES $out');
  });
}
