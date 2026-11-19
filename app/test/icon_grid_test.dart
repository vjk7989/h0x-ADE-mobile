import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/hx.dart';

/// The launcher icon is generated from HxMark's dot grid by tools/gen_icons.py.
/// These checks fail when the vector and the grid drift apart.
const _res = 'android/app/src/main/res';

final _dot = RegExp(
  r'M(-?[\d.]+) (-?[\d.]+)a([\d.]+) ([\d.]+) 0 1 0 ([\d.]+) 0a[\d.]+ [\d.]+ 0 1 0 -[\d.]+ 0',
);

void _checkVector(String file, String fill) {
  final xml = File('$_res/drawable/$file').readAsStringSync();
  expect(xml, contains('android:viewportWidth="108"'));
  expect(xml, contains('android:viewportHeight="108"'));
  expect(xml, contains('android:fillColor="$fill"'));
  // One <path>, every dot two arcs.
  expect('<path'.allMatches(xml).length, 1);
  final data = RegExp(r'pathData="([^"]*)"').firstMatch(xml)!.group(1)!;
  final dots = _dot.allMatches(data).toList();
  final want = HxMark.rows.fold<int>(0, (n, r) => n + '1'.allMatches(r).length);
  expect(dots.length, want, reason: 'one dot per 1 in the grid');
  // Nothing in the path but those dots.
  expect(data.replaceAll(_dot, ''), isEmpty);
  // Every dot, with its radius, is inside the 66 dp safe circle.
  for (final m in dots) {
    final r = double.parse(m.group(3)!);
    final cx = double.parse(m.group(1)!) + r;
    final cy = double.parse(m.group(2)!);
    expect(
      math.sqrt(math.pow(cx - 54, 2) + math.pow(cy - 54, 2)) + r,
      lessThanOrEqualTo(33.0),
      reason: 'dot at $cx,$cy leaves the safe zone',
    );
  }
  // The dots sit where the grid says: the same columns and rows, in order.
  final step = double.parse(dots.first.group(5)!) / 2 / 0.36;
  var i = 0;
  for (var r = 0; r < HxMark.rows.length; r++) {
    for (var c = 0; c < HxMark.rows[r].length; c++) {
      if (HxMark.rows[r][c] != '1') continue;
      final m = dots[i++];
      final rad = double.parse(m.group(3)!);
      final cx = double.parse(m.group(1)!) + rad;
      final cy = double.parse(m.group(2)!);
      expect(cx, closeTo(54 + (c - 10) * step, 0.06), reason: 'col $c row $r');
      expect(cy, closeTo(54 + (r - 12) * step, 0.06), reason: 'col $c row $r');
    }
  }
}

void main() {
  test('the grid is 21 x 25 and uses only 0 and 1', () {
    expect(HxMark.rows.length, 25);
    for (final r in HxMark.rows) {
      expect(r.length, 21);
      expect(RegExp(r'^[01]+$').hasMatch(r), isTrue);
    }
  });

  test('the foreground vector is the grid, in the accent', () {
    _checkVector('ic_launcher_foreground.xml', '#e78a53');
  });

  test('the monochrome vector is the same geometry in white', () {
    _checkVector('ic_launcher_monochrome.xml', '#ffffff');
    final a = File('$_res/drawable/ic_launcher_foreground.xml').readAsStringSync();
    final b = File('$_res/drawable/ic_launcher_monochrome.xml').readAsStringSync();
    String d(String s) => RegExp(r'pathData="([^"]*)"').firstMatch(s)!.group(1)!;
    expect(d(b), d(a));
  });

  test('the adaptive icons and the background are in place', () {
    for (final f in ['ic_launcher.xml', 'ic_launcher_round.xml']) {
      final xml = File('$_res/mipmap-anydpi-v26/$f').readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('@color/ic_launcher_background'));
      expect(xml, contains('@drawable/ic_launcher_foreground'));
      expect(xml, contains('<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>'));
    }
    expect(
      File('$_res/values/ic_launcher_background.xml').readAsStringSync(),
      contains('#121113'),
    );
  });

  test('legacy and round PNGs exist at every density; the manifest uses them', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final f in ['ic_launcher.png', 'ic_launcher_round.png']) {
        expect(File('$_res/mipmap-$d/$f').existsSync(), isTrue, reason: '$d/$f');
      }
    }
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
  });
}
