import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/ssh/core_probe.dart';

/// The text of a PowerShell -EncodedCommand argument.
String decode(String command) {
  final b64 = command.split(' ').last;
  final bytes = base64.decode(b64);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ]);
}

void main() {
  group('unix script, run for real with sh', () {
    late Directory home;
    late Directory pathDir;

    setUp(() {
      home = Directory.systemTemp.createTempSync('h0x-home-');
      pathDir = Directory.systemTemp.createTempSync('h0x-path-');
      addTearDown(() {
        home.deleteSync(recursive: true);
        pathDir.deleteSync(recursive: true);
      });
    });

    /// A fake core that says who it is and what it was given.
    String fakeCore(String dir, String tag, {bool executable = true}) {
      Directory(dir).createSync(recursive: true);
      final f = File('$dir/h0x-core')..writeAsStringSync('#!/bin/sh\necho "$tag \$@"\n');
      if (executable) Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    ProcessResult run(String command, {bool withPath = false}) => Process.runSync(
          '/bin/sh',
          ['-c', command],
          environment: {
            'HOME': home.path,
            'PATH': withPath ? '${pathDir.path}:/usr/bin:/bin' : '/usr/bin:/bin',
          },
          includeParentEnvironment: false,
        );

    final skip = Platform.isWindows ? 'needs sh' : false;

    test('nothing anywhere: the marker on stderr, exit 127, nothing on stdout', () {
      final r = run(unixCommand('connect'));
      expect(r.exitCode, 127);
      expect(r.stderr.toString().trim(), coreNotHere);
      expect(r.stdout, '');
    }, skip: skip);

    test('the arguments reach the core unchanged', () {
      fakeCore('${home.path}/.local/bin', 'local');
      final r = run(unixCommand('bridge spaces --show --json'));
      expect(r.stdout.toString().trim(), 'local bridge spaces --show --json');
    }, skip: skip);

    test('PATH comes before ~/.local/bin', () {
      fakeCore('${home.path}/.local/bin', 'local');
      fakeCore(pathDir.path, 'path');
      expect(run(unixCommand('connect'), withPath: true).stdout.toString().trim(), 'path connect');
      expect(run(unixCommand('connect')).stdout.toString().trim(), 'local connect');
    }, skip: skip);

    test('the override comes before PATH and the usual places', () {
      fakeCore('${home.path}/.local/bin', 'local');
      fakeCore(pathDir.path, 'path');
      final odd = fakeCore('${home.path}/odd', 'override');
      final r = run(unixCommand('connect', override: odd), withPath: true);
      expect(r.stdout.toString().trim(), 'override connect');
    }, skip: skip);

    test('an override with spaces and a quote in it is passed as one word', () {
      final odd = fakeCore("${home.path}/Hyper Ox's core", 'spaced');
      final r = run(unixCommand('connect', override: odd));
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), 'spaced connect');
    }, skip: skip);

    test('an override that is not there falls through to the usual places', () {
      fakeCore('${home.path}/.local/bin', 'local');
      final r = run(unixCommand('connect', override: '${home.path}/nope/h0x-core'));
      expect(r.stdout.toString().trim(), 'local connect');
    }, skip: skip);

    test('a file that is not executable, or a folder, is skipped', () {
      fakeCore('${home.path}/.local/bin', 'plain', executable: false);
      Directory('${home.path}/.cargo/bin/h0x-core').createSync(recursive: true);
      fakeCore('${home.path}/.nix-profile/bin', 'nix');
      final r = run(unixCommand('connect'));
      expect(r.stdout.toString().trim(), 'nix connect');
    }, skip: skip);

    test('the order of the usual places inside HOME', () {
      // each one is removed after it wins, so the next shows
      final order = ['.local/bin', '.local/share/mise/shims', '.nix-profile/bin', '.cargo/bin'];
      for (final d in order) {
        fakeCore('${home.path}/$d', d);
      }
      for (final d in order) {
        expect(run(unixCommand('connect')).stdout.toString().trim(), '$d connect');
        File('${home.path}/$d/h0x-core').deleteSync();
      }
      expect(run(unixCommand('connect')).exitCode, 127);
    }, skip: skip);

    test('the output of the shell stays clean: no banner of our own', () {
      fakeCore('${home.path}/.local/bin', 'local');
      final r = run(unixCommand('connect'));
      expect(r.stderr, '');
    }, skip: skip);
  });

  group('unix command text', () {
    test('exact shape, no override', () {
      expect(
        unixCommand('connect'),
        "sh -c 'for p in \"\$1\" \"\$(command -v h0x-core 2>/dev/null)\" "
        '"\$HOME/.local/bin/h0x-core" "/usr/local/bin/h0x-core" "/opt/homebrew/bin/h0x-core" '
        '"\$HOME/.local/share/mise/shims/h0x-core" "\$HOME/.nix-profile/bin/h0x-core" '
        '"/run/current-system/sw/bin/h0x-core" "\$HOME/.cargo/bin/h0x-core"; do '
        'if [ -n "\$p" ] && [ -f "\$p" ] && [ -x "\$p" ]; then exec "\$p" connect; fi; done; '
        "echo \"h0x-core is not installed here\" >&2; exit 127' sh ''",
      );
    });

    test('the override is the last word, single-quoted, quotes escaped', () {
      expect(unixCommand('connect', override: '/opt/h x/core').endsWith("sh '/opt/h x/core'"), isTrue);
      expect(unixCommand('connect', override: "/o'x").endsWith("sh '/o'\\''x'"), isTrue);
    });

    test('the script itself holds no single quote', () {
      final cmd = unixCommand('connect', override: "a'b");
      final script = cmd.substring("sh -c '".length, cmd.indexOf("' sh "));
      expect(script.contains("'"), isFalse);
    });

    test('shQuote', () {
      expect(shQuote(''), "''");
      expect(shQuote('a b'), "'a b'");
      expect(shQuote("it's"), "'it'\\''s'");
    });
  });

  group('Windows probe', () {
    test('the command line has nothing for cmd or PowerShell to quote', () {
      final cmd = windowsProbeCommand(override: r"G:\Hyper Ox\O'Neil\h0x-core.exe");
      expect(RegExp(r'^powershell -NoProfile -NonInteractive -NoLogo -EncodedCommand [A-Za-z0-9+/=]+$').hasMatch(cmd), isTrue);
    });

    test('the encoded script is the script (UTF-16LE base64)', () {
      expect(decode(windowsProbeCommand()), windowsProbeScript());
      expect(decode(windowsProbeCommand(override: r'G:\x')), windowsProbeScript(override: r'G:\x'));
    });

    test('search order: override, PATH, LOCALAPPDATA, USERPROFILE, cargo, beside the app', () {
      final s = windowsProbeScript(override: r'G:\HyperOx\core\h0x-core.exe');
      final order = [
        r"$c += 'G:\HyperOx\core\h0x-core.exe'",
        'Get-Command h0x-core -CommandType Application',
        r'$env:LOCALAPPDATA\Programs\h0x-core\h0x-core.exe',
        r'$env:USERPROFILE\AppData\Local\Programs\h0x-core\h0x-core.exe',
        r'$env:USERPROFILE\.cargo\bin\h0x-core.exe',
        'Get-Command h0x-ade -CommandType Application',
        r'$d\h0x-core.exe',
        r'$d\core\h0x-core.exe',
        r'$up\core\h0x-core.exe',
      ];
      var at = -1;
      for (final part in order) {
        final i = s.indexOf(part);
        expect(i, greaterThan(at), reason: part);
        at = i;
      }
    });

    test('no override: the override line is a no-op for an empty string', () {
      expect(windowsProbeScript(), contains("if ('') { \$c += '' }"));
    });

    test('an override with a quote is escaped for PowerShell', () {
      expect(psQuote(r"G:\O'Neil\h0x-core.exe"), r"'G:\O''Neil\h0x-core.exe'");
      expect(windowsProbeScript(override: "a'b"), contains("\$c += 'a''b'"));
    });

    test('it only looks: no call that starts or changes anything', () {
      final s = windowsProbeScript(override: 'x');
      for (final bad in ['Start-Process', 'Invoke-', 'Remove-', 'Set-', 'New-Item', 'iex', '& ']) {
        expect(s.contains(bad), isFalse, reason: bad);
      }
      expect(s, contains('Test-Path'));
    });

    test('parseWindowsProbe', () {
      final f = parseWindowsProbe('H0X_CORE=G:\\HyperOx\\core\\h0x-core.exe\r\nH0X_SHORT=G:\\HYPERO~1\\core\\H0X-CO~1.EXE\r\n');
      expect(f?.path, r'G:\HyperOx\core\h0x-core.exe');
      expect(f?.shortPath, r'G:\HYPERO~1\core\H0X-CO~1.EXE');
      expect(parseWindowsProbe(''), isNull);
      expect(parseWindowsProbe('some banner\r\n'), isNull);
      expect(parseWindowsProbe('H0X_CORE=\r\n'), isNull);
      // no short path: the long one is used
      expect(parseWindowsProbe('H0X_CORE=C:\\a\\h0x-core.exe\n')?.shortPath, r'C:\a\h0x-core.exe');
      // noise around it is ignored
      expect(parseWindowsProbe('Welcome\r\nH0X_CORE=C:\\a\\c.exe\r\nbye')?.path, r'C:\a\c.exe');
    });
  });

  group('Windows run command', () {
    const spaced = FoundCore(r'G:\Hyper Ox\core\h0x-core.exe', r'G:\Hyper Ox\core\h0x-core.exe');
    const short = FoundCore(r'G:\Hyper Ox\core\h0x-core.exe', r'G:\HYPERO~1\core\H0X-CO~1.EXE');

    test('a short path has nothing to quote: the same under both shells', () {
      for (final shell in WindowsShell.values) {
        expect(windowsRunCommand(short, 'connect', shell: shell), r'cmd /d /c G:\HYPERO~1\core\H0X-CO~1.EXE connect');
      }
    });

    test('a spaced path under cmd is quoted for cmd', () {
      expect(windowsRunCommand(spaced, 'connect', shell: WindowsShell.cmd), r'cmd /d /c ""G:\Hyper Ox\core\h0x-core.exe" connect"');
      expect(windowsRunCommand(spaced, 'connect'), r'cmd /d /c ""G:\Hyper Ox\core\h0x-core.exe" connect"');
    });

    test('a spaced path under PowerShell is called with &', () {
      expect(windowsRunCommand(spaced, 'bridge spaces --show --json', shell: WindowsShell.powershell),
          r'& "G:\Hyper Ox\core\h0x-core.exe" bridge spaces --show --json');
    });

    test('the shell is read from what it said', () {
      expect(windowsShellFrom("'sh' is not recognized as an internal or external command,\r\n"), WindowsShell.cmd);
      expect(
        windowsShellFrom("sh : The term 'sh' is not recognized as the name of a cmdlet, function, script file, or operable program."),
        WindowsShell.powershell,
      );
      expect(windowsShellFrom('boom'), WindowsShell.unknown);
      expect(windowsShellFrom(''), WindowsShell.unknown);
    });
  });
}
