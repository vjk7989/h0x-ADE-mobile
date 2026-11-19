/// Finding `h0x-core` on a remote machine. The commands here are built as
/// strings and never run by this file; ssh_connection.dart sends them.
///
/// Unix: one `sh -c` that looks in the usual places in order and `exec`s the
/// first core it finds (one round trip).
///
/// Windows: the SSH login shell may be cmd or PowerShell, whose quoting
/// differs. So the probe is a PowerShell script passed as `-EncodedCommand`
/// (base64: no quote or space for either shell to touch). It only looks and
/// prints the path; the core is then started with that path (8.3 short form,
/// so there is nothing to quote).
library;

import 'dart:convert';

/// What the unix script prints on stderr when no core is found (core's own
/// marker for the same case).
const coreNotHere = 'h0x-core is not installed here';

/// A single-quoted sh word.
String shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Places a unix core may be, after the override and PATH, in order. `$HOME`
/// is expanded by the remote shell.
const unixCoreDirs = [
  r'$HOME/.local/bin', // core's installer
  '/usr/local/bin',
  '/opt/homebrew/bin',
  r'$HOME/.local/share/mise/shims',
  r'$HOME/.nix-profile/bin',
  '/run/current-system/sw/bin',
  r'$HOME/.cargo/bin',
];

/// What the unix script prints on stderr, after [coreNotHere], when it ran on
/// Windows (Git's or MSYS's `sh` is on the PATH there): the machine is
/// Windows, so the Windows search is the one to run.
const onWindowsMarker = 'H0X_WINDOWS';

/// The override as the unix script reads it: `o` and each UTF-8 byte as three
/// octal digits. Only digits and one letter, so there is nothing in it for
/// any shell (sh, cmd, PowerShell) to quote or run, wherever the line lands.
String encodeOverride(String override) =>
    'o${[for (final b in utf8.encode(override)) b.toRadixString(8).padLeft(3, '0')].join()}';

/// The unix connect command: finds the core and runs it with [args], or
/// prints [coreNotHere] on stderr and exits 127. [override] is a path the
/// person set for this machine (a leading `~` is the home folder); it is
/// tried first.
String unixCommand(String args, {String override = ''}) {
  final candidates = [
    r'"$q"',
    r'"$(command -v h0x-core 2>/dev/null)"',
    for (final d in unixCoreDirs) '"$d/h0x-core"',
  ].join(' ');
  // Decode the override (octal triples to bytes, through one printf so a
  // newline inside survives), expand `~`. The script has no single quote,
  // so it can sit inside one.
  final decode = r's=${1#o}; f=; while [ -n "$s" ]; do t=${s%"${s#???}"}; s=${s#???}; f="$f\\$t"; done; '
      r'q=; [ -n "$f" ] && q=$(printf "$f"); '
      r'case "$q" in "~") q=$HOME;; "~/"*) q=$HOME/${q#"~/"};; esac; ';
  final script = '${decode}for p in $candidates; do '
      r'if [ -n "$p" ] && [ -f "$p" ] && [ -x "$p" ]; then exec "$p" '
      '$args; fi; done; echo "$coreNotHere" >&2; '
      r'[ "$OS" = Windows_NT ] && echo '
      '$onWindowsMarker >&2; exit 127';
  return "sh -c '$script' sh ${encodeOverride(override)}";
}

/// A PowerShell single-quoted string.
String psQuote(String s) => "'${s.replaceAll("'", "''")}'";

/// The probe script (PowerShell). Prints `H0X_OS=windows`, then
/// `H0X_CORE=<full path>` and `H0X_SHORT=<8.3 path>` for the first core found.
/// `%VAR%` and a leading `~` in a candidate (the override) are expanded.
///
/// Order: the override, PATH (`where h0x-core`), `%LOCALAPPDATA%` and
/// `%USERPROFILE%\AppData\Local` (the installer's folder), cargo, then next to
/// an installed HyperOx app found on PATH (`h0x-ade`): its own folder, `core`
/// beside it, and `core` / `h0x-core` beside its folder.
String windowsProbeScript({String override = ''}) {
  final lines = <String>[
    r"$ErrorActionPreference = 'SilentlyContinue'",
    '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8',
    "Write-Output 'H0X_OS=windows'",
    r'$c = @()',
    'if (${psQuote(override)}) { \$c += ${psQuote(override)} }',
    r"$c += (Get-Command h0x-core -CommandType Application | Select-Object -First 1).Source",
    r'$c += "$env:LOCALAPPDATA\Programs\h0x-core\h0x-core.exe"',
    r'$c += "$env:USERPROFILE\AppData\Local\Programs\h0x-core\h0x-core.exe"',
    r'$c += "$env:USERPROFILE\.cargo\bin\h0x-core.exe"',
    r"$a = (Get-Command h0x-ade -CommandType Application | Select-Object -First 1).Source",
    r'if ($a) {',
    r'  $d = Split-Path -Parent $a',
    r'  $up = Split-Path -Parent $d',
    r'  $c += "$d\h0x-core.exe"',
    r'  $c += "$d\core\h0x-core.exe"',
    r'  if ($up) { $c += "$up\core\h0x-core.exe"; $c += "$up\h0x-core\h0x-core.exe" }',
    r'}',
    r'foreach ($p in $c) {',
    r'  if ($p) { $p = [Environment]::ExpandEnvironmentVariables($p) }',
    r"  if ($p -and $p.StartsWith('~')) { $p = $env:USERPROFILE + $p.Substring(1) }",
    r'  if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {',
    r'    $f = (Get-Item -LiteralPath $p).FullName',
    r'    $s = (New-Object -ComObject Scripting.FileSystemObject).GetFile($f).ShortPath',
    r"    Write-Output ('H0X_CORE=' + $f)",
    r"    Write-Output ('H0X_SHORT=' + $s)",
    r'    break',
    r'  }',
    r'}',
  ];
  return lines.join('\n');
}

/// The command line that runs [windowsProbeScript] from cmd or PowerShell.
String windowsProbeCommand({String override = ''}) => _encodedPowerShell(windowsProbeScript(override: override));

/// The result of the Windows probe.
class FoundCore {
  const FoundCore(this.path, this.shortPath);
  final String path;
  final String shortPath;
}

/// Reads the probe's stdout; null when it found no core.
FoundCore? parseWindowsProbe(String stdout) {
  String? path;
  String? short;
  for (final raw in stdout.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('H0X_CORE=')) path = line.substring(9);
    if (line.startsWith('H0X_SHORT=')) short = line.substring(10);
  }
  if (path == null || path.isEmpty) return null;
  return FoundCore(path, short == null || short.isEmpty ? path : short);
}

/// True when [stdout] is the output of the Windows probe (it always prints
/// `H0X_OS=windows` first), whether or not it found a core.
bool isWindowsProbe(String stdout) => stdout.split(RegExp(r'\r?\n')).any((l) => l.trim().startsWith('H0X_'));

/// Which shell a Windows machine logs SSH commands into.
enum WindowsShell { cmd, powershell, unknown }

/// The shell, from what it said about the unix command it could not run.
WindowsShell windowsShellFrom(String stderr) {
  if (RegExp(r'is not recognized as (the|a) name of a cmdlet').hasMatch(stderr) || stderr.contains('CommandNotFoundException')) {
    return WindowsShell.powershell;
  }
  if (stderr.contains('is not recognized as an internal or external command')) return WindowsShell.cmd;
  return WindowsShell.unknown;
}

bool _plain(String p) => RegExp(r'^[A-Za-z0-9_.:\\~-]+$').hasMatch(p);

/// A path as the login cmd reads it between `""` and `"`: its own metacharacters
/// escaped with `^` (the nested cmd gets them back, inside quotes).
String _cmdEscape(String p) => p.replaceAllMapped(RegExp(r'[&|<>^()]'), (m) => '^${m[0]}');

/// The PowerShell script that starts the core: the path is a single-quoted
/// literal, so nothing in it is expanded. PowerShell hands the child its own
/// stdin and stdout untouched (checked with all 256 byte values, 1 MB).
String windowsLaunchScript(String path, String args) => "& ${psQuote(path)} $args\nexit \$LASTEXITCODE";

String _encodedPowerShell(String script) {
  final bytes = <int>[for (final u in script.codeUnits) ...[u & 0xff, u >> 8]];
  return 'powershell -NoProfile -NonInteractive -NoLogo -EncodedCommand ${base64.encode(bytes)}';
}

/// The command that runs the core found by the probe with [args], for any
/// login shell. A path without spaces or odd characters (the 8.3 form usually
/// is) is the same in cmd and PowerShell. Otherwise: for a known [shell] the
/// path is quoted the way that shell reads it (cmd: `^`-escaped inside the
/// nested quotes; PowerShell: a single-quoted literal); when the shell is not
/// known (a Windows in another language), or the path has `%` pairs cmd would
/// expand, the launch is a PowerShell script passed as base64, which no shell
/// parses.
String windowsRunCommand(FoundCore core, String args, {WindowsShell shell = WindowsShell.unknown}) {
  if (_plain(core.shortPath)) return 'cmd /d /c ${core.shortPath} $args';
  final p = core.path;
  switch (shell) {
    case WindowsShell.powershell:
      return '& ${psQuote(p)} $args';
    case WindowsShell.cmd:
      if (RegExp('%.*%').hasMatch(p)) break;
      return 'cmd /d /c ""${_cmdEscape(p)}" $args"';
    case WindowsShell.unknown:
      break;
  }
  return _encodedPowerShell(windowsLaunchScript(p, args));
}
