import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/terminal_theme.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:material_ui/material_ui.dart';

/// design/tokens.md (a byte copy in test/fixtures) is the contract for the
/// five themes it lists.
const _tokenThemes = ['paper', 'darkmatter', 'sodium', 'voltage', 'phosphor'];

final _hex = RegExp(r'#[0-9a-f]{6,8}');

/// Rows of the table whose header starts with [header]: first cell -> cells.
Map<String, List<String>> _table(String md, String header) {
  final lines = md.split('\n');
  final start = lines.indexWhere((l) => l.startsWith(header));
  expect(start, greaterThanOrEqualTo(0), reason: 'table "$header" not found');
  final rows = <String, List<String>>{};
  for (var i = start + 2; i < lines.length && lines[i].startsWith('|'); i++) {
    final cells = lines[i]
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    rows[cells.first] = cells.sublist(1);
  }
  return rows;
}

String _firstHex(String cell) => _hex.firstMatch(cell)!.group(0)!;

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final md = File('test/fixtures/design_tokens.md').readAsStringSync();

  test('every desktop theme ships, ids are unique', () {
    final ids = kThemeSpecs.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(
      ids,
      containsAll([
        'graphite',
        'ink',
        'moss',
        'paper',
        'amber-minimal',
        'atom-one-dark',
        'candyland',
        'claymorphism',
        'darkmatter',
        'neo-brutalism',
        'soft-pop',
        'win98',
        ..._tokenThemes,
      ]),
    );
    expect(kThemeSpecs.length, 15);
    expect(isThemeId(kDefaultLightTheme), isTrue);
    expect(isThemeId(kDefaultDarkTheme), isTrue);
    expect(themeById(kDefaultLightTheme).isLight, isTrue);
    expect(themeById(kDefaultDarkTheme).isLight, isFalse);
  });

  test('an unknown theme id is an error', () {
    expect(() => themeById('nope'), throwsArgumentError);
  });

  test('each theme has 16 ANSI colours and parses to opaque colours', () {
    for (final t in kThemeSpecs) {
      expect(t.terminal.ansi.length, 16, reason: t.id);
      final term = TerminalColors(t.terminal);
      expect(term.ansi.length, 16, reason: t.id);
      for (final c in [term.background, term.foreground, ...term.ansi]) {
        expect(c.a, 1.0, reason: t.id);
      }
    }
  });

  test('parseHex reads #rrggbb and #rrggbbaa', () {
    expect(parseHex('#112233'), const Color(0xFF112233));
    expect(parseHex('#11223380'), const Color(0x80112233));
  });

  test('colour roles equal design/tokens.md', () {
    final table = _table(md, '| Role |');
    final header = md
        .split('\n')
        .firstWhere((l) => l.startsWith('| Role |'))
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    var checked = 0;
    for (final entry in table.entries) {
      final role = RegExp(r'`(\w+)`').firstMatch(entry.key)!.group(1)!;
      for (final id in _tokenThemes) {
        final col = header.indexOf(id) - 1;
        final spec = themeById(id);
        expect(
          spec.roles[role],
          _firstHex(entry.value[col]),
          reason: '$id $role',
        );
        checked++;
      }
    }
    expect(checked, 21 * 5);
  });

  test('terminal palettes equal design/tokens.md', () {
    final table = _table(md, '| Slot |');
    final header = md
        .split('\n')
        .firstWhere((l) => l.startsWith('| Slot |'))
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    var checked = 0;
    for (final entry in table.entries) {
      for (final id in _tokenThemes) {
        final want = _firstHex(entry.value[header.indexOf(id) - 1]);
        final t = themeById(id).terminal;
        final slot = entry.key;
        final got = switch (slot) {
          'background' => t.background,
          'foreground' => t.foreground,
          'cursor' => t.cursor,
          'selection' => t.selection,
          _ => t.ansi[int.parse(slot.split(' ').first)],
        };
        expect(got, want, reason: '$id terminal $slot');
        checked++;
      }
    }
    expect(checked, 20 * 5);
  });

  test('body text contrast is at least 4.5 on screen and card, all themes', () {
    for (final t in kThemeSpecs) {
      final c = HxColors(t.roles);
      for (final bg in [c.screen, c.card]) {
        expect(
          _ratio(c.foreground, bg),
          greaterThanOrEqualTo(4.5),
          reason: '${t.id} foreground',
        );
        expect(
          _ratio(c.muted, bg),
          greaterThanOrEqualTo(4.5),
          reason: '${t.id} muted',
        );
      }
    }
  });

  test('the tokens themes also meet the button and field-edge ratios', () {
    for (final id in _tokenThemes) {
      final c = HxColors(themeById(id).roles);
      expect(_ratio(c.accentForeground, c.accent), greaterThanOrEqualTo(4.5));
      expect(_ratio(c.solidForeground, c.solid), greaterThanOrEqualTo(4.5));
      expect(_ratio(c.outline, c.card), greaterThanOrEqualTo(3.0));
      expect(_ratio(c.outline, c.screen), greaterThanOrEqualTo(3.0));
    }
  });

  test('themeData follows the theme: brightness, scheme and extension', () {
    for (final t in kThemeSpecs) {
      final data = themeData(t);
      expect(
        data.colorScheme.brightness,
        t.isLight ? Brightness.light : Brightness.dark,
        reason: t.id,
      );
      final hx = data.extension<HxTheme>()!;
      expect(hx.spec.id, t.id);
      expect(data.colorScheme.surface, hx.colors.screen);
      expect(data.colorScheme.primary, hx.colors.accent);
    }
  });

  test('the terminal view uses the theme palette unchanged', () {
    final t = HxTheme(themeById('darkmatter'));
    final x = terminalThemeFor(t.terminal);
    expect(x.background, parseHex('#121113'));
    expect(x.cursor, parseHex('#e78a53'));
    expect(x.red, parseHex('#ed5350'));
    expect(x.brightWhite, parseHex('#c1c1c1'));
  });
}
