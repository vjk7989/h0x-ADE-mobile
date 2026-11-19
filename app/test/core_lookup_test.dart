import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/ssh/core_probe.dart';
import 'package:hyperox/conn/ssh/known_hosts.dart';
import 'package:hyperox/conn/ssh/ssh_connection.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/conn/ssh/ssh_transport.dart';
import 'package:hyperox/data/ssh_machines_repo.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_core.dart';
import 'support/mem_link.dart' show settle;

// Deep edge cases for finding h0x-core on a remote machine (unix sh,
// Windows cmd and PowerShell). The unix script is run for real with /bin/sh;
// the Windows side is checked against models of how cmd.exe and PowerShell
// read a command line, and through the connection with realistic outputs.

/// The text of a PowerShell -EncodedCommand argument.
String decode(String command) {
  final bytes = base64.decode(command.split(' ').last);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ]);
}

/// The commands cmd.exe splits [line] into (on `&`, `&&`, `|`, `||` outside
/// double quotes), with its `^` escapes removed. `>&2` stays a redirection.
List<String> cmdCommands(String line) {
  final out = <String>[];
  var cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
      cur.write(ch);
    } else if (!quoted && ch == '^' && i + 1 < line.length) {
      cur.write(line[++i]);
    } else if (!quoted && (ch == '&' || ch == '|') && !(ch == '&' && i > 0 && '<>'.contains(line[i - 1]))) {
      out.add(cur.toString());
      cur = StringBuffer();
      if (i + 1 < line.length && line[i + 1] == ch) i++;
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString());
  return out;
}

/// How many unconditional `&` separators cmd.exe sees in [line]: a command
/// after one of them runs even when `sh` was not found before it.
int cmdLoneAmpersands(String line) {
  var n = 0;
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (!quoted && ch == '^') {
      i++;
    } else if (!quoted && ch == '&') {
      if (i + 1 < line.length && line[i + 1] == '&') {
        i++;
      } else if (!(i > 0 && '<>'.contains(line[i - 1]))) {
        n++;
      }
    }
  }
  return n;
}

/// True when PowerShell's tokenizer closes every quote in [line] (otherwise
/// the whole line is a parse error and nothing in it runs).
bool psBalanced(String line) {
  var state = 0; // 0 outside, 1 single, 2 double
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    final next = i + 1 < line.length ? line[i + 1] : '';
    switch (state) {
      case 0:
        if (ch == '`') {
          i++;
        } else if (ch == "'") {
          state = 1;
        } else if (ch == '"') {
          state = 2;
        }
      case 1:
        if (ch == "'") {
          if (next == "'") {
            i++;
          } else {
            state = 0;
          }
        }
      case 2:
        if (ch == '`') {
          i++;
        } else if (ch == '"') {
          if (next == '"') {
            i++;
          } else {
            state = 0;
          }
        }
    }
  }
  return state == 0;
}

/// The file PowerShell calls in `& <word> args`, or null when that word is a
/// double-quoted string PowerShell would expand (`$name`, `$(`, backtick).
String? psCallTarget(String line) {
  expect(line.startsWith('& '), isTrue, reason: line);
  final rest = line.substring(2);
  if (rest.startsWith("'")) {
    final b = StringBuffer();
    for (var i = 1; i < rest.length; i++) {
      if (rest[i] == "'") {
        if (i + 1 < rest.length && rest[i + 1] == "'") {
          b.write("'");
          i++;
          continue;
        }
        return b.toString();
      }
      b.write(rest[i]);
    }
    return null;
  }
  if (rest.startsWith('"')) {
    final end = rest.indexOf('"', 1);
    final word = rest.substring(1, end);
    if (word.contains('`') || RegExp(r'\$[\w{(:?^$]').hasMatch(word)) return null;
    return word;
  }
  return rest.split(' ').first;
}

const _cmdNotRecognized = "'sh' is not recognized as an internal or external command,\r\n"
    'operable program or batch file.\r\n';
const _ps51NotRecognized = "sh : The term 'sh' is not recognized as the name of a cmdlet, function, script file, or "
    'operable program. Check the spelling of the name, or if a path was included, verify that the path is correct '
    'and try again.\r\nAt line:1 char:1\r\n+ sh -c \'for p in ...\r\n    + CategoryInfo          : ObjectNotFound: '
    '(sh:String) [], CommandNotFoundException\r\n    + FullyQualifiedErrorId : CommandNotFoundException\r\n';

/// PowerShell 7 (pwsh as the OpenSSH DefaultShell), concise error view.
const _ps7NotRecognized = "sh: The term 'sh' is not recognized as a name of a cmdlet, function, script file, or "
    'executable program.\nCheck the spelling of the name, or if a path was included, verify that the path is '
    'correct and try again.\n';
const _psParseError = "The string is missing the terminator: '.\r\n    + CategoryInfo          : ParserError: (:) [], "
    'ParentContainsErrorRecordException\r\n    + FullyQualifiedErrorId : TerminatorExpectedAtEndOfString\r\n';

/// What Windows PowerShell 5.1 prints on stderr on its first run in a session.
const _clixmlNoise = '#< CLIXML\r\n<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">'
    '<Obj S="progress" RefId="0"><TN RefId="0"><T>System.Management.Automation.PSCustomObject</T></TN><MS>'
    '<I64 N="SourceId">1</I64><PR N="Record"><AV>Preparing modules for first use.</AV></PR></MS></Obj></Objs>\r\n';

String probeOut(String path, [String? short]) => 'H0X_CORE=$path\r\nH0X_SHORT=${short ?? path}\r\n';

class _Rig {
  final core = FakeCoreState();
  final secrets = MemSecrets();
  final transports = <FakeSshTransport>[];
  final delays = <Duration>[];
  late RemoteProcess Function(String cmd) exec;
  late final KnownHosts known = KnownHosts(secrets);

  SshMachineConnection make({String corePath = ''}) => SshMachineConnection(
        target: SshTarget(id: 'm1', name: 'box', host: 'box.local', username: 'me', corePath: corePath),
        transport: ({required host, required port, required username, required key, required verify}) {
          final t = FakeSshTransport(onExec: (c) => exec(c), verify: verify);
          transports.add(t);
          return t;
        },
        knownHosts: known,
        keys: SshKeys(secrets),
        delay: (d) async => delays.add(d),
        readyTimeout: const Duration(milliseconds: 200),
      );

  /// A Windows login: [shellError] for the unix line, [probe] stdout (and
  /// [probeErr] stderr) for the probe, the fake core for anything else.
  void windows({
    required String probe,
    String shellError = _cmdNotRecognized,
    String probeErr = '',
    String Function(String cmd)? unixError,
  }) {
    exec = (cmd) {
      if (cmd.startsWith('sh -c')) return ScriptedProcess(stderr: unixError?.call(cmd) ?? shellError, code: 1);
      if (cmd.startsWith('powershell')) return ScriptedProcess(stdout: probe, stderr: probeErr, code: 0);
      if (cmd.contains('bridge spaces')) return ScriptedProcess(stdout: '{"spaces":[],"agents":[]}', code: 0);
      return FakeCoreProcess(core);
    };
  }

  List<String> get commands => [for (final t in transports) ...t.commands];
  int get probes => commands.where((c) => c.startsWith('powershell')).length;
}

Future<void> waitFor(bool Function() cond) async {
  for (var i = 0; i < 500 && !cond(); i++) {
    await settle();
  }
  expect(cond(), isTrue, reason: 'timed out waiting');
}

void main() {
  // ---------------------------------------------------------------- unix ---
  group('unix lookup, run for real with sh', () {
    late Directory root;
    late String home;
    late String pathDir;

    setUp(() {
      root = Directory.systemTemp.createTempSync('h0x-lookup-');
      home = '${root.path}/home';
      pathDir = '${root.path}/bin';
      Directory(home).createSync();
      Directory(pathDir).createSync();
      addTearDown(() => root.deleteSync(recursive: true));
    });

    String fakeCore(String dir, String tag, {bool executable = true}) {
      Directory(dir).createSync(recursive: true);
      final f = File('$dir/h0x-core')..writeAsStringSync('#!/bin/sh\necho "$tag \$@"\n');
      if (executable) Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    ProcessResult run(String command, {String? homeDir, String? extraPath}) => Process.runSync(
          '/bin/sh',
          ['-c', command],
          environment: {
            'HOME': homeDir ?? home,
            'PATH': '${extraPath == null ? '' : '$extraPath:'}/usr/bin:/bin',
          },
          includeParentEnvironment: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

    String out(ProcessResult r) => r.stdout.toString().trim();

    final skip = Platform.isWindows ? 'needs sh' : false;

    test('override that is a directory is skipped; PATH is next', () {
      fakeCore(pathDir, 'path');
      final dir = Directory('$home/HyperOx/core')..createSync(recursive: true);
      expect(out(run(unixCommand('connect', override: dir.path), extraPath: pathDir)), 'path connect');
      // with a trailing slash too
      expect(out(run(unixCommand('connect', override: '${dir.path}/'), extraPath: pathDir)), 'path connect');
    }, skip: skip);

    test('override that is not executable is skipped; the usual places are next', () {
      final plain = fakeCore('$home/odd', 'override', executable: false);
      fakeCore('$home/.local/bin', 'local');
      expect(out(run(unixCommand('connect', override: plain))), 'local connect');
    }, skip: skip);

    test('override that is a directory and nothing else: missing, exit 127', () {
      final r = run(unixCommand('connect', override: home));
      expect(r.exitCode, 127);
      expect(r.stderr.toString().trim(), coreNotHere);
      expect(r.stdout, '');
    }, skip: skip);

    for (final name in [
      'Hyper Ox ünïcødé 核心',
      '100% & ^ ! (x86)',
      r'$HOME $(touch PWNED) `touch PWNED2`',
      "it's \"quoted\"",
      r'back\slash; semi|pipe>gt<lt',
      'new\nline\ttab',
    ]) {
      test('override in a folder named ${jsonEncode(name)} is run as one word, nothing else runs', () {
        final core = fakeCore('$home/$name', 'override');
        final r = run(unixCommand('connect', override: core));
        expect(r.exitCode, 0, reason: r.stderr.toString());
        expect(out(r), 'override connect');
        expect(r.stderr, '');
        expect(File('${root.path}/PWNED').existsSync(), isFalse);
        expect(File('$home/PWNED').existsSync(), isFalse);
        expect(File('$home/PWNED2').existsSync(), isFalse);
      }, skip: skip);
    }

    test('an override that tries to inject a command runs nothing', () {
      final marker = '${root.path}/INJECTED';
      fakeCore('$home/.local/bin', 'local');
      for (final evil in ["x'; touch $marker; '", 'x" ; touch $marker ; "', r'$(touch ' '$marker)', '`touch $marker`']) {
        final r = run(unixCommand('connect', override: evil));
        expect(out(r), 'local connect', reason: evil);
        expect(File(marker).existsSync(), isFalse, reason: evil);
      }
    }, skip: skip);

    test('a very long override path (about 2000 bytes) still works', () {
      final deep = [for (var i = 0; i < 50; i++) 'segment-number-$i-of-a-deep-tree'].join('/');
      final core = fakeCore('$home/$deep', 'deep');
      expect(core.length, greaterThan(1500));
      expect(out(run(unixCommand('connect', override: core))), 'deep connect');
    }, skip: skip);

    test('an empty or whitespace-only override is the same as none', () {
      fakeCore('$home/.local/bin', 'local');
      expect(out(run(unixCommand('connect', override: ''))), 'local connect');
      expect(out(run(unixCommand('connect', override: '   '))), 'local connect');
    }, skip: skip);

    test('a home folder with spaces: ~/.local/bin and ~/.cargo/bin are still found', () {
      final spaced = '${root.path}/Jane Q Public';
      fakeCore('$spaced/.cargo/bin', 'cargo');
      expect(out(run(unixCommand('connect'), homeDir: spaced)), 'cargo connect');
      fakeCore('$spaced/.local/bin', 'local');
      expect(out(run(unixCommand('connect'), homeDir: spaced)), 'local connect');
    }, skip: skip);

    test('a PATH entry with spaces is searched', () {
      final spaced = '${root.path}/My Tools/bin';
      fakeCore(spaced, 'spacedpath');
      fakeCore('$home/.local/bin', 'local');
      expect(out(run(unixCommand('connect'), extraPath: spaced)), 'spacedpath connect');
    }, skip: skip);

    test('a core on PATH that is not executable does not stop the search', () {
      fakeCore(pathDir, 'path', executable: false);
      fakeCore('$home/.local/bin', 'local');
      expect(out(run(unixCommand('connect'), extraPath: pathDir)), 'local connect');
    }, skip: skip);

    test('a symlinked core is followed (mise / nix / homebrew style)', () {
      final real = fakeCore('${root.path}/store/abc123-h0x-core/bin', 'linked');
      Directory('$home/.nix-profile/bin').createSync(recursive: true);
      Process.runSync('ln', ['-s', real, '$home/.nix-profile/bin/h0x-core']);
      expect(out(run(unixCommand('connect'))), 'linked connect');
      // the override may be a symlink too
      Process.runSync('ln', ['-s', real, '${root.path}/core-link']);
      fakeCore('$home/.local/bin', 'local');
      expect(out(run(unixCommand('connect', override: '${root.path}/core-link'))), 'linked connect');
    }, skip: skip);

    test('a broken symlink is skipped and the next place is used', () {
      Directory('$home/.local/bin').createSync(recursive: true);
      Process.runSync('ln', ['-s', '${root.path}/gone', '$home/.local/bin/h0x-core']);
      fakeCore('$home/.cargo/bin', 'cargo');
      expect(out(run(unixCommand('connect'))), 'cargo connect');
    }, skip: skip);

    test('the override comes before a core in every usual place in HOME', () {
      for (final d in ['.local/bin', '.local/share/mise/shims', '.nix-profile/bin', '.cargo/bin']) {
        fakeCore('$home/$d', d);
      }
      fakeCore(pathDir, 'path');
      final o = fakeCore('$home/opt x', 'override');
      expect(out(run(unixCommand('connect', override: o), extraPath: pathDir)), 'override connect');
    }, skip: skip);

    test('only the core is started: the probe has no other side effect', () {
      final core = fakeCore('$home/.local/bin', 'local');
      final before = Directory(home).listSync(recursive: true).map((e) => e.path).toSet();
      run(unixCommand('connect'));
      run(unixCommand('connect', override: '$home/none'));
      final after = Directory(home).listSync(recursive: true).map((e) => e.path).toSet();
      expect(after, before);
      expect(File(core).existsSync(), isTrue);
    }, skip: skip);
  });

  // -------------------------------------- unix line as a Windows shell sees it
  group('the unix line on a Windows login shell', () {
    test('cmd: no override, nothing runs after sh fails (only && chains)', () {
      expect(cmdLoneAmpersands(unixCommand('connect')), 0);
    });

    test('cmd: an override with & does not start a second command', () {
      // Found bug: the override is inside sh single quotes, which cmd ignores.
      final line = unixCommand('connect', override: r'C:\Tools\R&D\h0x-core.exe');
      expect(cmdLoneAmpersands(line), 0, reason: line);
    });

    test('PowerShell: the line parses with no override and with spaces, & and \$', () {
      expect(psBalanced(unixCommand('connect')), isTrue);
      expect(psBalanced(unixCommand('connect', override: r'C:\Program Files (x86)\R&D $x\h0x-core.exe')), isTrue);
    });

    test("PowerShell: an override with an apostrophe (C:\\Users\\O'Neil) still parses", () {
      // Found bug: shQuote's '\'' is not a PowerShell escape, so the line is
      // a parse error and PowerShell never says "sh is not recognized".
      final line = unixCommand('connect', override: r"C:\Users\O'Neil\h0x-core.exe");
      expect(psBalanced(line), isTrue, reason: line);
    });
  });

  // ------------------------------------------------------- Windows probe ---
  group('Windows probe script', () {
    for (final o in [
      r'\\server\share\h0x-core.exe',
      r'G:\HyperOx\core\',
      r'C:\100% sure\a&b^c!d (x86)\h0x-core.exe',
      r'C:\Users\Zoë\核心\h0x-core.exe',
      r"C:\Users\O'Neil\h0x-core.exe",
      r"'); Start-Process calc; ('",
      r'$(Start-Process calc)',
      'C:\\${'x' * 300}\\h0x-core.exe',
    ]) {
      test('override ${jsonEncode(o)} is one literal string, quotes closed', () {
        final s = windowsProbeScript(override: o);
        final line = s.split('\n').firstWhere((l) => l.startsWith('if ('));
        expect(line, "if (${psQuote(o)}) { \$c += ${psQuote(o)} }");
        expect(psBalanced(line), isTrue);
        expect(psBalanced(s), isTrue);
        // and it survives the base64 trip unchanged
        expect(decode(windowsProbeCommand(override: o)), s);
        expect(RegExp(r'^powershell -NoProfile -NonInteractive -NoLogo -EncodedCommand [A-Za-z0-9+/=]+$')
            .hasMatch(windowsProbeCommand(override: o)), isTrue);
      });
    }

    test('a folder override is not taken: only a file (Leaf) counts', () {
      expect(windowsProbeScript(), contains('Test-Path -LiteralPath \$p -PathType Leaf'));
      expect(windowsProbeScript(), isNot(contains('Test-Path -Path')));
    });

    test('LOCALAPPDATA comes before cargo; the first hit wins (break)', () {
      final s = windowsProbeScript();
      expect(s.indexOf(r'$env:LOCALAPPDATA\Programs'), lessThan(s.indexOf(r'.cargo\bin')));
      expect(s.indexOf(r'$env:USERPROFILE\AppData\Local\Programs'), lessThan(s.indexOf(r'.cargo\bin')));
      final loop = s.substring(s.indexOf('foreach'));
      expect(loop.indexOf('break'), greaterThan(loop.indexOf("Write-Output ('H0X_SHORT=")));
    });

    test('beside an installed h0x-ade: its folder, core\\ in it, then core\\ and h0x-core\\ beside it', () {
      final s = windowsProbeScript();
      final a = s.indexOf('Get-Command h0x-ade');
      expect(a, greaterThan(s.indexOf(r'.cargo\bin')));
      final order = [r'"$d\h0x-core.exe"', r'"$d\core\h0x-core.exe"', r'"$up\core\h0x-core.exe"', r'"$up\h0x-core\h0x-core.exe"'];
      var at = a;
      for (final p in order) {
        expect(s.indexOf(p), greaterThan(at), reason: p);
        at = s.indexOf(p);
      }
    });

    test('the probe never runs the core or anything it found', () {
      final s = windowsProbeScript(override: r'C:\x\h0x-core.exe');
      expect(s, isNot(contains('h0x-core.exe"\n& ')));
      expect(RegExp(r'^\s*&\s', multiLine: true).hasMatch(s), isFalse);
      expect(RegExp(r'\$p\s+connect|\$f\s+connect').hasMatch(s), isFalse);
      expect(s.toLowerCase(), isNot(contains('invoke-expression')));
      expect(s.toLowerCase(), isNot(contains('start-process')));
    });
  });

  group('parseWindowsProbe with real-world output', () {
    test('a login banner and indentation around the lines', () {
      final f = parseWindowsProbe(
          'Windows PowerShell\r\nCopyright (C) Microsoft Corporation.\r\n\r\n'
          '   H0X_CORE=C:\\Users\\me\\AppData\\Local\\Programs\\h0x-core\\h0x-core.exe  \r\n'
          '\tH0X_SHORT=C:\\Users\\me\\AppData\\Local\\Programs\\H0X-CO~1\\H0X-CO~1.EXE\r\n'
          'Goodbye\r\n');
      expect(f?.path, r'C:\Users\me\AppData\Local\Programs\h0x-core\h0x-core.exe');
      expect(f?.shortPath, r'C:\Users\me\AppData\Local\Programs\H0X-CO~1\H0X-CO~1.EXE');
    });

    test('a UTF-8 byte order mark before the first line', () {
      final f = parseWindowsProbe('\uFEFFH0X_CORE=C:\\a\\h0x-core.exe\r\nH0X_SHORT=C:\\a\\h0x-core.exe\r\n');
      expect(f?.path, r'C:\a\h0x-core.exe');
    });

    test('LF only, CR only at the end, and no trailing newline', () {
      expect(parseWindowsProbe('H0X_CORE=C:\\a\\c.exe\nH0X_SHORT=C:\\A\\C.EXE')?.shortPath, r'C:\A\C.EXE');
      expect(parseWindowsProbe('H0X_CORE=C:\\a\\c.exe\r')?.path, r'C:\a\c.exe');
    });

    test('an empty short path (8.3 off or COM blocked) falls back to the long one', () {
      final f = parseWindowsProbe('H0X_CORE=G:\\Hyper Ox\\h0x-core.exe\r\nH0X_SHORT=\r\n');
      expect(f?.shortPath, r'G:\Hyper Ox\h0x-core.exe');
    });

    test('a short path without a long one is not a core', () {
      expect(parseWindowsProbe('H0X_SHORT=C:\\A\\C.EXE\r\n'), isNull);
    });

    test('UNC, unicode, = and a very long path come back unchanged', () {
      for (final p in [
        r'\\server\share\tools\h0x-core.exe',
        r'C:\Users\Zoë\核心\h0x-core.exe',
        r'C:\a=b\h0x-core.exe',
        'C:\\${'deep\\' * 80}h0x-core.exe',
      ]) {
        expect(parseWindowsProbe(probeOut(p))?.path, p);
      }
    });

    test('the marker must start the line: a banner that mentions it is ignored', () {
      expect(parseWindowsProbe('echo H0X_CORE=C:\\fake.exe\r\n'), isNull);
    });
  });

  group('Windows run command, as cmd and PowerShell read it', () {
    const args = 'connect';

    test('UNC short path is plain: run directly', () {
      const f = FoundCore(r'\\server\share x\h0x-core.exe', r'\\server\SHAREX~1\H0X-CO~1.EXE');
      expect(windowsRunCommand(f, args, shell: WindowsShell.cmd), r'cmd /d /c \\server\SHAREX~1\H0X-CO~1.EXE connect');
    });

    for (final p in [
      r'C:\Program Files (x86)\HyperOx\h0x-core.exe',
      r'C:\Users\Zoë Q\核心\h0x-core.exe',
      r"C:\Users\O'Neil\h0x core.exe",
      r'C:\100% done\h0x-core.exe',
      r'C:\wow!\h0x core.exe',
      r'\\server\share x\h0x-core.exe',
      'C:\\${'very long folder ' * 15}\\h0x-core.exe',
    ]) {
      test('cmd keeps ${jsonEncode(p)} whole (no 8.3 name)', () {
        final line = windowsRunCommand(FoundCore(p, p), args, shell: WindowsShell.cmd);
        final cmds = cmdCommands(line);
        expect(cmds, hasLength(1), reason: line);
        expect(cmds.single, contains(p));
      });

      test('PowerShell calls ${jsonEncode(p)} literally (no 8.3 name)', () {
        final line = windowsRunCommand(FoundCore(p, p), args, shell: WindowsShell.powershell);
        expect(psBalanced(line), isTrue, reason: line);
        expect(psCallTarget(line), p);
        expect(line.endsWith(' connect'), isTrue);
      });
    }

    for (final p in [r'G:\Tools\R&D\h0x-core.exe', r'G:\a^b\h0x core.exe', r'G:\x|y\h0x core.exe']) {
      test('cmd keeps ${jsonEncode(p)} whole: one command, path intact', () {
        // Found bug: ""p" args" leaves p outside quotes for the login cmd.
        final line = windowsRunCommand(FoundCore(p, p), args, shell: WindowsShell.cmd);
        final cmds = cmdCommands(line);
        expect(cmds, hasLength(1), reason: line);
        expect(cmds.single, contains(p), reason: line);
      });
    }

    for (final p in [r'C:\Users\me\$work\h0x-core.exe', r'C:\tools`n\h0x core.exe', r'C:\$(calc)\h0x-core.exe']) {
      test('PowerShell calls ${jsonEncode(p)} literally: no \$ or backtick expansion', () {
        // Found bug: & "p" expands $name, $( ) and backtick escapes.
        final line = windowsRunCommand(FoundCore(p, p), args, shell: WindowsShell.powershell);
        expect(psCallTarget(line), p, reason: line);
      });
    }
  });

  group('which Windows shell answered', () {
    test('cmd with CRLF and the second line', () {
      expect(windowsShellFrom(_cmdNotRecognized), WindowsShell.cmd);
    });
    test('Windows PowerShell 5.1 full error record', () {
      expect(windowsShellFrom(_ps51NotRecognized), WindowsShell.powershell);
    });
    test('PowerShell 7 (pwsh as DefaultShell) concise error', () {
      // Found bug: pwsh says "as a name of", not "as the name of", and its
      // concise view has no CommandNotFoundException.
      expect(windowsShellFrom(_ps7NotRecognized), WindowsShell.powershell);
    });
    test('a unix "sh: not found" is not Windows', () {
      expect(windowsShellFrom('sh: 1: h0x-core: not found\n'), WindowsShell.unknown);
    });
  });

  // ------------------------------------------------ through the connection --
  group('connection: lookup on a Windows login', () {
    late _Rig rig;
    setUp(() async {
      rig = _Rig();
      await rig.known.trust('box.local', 22, 'SHA256:hostkey');
    });

    test('PowerShell 5.1 login whose profile prints a banner; probe stderr has CLIXML noise', () async {
      rig.windows(
        shellError: _ps51NotRecognized,
        probe: 'Windows PowerShell\r\nCopyright (C) Microsoft Corporation. All rights reserved.\r\n\r\n'
            '${probeOut(r'C:\Users\me\AppData\Local\Programs\h0x-core\h0x-core.exe', r'C:\Users\me\AppData\Local\Programs\H0X-CO~1\H0X-CO~1.EXE')}',
        probeErr: _clixmlNoise,
      );
      final c = rig.make();
      expect(await c.start(), isA<Ready>());
      expect(rig.commands.last, r'cmd /d /c C:\Users\me\AppData\Local\Programs\H0X-CO~1\H0X-CO~1.EXE connect');
      await c.close();
    });

    test('PowerShell 7 as the login shell: the probe still runs and the core starts', () async {
      rig.windows(shellError: _ps7NotRecognized, probe: probeOut(r'C:\Program Files\HyperOx\h0x-core.exe'));
      final c = rig.make();
      final s = await c.start();
      expect(rig.probes, 1, reason: 'the probe was never sent; state: ${s is Failed ? s.reason : s}');
      expect(s, isA<Ready>());
      await c.close();
    });

    test("PowerShell login with an apostrophe in the override: the probe runs", () async {
      const o = r"C:\Users\O'Neil\h0x-core.exe";
      rig.windows(
        probe: probeOut(o, r'C:\Users\ONEIL~1\H0X-CO~1.EXE'),
        unixError: (cmd) => psBalanced(cmd) ? _ps51NotRecognized : _psParseError,
      );
      final c = rig.make(corePath: o);
      final s = await c.start();
      expect(s, isA<Ready>(), reason: s is Failed ? s.reason : '$s');
      expect(rig.commands[1], windowsProbeCommand(override: o));
      await c.close();
    });

    test('a unicode core path survives the UTF-8 trip from the probe', () async {
      const p = r'C:\Users\Zoë\核心 app\h0x-core.exe';
      rig.windows(shellError: _ps51NotRecognized, probe: probeOut(p));
      final c = rig.make();
      expect(await c.start(), isA<Ready>());
      expect(rig.commands.last, '& "$p" connect');
      await c.close();
    });

    test('a probe that prints only noise and an empty H0X_CORE is CoreMissing, no retry, Advanced named', () async {
      rig.windows(probe: 'Welcome\r\nH0X_CORE=\r\nH0X_SHORT=\r\n', probeErr: _clixmlNoise);
      final c = rig.make();
      final s = await c.start();
      expect(s, isA<CoreMissing>());
      expect((s as Failed).retryIn, isNull);
      expect(s.reason, contains('Advanced'));
      expect(rig.delays, isEmpty);
      expect(rig.probes, 1);
      await c.close();
    });

    test('one probe per session: spaces() reuses it; a reconnect probes once more', () async {
      rig.windows(probe: probeOut(r'G:\HyperOx\core\h0x-core.exe', r'G:\HYPERO~1\core\H0X-CO~1.EXE'));
      final c = rig.make();
      await c.start();
      await c.spaces();
      await c.spaces();
      expect(rig.probes, 1);
      rig.core.process!.drop();
      await waitFor(() => rig.transports.length == 2 && rig.transports.last.commands.length == 3);
      expect(rig.probes, 2);
      expect([for (final t in rig.transports) t.commands.where((x) => x.startsWith('powershell')).length], [1, 1]);
      await c.close();
    });

    test('a new override gives a new probe with the new path (the old one is not reused)', () async {
      rig.windows(probe: probeOut(r'C:\a\h0x-core.exe'));
      final first = rig.make(corePath: r'C:\a\h0x-core.exe');
      await first.start();
      await first.close();
      final second = rig.make(corePath: r'D:\b c\h0x-core.exe');
      await second.start();
      expect(rig.transports.last.commands[0], unixCommand('connect', override: r'D:\b c\h0x-core.exe'));
      expect(rig.transports.last.commands[1], windowsProbeCommand(override: r'D:\b c\h0x-core.exe'));
      await second.close();
    });

    test('the probed core fails with exit 127: CoreMissing, not a retry loop', () async {
      rig.exec = (cmd) {
        if (cmd.startsWith('sh -c')) return ScriptedProcess(stderr: _cmdNotRecognized, code: 1);
        if (cmd.startsWith('powershell')) return ScriptedProcess(stdout: probeOut(r'C:\a\h0x-core.exe'), code: 0);
        return ScriptedProcess(stderr: '$coreNotHere\r\n', code: 127);
      };
      final s = await rig.make().start();
      expect(s, isA<CoreMissing>());
      expect(rig.delays, isEmpty);
    });
  });

  // ------------------------------------------------------------ storage ---
  group('stored override', () {
    test('JSON: empty string and null both load as no override; empty is not written', () {
      const base = {'id': 'a', 'name': 'a', 'host': 'h', 'user': 'u', 'port': 22};
      expect(SshMachine.fromJson({...base, 'corePath': ''}).corePath, '');
      expect(SshMachine.fromJson({...base, 'corePath': null}).corePath, '');
      expect(SshMachine.fromJson({...base, 'corePath': ''}).toJson().containsKey('corePath'), isFalse);
    });

    test('JSON: Windows, UNC and unicode paths round-trip exactly', () {
      for (final p in [r'C:\Program Files\HyperOx\h0x-core.exe', r'\\server\share\h0x-core.exe', '/home/zoë/核心/h0x-core', r"C:\O'Neil\x\"]) {
        const m = SshMachine(id: 'a', name: 'a', host: 'h', user: 'u');
        final back = SshMachine.fromJson(jsonDecode(jsonEncode(m.copyWith(corePath: p).toJson())) as Map<String, Object?>);
        expect(back.corePath, p);
      }
    });

    test('copyWith(corePath: "") clears it; copyWith() keeps it', () {
      const m = SshMachine(id: 'a', name: 'a', host: 'h', user: 'u', corePath: '/x');
      expect(m.copyWith(corePath: '').corePath, '');
      expect(m.copyWith().corePath, '/x');
    });

    test('an old store with no corePath next to a new one: both load', () async {
      SharedPreferences.setMockInitialValues({
        'ssh.machines': jsonEncode([
          {'id': 'a', 'name': 'old', 'host': 'h1', 'user': 'u', 'port': 22, 'tailscale': false},
          {'id': 'b', 'name': 'new', 'host': 'h2', 'user': 'u', 'port': 22, 'corePath': r'C:\x\h0x-core.exe'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final ms = c.read(sshMachinesProvider);
      expect([for (final m in ms) m.corePath], ['', r'C:\x\h0x-core.exe']);
    });

    test('setCorePath strips quotes pasted around the path', () async {
      SharedPreferences.setMockInitialValues({
        'ssh.machines': jsonEncode([
          {'id': 'a', 'name': 'a', 'host': 'h', 'user': 'u', 'port': 22},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      // Found bug: only whitespace is trimmed, so a pasted "..." never matches a file.
      await c.read(sshMachinesProvider.notifier).setCorePath('a', ' "C:\\Program Files\\HyperOx\\h0x-core.exe" ');
      expect(c.read(sshMachinesProvider).single.corePath, r'C:\Program Files\HyperOx\h0x-core.exe');
    });

    test('changing the override rebuilds the connection with the new path and closes the old one', () async {
      SharedPreferences.setMockInitialValues({
        'ssh.machines': jsonEncode([
          // a closed local port and Tailscale (no key): nothing leaves the box
          {'id': 'a', 'name': 'a', 'host': '127.0.0.1', 'user': 'u', 'port': 1, 'tailscale': true},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secretStoreProvider.overrideWithValue(MemSecrets()),
      ]);
      addTearDown(c.dispose);
      final before = c.read(connectionsProvider).single as SshMachineConnection;
      expect(before.target.corePath, '');
      await c.read(sshMachinesProvider.notifier).setCorePath('a', r'D:\HyperOx\h0x-core.exe');
      final after = c.read(connectionsProvider).single as SshMachineConnection;
      expect(identical(before, after), isFalse);
      expect(after.target.corePath, r'D:\HyperOx\h0x-core.exe');
      // the old connection was closed: it ends its state stream
      await before.state.last.timeout(const Duration(seconds: 5));
    });
  });

  // ---------------------------------------------- Windows probe, for real ---
  group('Windows probe script, run for real with pwsh', () {
    String? pwsh;
    try {
      final r = Process.runSync('which', ['pwsh']);
      if (r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty) pwsh = r.stdout.toString().trim();
    } catch (_) {}
    final skip = pwsh == null || Platform.isWindows ? 'needs pwsh on a unix host' : false;

    late Directory root;
    late String pathDir;
    setUp(() {
      root = Directory.systemTemp.createTempSync('h0x-pwsh-');
      pathDir = '${root.path}/bin';
      Directory(pathDir).createSync();
      addTearDown(() => root.deleteSync(recursive: true));
    });

    String fake(String dir, {String name = 'h0x-core'}) {
      Directory(dir).createSync(recursive: true);
      final f = File('$dir/$name')..writeAsStringSync('#!/bin/sh\necho ran > "${root.path}/RAN"\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    ProcessResult probe({String override = '', String? extraPath}) {
      final args = windowsProbeCommand(override: override).split(' ').skip(1).toList();
      final env = Map<String, String>.of(Platform.environment)
        ..remove('LOCALAPPDATA')
        ..remove('USERPROFILE')
        ..['PATH'] = '${extraPath == null ? '' : '$extraPath:'}/usr/bin:/bin:/usr/local/bin:/opt/microsoft/powershell/7';
      return Process.runSync(pwsh!, args, environment: env, includeParentEnvironment: false, stdoutEncoding: utf8);
    }

    test('override first, then PATH; the found file is never run', () {
      fake(pathDir);
      final o = fake('${root.path}/odd place');
      final r = probe(override: o, extraPath: pathDir);
      expect(parseWindowsProbe(r.stdout as String)?.path, o, reason: '${r.stdout}\n${r.stderr}');
      expect(parseWindowsProbe(probe(extraPath: pathDir).stdout as String)?.path, '$pathDir/h0x-core');
      expect(File('${root.path}/RAN').existsSync(), isFalse);
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

    test('an override that is a folder is skipped; PATH is next', () {
      fake(pathDir);
      Directory('${root.path}/folder').createSync();
      final r = probe(override: '${root.path}/folder', extraPath: pathDir);
      expect(parseWindowsProbe(r.stdout as String)?.path, '$pathDir/h0x-core');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

    test(r"an override with spaces, ', &, $, %, ^, !, ( ) and unicode is found as written", () {
      final o = fake("${root.path}/Zoë's R&D \$x 100% ^!(x86) 核心");
      final r = probe(override: o);
      expect(parseWindowsProbe(r.stdout as String)?.path, o, reason: '${r.stdout}\n${r.stderr}');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

    test('a PATH entry with spaces is searched', () {
      final spaced = '${root.path}/My Tools';
      fake(spaced);
      final r = probe(extraPath: spaced);
      expect(parseWindowsProbe(r.stdout as String)?.path, '$spaced/h0x-core');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

    test('nothing anywhere (h0x-ade on PATH with no core beside it): no H0X_CORE line', () {
      fake(pathDir, name: 'h0x-ade');
      final r = probe(override: '${root.path}/nope', extraPath: pathDir);
      expect(parseWindowsProbe(r.stdout as String), isNull, reason: '${r.stdout}');
      expect(File('${root.path}/RAN').existsSync(), isFalse);
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
  });
}
