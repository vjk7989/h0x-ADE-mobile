import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every banner leaves with the same fade and collapse: a banner (HxBanner or
/// one of the screens' banner wrappers) is only built inside an HxBannerSlot.
void main() {
  test('no banner is built outside an HxBannerSlot', () {
    final back = String.fromCharCode(92);
    final bad = <String>[];
    final use = RegExp(r'(?<![A-Za-z])(HxBanner|_Banner|_ApprovalBanner|_Note)\(');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(back, '/');
      if (!path.endsWith('.dart') || path.endsWith('lib/widgets/hx.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!use.hasMatch(line)) continue;
        // The wrapper classes' own constructors and their one HxBanner.
        if (RegExp(r'const (_Banner|_Note|_ApprovalBanner)\(\{').hasMatch(line)) continue;
        final from = i < 14 ? 0 : i - 14;
        final near = lines.sublist(from, i + 1).join('\n');
        final inWrapper = RegExp(r'class _(Banner|ApprovalBanner|Note)\b').hasMatch(near);
        if (!near.contains('HxBannerSlot(') && !inWrapper) bad.add('$path:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: 'wrap in HxBannerSlot: $bad');
  });
}
