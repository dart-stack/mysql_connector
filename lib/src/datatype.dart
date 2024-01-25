import 'dart:typed_data';

import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/packet.dart';
import 'package:mysql_connector/src/resultset.dart';
import 'package:mysql_connector/src/utils.dart';

// TODO: adopt `Codec` in which `dart:convert`

// See https://mariadb.com/kb/en/com_stmt_execute/#binary-parameter-encoding
List<int> encode(ResultSetColumn column, dynamic value) {
  switch (column.fieldType) {
    case mysqlTypeDouble:
      return encodeDouble(value);

    case mysqlTypeLonglong:
      return encodeBigInt(value, (column.detailFlag & fieldFlagUnsigned) > 0);

    case mysqlTypeLong:
      return encodeInteger(value, (column.detailFlag & fieldFlagUnsigned) > 0);

    case mysqlTypeInt24:
      return encodeMediumInt(
          value, (column.detailFlag & fieldFlagUnsigned) > 0);

    case mysqlTypeFloat:
      return encodeFloat(value);

    case mysqlTypeShort:
      return encodeSmallInt(value, (column.detailFlag & fieldFlagUnsigned) > 0);

    case mysqlTypeYear:
      return encodeYear(value);

    case mysqlTypeTiny:
      return encodeTinyInt(value, (column.detailFlag & fieldFlagUnsigned) > 0);

    case mysqlTypeDate:
      return encodeDate(value);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return encodeTimestamp(value);

    case mysqlTypeTime:
      return encodeTime(value);

    case mysqlTypeNewdecimal:
      return encodeDecimal(value, column.decimals);

    case mysqlTypeTinyBlob:
    case mysqlTypeMediumBlob:
    case mysqlTypeLongBlob:
    case mysqlTypeBlob:
    case mysqlTypeGeometry:
    case mysqlTypeString:
    case mysqlTypeVarchar:
    case mysqlTypeVarString:
      final writer = BytesBuilder();
      writeLengthEncodedBytes(writer, value);
      return writer.takeBytes();

    default:
      throw ArgumentError("unsupported mysql type ${column.fieldType}");
  }
}

// See https://mariadb.com/kb/en/resultset-row/#binary-resultset-row
dynamic decode(
  ResultSetColumn column,
  List<int> buffer, [
  Cursor? cursor,
]) {
  cursor ??= Cursor.zero();

  switch (column.fieldType) {
    case mysqlTypeDouble:
      return decodeDouble(buffer, cursor);

    case mysqlTypeLonglong:
      return decodeBigInt(
          buffer, (column.detailFlag & fieldFlagUnsigned) > 0, cursor);

    case mysqlTypeLong:
      return decodeInteger(
          buffer, (column.detailFlag & fieldFlagUnsigned) > 0, cursor);

    case mysqlTypeInt24:
      return decodeMediumInt(
          buffer, (column.detailFlag & fieldFlagUnsigned) > 0, cursor);

    case mysqlTypeFloat:
      return decodeFloat(buffer, cursor);

    case mysqlTypeShort:
      return decodeSmallInt(
          buffer, (column.detailFlag & fieldFlagUnsigned) > 0, cursor);

    case mysqlTypeYear:
      return decodeYear(buffer, cursor);

    case mysqlTypeTiny:
      return decodeTinyInt(
          buffer, (column.detailFlag & fieldFlagUnsigned) > 0, cursor);

    case mysqlTypeDate:
      return decodeDate(buffer, cursor);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return decodeTimestamp(buffer, cursor);

    case mysqlTypeTime:
      return decodeTime(buffer, cursor);

    case mysqlTypeNewdecimal:
      return decodeDecimal(buffer, cursor);

    case mysqlTypeTinyBlob:
    case mysqlTypeMediumBlob:
    case mysqlTypeLongBlob:
    case mysqlTypeBlob:
    case mysqlTypeGeometry:
    case mysqlTypeString:
    case mysqlTypeVarchar:
    case mysqlTypeVarString:
      return readLengthEncodedBytes(buffer, cursor);
  }
}

// See https://mariadb.com/kb/en/resultset-row/#decimal-binary-encoding
List<int> encodeDecimal(double value, int decimals) {
  final writer = BytesBuilder();
  writeLengthEncodedString(writer, value.toStringAsFixed(decimals));
  return writer.takeBytes();
}

List<int> encodeDouble(double value) {
  final data = ByteData(8);
  data.setFloat64(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> encodeBigInt(int value, bool unsigned) {
  final data = ByteData(8);
  if (unsigned) {
    data.setUint64(0, value, Endian.little);
  } else {
    data.setInt64(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeInteger(int value, bool unsigned) {
  final data = ByteData(4);
  if (unsigned) {
    data.setUint32(0, value, Endian.little);
  } else {
    data.setInt32(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeMediumInt(int value, bool unsigned) {
  final data = ByteData(4);
  if (unsigned) {
    data.setUint32(0, value, Endian.little);
  } else {
    data.setInt32(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeFloat(double value) {
  final data = ByteData(4);
  data.setFloat32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> encodeSmallInt(int value, bool unsigned) {
  final data = ByteData(2);
  if (unsigned) {
    data.setUint16(0, value, Endian.little);
  } else {
    data.setInt16(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeYear(int value) {
  return encodeSmallInt(value, false);
}

List<int> encodeTinyInt(int value, bool unsigned) {
  final data = ByteData(1);
  if (unsigned) {
    data.setUint8(0, value);
  } else {
    data.setInt8(0, value);
  }
  return data.buffer.asUint8List();
}

List<int> encodeDate(
  DateTime time, {
  bool isZero = false,
}) {
  final writer = BytesBuilder();
  if (isZero) {
    writer.addByte(0);
    return writer.takeBytes();
  }
  writer.addByte(4);

  final ymd = ByteData(4);
  ymd.setUint16(0, time.year, Endian.little);
  ymd.setUint8(2, time.month);
  ymd.setUint8(3, time.day);
  writer.add(ymd.buffer.asUint8List());

  return writer.takeBytes();
}

List<int> encodeTimestamp(
  DateTime time, {
  bool isZero = false,
  bool includeTimePart = true,
  bool includeMicrosecondPart = true,
}) {
  final writer = BytesBuilder();
  if (isZero) {
    writer.addByte(0);
    return writer.takeBytes();
  }
  if (!includeTimePart) {
    writer.addByte(4);
  } else if (!includeMicrosecondPart) {
    writer.addByte(7);
  } else {
    writer.addByte(11);
  }

  final ymd = ByteData(4);
  ymd.setUint16(0, time.year, Endian.little);
  ymd.setUint8(2, time.month);
  ymd.setUint8(3, time.day);
  writer.add(ymd.buffer.asUint8List());
  if (!includeTimePart) {
    return writer.takeBytes();
  }

  final hms = ByteData(3);
  hms.setUint8(0, time.hour);
  hms.setUint8(1, time.minute);
  hms.setUint8(2, time.second);
  writer.add(hms.buffer.asUint8List());
  if (!includeMicrosecondPart) {
    return writer.takeBytes();
  }

  final ms = ByteData(4);
  ms.setUint32(0, time.microsecond, Endian.little);
  writer.add(ms.buffer.asUint8List());

  return writer.takeBytes();
}

List<int> encodeTime(
  DateTime time, {
  bool isZero = false,
  bool isNegative = false,
  bool includeMicrosecondPart = true,
}) {
  final writer = BytesBuilder();
  if (isZero) {
    writer.addByte(0);
    return writer.takeBytes();
  }
  if (!includeMicrosecondPart) {
    writer.addByte(8);
  } else {
    writer.addByte(12);
  }

  if (isNegative) {
    writer.addByte(1);
  } else {
    writer.addByte(0);
  }

  final ymdhms = ByteData(7);
  ymdhms.setUint16(0, time.year);
  ymdhms.setUint16(2, time.month);
  ymdhms.setUint16(3, time.day);
  ymdhms.setUint16(4, time.hour);
  ymdhms.setUint16(5, time.minute);
  ymdhms.setUint16(6, time.second);
  writer.add(ymdhms.buffer.asUint8List());
  if (!includeMicrosecondPart) {
    return writer.takeBytes();
  }

  final ms = ByteData(4);
  ms.setUint32(0, time.microsecond, Endian.little);
  writer.add(ms.buffer.asUint8List());

  return writer.takeBytes();
}

double decodeDecimal(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = readLengthEncodedString(buffer, cursor);
  return double.parse(data!);
}

double decodeDouble(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final buf = readBytes(buffer, cursor, 8);
  final data = ByteData.sublistView(buf.toUint8List());
  return data.getFloat64(0, Endian.little);
}

int decodeBigInt(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 8).toUint8List());
  if (unsigned) {
    return data.getUint64(0, Endian.little);
  } else {
    return data.getInt64(0, Endian.little);
  }
}

int decodeInteger(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 4).toUint8List());
  if (unsigned) {
    return data.getUint32(0, Endian.little);
  } else {
    return data.getInt32(0, Endian.little);
  }
}

int decodeMediumInt(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 4).toUint8List());
  if (unsigned) {
    return data.getUint32(0, Endian.little);
  } else {
    return data.getInt32(0, Endian.little);
  }
}

double decodeFloat(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 4).toUint8List());
  return data.getFloat32(0);
}

int decodeSmallInt(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 2).toUint8List());
  if (unsigned) {
    return data.getUint16(0);
  } else {
    return data.getInt16(0);
  }
}

int decodeYear(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  return decodeSmallInt(buffer, true, cursor);
}

int decodeTinyInt(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 1).toUint8List());
  if (unsigned) {
    return data.getUint8(0);
  } else {
    return data.getInt8(0);
  }
}

DateTime decodeDate(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final length = readBytes(buffer, cursor, 1)[0];
  if (length == 0) {
    return DateTime(0, 0, 0, 0, 0, 0, 0, 0);
  }

  final data =
      ByteData.sublistView(readBytes(buffer, cursor, length).toUint8List());

  return DateTime(data.getUint16(0), data.getUint8(2), data.getUint8(3));
}

DateTime decodeTimestamp(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final length = readBytes(buffer, cursor, 1)[0];
  if (length == 0) {
    return DateTime(0, 0, 0, 0, 0, 0, 0, 0);
  }

  final buf = Uint8List(11)
    ..setRange(0, length, readBytes(buffer, cursor, length).toUint8List());
  final data = ByteData.sublistView(buf);

  return DateTime(
    data.getUint16(0), // year
    data.getUint8(2), // month
    data.getUint8(3), // day
    data.getUint8(4), // hour
    data.getUint8(5), // minute
    data.getUint8(6), // second
    0,
    data.getUint32(7), // microsecond
  );
}

DateTime decodeTime(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final length = readBytes(buffer, cursor, 1)[0];
  if (length == 0) {
    return DateTime(0, 0, 0, 0, 0, 0, 0, 0);
  }

  // TODO: negative time support
  cursor.increase(1);

  final buf = Uint8List(12)
    ..setRange(0, length, readBytes(buffer, cursor, length - 1).toUint8List());
  final data = ByteData.sublistView(buf);

  return DateTime(
    data.getUint16(0), // year
    data.getUint8(2), // month
    data.getUint8(3), // day
    data.getUint8(4), // hour
    data.getUint8(5), // minute
    data.getUint8(6), // second
    0,
    data.getUint32(7), // microsecond
  );
}
