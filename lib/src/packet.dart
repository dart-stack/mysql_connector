import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'utils.dart';

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

void writeZeroTerminatedBytes(BytesBuilder writer, List<int> value) {
  writer.add(
      value.expand((byte) => byte == 0x00 ? [0x5c, 0x00] : [byte]).toList());
  writer.addByte(0x00);
}

void writeLengthEncodedBytes(BytesBuilder writer, List<int> value) {
  writeLengthEncodedInteger(writer, value.length);
  writeBytes(writer, value);
}

void writeString(
  BytesBuilder writer,
  String value, [
  Encoding encoding = utf8,
]) {
  writeBytes(writer, encoding.encode(value));
}

void writeZeroTerminatedString(
  BytesBuilder writer,
  String value, [
  Encoding encoding = utf8,
]) {
  writeZeroTerminatedBytes(writer, encoding.encode(value));
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

class PacketBuilder {
  final BytesBuilder _writer = BytesBuilder();

  final Encoding _encoding;

  final int _maxPacketSize;

  PacketBuilder({
    Encoding encoding = utf8,
    int maxPacketSize = 0xffffff,
  })  : _encoding = encoding,
        _maxPacketSize = maxPacketSize;

  int get length =>
      _writer.length + min(1, (_writer.length / _maxPacketSize).ceil()) * 4;

  void addByte(int byte) {
    _writer.addByte(byte);
  }

  void addBytes(List<int> bytes) {
    _writer.add(bytes);
  }

  void addInteger(int length, int value) {
    assert(const [1, 2, 3, 4, 6, 8].contains(length));

    for (int i = 0; i < length; i++) {
      _writer.addByte((value >> (i * 8)) & 0xff);
    }
  }

  void addString(String value) {
    _writer.add(_encoding.encode(value));
  }

  void addLengthEncodedInteger(int? value) {
    if (value == null) {
      _writer.addByte(0xFB);
      return;
    }
    if (value < 0xfb) {
      _writer.addByte(value);
    } else if (value <= 0xffff) {
      _writer.addByte(0xFC);
      _writer.addByte((value >> 0) & 0xff);
      _writer.addByte((value >> 8) & 0xff);
    } else if (value <= 0xffffff) {
      _writer.addByte(0xFD);
      _writer.addByte((value >> 0) & 0xff);
      _writer.addByte((value >> 8) & 0xff);
      _writer.addByte((value >> 16) & 0xff);
    } else {
      _writer.addByte(0xFE);
      _writer.addByte((value >> 0) & 0xff);
      _writer.addByte((value >> 8) & 0xff);
      _writer.addByte((value >> 16) & 0xff);
      _writer.addByte((value >> 24) & 0xff);
      _writer.addByte((value >> 32) & 0xff);
      _writer.addByte((value >> 40) & 0xff);
      _writer.addByte((value >> 48) & 0xff);
      _writer.addByte((value >> 56) & 0xff);
    }
  }

  void addLengthEncodedString(String? value) {
    if (value == null) {
      addLengthEncodedInteger(null);
      return;
    }
    final encoded = _encoding.encode(value);
    addLengthEncodedInteger(encoded.length);
    _writer.add(encoded);
  }

  void addZeroTerminatedString(String value) {
    _writer.add(_encoding.encode(value));
    _writer.addByte(0x00);
  }

  Uint8List _buildPacketLength(int length) {
    final buffer = Uint8List(3);
    buffer[0] = (length >> 0) & 0xff;
    buffer[1] = (length >> 8) & 0xff;
    buffer[2] = (length >> 16) & 0xff;

    return buffer;
  }

  Uint8List _splitAndBuild() {
    final buffer = BytesBuilder();
    if (_writer.isEmpty) {
      buffer.add(const [0x00, 0x00, 0x00, 0xff]);
      return buffer.takeBytes();
    }

    final payloadBuffer = _writer.toBytes();
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

  Uint8List build() {
    return _splitAndBuild();
  }
}

Map<String, dynamic> readOkPacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  cursor.increase(standardPacketHeaderLength);
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

  final payloadLength = readInteger(buffer, cursor, 3);
  cursor.increase(1);
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
      props["message"] = readString(buffer, cursor,
          standardPacketHeaderLength + payloadLength - cursor.position);
    } else {
      props["message"] = readString(buffer, cursor,
          standardPacketHeaderLength + payloadLength - cursor.position);
    }
  }

  return props;
}

Map<String, dynamic> readEofPacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  cursor.increase(standardPacketHeaderLength);
  cursor.increase(1); // note: skip leading byte

  props["numWarnings"] = readInteger(buffer, cursor, 2);
  props["serverStatus"] = readInteger(buffer, cursor, 2);

  return props;
}

Map<String, dynamic> readLocalInfilePacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  cursor.increase(4);
  cursor.increase(1);
  props["filename"] =
      readString(buffer, cursor, buffer.length - cursor.position);

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
