import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../theme/theme_controller.dart';

/// The biometric prompt, behind an interface so tests do not need a device.
abstract class BiometricGate {
  /// Whether the device has a fingerprint or face enrolled.
  Future<bool> available();

  /// Asks the person; the system prompt also offers the device PIN.
  Future<bool> authenticate(String reason);
}

class LocalAuthGate implements BiometricGate {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

final biometricGateProvider = Provider<BiometricGate>((ref) => LocalAuthGate());

/// Whether this device can lock the app. The lock switch is hidden when not.
final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.read(biometricGateProvider).available(),
);

/// How long the app may stay in the background before it locks.
const kLockAfter = Duration(minutes: 5);

const _kEnabled = 'lock.enabled';

class AppLockState {
  const AppLockState({required this.enabled, required this.locked});
  final bool enabled;
  final bool locked;
}

class AppLockController extends Notifier<AppLockState> {
  DateTime? _leftAt;

  @override
  AppLockState build() {
    final on = ref.watch(sharedPrefsProvider).getBool(_kEnabled) ?? false;
    // A cold start with the lock on starts locked.
    return AppLockState(enabled: on, locked: on);
  }

  /// Turning it on needs one successful prompt; off needs none.
  Future<bool> setEnabled(bool on) async {
    if (on && !await ref.read(biometricGateProvider).authenticate('Turn on app lock')) {
      return false;
    }
    await ref.read(sharedPrefsProvider).setBool(_kEnabled, on);
    state = AppLockState(enabled: on, locked: false);
    return true;
  }

  void onBackground(DateTime now) => _leftAt = now;

  void onForeground(DateTime now) {
    final left = _leftAt;
    _leftAt = null;
    if (state.enabled && left != null && now.difference(left) >= kLockAfter) {
      state = const AppLockState(enabled: true, locked: true);
    }
  }

  Future<bool> unlock() async {
    if (!await ref.read(biometricGateProvider).authenticate('Unlock HyperOx')) {
      return false;
    }
    state = AppLockState(enabled: state.enabled, locked: false);
    return true;
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
