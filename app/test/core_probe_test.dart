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

    test('a leading ~/ in the override is the home folder', () {
      final odd = fakeCore('${home.path}/my tools', 'tilde');
      expect(odd.startsWith(home.path), isTrue);
      final r = run(unixCommand('connect', override: '~/my tools/h0x-core'));
      expect(r.stdout.toString().trim(), 'tilde connect');
      // ~ alone is the home folder (a folder: skipped, nothing else found)
      expect(run(unixCommand('connect', override: '~')).exitCode, 127);
    }, skip: skip);

    test('on Windows (OS=Windows_NT, as Git sh sees it) it also says so; on unix it does not', () {
      final win = Process.runSync(
        '/bin/sh',
        ['-c', unixCommand('connect')],
        environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin', 'OS': 'Windows_NT'},
        includeParentEnvironment: false,
      );
      expect(win.exitCode, 127);
      expect(win.stderr.toString().trim().split('\n'), [coreNotHere, onWindowsMarker]);
      final unix = run(unixCommand('connect'));
      expect(unix.stderr.toString().trim(), coreNotHere);
    }, skip: skip);

    test('the output of the shell stays clean: no banner of our own', () {
      fakeCore('${home.path}/.local/bin', 'local');
      final r = run(unixCommand('connect'));
      expect(r.stderr, '');
    }, skip: skip);
  });

  group('unix command text', () {
    test('shape: the override is the last word, as digits; the candidates in order', () {
      final cmd = unixCommand('connect');
      expect(cmd.startsWith("sh -c '"), isTrue);
      expect(cmd.endsWith("' sh o"), isTrue);
      final order = [
        r'"$q"',
        r'"$(command -v h0x-core 2>/dev/null)"',
        r'"$HOME/.local/bin/h0x-core"',
        '"/usr/local/bin/h0x-core"',
        '"/opt/homebrew/bin/h0x-core"',
        r'"$HOME/.local/share/mise/shims/h0x-core"',
        r'"$HOME/.nix-profile/bin/h0x-core"',
        '"/run/current-system/sw/bin/h0x-core"',
        r'"$HOME/.cargo/bin/h0x-core"',
        r'exec "$p" connect',
        'h0x-core is not installed here',
      ];
      var at = -1;
      for (final part in order) {
        final i = cmd.indexOf(part);
        expect(i, greaterThan(at), reason: part);
        at = i;
      }
    });

    test('the override is only digits on the line: nothing for any shell to read', () {
      for (final o in [r'/opt/h x/core', "/o'x", r'C:\R&D\a^b|c>d<e (x) $x `y` %z% "q"', 'Zoë 核心', '']) {
        final cmd = unixCommand('connect', override: o);
        expect(RegExp(r" sh o[0-7]*$").hasMatch(cmd), isTrue, reason: o);
        expect(cmd.contains(o) && o.isNotEmpty, isFalse, reason: 'the path itself is not on the line: $o');
      }
    });

    test('encodeOverride: UTF-8 bytes in octal, three digits each', () {
      expect(encodeOverride(''), 'o');
      expect(encodeOverride('abc'), 'o141142143');
      expect(encodeOverride('é'), 'o303251');
      expect(encodeOverride('\n'), 'o012');
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

    test('the marker is the first thing printed', () {
      final lines = windowsProbeScript().split('\n');
      expect(lines.indexWhere((l) => l.contains('H0X_OS=windows')), lessThan(lines.indexWhere((l) => l.contains('H0X_CORE='))));
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

    test('the probe says it is Windows even when it finds no core', () {
      expect(isWindowsProbe(windowsProbeScript().contains("Write-Output 'H0X_OS=windows'") ? 'H0X_OS=windows\r\n' : ''), isTrue);
      expect(isWindowsProbe('H0X_OS=windows\r\n'), isTrue);
      expect(isWindowsProbe('Welcome to box\r\n'), isFalse);
      expect(isWindowsProbe(''), isFalse);
    });

    test('candidates are expanded: %VAR% and a leading ~', () {
      final s = windowsProbeScript(override: r'%LOCALAPPDATA%\x\h0x-core.exe');
      expect(s, contains(r'[Environment]::ExpandEnvironmentVariables($p)'));
      expect(s, contains(r"$p.StartsWith('~')"));
      expect(s.indexOf('ExpandEnvironmentVariables'), lessThan(s.indexOf('Test-Path')));
      // the override itself stays a literal in the script: the expansion happens in PowerShell
      expect(s, contains(r"'%LOCALAPPDATA%\x\h0x-core.exe'"));
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
    });

    test('cmd metacharacters in the path are escaped with ^ for the login cmd', () {
      const p = FoundCore(r'G:\R&D (x)\a^b\h0x-core.exe', r'G:\R&D (x)\a^b\h0x-core.exe');
      expect(windowsRunCommand(p, 'connect', shell: WindowsShell.cmd), r'cmd /d /c ""G:\R^&D ^(x^)\a^^b\h0x-core.exe" connect"');
    });

    test('a spaced path under PowerShell is a single-quoted literal', () {
      expect(windowsRunCommand(spaced, 'bridge spaces --show --json', shell: WindowsShell.powershell),
          r"& 'G:\Hyper Ox\core\h0x-core.exe' bridge spaces --show --json");
      const odd = FoundCore(r"C:\O'Neil\$x `y`\h0x-core.exe", r"C:\O'Neil\$x `y`\h0x-core.exe");
      expect(windowsRunCommand(odd, 'connect', shell: WindowsShell.powershell), r"& 'C:\O''Neil\$x `y`\h0x-core.exe' connect");
    });

    test('an unknown shell gets a launch no shell parses: a base64 PowerShell script', () {
      final cmd = windowsRunCommand(spaced, 'connect');
      expect(RegExp(r'^powershell -NoProfile -NonInteractive -NoLogo -EncodedCommand [A-Za-z0-9+/=]+$').hasMatch(cmd), isTrue);
      expect(decode(cmd), windowsLaunchScript(spaced.path, 'connect'));
      expect(windowsLaunchScript(spaced.path, 'connect'), "& 'G:\\Hyper Ox\\core\\h0x-core.exe' connect\nexit \$LASTEXITCODE");
    });

    test('cmd with a %VAR% pair in the path would expand it: launched the encoded way', () {
      const p = FoundCore(r'C:\%TEMP%\h0x core\h0x-core.exe', r'C:\%TEMP%\h0x core\h0x-core.exe');
      expect(windowsRunCommand(p, 'connect', shell: WindowsShell.cmd).startsWith('powershell '), isTrue);
    });

    test('the shell is read from what it said', () {
      expect(windowsShellFrom("'sh' is not recognized as an internal or external command,\r\n"), WindowsShell.cmd);
      expect(
        windowsShellFrom("sh : The term 'sh' is not recognized as the name of a cmdlet, function, script file, or operable program."),
        WindowsShell.powershell,
      );
      expect(windowsShellFrom('boom'), WindowsShell.unknown);
      expect(windowsShellFrom(''), WindowsShell.unknown);
      // PowerShell 7: "a name", and no CommandNotFoundException in the concise view
      expect(windowsShellFrom("sh: The term 'sh' is not recognized as a name of a cmdlet, function, script file, or executable program."),
          WindowsShell.powershell);
      // another language: unknown (the probe decides, not the text)
      expect(windowsShellFrom('Der Befehl "sh" ist entweder falsch geschrieben oder konnte nicht gefunden werden.'), WindowsShell.unknown);
    });
  });
}
