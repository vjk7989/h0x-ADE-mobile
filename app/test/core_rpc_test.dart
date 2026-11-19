import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart' show TermSize;
import 'package:hyperox/conn/ssh/core_rpc.dart';
import 'package:hyperox/conn/ssh/frames.dart';

import 'support/mem_link.dart';

void main() {
  group('frames', () {
    test('encode is byte-exact per wire.rs', () {
      expect(
        encodeFrame(1, kindData, [0x61, 0x62, 0x63]),
        [1, 0, 0, 0, /*kind*/ 0, 3, 0, 0, 0, 0x61, 0x62, 0x63],
      );
      expect(encodeFrame(0x01020304, kindCredit, const []),
          [4, 3, 2, 1, 1, 0, 0, 0, 0]);
    });

    test('round trip, including an empty payload', () {
      final d = FrameDecoder();
      final out = d.add(cat([
        encodeFrame(7, kindData, utf8.encode('hi')),
        encodeFrame(8, kindClose, const []),
      ]));
      expect(out, hasLength(2));
      expect([out[0].channel, out[0].kind, utf8.decode(out[0].payload)], [7, 0, 'hi']);
      expect([out[1].channel, out[1].kind, out[1].payload.length], [8, 2, 0]);
    });

    test('a frame split across reads, byte by byte', () {
      final d = FrameDecoder();
      final bytes = encodeFrame(3, kindData, utf8.encode('split me'));
      final got = <Frame>[];
      for (final b in bytes) {
        got.addAll(d.add([b]));
      }
      expect(got, hasLength(1));
      expect(utf8.decode(got.single.payload), 'split me');
      expect(d.pending, 0);
    });

    test('several frames in one read, then a partial one', () {
      final d = FrameDecoder();
      final a = encodeFrame(1, kindData, [1]);
      final b = encodeFrame(2, kindData, [2, 2]);
      final c = encodeFrame(3, kindData, [3, 3, 3]);
      final first = d.add(cat([a, b, c.sublist(0, 11)]));
      expect(first.map((f) => f.channel), [1, 2]);
      expect(d.add(c.sublist(11)).map((f) => f.channel), [3]);
    });

    test('a length over the limit throws as soon as the header is in', () {
      final h = ByteData(frameHeader)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(5, maxPayload + 1, Endian.little);
      expect(() => FrameDecoder().add(h.buffer.asUint8List()),
          throwsA(isA<FrameException>()));
    });

    test('the limit itself is allowed to start (waits for the payload)', () {
      final h = ByteData(frameHeader)..setUint32(5, maxPayload, Endian.little);
      expect(FrameDecoder().add(h.buffer.asUint8List()), isEmpty);
    });

    test('encoding over the limit is refused', () {
      expect(() => encodeFrame(0, kindData, Uint8List(maxPayload + 1)),
          throwsA(isA<FrameException>()));
    });
  });

  group('CoreRpc', () {
    late MemLink link;
    late CoreRpc rpc;
    setUp(() {
      link = MemLink();
      rpc = CoreRpc(link);
    });

    Future<void> ready() async {
      final h = rpc.hello();
      await settle();
      link.push(helloReply());
      await h;
    }

    test('hello asks for framed mode at generation 1', () async {
      final h = rpc.hello();
      expect(link.helloRequest['method'], 'hello');
      expect(link.helloRequest['params'], {'generation': 1, 'framed': true});
      link.push(helloReply());
      final r = await h;
      expect(r['core']['name'], 'box');
    });

    test('bytes after the hello line in the same read are frames', () async {
      final note = rpc.notifications.first;
      final h = rpc.hello();
      link.push(cat([
        helloReply(),
        jsonFrame(0, {'jsonrpc': '2.0', 'method': 'ping', 'params': {'n': 1}}),
      ]));
      await h;
      final n = await note;
      expect(n.method, 'ping');
      expect(n.params, {'n': 1});
    });

    test('calls use ids from 2 on channel 0', () async {
      await ready();
      final f = rpc.call('terminal.list');
      link.push(jsonFrame(0, {'jsonrpc': '2.0', 'id': 2, 'result': {'terminals': []}}));
      expect(await f, {'terminals': []});
      expect(link.sentCalls.single['method'], 'terminal.list');
      expect(link.sentCalls.single['id'], 2);
      expect(link.sentCalls.single['jsonrpc'], '2.0');
    });

    test('a hello reply split mid-line still works', () async {
      final h = rpc.hello();
      final r = helloReply();
      link.push(r.sublist(0, 10));
      await settle();
      link.push(r.sublist(10));
      expect((await h)['framed'], true);
    });

    test('replies match their ids even out of order', () async {
      await ready();
      final a = rpc.call('terminal.read', {'terminal': 't1'});
      final b = rpc.call('terminal.read', {'terminal': 't2'});
      link.push(cat([
        jsonFrame(0, {'jsonrpc': '2.0', 'id': 3, 'result': 'second'}),
        jsonFrame(0, {'jsonrpc': '2.0', 'id': 2, 'result': 'first'}),
      ]));
      expect(await a, 'first');
      expect(await b, 'second');
    });

    test('a core error is a typed exception with kind and hint', () async {
      await ready();
      final f = rpc.call('terminal.read', {'terminal': 'zz'});
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'error': {
          'code': -32000,
          'message': 'no such terminal',
          'data': {'kind': 'not_found', 'hint': 'try ls'}
        }
      }));
      await expectLater(
        f,
        throwsA(isA<CoreRpcException>()
            .having((e) => e.kind, 'kind', 'not_found')
            .having((e) => e.hint, 'hint', 'try ls')
            .having((e) => e.message, 'message', 'no such terminal')),
      );
    });

    test('an unsupported generation fails hello with its kind', () async {
      final h = rpc.hello();
      link.push(utf8.encode('${jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'error': {
              'code': -32000,
              'message': 'protocol generation 9 not supported',
              'data': {'kind': 'unsupported_generation', 'hint': 'this core speaks generation 1'}
            }
          })}\n'));
      await expectLater(h,
          throwsA(isA<CoreRpcException>().having((e) => e.kind, 'kind', 'unsupported_generation')));
      expect(link.closed, isTrue);
    });

    test('a login banner before the JSON is flagged', () async {
      final h = rpc.hello();
      link.push(utf8.encode('Welcome to box!\n'));
      await expectLater(
          h, throwsA(isA<CoreProtocolException>().having((e) => e.banner, 'banner', true)));
    });

    test('output with no newline before the pipe ends is flagged as noise', () async {
      final h = rpc.hello();
      link.push(utf8.encode('sh: h0x-core: not found'));
      link.end();
      await expectLater(
          h, throwsA(isA<CoreProtocolException>().having((e) => e.banner, 'banner', true)));
    });

    test('hello that does not switch to framed fails', () async {
      final h = rpc.hello();
      link.push(helloReply(framed: false));
      await expectLater(h, throwsA(isA<CoreProtocolException>()));
    });

    test('an oversize frame fails everything and closes the pipe', () async {
      await ready();
      final f = rpc.call('terminal.list');
      final h = ByteData(frameHeader)..setUint32(5, maxPayload + 1, Endian.little);
      link.push(h.buffer.asUint8List());
      await expectLater(f, throwsA(isA<CoreProtocolException>()));
      expect(link.closed, isTrue);
      await expectLater(rpc.call('terminal.list'), throwsA(isA<CoreProtocolException>()));
    });

    test('the pipe ending fails pending calls and completes closed', () async {
      await ready();
      final f = rpc.call('terminal.list');
      link.end();
      await expectLater(f, throwsA(isA<CoreProtocolException>()));
      await rpc.closed;
    });

    test('unknown frame kinds and unknown channels are ignored', () async {
      await ready();
      link.push(cat([
        encodeFrame(0, 99, [1]),
        encodeFrame(55, kindData, [1]),
        encodeFrame(55, 77, [1]),
      ]));
      final f = rpc.call('terminal.list');
      link.push(jsonFrame(0, {'jsonrpc': '2.0', 'id': 2, 'result': 1}));
      expect(await f, 1);
    });

    test('attach: data frames behind the reply in one read are not lost', () async {
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24, history: 100);
      link.push(cat([
        jsonFrame(0, {
          'jsonrpc': '2.0',
          'id': 2,
          'result': {
            'channel': 5,
            'terminal': {'address': 't1'},
            'resize_notifications': true,
            'automatic_input': false,
          }
        }),
        encodeFrame(5, kindData, utf8.encode('\x1b[31mred\x1b[0m')),
      ]));
      final att = await f;
      final req = link.sentCalls.single;
      expect(req['method'], 'terminal.attach');
      expect(req['params'],
          {
            'terminal': 't1',
            'cols': 80,
            'rows': 24,
            'history': 100,
            'observe': true,
            'resize_notifications': true,
          });
      expect(att.terminal['address'], 't1');
      final first = await att.data.first;
      expect(utf8.decode(first), '\x1b[31mred\x1b[0m');
    });

    test('credit: the client acknowledges what it consumed, in batches', () async {
      link = MemLink();
      rpc = CoreRpc(link, creditEvery: 100);
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'channel': 9, 'terminal': {}}
      }));
      final att = await f;
      att.data.listen((_) {});
      link.push(encodeFrame(9, kindData, Uint8List(60)));
      await settle();
      expect(link.sentFrames.where((f) => f.kind == kindCredit), isEmpty,
          reason: 'under the batch size');
      link.push(encodeFrame(9, kindData, Uint8List(60)));
      await settle();
      final credits = link.sentFrames.where((f) => f.kind == kindCredit).toList();
      expect(credits, hasLength(1));
      expect(credits.single.channel, 9);
      expect(ByteData.sublistView(credits.single.payload).getUint32(0, Endian.little), 120);
    });

    test('backpressure: a paused listener holds back credit until it resumes', () async {
      link = MemLink();
      rpc = CoreRpc(link, creditEvery: 60);
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'channel': 9, 'terminal': {}}
      }));
      final att = await f;
      final got = <int>[];
      final sub = att.data.listen((c) => got.addAll(c));
      sub.pause();
      for (var i = 0; i < 5; i++) {
        link.push(encodeFrame(9, kindData, Uint8List(60)));
      }
      await settle();
      expect(got, isEmpty);
      expect(link.sentFrames.where((f) => f.kind == kindCredit), isEmpty,
          reason: 'nothing consumed, so core stays stopped at its window');
      sub.resume();
      await settle();
      expect(got, hasLength(300));
      final credited = link.sentFrames
          .where((f) => f.kind == kindCredit)
          .map((f) => ByteData.sublistView(f.payload).getUint32(0, Endian.little))
          .fold<int>(0, (a, b) => a + b);
      expect(credited, 300, reason: 'every chunk handed over is acknowledged');
    });

    test('no listener at all: nothing is acknowledged, data waits', () async {
      link = MemLink();
      rpc = CoreRpc(link, creditEvery: 10);
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'channel': 9, 'terminal': {}}
      }));
      final att = await f;
      link.push(encodeFrame(9, kindData, Uint8List(50)));
      await settle();
      expect(link.sentFrames.where((f) => f.kind == kindCredit), isEmpty);
      final first = await att.data.first;
      expect(first, hasLength(50));
    });

    test('RESIZE frames become sizes; the attach size comes from the terminal', () async {
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {
          'channel': 4,
          'terminal': {'cols': 120, 'rows': 40}
        }
      }));
      final att = await f;
      expect(att.initial, const TermSize(120, 40));
      final sizes = att.sizes.take(2).toList();
      final d = ByteData(4)
        ..setUint16(0, 132, Endian.little)
        ..setUint16(2, 43, Endian.little);
      link.push(encodeFrame(4, kindResize, d.buffer.asUint8List()));
      link.push(encodeFrame(4, kindResize, [1, 2, 3])); // malformed: ignored
      link.push(encodeFrame(4, kindResize, d.buffer.asUint8List()));
      expect(await sizes, [const TermSize(132, 43), const TermSize(132, 43)]);
    });

    test('a terminal without a size falls back to 80x24', () async {
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'channel': 4, 'terminal': {}}
      }));
      expect((await f).initial, const TermSize(80, 24));
    });

    test('cancelling the data subscription detaches (CLOSE sent)', () async {
      await ready();
      final f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'channel': 4, 'terminal': {}}
      }));
      final att = await f;
      final sub = att.data.listen((_) {});
      await sub.cancel();
      await settle();
      expect(link.sentFrames.where((f) => f.kind == kindClose).single.channel, 4);
    });

    test('detaching sends CLOSE on the channel; core CLOSE ends the stream', () async {
      await ready();
      var f = rpc.attach(terminal: 't1', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'channel': 4, 'terminal': {}}
      }));
      final a = await f;
      await a.close();
      final close = link.sentFrames.singleWhere((f) => f.kind == kindClose);
      expect(close.channel, 4);
      expect(close.payload, isEmpty);

      f = rpc.attach(terminal: 't2', cols: 80, rows: 24);
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 3,
        'result': {'channel': 6, 'terminal': {}}
      }));
      final b = await f;
      final done = b.data.toList();
      link.push(cat([
        encodeFrame(6, kindData, [65]),
        encodeFrame(6, kindClose, utf8.encode('{"reason":"finished"}')),
      ]));
      expect((await done).expand((x) => x), [65]);
    });

    test('subscribe: events split across frames and joined in one are parsed', () async {
      await ready();
      final f = rpc.subscribe(labels: {'app': 'x'});
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {
          'channel': 3,
          'seq': 12,
          'terminals': [
            {'address': 't1'}
          ]
        }
      }));
      final sub = await f;
      expect(sub.seq, 12);
      expect(sub.terminals.single['address'], 't1');
      expect(link.sentCalls.single['params'], {
        'labels': {'app': 'x'}
      });
      final got = sub.events.take(3).toList();
      const l1 = '{"jsonrpc":"2.0","method":"event","params":{"type":"status","terminal":"t1","seq":13}}\n';
      const l2 = '{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":13}}\n';
      final both = utf8.encode('$l1$l2');
      link.push(encodeFrame(3, kindData, both.sublist(0, 30)));
      link.push(encodeFrame(3, kindData, both.sublist(30)));
      link.push(encodeFrame(3, kindData,
          utf8.encode('{"jsonrpc":"2.0","method":"missed","params":{"seq":20,"terminals":[]}}\n')));
      final events = await got;
      expect(events.map((e) => e.method), ['event', 'heartbeat', 'missed']);
      expect(events.first.params['type'], 'status');
    });

    test('subscribe without a channel (plain mode) is a protocol error', () async {
      await ready();
      final f = rpc.subscribe();
      link.push(jsonFrame(0, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'seq': 1, 'terminals': []}
      }));
      await expectLater(f, throwsA(isA<CoreProtocolException>()));
    });
  });
}
