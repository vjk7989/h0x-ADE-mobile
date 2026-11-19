import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';

/// The connections the screens use: one per machine, already started (the
/// machine store creates them; screens never build a transport). Empty until
/// the Machines work provides the real list; tests override it with fakes.
final connectionsProvider = Provider<List<MachineConnection>>((ref) => const []);
