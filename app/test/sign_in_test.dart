import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/auth/auth_service.dart';
import 'package:hyperox/screens/sign_in_screen.dart';
import 'package:hyperox/screens/unlock_screen.dart';
import 'package:hyperox/session_state.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/golden.dart';

class FakeAuth implements AuthService {
  final calls = <AuthProvider>[];
  Completer<void>? pending;
  Object? error;
  var signedOut = 0;

  @override
  Future<void> signIn(AuthProvider provider) async {
    calls.add(provider);
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> signOut() async => signedOut++;
}

class FakeGate implements BiometricGate {
  FakeGate({this.isAvailable = true, this.accept = true});
  bool isAvailable;
  bool accept;
  int prompts = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

Future<ProviderContainer> _container({
  Map<String, Object> stored = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs), ...overrides],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SignInScreen, SSH-only build', () {
    testWidgets('shows no account button, only the SSH path', (tester) async {
      await pumpGolden(tester, const SignInScreen());
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Continue with GitHub'), findsNothing);
      expect(find.text('Continue with email'), findsNothing);
      expect(find.text('Continue without an account'), findsOneWidget);
    });

    testWidgets('the SSH path goes to Add machine without any account', (
      tester,
    ) async {
      final c = await _container();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SignInScreen()),
          GoRoute(
            path: '/machines/add',
            builder: (_, _) => const Text('ADD MACHINE'),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: themeData(themeById('paper')),
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('Continue without an account'));
      await tester.pumpAndSettle();
      expect(find.text('ADD MACHINE'), findsOneWidget);
      expect(c.read(signedInProvider), isFalse);
      expect(c.read(authServiceProvider), isA<UnavailableAuthService>());
    });

    testWidgets('the overflow menu offers the theme picker', (tester) async {
      await pumpGolden(tester, const SignInScreen());
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
    });
  });

  group('SignInScreen, account mode (mocked providers)', () {
    Future<FakeAuth> pumpAccount(WidgetTester tester) async {
      final auth = FakeAuth();
      await pumpGolden(
        tester,
        const SignInScreen(accountMode: true),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      return auth;
    }

    testWidgets('each button calls its provider', (tester) async {
      final auth = await pumpAccount(tester);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with GitHub'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(auth.calls, [
        AuthProvider.google,
        AuthProvider.github,
        AuthProvider.email,
      ]);
    });

    testWidgets('a failure shows a message and keeps the buttons', (
      tester,
    ) async {
      final auth = await pumpAccount(tester);
      auth.error = const AuthFailure('Wrong password.');
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(find.text("Sign-in didn't finish"), findsOneWidget);
      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('no network (unknown error) shows a generic message', (
      tester,
    ) async {
      final auth = await pumpAccount(tester);
      auth.error = StateError('socket');
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check your connection'), findsOneWidget);
    });

    testWidgets('waiting disables the others; Cancel returns', (tester) async {
      final auth = await pumpAccount(tester);
      auth.pending = Completer<void>();
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(find.text('Waiting for Google…'), findsOneWidget);
      // The other providers do nothing while one is pending.
      await tester.tap(find.text('Continue with GitHub'));
      await tester.pump();
      expect(auth.calls, [AuthProvider.google]);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Waiting for Google…'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      auth.pending!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('AuthController', () {
    test('sign-out clears account keys and keeps SSH machines', () async {
      final auth = FakeAuth();
      final c = await _container(
        stored: {
          '${kAccountKeyPrefix}uid': 'u1',
          '${kAccountKeyPrefix}phone': 'p1',
          'ssh.machines': '[]',
        },
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      final n = c.read(authControllerProvider.notifier);
      await n.signIn(AuthProvider.google);
      expect(c.read(signedInProvider), isTrue);
      await n.signOut();
      expect(c.read(signedInProvider), isFalse);
      final prefs = c.read(sharedPrefsProvider);
      expect(prefs.getKeys(), {'ssh.machines'});
      expect(auth.signedOut, 1);
    });

    test('the default service refuses account sign-in', () async {
      final c = await _container();
      expect(
        c.read(authControllerProvider.notifier).signIn(AuthProvider.google),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('AppLockController', () {
    final t0 = DateTime(2026, 11, 18, 12);

    test('off by default, never locks', () async {
      final c = await _container(
        overrides: [biometricGateProvider.overrideWithValue(FakeGate())],
      );
      final n = c.read(appLockProvider.notifier);
      expect(c.read(appLockProvider).locked, isFalse);
      n.onBackground(t0);
      n.onForeground(t0.add(const Duration(hours: 2)));
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('on: starts locked, locks after 5 minutes away, not before', () async {
      final c = await _container(
        stored: {'lock.enabled': true},
        overrides: [biometricGateProvider.overrideWithValue(FakeGate())],
      );
      final n = c.read(appLockProvider.notifier);
      expect(c.read(appLockProvider).locked, isTrue);
      expect(await n.unlock(), isTrue);
      expect(c.read(appLockProvider).locked, isFalse);

      n.onBackground(t0);
      n.onForeground(t0.add(const Duration(minutes: 4, seconds: 59)));
      expect(c.read(appLockProvider).locked, isFalse);
      n.onBackground(t0);
      n.onForeground(t0.add(const Duration(minutes: 5)));
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('a refused prompt keeps it locked', () async {
      final gate = FakeGate(accept: false);
      final c = await _container(
        stored: {'lock.enabled': true},
        overrides: [biometricGateProvider.overrideWithValue(gate)],
      );
      expect(await c.read(appLockProvider.notifier).unlock(), isFalse);
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('turning it on needs a successful prompt', () async {
      final gate = FakeGate(accept: false);
      final c = await _container(
        overrides: [biometricGateProvider.overrideWithValue(gate)],
      );
      final n = c.read(appLockProvider.notifier);
      expect(await n.setEnabled(true), isFalse);
      expect(c.read(appLockProvider).enabled, isFalse);
      gate.accept = true;
      expect(await n.setEnabled(true), isTrue);
      expect(c.read(appLockProvider).enabled, isTrue);
      expect(c.read(sharedPrefsProvider).getBool('lock.enabled'), isTrue);
    });

    test('no biometrics on the device: the switch is hidden', () async {
      final c = await _container(
        overrides: [
          biometricGateProvider.overrideWithValue(FakeGate(isAvailable: false)),
        ],
      );
      expect(await c.read(biometricsAvailableProvider.future), isFalse);
    });
  });

  group('UnlockScreen', () {
    testWidgets('golden light and dark, labelled targets', (tester) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        await pumpGolden(
          tester,
          const UnlockScreen(),
          brightness: b,
          overrides: [
            biometricGateProvider.overrideWithValue(FakeGate(accept: false)),
          ],
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/unlock_${b.name}.png'),
        );
      }
    });

    testWidgets('semantics: labelled targets', (tester) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        await pumpGolden(
          tester,
          const UnlockScreen(),
          brightness: b,
          dpr: 3.0,
          overrides: [
            biometricGateProvider.overrideWithValue(FakeGate(accept: false)),
          ],
        );
        await expectAccessible(tester);
      }
    });
  });

  group('SignInScreen goldens', () {
    final cases = <String, Future<void> Function(WidgetTester)>{};
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final tag = '${dark ? 'dark' : 'light'}_${scale.round()}';
        cases['ssh_only_$tag'] = (tester) => pumpGolden(
          tester,
          const SignInScreen(),
          brightness: dark ? Brightness.dark : Brightness.light,
          textScale: scale,
        );
        cases['account_$tag'] = (tester) => pumpGolden(
          tester,
          const SignInScreen(accountMode: true),
          brightness: dark ? Brightness.dark : Brightness.light,
          textScale: scale,
        );
      }
    }
    cases['tablet_dark'] = (tester) => pumpGolden(
      tester,
      const SignInScreen(accountMode: true),
      frame: Frame.tablet,
      brightness: Brightness.dark,
    );
    for (final e in cases.entries) {
      testWidgets('golden ${e.key}', (tester) async {
        await e.value(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/sign_in_${e.key}.png'),
        );
      });
    }

    testWidgets('waiting and error states', (tester) async {
      final auth = FakeAuth()..pending = Completer<void>();
      await pumpGolden(
        tester,
        const SignInScreen(accountMode: true),
        brightness: Brightness.dark,
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sign_in_waiting_dark_1.png'),
      );
      auth.pending!.complete();
      auth.error = const AuthFailure(
        'The browser closed before Google confirmed. Nothing was saved.',
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sign_in_error_dark_1.png'),
      );
    });

    testWidgets('semantics: SSH-only build', (tester) async {
      await pumpGolden(tester, const SignInScreen(), dpr: 3.0);
      await expectAccessible(tester);
    });

    testWidgets('semantics: account mode, dark, text 2.0', (tester) async {
      await pumpGolden(
        tester,
        const SignInScreen(accountMode: true),
        brightness: Brightness.dark,
        textScale: 2.0,
        dpr: 3.0,
      );
      await expectAccessible(tester);
    });
  });
}
