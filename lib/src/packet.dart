import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'utils.dart';

void writeBytes(BytesBuilder builder, List<int> value) {
  builder.add(value is Uint8List ? value : Uint8List.fromList(value));
}

void writeInteger(BytesBuilder builder, int length, int value) {
  for (int i = 0; i < length; i++) {
    builder.addByte((value >> (i * 8)) & 0xff);
  }
}

void writeLengthEncodedInteger(BytesBuilder builder, int? value) {
  if (value == null) {
    builder.addByte(0xFB);
    return;
  }
  if (value < 0xfb) {
    builder.addByte(value);
  } else if (value <= 0xffff) {
    builder.addByte(0xFC);
    builder.addByte(value & 0xff);
    builder.addByte((value >> 8) & 0xff);
  } else if (value <= 0xffffff) {
    builder.addByte(0xFD);
    builder.addByte(value & 0xff);
    builder.addByte((value >> 8) & 0xff);
    builder.addByte((value >> 16) & 0xff);
  } else {
    builder.addByte(0xFE);
    builder.addByte(value & 0xff);
    builder.addByte((value >> 8) & 0xff);
    builder.addByte((value >> 16) & 0xff);
    builder.addByte((value >> 24) & 0xff);
    builder.addByte((value >> 32) & 0xff);
    builder.addByte((value >> 40) & 0xff);
    builder.addByte((value >> 48) & 0xff);
    builder.addByte((value >> 56) & 0xff);
  }
}

void writeZeroTerminatedBytes(BytesBuilder builder, List<int> value) {
  builder.add(
      value.expand((byte) => byte == 0x00 ? [0x5c, 0x00] : [byte]).toList());
  builder.addByte(0x00);
}

void writeLengthEncodedBytes(BytesBuilder builder, List<int> value) {
  writeLengthEncodedInteger(builder, value.length);
  writeBytes(builder, value);
}

void writeString(
  BytesBuilder builder,
  String value, [
  Encoding encoding = utf8,
]) {
  writeBytes(builder, encoding.encode(value));
}

void writeZeroTerminatedString(
  BytesBuilder builder,
  String value, [
  Encoding encoding = utf8,
]) {
  writeZeroTerminatedBytes(builder, encoding.encode(value));
}

void writeLengthEncodedString(
  BytesBuilder builder,
  String? value, [
  Encoding encoding = utf8,
]) {
  if (value == null) {
    writeLengthEncodedInteger(builder, null);
    return;
  }
  writeLengthEncodedBytes(builder, encoding.encode(value));
}

class PacketBuilder {
  final BytesBuilder _payload = BytesBuilder();

  final Encoding _encoding;

  final int _maxPacketSize;

  PacketBuilder({
    Encoding encoding = utf8,
    int maxPacketSize = 0xffffff,
  })  : _encoding = encoding,
        _maxPacketSize = maxPacketSize;

  int get length =>
      _payload.length + min(1, (_payload.length / _maxPacketSize).ceil()) * 4;

  void addByte(int byte) {
    _payload.addByte(byte);
  }

  void addBytes(List<int> bytes) {
    _payload.add(bytes);
  }

  void addInteger(int length, int value) {
    assert(const [1, 2, 3, 4, 6, 8].contains(length));

    for (int i = 0; i < length; i++) {
      _payload.addByte((value >> (i * 8)) & 0xff);
    }
  }

  void addString(String value) {
    _payload.add(_encoding.encode(value));
  }

  void addLengthEncodedInteger(int? value) {
    if (value == null) {
      _payload.addByte(0xFB);
      return;
    }
    if (value < 0xfb) {
      _payload.addByte(value);
    } else if (value <= 0xffff) {
      _payload.addByte(0xFC);
      _payload.addByte((value >> 0) & 0xff);
      _payload.addByte((value >> 8) & 0xff);
    } else if (value <= 0xffffff) {
      _payload.addByte(0xFD);
      _payload.addByte((value >> 0) & 0xff);
      _payload.addByte((value >> 8) & 0xff);
      _payload.addByte((value >> 16) & 0xff);
    } else {
      _payload.addByte(0xFE);
      _payload.addByte((value >> 0) & 0xff);
      _payload.addByte((value >> 8) & 0xff);
      _payload.addByte((value >> 16) & 0xff);
      _payload.addByte((value >> 24) & 0xff);
      _payload.addByte((value >> 32) & 0xff);
      _payload.addByte((value >> 40) & 0xff);
      _payload.addByte((value >> 48) & 0xff);
      _payload.addByte((value >> 56) & 0xff);
    }
  }

  void addLengthEncodedString(String? value) {
    if (value == null) {
      addLengthEncodedInteger(null);
      return;
    }
    final encoded = _encoding.encode(value);
    addLengthEncodedInteger(encoded.length);
    _payload.add(encoded);
  }

  void addZeroTerminatedString(String value) {
    _payload.add(_encoding.encode(value));
    _payload.addByte(0x00);
  }

  Uint8List _buildPacketLength(int length) {
    final buffer = Uint8List(3);
    buffer[0] = (length >> 0) & 0xff;
    buffer[1] = (length >> 8) & 0xff;
    buffer[2] = (length >> 16) & 0xff;

    return buffer;
  }

  Uint8List build() {
    final buffer = BytesBuilder();
    if (_payload.isEmpty) {
      buffer.add(const [0x00, 0x00, 0x00, 0xff]);
      return buffer.takeBytes();
    }

    final payloadBuffer = _payload.toBytes();
    int offset = 0;
    for (;;) {
      if (offset == payloadBuffer.length) {
        return buffer.takeBytes();
      }
      if (payloadBuffer.length - offset > _maxPacketSize) {
        buffer.add(_buildPacketLength(_maxPacketSize));
        buffer.addByte(0xff);
        buffer.add(payloadBuffer.sublist(offset, offset + _maxPacketSize));
        offset += _maxPacketSize;
      } else {
        buffer.add(_buildPacketLength(payloadBuffer.length - offset));
        buffer.addByte(0xff);
        buffer.add(payloadBuffer.sublist(offset, payloadBuffer.length));
        offset = payloadBuffer.length;
      }
    }
  }
}

class PacketHeader {
  final int length;

  final int sequence;

  const PacketHeader(this.length, this.sequence);
}

PacketHeader readPacketHeader(List<int> buffer, Cursor cursor) {
  return PacketHeader(
    readInteger(buffer, cursor, 3),
    readInteger(buffer, cursor, 1),
  );
}

Map<String, dynamic> readOkPacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  readPacketHeader(buffer, cursor);
  cursor.increase(1); // note: skip indicator byte

  props["affectedRows"] = readLengthEncodedInteger(buffer, cursor);
  props["lastInsertId"] = readLengthEncodedInteger(buffer, cursor);
  props["serverStatus"] = readInteger(buffer, cursor, 2);
  props["numWarnings"] = readInteger(buffer, cursor, 2);

  return props;
}

Map<String, dynamic> readErrPacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  final header = readPacketHeader(buffer, cursor);
  cursor.increase(1); // note: skip indicator byte

  props["errorCode"] = readInteger(buffer, cursor, 2);
  if (props["errorCode"] == 0xffff) {
    props["stage"] = readInteger(buffer, cursor, 1);
    props["maxStage"] = readInteger(buffer, cursor, 1);
    props["progress"] = readInteger(buffer, cursor, 3);
    props["progressInfo"] = readLengthEncodedString(buffer, cursor);
  } else {
    if (buffer[cursor.position] == 0x23) {
      cursor.increase(1);
      props["sqlState"] = readString(buffer, cursor, 5);
      props["message"] =
          readString(buffer, cursor, header.length - cursor.position + 4);
      cursor.setPosition(header.length);
    } else {
      props["message"] =
          readString(buffer, cursor, header.length - cursor.position + 4);
      cursor.setPosition(header.length);
    }
  }

  return props;
}

Map<String, dynamic> readEofPacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  readPacketHeader(buffer, cursor);
  cursor.increase(1); // note: skip indicator byte

  props["numWarnings"] = readInteger(buffer, cursor, 2);
  props["serverStatus"] = readInteger(buffer, cursor, 2);

  return props;
}

Map<String, dynamic> readLocalInfilePacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  cursor.increase(4);
  cursor.increase(1);
  props["filename"] = readString(buffer, cursor, buffer.length - cursor.position);

  return props;
}

class OkPacket {
  final Map<String, dynamic> props;

  const OkPacket(this.props);

  int get affectedRows => props["affectedRows"];

  int get lastInsertId => props["lastInsertId"];

  int get serverStatus => props["serverStatus"];

  int get numberOfWarnings => props["numWarnings"];
}

class ErrPacket {
  final Map<String, dynamic> props;

  const ErrPacket(this.props);

  int get errorCode => props["errorCode"];

  bool get progressReport => errorCode == 0xFFFF;

  int get stage => props["stage"];

  int get maxStage => props["maxStage"];

  int get progress => props["progress"];

  String get progressInfo => props["progressInfo"];

  String get sqlState => props["sqlState"];

  String get errorMessage => props["message"];
}

class EofPacket {
  final Map<String, dynamic> props;

  const EofPacket(this.props);

  int get numberOfWarnings => props["numWarnings"];

  int get serverStatus => props["serverStatus"];
}

extension IntListExtension on List<int> {
  String toHex() {
    return map((x) => x.toRadixString(16)).join();
  }
}
