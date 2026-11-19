import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/hx_icon_compat.dart' as compat;
import 'package:hyperox/widgets/hx_icons.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

void main() {
  group('parseSvgPath', () {
    test('absolute and relative lines give the same box', () {
      final a = parseSvgPath('M2 3L10 3L10 9Z').getBounds();
      final b = parseSvgPath('m2 3 l8 0 l0 6 z').getBounds();
      expect(a, const Rect.fromLTRB(2, 3, 10, 9));
      expect(b, a);
    });

    test('H, V and implicit lineto after M', () {
      expect(
        parseSvgPath('M1 1H5V4').getBounds(),
        const Rect.fromLTRB(1, 1, 5, 4),
      );
      expect(
        parseSvgPath('M1 1 5 1 5 4').getBounds(),
        const Rect.fromLTRB(1, 1, 5, 4),
      );
    });

    test('arcs: a full circle from two arcs, with glued flags', () {
      final r = parseSvgPath('M3 11a8 8 0 1 0 16 0a8 8 0 1 0 -16 0').getBounds();
      expect(r.left, closeTo(3, 0.01));
      expect(r.right, closeTo(19, 0.01));
      expect(r.height, closeTo(16, 0.01));
      // flags without separators: "a2 2 0 011 1"
      final glued = parseSvgPath('M0 0a2 2 0 011 1').getBounds();
      expect(glued.right, closeTo(1, 0.5));
    });

    test('curves: C, S, Q and T end where they say', () {
      final c = parseSvgPath('M0 0C0 4 4 4 4 0S8 -4 8 0');
      expect(c.getBounds().right, closeTo(8, 0.01));
      final q = parseSvgPath('M0 0Q2 4 4 0T8 0');
      expect(q.getBounds().right, closeTo(8, 0.01));
    });

    test('numbers glued by signs and dots parse', () {
      expect(
        parseSvgPath('M1.5.5l-1-.5').getBounds(),
        const Rect.fromLTRB(0.5, 0, 1.5, 0.5),
      );
    });

    test('bad data is an error, not a hang', () {
      expect(() => parseSvgPath('M1'), throwsFormatException);
      expect(() => parseSvgPath('X1 2'), throwsFormatException);
      expect(() => parseSvgPath('1 2'), throwsFormatException);
    });
  });

  group('the Lucide set', () {
    test('every path parses', () {
      expect(kLucide.length, greaterThan(40));
      for (final e in kLucide.entries) {
        for (final (d, _) in e.value) {
          expect(() => parseSvgPath(d), returnsNormally, reason: e.key);
        }
      }
      for (final e in kLucideDuo.entries) {
        for (final d in e.value) {
          expect(() => parseSvgPath(d), returnsNormally, reason: 'duo ${e.key}');
        }
      }
    });

    test('every duotone icon also has a line icon', () {
      expect(kLucide.keys, containsAll(kLucideDuo.keys));
    });

    test('every Material icon the app uses has a Lucide twin in the set', () {
      for (final name in [
        'inbox',
        'machines',
        'spaces',
        'todo',
        'settings',
        'alert',
        'info',
        'wifi-off',
        'triangle',
        'check',
        'plus',
        'pin',
      ]) {
        expect(kLucide.containsKey(name), isTrue, reason: name);
      }
    });
  });

  group('HxIcon', () {
    testWidgets('paints a known name at the size asked, and nothing for an unknown one', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              HxIcon('inbox', size: 24, color: Color(0xFF000000)),
              HxIcon('square-terminal', size: 40, duo: true, color: Color(0xFF123456)),
              HxIcon('no-such-icon', size: 16),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(HxIcon).at(1)), const Size(40, 40));
    });
  });

  group('the Material icon bridge', () {
    test('known Material icons map to Lucide names', () {
      expect(compat.lucideNameFor(Icons.inbox_outlined), 'inbox');
      expect(compat.lucideNameFor(Icons.checklist), 'todo');
      expect(compat.lucideNameFor(Icons.cloud_off_outlined), 'wifi-off');
    });

    test('every mapped name exists in the set', () {
      for (final icon in [
        Icons.arrow_back,
        Icons.copy_outlined,
        Icons.ios_share,
        Icons.stop_circle_outlined,
        Icons.notifications_none,
        Icons.check,
        Icons.check_circle_outline,
        Icons.content_paste,
        Icons.send,
        Icons.more_vert,
        Icons.search,
        Icons.close,
        Icons.add,
        Icons.push_pin,
        Icons.terminal,
        Icons.chevron_right,
        Icons.desktop_windows_outlined,
        Icons.dns_outlined,
        Icons.edit_outlined,
        Icons.delete_outline,
        Icons.gpp_maybe_outlined,
        Icons.keyboard_arrow_down,
        Icons.edit_note,
        Icons.fingerprint,
      ]) {
        final n = compat.lucideNameFor(icon);
        expect(n, isNotNull, reason: '$icon');
        expect(kLucide.containsKey(n), isTrue, reason: '$n');
      }
    });

    testWidgets('an icon with no twin falls back to the Material glyph', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: compat.Icon(Icons.accessibility_new),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
