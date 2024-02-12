import 'dart:io';
import 'dart:typed_data';

import 'utils.dart';

class PacketCompressor {
  List<int> compress(
    List<int> buffer,
    int sequence,
    int threshold, {
    int maxPacketSize = 0xffffff,
  }) {
    assert(maxPacketSize <= 0xffffff);
    if (buffer.isEmpty) {
      return [0x00, 0x00, 0x00, sequence, 0x00, 0x00, 0x00];
    }
    final maxPayloadSize = maxPacketSize - compressedPacketHeaderLength;
    final writer = BytesBuilder();
    final payloadWriter = BytesBuilder();
    int offset = 0;
    for (;;) {
      if (offset == buffer.length) {
        break;
      }
      final payloadLength = readInteger(buffer, Cursor.from(offset), 3);
      assert(payloadLength <= 0xffffff);

      int remaining = standardPacketHeaderLength + payloadLength;
      for (;;) {
        if (remaining == 0) {
          break;
        }
        final payloadRemaining = maxPayloadSize - payloadWriter.length;
        if (payloadRemaining == 0) {
          _compressAndPack(
              writer, sequence++, payloadWriter.takeBytes(), threshold);
        } else if (remaining > payloadRemaining) {
          payloadWriter.add(
              getUnmodifiableRangeEfficiently(buffer, offset, offset + payloadRemaining));
          _compressAndPack(
              writer, sequence++, payloadWriter.takeBytes(), threshold);
          offset += payloadRemaining;
          remaining -= payloadRemaining;
        } else {
          payloadWriter
              .add(getUnmodifiableRangeEfficiently(buffer, offset, offset + remaining));
          offset += remaining;
          remaining = 0;
        }
      }
    }
    if (payloadWriter.length > 0) {
      _compressAndPack(
          writer, sequence++, payloadWriter.takeBytes(), threshold);
    }
    return writer.takeBytes();
  }

  void _compressAndPack(
      BytesBuilder writer, int sequence, List<int> payload, int threshold) {
    if (payload.length > threshold) {
      final compressedPayload = zlib.encode(payload);
      writeInteger(writer, 3, compressedPayload.length);
      writeInteger(writer, 1, sequence);
      writeInteger(writer, 3, payload.length);
      writeBytes(writer, compressedPayload);
    } else {
      writeInteger(writer, 3, payload.length);
      writeInteger(writer, 1, sequence);
      writeInteger(writer, 3, 0);
      writeBytes(writer, payload);
    }
  }

  List<int> decompress(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();

    final writer = BytesBuilder();

    for (;;) {
      assert(cursor.position <= buffer.length, "cursor is out of range");

      if (cursor.position == buffer.length) {
        return writer.takeBytes();
      }
      assert(
        buffer.length >= cursor.position + 7,
        "invalid compressed packet length",
      );

      final compressedLength = readInteger(buffer, cursor, 3);
      readInteger(buffer, cursor, 1);
      final uncompressedLength = readInteger(buffer, cursor, 3);

      final start = cursor.position;
      final end = start + compressedLength;
      if (uncompressedLength == 0) {
        writer.add(getUnmodifiableRangeEfficiently(buffer, start, end));
      } else {
        final decompressed =
            zlib.decode(getUnmodifiableRangeEfficiently(buffer, start, end));
        assert(
          decompressed.length == uncompressedLength,
          "decompressed payload held an incorrect length",
        );
        writer.add(decompressed);
      }

      cursor.increment(compressedLength);
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
