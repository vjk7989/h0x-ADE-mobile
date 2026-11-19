import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/screens/theme_picker_screen.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/golden.dart';

Future<ProviderContainer> _container([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ThemeController', () {
    test('defaults: system, paper, darkmatter', () async {
      final c = await _container();
      final s = c.read(themeControllerProvider);
      expect(s.mode, HxThemeMode.system);
      expect(s.light, 'paper');
      expect(s.dark, 'darkmatter');
      expect(s.active(Brightness.light).id, 'paper');
      expect(s.active(Brightness.dark).id, 'darkmatter');
    });

    test('choosing a dark theme in dark mode fills the dark slot', () async {
      final c = await _container({'theme.mode': 'dark'});
      await c
          .read(themeControllerProvider.notifier)
          .select('graphite', platform: Brightness.light);
      final s = c.read(themeControllerProvider);
      expect(s.dark, 'graphite');
      expect(s.light, 'paper');
      expect(s.mode, HxThemeMode.dark);
    });

    test('choosing a light theme while a dark one shows switches mode', () async {
      final c = await _container();
      await c
          .read(themeControllerProvider.notifier)
          .select('soft-pop', platform: Brightness.dark);
      final s = c.read(themeControllerProvider);
      expect(s.light, 'soft-pop');
      expect(s.mode, HxThemeMode.light);
      expect(s.active(Brightness.dark).id, 'soft-pop');
    });

    test('the choice is persisted and read back', () async {
      final c = await _container();
      final n = c.read(themeControllerProvider.notifier);
      await n.select('moss', platform: Brightness.dark);
      await n.setMode(HxThemeMode.dark);
      final prefs = c.read(sharedPrefsProvider);
      expect(prefs.getString('theme.dark'), 'moss');
      expect(prefs.getString('theme.mode'), 'dark');

      final again = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      final s = again.read(themeControllerProvider);
      expect(s.dark, 'moss');
      expect(s.mode, HxThemeMode.dark);
    });

    test('a stored unknown or wrong-slot id falls back to the default', () async {
      final c = await _container({
        'theme.light': 'does-not-exist',
        'theme.dark': 'paper',
        'theme.mode': 'sideways',
      });
      final s = c.read(themeControllerProvider);
      expect(s.light, 'paper');
      expect(s.dark, 'darkmatter');
      expect(s.mode, HxThemeMode.system);
    });
  });

  group('ThemePickerScreen', () {
    testWidgets('lists every theme and ticks the one on screen', (tester) async {
      await pumpGolden(tester, const ThemePickerScreen());
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Darkmatter, dark theme'), findsOneWidget);
      // Light themes sit below the dark ones; the list builds lazily.
      await tester.scrollUntilVisible(find.text('Paper'), 300);
      expect(
        find.bySemanticsLabel('Paper, light theme, selected'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tapping a theme selects it and ticks it', (tester) async {
      await pumpGolden(
        tester,
        const ThemePickerScreen(),
        brightness: Brightness.dark,
      );
      final handle = tester.ensureSemantics();
      final label = find.bySemanticsLabel('Darkmatter, dark theme, selected');
      expect(label, findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Moss, dark theme'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Moss, dark theme, selected'), findsOneWidget);
      expect(find.bySemanticsLabel('Darkmatter, dark theme'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the mode control switches System / Light / Dark', (tester) async {
      await pumpGolden(tester, const ThemePickerScreen());
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('System mode, selected'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dark mode'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Dark mode, selected'), findsOneWidget);
      handle.dispose();
    });

    for (final id in ['darkmatter', 'paper']) {
      final dark = id == 'darkmatter';
      for (final scale in [1.0, 2.0]) {
        testWidgets('golden $id text $scale', (tester) async {
          await pumpGolden(
            tester,
            const ThemePickerScreen(),
            brightness: dark ? Brightness.dark : Brightness.light,
            textScale: scale,
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/theme_picker_${id}_${scale.round()}.png'),
          );
        });
      }
    }

    testWidgets('semantics: labelled targets of at least 48 dp', (tester) async {
      await pumpGolden(tester, const ThemePickerScreen());
      await expectAccessible(tester);
    });

    testWidgets('semantics in dark with text 2.0', (tester) async {
      await pumpGolden(
        tester,
        const ThemePickerScreen(),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      await expectAccessible(tester);
    });
  });
}
