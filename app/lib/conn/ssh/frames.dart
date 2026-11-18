import 'dart:typed_data';

/// Core's framed mode (h0x-core crates/h0x-core/src/wire.rs):
/// `[channel u32 LE][kind u8][len u32 LE][payload]`.
const frameHeader = 9;
const maxPayload = 16 << 20;

/// Payload bytes: JSON-RPC on channel 0, terminal bytes on streams.
const kindData = 0;

/// u32 LE: the receiver consumed this many bytes; the sender may send more.
const kindCredit = 1;

/// The channel is over (JSON reason from the core, empty from a client).
const kindClose = 2;

/// u16 LE cols, u16 LE rows.
const kindResize = 3;

/// Credit a stream starts with before the receiver acknowledges anything.
const streamWindow = 256 * 1024;

class FrameException implements Exception {
  FrameException(this.message);
  final String message;
  @override
  String toString() => 'FrameException: $message';
}

class Frame {
  const Frame(this.channel, this.kind, this.payload);
  final int channel;
  final int kind;
  final Uint8List payload;
}

Uint8List encodeFrame(int channel, int kind, List<int> payload) {
  if (payload.length > maxPayload) {
    throw FrameException('payload of ${payload.length} bytes exceeds $maxPayload');
  }
  final out = Uint8List(frameHeader + payload.length);
  final d = ByteData.sublistView(out);
  d.setUint32(0, channel, Endian.little);
  out[4] = kind;
  d.setUint32(5, payload.length, Endian.little);
  out.setRange(frameHeader, out.length, payload);
  return out;
}

/// Splits a byte stream into frames: a frame may arrive across several reads,
/// and one read may hold several frames. A length over [maxPayload] throws
/// (the caller must close the connection, as core does).
class FrameDecoder {
  Uint8List _buf = Uint8List(0);

  /// Bytes held that do not yet make a whole frame.
  int get pending => _buf.length;

  List<Frame> add(List<int> chunk) {
    if (chunk.isNotEmpty) {
      final next = Uint8List(_buf.length + chunk.length);
      next.setRange(0, _buf.length, _buf);
      next.setRange(_buf.length, next.length, chunk);
      _buf = next;
    }
    final frames = <Frame>[];
    var at = 0;
    while (_buf.length - at >= frameHeader) {
      final d = ByteData.sublistView(_buf, at, at + frameHeader);
      final len = d.getUint32(5, Endian.little);
      if (len > maxPayload) {
        throw FrameException('frame of $len bytes exceeds $maxPayload');
      }
      if (_buf.length - at - frameHeader < len) break;
      final start = at + frameHeader;
      frames.add(Frame(
        d.getUint32(0, Endian.little),
        _buf[at + 4],
        Uint8List.fromList(_buf.sublist(start, start + len)),
      ));
      at = start + len;
    }
    if (at > 0) _buf = Uint8List.fromList(_buf.sublist(at));
    return frames;
  }
}
