import 'dart:convert';

import 'package:hyperox/data/ssh_machines_repo.dart';

const devbox = SshMachine(
  id: 'm1',
  name: 'devbox',
  host: 'devbox.tail3a1f.ts.net',
  user: 'dev',
);
const raspi = SshMachine(
  id: 'm2',
  name: 'raspi',
  host: '192.168.1.42',
  user: 'pi',
);
const gcp = SshMachine(
  id: 'm3',
  name: 'h0x-gcp',
  host: '34.93.12.8',
  user: 'ubuntu',
);

Map<String, Object> storedMachines(List<SshMachine> ms) => {
  'ssh.machines': jsonEncode([for (final m in ms) m.toJson()]),
};
