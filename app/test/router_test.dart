import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/main.dart';
import 'package:hyperox/router.dart';
import 'package:hyperox/session_state.dart';

String? go(String location, {bool signedIn = false, int ssh = 0}) =>
    redirectFor(location: location, signedIn: signedIn, sshMachines: ssh);

void main() {
  group('redirectFor', () {
    test('no account and no SSH machine goes to sign-in', () {
      expect(go('/'), '/sign-in');
      expect(go('/inbox'), '/sign-in');
      expect(go('/machines'), '/sign-in');
      expect(go('/settings'), '/sign-in');
    });

    test('sign-in and Add machine stay open without an account', () {
      expect(go('/sign-in'), isNull);
      expect(go('/machines/add'), isNull);
    });

    test('SSH machines only go to the Inbox', () {
      expect(go('/', ssh: 1), '/inbox');
      expect(go('/sign-in', ssh: 2), '/inbox');
      expect(go('/inbox', ssh: 1), isNull);
      expect(go('/machines', ssh: 1), isNull);
    });

    test('a signed-in user goes to the Inbox', () {
      expect(go('/', signedIn: true), '/inbox');
      expect(go('/sign-in', signedIn: true), '/inbox');
      expect(go('/spaces', signedIn: true), isNull);
    });
  });

  Future<String> pumpAt(
    WidgetTester tester, {
    required bool signedIn,
    required int ssh,
  }) async {
    final container = ProviderContainer(
      overrides: [
        signedInProvider.overrideWithValue(signedIn),
        sshMachineCountProvider.overrideWithValue(ssh),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HyperOxApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
  }

  testWidgets('a new user lands on sign-in', (tester) async {
    expect(await pumpAt(tester, signedIn: false, ssh: 0), '/sign-in');
  });

  testWidgets('a user with SSH machines only lands on the Inbox', (
    tester,
  ) async {
    expect(await pumpAt(tester, signedIn: false, ssh: 1), '/inbox');
  });
}
