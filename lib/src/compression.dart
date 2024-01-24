import 'dart:io';
import 'dart:typed_data';

import 'packet.dart';
import 'utils.dart';

class PacketCompressor {
  List<int> compress(
    List<int> packets,
    int sequence,
    int threshold, {
    int maxPacketSize = 0xffffff,
  }) {
    assert(maxPacketSize <= 0xffffff, "maxPacketSize is up to 0xffffff");

    if (packets.isEmpty) {
      return [0x00, 0x00, 0x00, sequence, 0x00, 0x00, 0x00];
    }

    final cursor = Cursor.zero();
    final buffer = BytesBuilder();

    var available = maxPacketSize;
    var payload = <int>[];

    void packAndClear() {
      if (payload.isNotEmpty) {
        if (payload.length < threshold) {
          writeInteger(buffer, 3, payload.length);
          writeInteger(buffer, 1, sequence++);
          writeInteger(buffer, 3, 0);
          writeBytes(buffer, payload);
        } else {
          final uncompressedLen = payload.length;
          final compressed = zlib.encode(payload);

          writeInteger(buffer, 3, compressed.length);
          writeInteger(buffer, 1, sequence++);
          writeInteger(buffer, 3, uncompressedLen);
          writeBytes(buffer, compressed);
        }

        available = maxPacketSize;
        payload.clear();
      }
    }

    for (;;) {
      assert(cursor.position <= packets.length, "cursor is out of range");

      if (cursor.position == packets.length) {
        if (payload.isNotEmpty) {
          packAndClear();
        }

        return buffer.takeBytes();
      }

      assert(
        packets.length >= cursor.position + standardPacketHeaderLength,
        "invalid standard packet length",
      );

      var len = readInteger(packets, cursor.clone(), 3);
      if ((len + standardPacketHeaderLength) > available) {
        packAndClear();
      }

      payload.addAll(readBytes(packets, cursor, len + standardPacketHeaderLength));
      available -= len + standardPacketHeaderLength;
    }
  }

  List<int> decompress(
    List<int> packets, [
    Cursor? cursor,
  ]) {
    if (packets.isEmpty) {
      return [];
    }
    cursor ??= Cursor.zero();

    final buffer = BytesBuilder();

    for (;;) {
      assert(cursor.position <= packets.length, "cursor is out of range");

      if (cursor.position == packets.length) {
        return buffer.takeBytes();
      }
      assert(
        packets.length >= cursor.position + 7,
        "invalid compressed packet length",
      );

      final compressedLen = readInteger(packets, cursor, 3);
      readInteger(packets, cursor, 1);
      final uncompressedLen = readInteger(packets, cursor, 3);

      if (uncompressedLen == 0) {
        buffer.add(readBytes(packets, cursor, compressedLen));
      } else {
        final decompressed =
            zlib.decode(readBytes(packets, cursor, compressedLen));
        assert(
          decompressed.length == uncompressedLen,
          "decompressed payload held an incorrect length",
        );
        buffer.add(decompressed);
      }
    }
  }
}



class CompressedPacketBufferView {
  final List<int> _buffer;

  final Cursor _cursor = Cursor.zero();

  CompressedPacketBufferView(this._buffer);

  int get numberOfCompressedPackets => countCompressedPackets(_buffer);

  void resetCursor() {
    _cursor.reset();
  }
}

class CompressedPacketHeaderView {
  final Uint8List _buffer;

  const CompressedPacketHeaderView(this._buffer);

  int get length => readInteger(_buffer, Cursor.zero(), 3);

  int get sequence => readInteger(_buffer, Cursor.from(3), 1);

  int get lengthBeforeCompress => readInteger(_buffer, Cursor.from(4), 3);

  bool get compressed => lengthBeforeCompress == 0;

  @override
  String toString() {
    return "CompressedPacketHeaderView(length: $length, sequence: $sequence, lengthBeforeCompress: $lengthBeforeCompress)";
  }
}
