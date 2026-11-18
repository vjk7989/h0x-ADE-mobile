import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_controller.dart';

enum AuthProvider { google, github, email }

/// Sign-in did not complete. [message] is shown to the user as is.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The account backend (Firebase). SSH-only mode never calls it: the
/// default [UnavailableAuthService] is all this build has, so nothing in
/// the SSH-only path can touch Firebase.
abstract class AuthService {
  Future<void> signIn(AuthProvider provider);
  Future<void> signOut();
}

class UnavailableAuthService implements AuthService {
  const UnavailableAuthService();

  @override
  Future<void> signIn(AuthProvider provider) => throw const AuthFailure(
    'Account sign-in is not available in this build. '
    'Continue without an account (SSH only).',
  );

  @override
  Future<void> signOut() async {}
}

final authServiceProvider = Provider<AuthService>(
  (ref) => const UnavailableAuthService(),
);

/// Prefix of every shared-preferences key that belongs to the signed-in
/// account. Sign-out removes them; SSH machines use other keys.
const kAccountKeyPrefix = 'account.';

class AuthController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> signIn(AuthProvider provider) async {
    await ref.read(authServiceProvider).signIn(provider);
    state = true;
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    final prefs = ref.read(sharedPrefsProvider);
    for (final k in prefs.getKeys().where((k) => k.startsWith(kAccountKeyPrefix))) {
      await prefs.remove(k);
    }
    state = false;
  }
}

final authControllerProvider = NotifierProvider<AuthController, bool>(
  AuthController.new,
);
