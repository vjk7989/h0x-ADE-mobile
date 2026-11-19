import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hyperox/conn/ssh/core_rpc.dart';
import 'package:hyperox/conn/ssh/frames.dart';

/// An in-memory ByteLink: [push] plays bytes core would send; what the client
/// writes is kept in [written].
class MemLink implements ByteLink {
  final _in = StreamController<List<int>>();
  final written = BytesBuilder();
  var closed = false;

  @override
  Stream<List<int>> get input => _in.stream;

  @override
  void write(List<int> bytes) => written.add(bytes);

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void push(List<int> bytes) => _in.add(bytes);

  void end() => _in.close();

  /// The first written line (the hello request), parsed.
  Map<String, dynamic> get helloRequest {
    final all = written.toBytes();
    final nl = all.indexOf(0x0a);
    return jsonDecode(utf8.decode(all.sublist(0, nl))) as Map<String, dynamic>;
  }

  /// Frames written after the hello line.
  List<Frame> get sentFrames {
    final all = written.toBytes();
    final nl = all.indexOf(0x0a);
    return FrameDecoder().add(all.sublist(nl + 1));
  }

  /// JSON bodies of the channel-0 frames the client sent.
  List<Map<String, dynamic>> get sentCalls => [
        for (final f in sentFrames)
          if (f.channel == 0 && f.kind == kindData)
            jsonDecode(utf8.decode(f.payload)) as Map<String, dynamic>
      ];
}

Uint8List jsonFrame(int channel, Object body) =>
    encodeFrame(channel, kindData, utf8.encode(jsonEncode(body)));

Uint8List helloReply({Object? id = 1, bool framed = true}) => Uint8List.fromList(utf8.encode(
    '${jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'generation': 1,
            'version': '0.0.0',
            'core': {'id': 'abc', 'name': 'box'},
            'framed': framed,
            'methods': ['terminal.list'],
            'features': [],
          }
        })}\n'));

Uint8List cat(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

/// Lets queued microtasks and stream events run.
Future<void> settle() => Future<void>.delayed(Duration.zero);
