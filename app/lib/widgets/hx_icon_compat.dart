import 'package:material_ui/material_ui.dart' as m show Icon;
import 'package:material_ui/material_ui.dart'
    show BuildContext, IconData, IconTheme, Icons, Color, StatelessWidget, Widget;

import 'hx_icons.dart';

/// Material icon -> the Lucide icon HyperOx draws instead (tokens section
/// 10: Lucide, the desktop's set). Built once; the key is the code point.
final Map<int, String> _lucideFor = {
  Icons.arrow_back.codePoint: 'arrow-left',
  Icons.copy_outlined.codePoint: 'copy',
  Icons.ios_share.codePoint: 'share',
  Icons.stop_circle_outlined.codePoint: 'stop',
  Icons.notifications_none.codePoint: 'bell',
  Icons.check.codePoint: 'check',
  Icons.check_circle_outline.codePoint: 'check-circle',
  Icons.content_paste.codePoint: 'paste',
  Icons.send.codePoint: 'send',
  Icons.more_vert.codePoint: 'more',
  Icons.search.codePoint: 'search',
  Icons.close.codePoint: 'x',
  Icons.inbox_outlined.codePoint: 'inbox',
  Icons.add.codePoint: 'plus',
  Icons.push_pin.codePoint: 'pin',
  Icons.cloud_outlined.codePoint: 'cloud',
  Icons.terminal.codePoint: 'square-terminal',
  Icons.chevron_right.codePoint: 'chevron-right',
  Icons.desktop_windows_outlined.codePoint: 'monitor',
  Icons.dns_outlined.codePoint: 'server',
  Icons.edit_outlined.codePoint: 'pencil',
  Icons.key_outlined.codePoint: 'key',
  Icons.vpn_key_outlined.codePoint: 'key',
  Icons.delete_outline.codePoint: 'trash',
  Icons.gpp_maybe_outlined.codePoint: 'shield-alert',
  Icons.person_outline.codePoint: 'user',
  Icons.palette_outlined.codePoint: 'palette',
  Icons.refresh.codePoint: 'refresh',
  Icons.login.codePoint: 'enter',
  Icons.code.codePoint: 'github',
  Icons.mail_outline.codePoint: 'mail',
  Icons.computer_outlined.codePoint: 'machines',
  Icons.dashboard_outlined.codePoint: 'spaces',
  Icons.cloud_off_outlined.codePoint: 'wifi-off',
  Icons.warning_amber_outlined.codePoint: 'triangle',
  Icons.error_outline.codePoint: 'alert',
  Icons.info_outline.codePoint: 'info',
  Icons.unfold_more.codePoint: 'updown',
  Icons.play_arrow_outlined.codePoint: 'play',
  Icons.keyboard_arrow_down.codePoint: 'chevron-down',
  Icons.keyboard_arrow_right.codePoint: 'chevron-right',
  Icons.edit_note.codePoint: 'square-pen',
  Icons.circle.codePoint: 'circle',
  Icons.checklist.codePoint: 'todo',
  Icons.settings_outlined.codePoint: 'settings',
  Icons.keyboard_return.codePoint: 'enter',
  Icons.fingerprint.codePoint: 'fingerprint',
};

/// The name of the Lucide icon that replaces [icon], or null.
String? lucideNameFor(IconData icon) => _lucideFor[icon.codePoint];

/// A drop-in for the Material `Icon`: screens keep writing `Icon(Icons.x)`,
/// and the glyph drawn is the Lucide one (an icon with no Lucide twin falls
/// back to the Material glyph).
class Icon extends StatelessWidget {
  const Icon(this.icon, {super.key, this.size, this.color});

  final IconData? icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final data = icon;
    final theme = IconTheme.of(context);
    final name = data == null ? null : lucideNameFor(data);
    if (name == null) return m.Icon(data, size: size, color: color);
    return HxIcon(name, size: size ?? theme.size ?? 24, color: color ?? theme.color);
  }
}
