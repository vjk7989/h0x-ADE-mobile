import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/state/key_input.dart';

List<String> names(List<Key> ks) => [for (final k in ks) k.name];

void main() {
  group('keysFromOutput', () {
    test('typed text becomes one key per character', () {
      expect(names(keysFromOutput('ls')), ['l', 's']);
      expect(names(keysFromOutput('A')), ['shift+a']);
    });

    test('control keys', () {
      expect(names(keysFromOutput('\r')), ['enter']);
      expect(names(keysFromOutput('\t')), ['tab']);
      expect(names(keysFromOutput('\x7f')), ['backspace']);
      expect(names(keysFromOutput(' ')), ['space']);
      expect(names(keysFromOutput('\x1b')), ['esc']);
      expect(names(keysFromOutput('\x03')), ['ctrl+c']);
      expect(names(keysFromOutput('\x04')), ['ctrl+d']);
    });

    test('arrow, home, end and paging sequences', () {
      expect(
        names(keysFromOutput('\x1b[A\x1b[B\x1b[C\x1b[D')),
        ['up', 'down', 'right', 'left'],
      );
      expect(names(keysFromOutput('\x1b[H\x1b[F')), ['home', 'end']);
      expect(
        names(keysFromOutput('\x1b[3~\x1b[5~\x1b[6~')),
        ['delete', 'pageup', 'pagedown'],
      );
    });

    test('application-cursor (SS3) arrows and home/end are keys, not Esc plus letters', () {
      expect(
        names(keysFromOutput('OAOBOCOD')),
        ['up', 'down', 'right', 'left'],
      );
      expect(names(keysFromOutput('OHOF')), ['home', 'end']);
      expect(names(keysFromOutput('OAx')), ['up', 'x']);
    });

    test('Esc then a capital O with no cursor letter stays Esc and shift+o', () {
      expect(names(keysFromOutput('Oz')), ['esc', 'shift+o', 'z']);
    });

    test('an unknown escape sequence is dropped whole', () {
      expect(names(keysFromOutput('\x1b[1;5Zx')), ['x']);
    });

    test('empty input gives no keys', () {
      expect(keysFromOutput(''), isEmpty);
    });

    test('capitals are shift+letter, as core lowercases key names', () {
      expect(names(keysFromOutput('Ab')), ['shift+a', 'b']);
    });

    test('characters core has no key name for are dropped', () {
      expect(keysFromOutput('é€|~!'), isEmpty);
      expect(names(keysFromOutput('a|b')), ['a', 'b']);
    });

    test('the punctuation core knows is kept', () {
      expect(names(keysFromOutput("/-.,;=[]'")), [
        '/', '-', '.', ',', ';', '=', '[', ']', "'",
      ]);
      expect(names(keysFromOutput('5')), ['5']);
    });
  });

  group('Modifiers', () {
    test('one tap is for the next key only', () {
      final m = Modifiers()..tapCtrl();
      expect(m.ctrl, Sticky.once);
      expect(m.apply(const Key('c')).name, 'ctrl+c');
      expect(m.ctrl, Sticky.off);
      expect(m.apply(const Key('c')).name, 'c');
    });

    test('a second tap locks, a third turns it off', () {
      final m = Modifiers()
        ..tapCtrl()
        ..tapCtrl();
      expect(m.ctrl, Sticky.locked);
      expect(m.apply(Key.up).name, 'ctrl+up');
      expect(m.apply(Key.up).name, 'ctrl+up');
      m.tapCtrl();
      expect(m.ctrl, Sticky.off);
      expect(m.apply(Key.up).name, 'up');
    });

    test('Ctrl and Alt together', () {
      final m = Modifiers()
        ..tapCtrl()
        ..tapAlt();
      expect(m.apply(const Key('x')).name, 'ctrl+alt+x');
      expect(m.ctrl, Sticky.off);
      expect(m.alt, Sticky.off);
    });

    test('a key that already has the modifier is not doubled', () {
      final m = Modifiers()..tapCtrl();
      expect(m.apply(const Key('ctrl+c')).name, 'ctrl+c');
    });

    test('listeners hear changes', () {
      final m = Modifiers();
      var n = 0;
      m.addListener(() => n++);
      m.tapAlt();
      m.apply(Key.tab);
      expect(n, 2);
    });
  });
}
