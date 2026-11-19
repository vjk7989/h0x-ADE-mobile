import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_service.dart';
import 'conn/machine_connection.dart';
import 'data/ssh_machines_repo.dart';

/// Whether an account is signed in. Always false while [kAccountMode] is off.
final signedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider),
);

/// How many SSH machines this phone has saved.
final sshMachineCountProvider = Provider<int>(
  (ref) => ref.watch(sshMachinesProvider).length,
);

/// Account (cloud) machines. Empty until account mode ships.
final cloudMachinesProvider = Provider<List<MachineInfo>>((ref) => const []);
