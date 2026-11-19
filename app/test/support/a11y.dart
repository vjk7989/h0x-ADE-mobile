import 'package:flutter_test/flutter_test.dart';

/// The three guidelines every screen must pass (target size, labelled
/// targets, text contrast). A tappable without a label, or smaller than
/// 48x48 dp, fails here.
///
/// The contrast guideline reads rendered pixels, and thin small text
/// anti-aliased at 1x never reaches its true colour. The check therefore
/// renders at 3x (the same layout in dp) so it measures the theme's colours.
Future<void> expectAccessible(WidgetTester tester) async {
  final logical = tester.view.physicalSize / tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = logical * 3.0;
  await tester.pumpAndSettle();
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}
