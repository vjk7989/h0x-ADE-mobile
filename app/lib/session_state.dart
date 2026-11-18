import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_service.dart';

/// Whether an account is signed in. Always false while [kAccountMode] is off.
final signedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider),
);

/// How many SSH machines this phone has saved.
final sshMachineCountProvider = Provider<int>((ref) => 0);
