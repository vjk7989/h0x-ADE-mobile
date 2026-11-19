import 'package:material_ui/material_ui.dart';

import '../conn/machine_connection.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import 'hx.dart';

/// The colour of a state (tokens, status vocabulary): needs you = `working`,
/// working = `done` (blue), idle and the rest = `muted`.
Color groupColor(HxColors c, AgentGroup g) => switch (g) {
      AgentGroup.needsYou => c.working,
      AgentGroup.working => c.done,
      AgentGroup.done => c.ok,
      AgentGroup.idle => c.muted,
    };

String groupWord(AgentGroup g, {String? kind}) => switch (g) {
      AgentGroup.needsYou => kind == 'question' ? 'question' : 'needs you',
      AgentGroup.working => 'working',
      AgentGroup.done => 'done',
      AgentGroup.idle => 'idle',
    };

/// `[ssh]` (blue) or `[account]` (accent).
class ModeTag extends StatelessWidget {
  const ModeTag(this.mode, {super.key});
  final ConnMode mode;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return HxTag(mode == ConnMode.ssh ? 'ssh' : 'account',
        color: mode == ConnMode.ssh ? c.done : c.accent);
  }
}

/// A small caps section label with a count on the right: `NEEDS YOU   2`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.count, this.dot});
  final String text;
  final int? count;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text.toUpperCase(), style: HxType.labelXs.copyWith(color: c.muted)),
            ),
          ),
          if (count != null)
            Text('$count', style: HxType.labelXs.copyWith(color: c.muted)),
        ],
      ),
    );
  }
}

/// Replaces a home folder prefix by `~` (`/home/u/x`, `/Users/u/x`, `C:\Users\u\x`).
String shortFolder(String folder) {
  final m = RegExp(r'^(?:/home/[^/]+|/Users/[^/]+|[A-Za-z]:[\\/]Users[\\/][^\\/]+)(?=[\\/]|$)')
      .firstMatch(folder);
  if (m == null) return folder;
  final rest = folder.substring(m.end).replaceAll('\\', '/');
  return rest.isEmpty ? '~' : '~$rest';
}

/// Two letters for an avatar tile: `claude` -> `cl`.
String initials(String name) {
  final t = name.trim().toLowerCase();
  if (t.isEmpty) return '··';
  return t.length == 1 ? t : t.substring(0, 2);
}

/// A 40 dp duotone tile with an agent's initials.
class AgentTile extends StatelessWidget {
  const AgentTile(this.name, {super.key, this.color});
  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final tone = color ?? c.muted;
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(initials(name),
            style: HxType.mono.copyWith(color: c.foreground, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
