import 'package:material_ui/material_ui.dart' hide Key;

import '../conn/machine_connection.dart';
import '../state/key_input.dart';
import '../theme/themes.dart';
import '../theme/type.dart';

class _K {
  const _K(this.label, this.key, {this.speak, this.wide = false});

  final String label;

  /// Null for the modifiers.
  final Key? key;
  final String? speak;

  /// Home and End: a 56 dp target.
  final bool wide;
}

const _keys = [
  _K('Esc', Key.esc),
  _K('Tab', Key.tab),
  _K('Ctrl', null),
  _K('Alt', null),
  _K('↑', Key.up, speak: 'Up'),
  _K('↓', Key.down, speak: 'Down'),
  _K('←', Key.left, speak: 'Left'),
  _K('→', Key.right, speak: 'Right'),
  _K('|', Key('|'), speak: 'Pipe'),
  _K('~', Key('~'), speak: 'Tilde'),
  _K('/', Key('/'), speak: 'Slash'),
  _K('-', Key('-'), speak: 'Dash'),
  _K('Home', Key('home'), wide: true),
  _K('End', Key('end'), wide: true),
];

/// The last row above the keyboard: Esc Tab Ctrl Alt arrows | ~ / - Home End
/// scroll sideways, Enter stays pinned on the right. Ctrl and Alt are
/// sticky: one tap is for the next key only, a second tap locks.
class KeyBar extends StatelessWidget {
  const KeyBar({
    super.key,
    required this.modifiers,
    required this.onKeys,
    this.enabled = true,
    this.disabledReason,
  });

  final Modifiers modifiers;
  final void Function(List<Key> keys) onKeys;
  final bool enabled;

  /// Why the keys are off, read by the screen reader.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final extra = scale - 1;
    final capW = 40 + 28 * extra;
    final capH = 36 + 20 * extra;
    final targetH = (capH + 8 + 8 * extra).clamp(48.0, 72.0);
    final barH = targetH;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Container(
        height: barH,
        decoration: BoxDecoration(
          color: dark ? c.chrome : const Color(0xFFEFEFEC),
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: ListenableBuilder(
          listenable: modifiers,
          builder: (context, _) => Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 4, right: 28),
                      children: [
                        for (final k in _keys) _cap(context, k, capW, capH, targetH),
                      ],
                    ),
                    // A 28 dp fade shows that more keys follow.
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 28,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                (dark ? c.chrome : const Color(0xFFEFEFEC))
                                    .withAlpha(0),
                                dark ? c.chrome : const Color(0xFFEFEFEC),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _enter(context, capH, targetH),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cap(
    BuildContext context,
    _K k,
    double capW,
    double capH,
    double targetH,
  ) {
    final c = context.hx.colors;
    final sticky = switch (k.label) {
      'Ctrl' => modifiers.ctrl,
      'Alt' => modifiers.alt,
      _ => null,
    };
    final isMod = k.key == null;
    final locked = sticky == Sticky.locked;
    final once = sticky == Sticky.once;
    final fill = locked
        ? c.accent
        : once
        ? c.selected
        : c.card;
    final fg = locked ? c.accentForeground : c.foreground;
    final speak = k.speak ?? k.label;
    final label = !isMod
        ? 'Key $speak'
        : locked
        ? 'Key $speak, locked'
        : once
        ? 'Key $speak, on for next key'
        : 'Key $speak, off';
    void tap() {
      if (!enabled) return;
      if (k.label == 'Ctrl') {
        modifiers.tapCtrl();
      } else if (k.label == 'Alt') {
        modifiers.tapAlt();
      } else {
        onKeys([modifiers.apply(k.key!)]);
      }
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled || disabledReason == null
          ? label
          : '$label, unavailable: $disabledReason',
      excludeSemantics: true,
      onTap: tap,
      child: InkWell(
        onTap: enabled ? tap : null,
        child: Container(
          constraints: BoxConstraints(
            minWidth: k.wide ? 56 : (capW + 8).clamp(48.0, 76.0),
            minHeight: targetH,
          ),
          alignment: Alignment.center,
          child: Container(
            width: k.wide ? capW + 16 : capW,
            height: capH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: once ? c.accent : c.hairline,
                width: once ? 1.5 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      k.label,
                      maxLines: 1,
                      style: HxType.mono.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                if (locked)
                  Positioned(
                    bottom: 4,
                    child: Container(width: 12, height: 2, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enter(BuildContext context, double capH, double targetH) {
    final c = context.hx.colors;
    void tap() {
      if (enabled) onKeys([modifiers.apply(Key.enter)]);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled || disabledReason == null
          ? 'Key Enter'
          : 'Key Enter, unavailable: $disabledReason',
      excludeSemantics: true,
      onTap: tap,
      child: InkWell(
        onTap: enabled ? tap : null,
        child: Container(
          constraints: BoxConstraints(minWidth: 64, minHeight: targetH),
          alignment: Alignment.center,
          child: Container(
            width: 56,
            height: capH,
            decoration: BoxDecoration(
              color: c.solid,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.keyboard_return,
              size: 20,
              color: c.solidForeground,
            ),
          ),
        ),
      ),
    );
  }
}
