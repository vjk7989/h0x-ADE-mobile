import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show OpenSSHEd25519KeyPair;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/settings_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

import 'support/a11y.dart';
import 'support/fake_connection.dart';
import 'support/fake_core.dart' show MemSecrets;
import 'support/golden.dart';
import 'support/golden_expect.dart';

class _Gate implements BiometricGate {
  _Gate(this.has);
  final bool has;

  @override
  Future<bool> available() async => has;

  @override
  Future<bool> authenticate(String reason) async => true;
}

void main() {
  late MemSecrets secrets;
  late List<String> copied;
  late List<String> shared;

  setUp(() {
    secrets = MemSecrets();
    copied = [];
    shared = [];
  });

  List<Override> overrides({bool biometrics = true, List<FakeConnection> machines = const []}) => [
        secretStoreProvider.overrideWithValue(secrets),
        biometricGateProvider.overrideWithValue(_Gate(biometrics)),
        connectionsProvider.overrideWithValue(<MachineConnection>[...machines]),
        inboxPollProvider.overrideWithValue(null),
        copyTextProvider.overrideWithValue((t) async => copied.add(t)),
        shareTextProvider.overrideWithValue((t) async => shared.add(t)),
      ];

  Future<void> show(WidgetTester t,
      {bool biometrics = true,
      List<FakeConnection> machines = const [],
      Brightness b = Brightness.light,
      double scale = 1,
      Frame f = Frame.phone,
      VoidCallback? onTheme}) async {
    await pumpGolden(
      t,
      SettingsScreen(onNavigate: (_) {}, onOpenTheme: onTheme),
      frame: f,
      brightness: b,
      textScale: scale,
      overrides: overrides(biometrics: biometrics, machines: machines),
    );
    await t.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  testWidgets('theme row shows the choice and opens the picker', (t) async {
    var opened = false;
    await show(t, onTheme: () => opened = true);
    expect(find.text('System · Paper / Darkmatter'), findsOneWidget);
    await t.tap(find.text('Theme'));
    expect(opened, isTrue);
  });

  testWidgets('the biometric switch is hidden when the device has none', (t) async {
    await show(t, biometrics: false);
    expect(find.text('Unlock with fingerprint'), findsNothing);
    expect(find.text('SECURITY'), findsNothing);
  });

  testWidgets('the biometric switch is shown when the device has one', (t) async {
    await show(t, biometrics: true);
    expect(find.text('Unlock with fingerprint'), findsOneWidget);
  });

  testWidgets('SSH-only build: no account, phones or sign-out blocks', (t) async {
    await show(t);
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
    expect(find.textContaining('Phones linked'), findsNothing);
  });

  testWidgets('no key yet: Create key makes one, shown with its fingerprint', (t) async {
    await show(t);
    await scrollTo(t, find.text('Create key'));
    expect(find.textContaining('No key yet'), findsOneWidget);
    await t.tap(find.text('Create key'));
    await t.pumpAndSettle();
    await scrollTo(t, find.byType(SelectableText));
    final line = t.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(line, startsWith('ssh-ed25519 '));
    expect(find.textContaining('SHA256:'), findsOneWidget);
    expect(secrets.map, isNotEmpty);
  });

  testWidgets('an existing key is shown without being replaced; Copy and Share send the line', (t) async {
    // make a key first, then open the screen again over the same storage
    await show(t);
    await scrollTo(t, find.text('Create key'));
    await t.tap(find.text('Create key'));
    await t.pumpAndSettle();
    final first = t.widget<SelectableText>(find.byType(SelectableText)).data!;
    await show(t);
    await scrollTo(t, find.byType(SelectableText));
    expect(t.widget<SelectableText>(find.byType(SelectableText)).data, first);
    await scrollTo(t, find.text('Copy'));
    await t.tap(find.text('Copy'));
    await t.pumpAndSettle();
    expect(copied, [first]);
    await t.tap(find.text('Share'));
    await t.pumpAndSettle();
    expect(shared, [first]);
  });

  testWidgets('Regenerate asks first; Cancel keeps the key, Regenerate replaces it', (t) async {
    await show(t);
    await scrollTo(t, find.text('Create key'));
    await t.tap(find.text('Create key'));
    await t.pumpAndSettle();
    final old = t.widget<SelectableText>(find.byType(SelectableText)).data!;
    await scrollTo(t, find.text('Regenerate key…'));
    await t.tap(find.text('Regenerate key…'));
    await t.pumpAndSettle();
    expect(find.text("Regenerate this phone's key?"), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(t.widget<SelectableText>(find.byType(SelectableText)).data, old);
    await t.tap(find.text('Regenerate key…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Regenerate'));
    await t.pumpAndSettle();
    await scrollTo(t, find.byType(SelectableText));
    expect(t.widget<SelectableText>(find.byType(SelectableText)).data, isNot(old));
    expect(find.text('New key'), findsOneWidget);
  });

  testWidgets('known hosts: listed, Forget removes one', (t) async {
    secrets.map['hyperox.ssh.known_hosts.v1'] =
        '{"devbox:22":"SHA256:AAAA","[::1]:2222":"SHA256:BBBB"}';
    await show(t);
    await scrollTo(t, find.text('devbox:22'));
    expect(find.text('[::1]:2222'), findsOneWidget);
    expect(find.text('SHA256:AAAA'), findsOneWidget);
    await t.tap(find.byTooltip('Forget host key for devbox:22'));
    await t.pumpAndSettle();
    expect(find.text('devbox:22'), findsNothing);
    expect(find.text('[::1]:2222'), findsOneWidget);
    expect(secrets.map['hyperox.ssh.known_hosts.v1'], isNot(contains('devbox')));
  });

  testWidgets('no known hosts says so', (t) async {
    await show(t);
    await scrollTo(t, find.text('No host has been trusted yet.'));
    expect(find.text('No host has been trusted yet.'), findsOneWidget);
  });

  testWidgets('notifications: one switch per machine, remembered', (t) async {
    final a = FakeConnection(id: 'devbox', name: 'devbox');
    await show(t, machines: [a]);
    await scrollTo(t, find.text('devbox'));
    expect(find.text('ssh · while the app is open'), findsOneWidget);
    final prefs = ProviderScope.containerOf(t.element(find.byType(SettingsScreen)))
        .read(sharedPrefsProvider);
    expect(prefs.getBool('notify.devbox'), isNull, reason: 'on by default');
    await t.tap(find.byType(Switch).last);
    await t.pumpAndSettle();
    expect(prefs.getBool('notify.devbox'), isFalse);
  });

  testWidgets('no machines: no notifications block', (t) async {
    await show(t);
    expect(find.text('NOTIFICATIONS'), findsNothing);
  });

  testWidgets('golden: top of the screen, light and dark, accessible', (t) async {
    await show(t, machines: [FakeConnection(id: 'devbox', name: 'devbox')]);
    await expectGolden(find.byType(MaterialApp), 'settings_phone_light');
    await expectAccessible(t);
    await show(t, machines: [FakeConnection(id: 'devbox', name: 'devbox')], b: Brightness.dark);
    await expectGolden(find.byType(MaterialApp), 'settings_phone_dark');
    await expectAccessible(t);
  });

  testWidgets('golden: key and known hosts, scrolled', (t) async {
    secrets.map['hyperox.ssh.known_hosts.v1'] = '{"devbox:22":"SHA256:4mQe0rTT0000000000000000000000000000000000"}';
    // A fixed key: a generated one is random, and so would be the golden.
    final sk = nacl.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 7)));
    secrets.map['hyperox.ssh.key.v1'] = OpenSSHEd25519KeyPair(
      Uint8List.fromList(sk.verifyKey.asTypedList),
      Uint8List.fromList(sk.asTypedList),
      'hyperox-phone',
    ).toPem();
    await show(t, b: Brightness.dark);
    await scrollTo(t, find.text('Regenerate key…'));
    await scrollTo(t, find.text('devbox:22'));
    await expectGolden(find.byType(MaterialApp), 'settings_phone_dark_key');
    await expectAccessible(t);
  });

  testWidgets('golden: text 200 percent, accessible', (t) async {
    await show(t, scale: 2);
    await expectGolden(find.byType(MaterialApp), 'settings_phone_light_200');
    await expectAccessible(t);
  });

  testWidgets('golden: tablet shows the categories and the selected one', (t) async {
    await show(t, f: Frame.tablet);
    await expectGolden(find.byType(MaterialApp), 'settings_tablet_light');
    await expectAccessible(t);
  });
}
