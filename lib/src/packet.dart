import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/session.dart';
import 'package:mysql_connector/src/socket.dart';

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

void writeLengthEncodedBytes(BytesBuilder writer, List<int> value) {
  writeLengthEncodedInteger(writer, value.length);
  writeBytes(writer, value);
}

void writeZeroTerminatedBytes(BytesBuilder writer, List<int> value) {
  writer.add(
      value.expand((byte) => byte == 0x00 ? [0x5c, 0x00] : [byte]).toList());
  writer.addByte(0x00);
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
  static const fieldAffectedRows = "affectedRows";
  static const fieldLastInsertId = "lastInsertId";
  static const fieldServerStatus = "serverStatus";
  static const fieldNumWarning = "numWarning";
  static const fieldInfo = "info";
  static const fieldSessionStateInfo = "sessionStateInfo";

  static OkPacket from(
    List<int> buffer,
    SessionContext session, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increase(standardPacketHeaderLength + 1);
    props[fieldAffectedRows] = readLengthEncodedInteger(buffer, cursor);
    props[fieldLastInsertId] = readLengthEncodedInteger(buffer, cursor);
    props[fieldServerStatus] = readInteger(buffer, cursor, 2);
    props[fieldNumWarning] = readInteger(buffer, cursor, 2);
    if (cursor.position < buffer.length) {
      props[fieldInfo] = readLengthEncodedString(buffer, cursor);
      if (session.hasCapabilities(capClientSessionTrack) &&
          (props[fieldServerStatus] & serverSessionStateChanged) > 0) {
        props[fieldSessionStateInfo] = readLengthEncodedString(buffer, cursor);
      }
    }

    return OkPacket._internal(props);
  }

  static Future<OkPacket> fromSocket(
    PacketSocketReader reader,
    SessionContext session,
  ) async {
    return from(await reader.readPacket(), session);
  }

  final Map<String, dynamic> props;

  const OkPacket._internal(this.props);

  int get affectedRows => props[fieldAffectedRows];

  int get lastInsertId => props[fieldLastInsertId];

  int get serverStatus => props[fieldServerStatus];

  int get numberOfWarnings => props[fieldNumWarning];

  String get info => props[fieldInfo];

  String get sessionStateInfo => props[fieldSessionStateInfo];

  @override
  String toString() {
    return props.toString();
  }
}

class ErrPacket {
  static const fieldErrorCode = "errorCode";
  static const fieldStage = "stage";
  static const fieldMaxStage = "maxStage";
  static const fieldProgress = "progress";
  static const fieldProgressInfo = "progressInfo";
  static const fieldSqlState = "sqlState";
  static const fieldErrorMessage = "errorMessage";

  static ErrPacket from(
    List<int> buffer,
    SessionContext session, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increase(standardPacketHeaderLength + 1);
    props[fieldErrorCode] = readInteger(buffer, cursor, 2);
    if (props[fieldErrorCode] == 0xffffff) {
      props[fieldStage] = readInteger(buffer, cursor, 1);
      props[fieldMaxStage] = readInteger(buffer, cursor, 1);
      props[fieldProgress] = readInteger(buffer, cursor, 3);
      props[fieldProgressInfo] = readLengthEncodedString(buffer, cursor);
    } else {
      if (buffer[cursor.position] == 35) {
        cursor.increase(1);
        props[fieldSqlState] = readString(buffer, cursor, 5);
        props[fieldErrorMessage] =
            readString(buffer, cursor, buffer.length - cursor.position);
      } else {
        props[fieldErrorMessage] =
            readString(buffer, cursor, buffer.length - cursor.position);
      }
    }

    return ErrPacket._internal(props);
  }

  static Future<ErrPacket> fromSocket(
    PacketSocketReader reader,
    SessionContext session,
  ) async {
    return from(await reader.readPacket(), session);
  }

  final Map<String, dynamic> props;

  const ErrPacket._internal(this.props);

  int get errorCode => props[fieldErrorCode];

  bool get isProgressReport => errorCode == 0xFFFF;

  int get stage => props[fieldStage];

  int get maxStage => props[fieldMaxStage];

  int get progress => props[fieldProgress];

  String get progressInfo => props[fieldProgressInfo];

  String? get sqlState => props[fieldSqlState];

  String get errorMessage => props[fieldErrorMessage];

  void throwIfError(Exception Function(ErrPacket error) exceptionFactory) {
    if (!isProgressReport) {
      final exception = exceptionFactory.call(this);
      throw exception;
    }
  }

  @override
  String toString() {
    return props.toString();
  }
}

class EofPacket {
  static const fieldNumWarnings = "numWarnings";
  static const fieldServerStatus = "serverStatus";

  static EofPacket from(
    List<int> buffer,
    SessionContext session, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increase(standardPacketHeaderLength + 1);
    props[fieldNumWarnings] = readInteger(buffer, cursor, 2);
    props[fieldServerStatus] = readInteger(buffer, cursor, 2);

    return EofPacket._internal(props);
  }

  static Future<EofPacket> fromSocket(
    PacketSocketReader reader,
    SessionContext session,
  ) async {
    return from(await reader.readPacket(), session);
  }

  final Map<String, dynamic> props;

  const EofPacket._internal(this.props);

  int get numberOfWarnings => props[fieldNumWarnings];

  int get serverStatus => props[fieldServerStatus];

  @override
  String toString() {
    return props.toString();
  }
}
