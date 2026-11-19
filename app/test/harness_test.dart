import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/a11y.dart';
import 'support/golden.dart';

class _Sample extends StatelessWidget {
  const _Sample();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.check),
          label: const Text('Continue without an account (SSH only)'),
        ),
      ),
    );
  }
}

class _BadButton extends StatelessWidget {
  const _BadButton();

  @override
  Widget build(BuildContext context) {
    // 40x40 dp, tappable, no label: breaks two guidelines on purpose.
    return Scaffold(
      body: Center(
        child: GestureDetector(
          onTap: () {},
          child: const SizedBox(
            width: 40,
            height: 40,
            child: ColoredBox(color: Color(0xFF888888)),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('sample widget golden, phone light', (tester) async {
    await pumpGolden(tester, const _Sample());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sample_phone_light.png'),
    );
  });

  testWidgets('sample widget golden, phone dark, text 2.0', (tester) async {
    await pumpGolden(
      tester,
      const _Sample(),
      brightness: Brightness.dark,
      textScale: 2.0,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sample_phone_dark_200.png'),
    );
  });

  testWidgets('a labelled 48 dp button passes the helper', (tester) async {
    await pumpGolden(tester, const _Sample(), dpr: 3.0);
    await expectAccessible(tester);
  });

  testWidgets('an unlabeled 40 dp button fails the helper', (tester) async {
    await pumpGolden(tester, const _BadButton());
    final handle = tester.ensureSemantics();
    await expectLater(tester, doesNotMeetGuideline(androidTapTargetGuideline));
    await expectLater(tester, doesNotMeetGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
