import 'dart:convert';
import 'dart:typed_data';

const standardPacketHeaderLength = 4;
const compressedPacketHeaderLength = 7;

const standardPacketSequenceOffset = 3;
const compressedPacketSequenceOffset = 3;

const standardPacketPayloadOffset = 4;
const compressedPacketPayloadOffset = 7;

class Cursor {
  int _position;

  Cursor._internal(this._position);

  factory Cursor.zero() => Cursor._internal(0);

  factory Cursor.from(int position) => Cursor._internal(position);

  int get position => _position;

  void reset() {
    _position = 0;
  }

  Cursor clone() {
    return Cursor.from(position);
  }

  void setPosition(int position) {
    _position = position;
  }

  void increment(int delta) {
    _position = _position + delta;
  }

  int incrementAndGet(int delta) {
    increment(delta);
    return position;
  }

  int getAndIncrement(int delta) {
    final p = position;
    increment(delta);
    return p;
  }
}

List<int> readBytes(List<int> buffer, Cursor cursor, int length) {
  assert(cursor.position + length <= buffer.length);

  final result = getUnmodifiableRangeEfficiently(
    buffer,
    cursor.position,
    cursor.position + length,
  );
  cursor.increment(length);
  return result;
}

int readInteger(List<int> buffer, Cursor cursor, int length) {
  assert(const [1, 2, 3, 4, 8].contains(length));

  final bytes = readBytes(buffer, cursor, length);

  var result = 0;
  for (var i = 0; i < bytes.length; i++) {
    result = result + ((bytes[i] & 0xff) << (8 * i));
  }

  return result;
}

int? readLengthEncodedInteger(List<int> buffer, Cursor cursor) {
  final leadingByte = buffer[cursor.position];
  cursor.increment(1);

  if (leadingByte < 0xFB) {
    return leadingByte;
  } else if (leadingByte == 0xFB) {
    return null;
  } else if (leadingByte == 0xFC) {
    return readInteger(buffer, cursor, 2);
  } else if (leadingByte == 0xFD) {
    return readInteger(buffer, cursor, 3);
  } else if (leadingByte == 0xFE) {
    return readInteger(buffer, cursor, 8);
  } else {
    throw UnimplementedError(
        "unrecognized leading byte $leadingByte when reading length-encoded integer");
  }
}

List<int>? readLengthEncodedBytes(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  final length = readLengthEncodedInteger(buffer, cursor);
  if (length == null) {
    return null;
  }
  return readBytes(buffer, cursor, length);
}

List<int> readBytesUntilEnd(List<int> buffer, Cursor cursor) {
  final result = buffer.sublist(cursor.position, buffer.length);
  cursor.increment(buffer.length - cursor.position);
  return result;
}

String readString(
  List<int> buffer,
  Cursor cursor,
  int length, [
  Encoding encoding = utf8,
]) {
  return encoding.decode(readBytes(buffer, cursor, length));
}

String? readLengthEncodedString(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  final length = readLengthEncodedInteger(buffer, cursor);
  if (length == null) {
    return null;
  }
  return readString(buffer, cursor, length, encoding);
}

String readZeroTerminatingString(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  final bytes = <int>[];

  for (int offset = 0;; offset++) {
    final curr = buffer[cursor.position + offset];
    if (curr == 0x00) {
      cursor.increment(offset + 1); // note: cursor should stop at after '\0'
      return encoding.decode(bytes);
    }

    bytes.add(curr);
  }
}

String readStringUntilEnd(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  return encoding.decode(readBytesUntilEnd(buffer, cursor));
}

void writeBytes(BytesBuilder writer, List<int> value) {
  writer.add(value.toUint8List());
}

void writeInteger(BytesBuilder writer, int length, int value) {
  for (int i = 0; i < length; i++) {
    writer.addByte((value >> (i * 8)) & 0xff);
  }
}

void writeLengthEncodedInteger(BytesBuilder writer, int? value) {
  if (value == null) {
    writer.addByte(0xFB);
    return;
  }
  if (value < 0xfb) {
    writer.addByte(value);
  } else if (value <= 0xffff) {
    writer.addByte(0xFC);
    writer.addByte(value & 0xff);
    writer.addByte((value >> 8) & 0xff);
  } else if (value <= 0xffffff) {
    writer.addByte(0xFD);
    writer.addByte(value & 0xff);
    writer.addByte((value >> 8) & 0xff);
    writer.addByte((value >> 16) & 0xff);
  } else {
    writer.addByte(0xFE);
    writer.addByte(value & 0xff);
    writer.addByte((value >> 8) & 0xff);
    writer.addByte((value >> 16) & 0xff);
    writer.addByte((value >> 24) & 0xff);
    writer.addByte((value >> 32) & 0xff);
    writer.addByte((value >> 40) & 0xff);
    writer.addByte((value >> 48) & 0xff);
    writer.addByte((value >> 56) & 0xff);
  }
}

void writeLengthEncodedBytes(BytesBuilder writer, List<int> value) {
  writeLengthEncodedInteger(writer, value.length);
  writeBytes(writer, value);
}

void writeZeroTerminatingBytes(
  BytesBuilder writer,
  List<int> value, {
  bool escape = false,
}) {
  final escapingSubstitution = const {
    0x00: [0x5c, 0x00],
  };
  if (escape) {
    writer.add(
        value.expand((byte) => escapingSubstitution[byte] ?? [byte]).toList());
  } else {
    writer.add(value);
  }
  writer.addByte(0x00);
}

void writeString(
  BytesBuilder writer,
  String value, [
  Encoding encoding = utf8,
]) {
  writeBytes(writer, encoding.encode(value));
}

void writeZeroTerminatingString(
  BytesBuilder writer,
  String value, [
  Encoding encoding = utf8,
]) {
  writeZeroTerminatingBytes(writer, encoding.encode(value));
}

void writeLengthEncodedString(
  BytesBuilder writer,
  String? value, [
  Encoding encoding = utf8,
]) {
  if (value == null) {
    writeLengthEncodedInteger(writer, null);
    return;
  }
  writeLengthEncodedBytes(writer, encoding.encode(value));
}

(bool, List<int>) tryReadStandardPacket(List<int> buffer, Cursor cursor) {
  if (buffer.length < standardPacketHeaderLength) {
    return (false, const []);
  }
  final payloadLength = buffer[0] | (buffer[1] << 8) | (buffer[2] << 16);
  if (buffer.length < standardPacketHeaderLength + payloadLength) {
    return (false, const []);
  }
  final packet = getUnmodifiableRangeEfficiently(
    buffer,
    cursor.position,
    cursor.position + standardPacketHeaderLength + payloadLength,
  );
  cursor.increment(standardPacketHeaderLength + payloadLength);
  return (true, packet);
}

(bool, List<int>) tryReadCompressedPacket(List<int> buffer, Cursor cursor) {
  if (buffer.length < compressedPacketHeaderLength) {
    return (false, const []);
  }
  final payloadLength = buffer[0] | (buffer[1] << 8) | (buffer[2] << 16);
  if (buffer.length < compressedPacketHeaderLength + payloadLength) {
    return (false, const []);
  }
  final packet = getUnmodifiableRangeEfficiently(
    buffer,
    cursor.position,
    cursor.position + compressedPacketHeaderLength + payloadLength,
  );
  cursor.increment(compressedPacketHeaderLength);
  return (true, packet);
}

Iterable<(int, int)> traverseStandardPackets(
  List<int> buffer, [
  Cursor? cursor,
]) sync* {
  cursor ??= Cursor.zero();
  for (;;) {
    if (buffer.length - cursor.position < standardPacketHeaderLength) {
      return;
    }
    final payloadLength = buffer[cursor.position] |
        (buffer[cursor.position + 1] << 8) |
        (buffer[cursor.position + 2] << 16);
    if (buffer.length - cursor.position <
        standardPacketHeaderLength + payloadLength) {
      return;
    }
    final range = (
      cursor.position,
      cursor.position + standardPacketHeaderLength + payloadLength
    );
    cursor.increment(standardPacketHeaderLength + payloadLength);
    yield range;
  }
}

Iterable<(int, int)> traverseCompressedPackets(
  List<int> buffer, [
  Cursor? cursor,
]) sync* {
  cursor ??= Cursor.zero();
  for (;;) {
    if (buffer.length - cursor.position < compressedPacketHeaderLength) {
      return;
    }
    final payloadLength = buffer[cursor.position] |
        (buffer[cursor.position + 1] << 8) |
        (buffer[cursor.position + 2] << 16);
    if (buffer.length - cursor.position <
        compressedPacketHeaderLength + payloadLength) {
      return;
    }
    final range = (
      cursor.position,
      cursor.position + compressedPacketHeaderLength + payloadLength
    );
    cursor.increment(compressedPacketHeaderLength + payloadLength);
    yield range;
  }
}

class Bitmap {
  static Bitmap from(List<int> buffer) {
    return Bitmap._internal(buffer.toUint8List(copy: true));
  }

  // build a bitmap to indicate null where true is.
  static Bitmap build(List<bool> selector) {
    // invariant: bytes length = floor((bits + 7) / 8)

    final buffer = <int>[0x00];
    var i = 0;
    for (int j = 0;; j++) {
      for (int k = 0; k < 8; k++) {
        if (i == selector.length) {
          return from(buffer);
        }
        if (selector[i] == true) {
          buffer[j] |= 1 << k;
        }
        ++i;
      }
      buffer.add(0x00);
    }
  }

  final Uint8List _bitmap;

  const Bitmap._internal(this._bitmap);

  List<int> get buffer => UnmodifiableUint8ListView(_bitmap);

  bool at(int offset) {
    final i = (offset / 8).floor();
    final j = offset % 8;
    return (_bitmap[i] & (1 << j)) > 0;
  }

  @override
  String toString() {
    return _bitmap
        .map((x) =>
            x.toRadixString(2).split('').reversed.join().padRight(8, '0'))
        .join();
  }
}

int getPacketPayloadLength(List<int> buffer, Cursor cursor) {
  return readInteger(buffer, cursor.clone(), 3);
}

List<int> getUnmodifiableRangeEfficiently(
    List<int> buffer, int start, int end) {
  if (buffer is Uint8List) {
    return buffer.sublist(start, end);
  }
  return buffer.sublist(start, end);
}

extension IntListToUint8ListExtension on List<int> {
  Uint8List toUint8List({bool copy = true}) {
    if (this is Uint8List && !copy) {
      return this as Uint8List;
    }
    return Uint8List.fromList(this);
  }
}

extension BoolIntToBitmapExtension on List<bool> {
  Bitmap toBitmap() {
    return Bitmap.build(this);
  }
}

int countStandardPackets(List<int> buffer) {
  return traverseStandardPackets(buffer).length;
}

int countCompressedPackets(List<int> buffer) {
  return traverseCompressedPackets(buffer).length;
}

String formatSize(int size) {
  return "$size";
}
