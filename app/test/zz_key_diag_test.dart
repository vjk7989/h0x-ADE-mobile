import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/state/key_input.dart';
import 'package:hyperox/widgets/key_bar.dart';
import 'package:material_ui/material_ui.dart' hide Key;

import 'support/golden.dart';

void main() {
  testWidgets('diag key hold', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
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
    final out = {'haptics': calls.length, 'esc2': t.getCenter(find.text('Esc').at(1)).toString()};
    await g.cancel();
    expect(out, isEmpty, reason: 'KEYDIAG $out');
  });
}
