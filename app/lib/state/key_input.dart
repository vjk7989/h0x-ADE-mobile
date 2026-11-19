import 'package:flutter/foundation.dart' hide Key;

import '../conn/machine_connection.dart';

/// A sticky modifier (Ctrl or Alt) of the key bar.
enum Sticky {
  off,

  /// One tap: applies to the next key only.
  once,

  /// Second tap: stays until tapped again.
  locked,
}

/// The Ctrl and Alt state of the key bar. A modifier turned on with one tap
/// is spent by the next key; a second tap locks it until it is tapped off.
class Modifiers extends ChangeNotifier {
  Sticky ctrl = Sticky.off;
  Sticky alt = Sticky.off;

  static Sticky _next(Sticky s) => switch (s) {
    Sticky.off => Sticky.once,
    Sticky.once => Sticky.locked,
    Sticky.locked => Sticky.off,
  };

  void tapCtrl() {
    ctrl = _next(ctrl);
    notifyListeners();
  }

  void tapAlt() {
    alt = _next(alt);
    notifyListeners();
  }

  /// [key] with the modifiers that are on, spending the one-shot ones.
  /// Names follow core: `ctrl+c`, `alt+x`, `ctrl+alt+up`.
  Key apply(Key key) {
    var name = key.name;
    var changed = false;
    if (alt != Sticky.off && !name.contains('alt+')) {
      name = 'alt+$name';
      if (alt == Sticky.once) {
        alt = Sticky.off;
        changed = true;
      }
    }
    if (ctrl != Sticky.off && !name.contains('ctrl+')) {
      name = 'ctrl+$name';
      if (ctrl == Sticky.once) {
        ctrl = Sticky.off;
        changed = true;
      }
    }
    if (changed) notifyListeners();
    return Key(name);
  }
}

const _csi = {
  'A': 'up',
  'B': 'down',
  'C': 'right',
  'D': 'left',
  'H': 'home',
  'F': 'end',
};

/// The characters core's key table names (crates/h0x-core/src/keys.rs):
/// lowercase letters, digits and these. Capitals go as shift+letter.
final _coreChars = RegExp(r"^[a-z0-9`\\[\],=\-.';/]$");

const _tilde = {'3': 'delete', '5': 'pageup', '6': 'pagedown'};

/// What the terminal view's `onOutput` wrote (typed text and escape
/// sequences) as core key names, so typing straight into the terminal sends
/// keys as typed. Sequences with no key name are dropped.
List<Key> keysFromOutput(String data) {
  final keys = <Key>[];
  final runes = data.runes.toList();
  var i = 0;
  while (i < runes.length) {
    final c = runes[i];
    if (c == 0x1b) {
      if (i + 2 < runes.length && runes[i + 1] == 0x5b /* [ */) {
        // CSI: ESC [ <letter>  or  ESC [ <digit> ~
        final f = String.fromCharCode(runes[i + 2]);
        if (_csi.containsKey(f)) {
          keys.add(Key(_csi[f]!));
          i += 3;
          continue;
        }
        if (i + 3 < runes.length &&
            runes[i + 3] == 0x7e /* ~ */ &&
            _tilde.containsKey(f)) {
          keys.add(Key(_tilde[f]!));
          i += 4;
          continue;
        }
        // Unknown sequence: drop it whole, up to its final byte.
        var j = i + 2;
        while (j < runes.length && runes[j] >= 0x20 && runes[j] <= 0x3f) {
          j++;
        }
        i = j + 1;
        continue;
      }
      keys.add(Key.esc);
      i++;
      continue;
    }
    i++;
    if (c == 0x0d || c == 0x0a) {
      keys.add(Key.enter);
    } else if (c == 0x09) {
      keys.add(Key.tab);
    } else if (c == 0x7f || c == 0x08) {
      keys.add(const Key('backspace'));
    } else if (c == 0x20) {
      keys.add(const Key('space'));
    } else if (c >= 0x01 && c <= 0x1a) {
      keys.add(Key('ctrl+${String.fromCharCode(0x60 + c)}'));
    } else if (c >= 0x41 && c <= 0x5a) {
      // Core lowercases key names: a capital is shift+letter.
      keys.add(Key('shift+${String.fromCharCode(c + 0x20)}'));
    } else if (c >= 0x20 && c < 0x7f && _coreChars.hasMatch(String.fromCharCode(c))) {
      keys.add(Key(String.fromCharCode(c)));
    }
    // Anything else has no core key name (terminal.keys has no raw text);
    // it is dropped. Compose and Send carry such text.
  }
  return keys;
}
