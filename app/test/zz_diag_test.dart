import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Key;
import 'package:xterm/xterm.dart';

Future<String> run(
  WidgetTester tester,
  Widget Function(Terminal t) build,
) async {
  final t = Terminal(maxLines: 5000);
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: build(t))));
  t.write('hello world\r\nsecond line');
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return '${t.viewWidth}x${t.viewHeight}';
}

void main() {
  testWidgets('diag xterm sizes', (tester) async {
    final out = <String, String>{};
    out['plain'] = await run(tester, (t) => TerminalView(t));
    out['style'] = await run(
      tester,
      (t) => TerminalView(
        t,
        textStyle: const TerminalStyle(fontSize: 12, fontFamily: 'JetBrainsMono'),
      ),
    );
    out['noscale'] = await run(
      tester,
      (t) => TerminalView(t, textScaler: TextScaler.noScaling),
    );
    out['padding'] = await run(
      tester,
      (t) => TerminalView(t, padding: const EdgeInsets.all(10)),
    );
    out['readOnly'] = await run(tester, (t) => TerminalView(t, readOnly: true));
    out['theme'] = await run(
      tester,
      (t) => TerminalView(t, theme: TerminalThemes.defaultTheme),
    );
    out['gesture'] = await run(
      tester,
      (t) => GestureDetector(
        onScaleUpdate: (_) {},
        child: Opacity(opacity: 1, child: TerminalView(t)),
      ),
    );
    expect(out, isEmpty, reason: 'SIZES $out');
  });
}
