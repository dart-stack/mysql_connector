import 'dart:typed_data';

import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/packet.dart';
import 'package:mysql_connector/src/utils.dart';

// TODO: adopt `Codec` of `dart:convert`

// See https://mariadb.com/kb/en/result-set-packets/#field-types
List<int> encode(MysqlType mysqlType, dynamic value) {
  switch (mysqlType.mysqlType) {
    case mysqlTypeDouble:
      return encodeDouble(value);

    case mysqlTypeLonglong:
      return encodeBigInt(value, mysqlType.unsigned);

    case mysqlTypeLong:
      return encodeInteger(value, mysqlType.unsigned);

    case mysqlTypeInt24:
      return encodeInteger(value, mysqlType.unsigned);

    case mysqlTypeFloat:
      return encodeFloat(value);

    case mysqlTypeShort:
      return encodeSmallInt(value, mysqlType.unsigned);

    case mysqlTypeYear:
      return encodeYear(value);

    case mysqlTypeTiny:
      return encodeTinyInt(value, mysqlType.unsigned);

    case mysqlTypeDate:
      return encodeDate(value);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return encodeTimestamp(value);

    case mysqlTypeTime:
      return encodeTime(value);

    // TODO: requiring further research for encoding MYSQL_TYPE_DECIMAL
    case mysqlTypeDecimal:
    case mysqlTypeNewdecimal:
      return encodeDecimal(value, mysqlType.decimals);

    case mysqlTypeTinyBlob:
    case mysqlTypeMediumBlob:
    case mysqlTypeLongBlob:
    case mysqlTypeBlob:
    case mysqlTypeGeometry:
    case mysqlTypeString:
    case mysqlTypeVarchar:
    case mysqlTypeVarString:
    case mysqlTypeJson:
    // TODO: requiring further research for encoding MYSQL_TYPE_BIT
    case mysqlTypeBit:
    // TODO: requiring further research for encoding MYSQL_TYPE_NEWDATE
    case mysqlTypeNewdate:
    // TODO: requiring further research for encoding MYSQL_TYPE_ENUM
    case mysqlTypeEnum:
    // TODO: requiring further research for encoding MYSQL_TYPE_SET
    case mysqlTypeSet:
      final writer = BytesBuilder();
      writeLengthEncodedBytes(writer, value);
      return writer.takeBytes();

    default:
      throw ArgumentError("unsupported mysql type ${mysqlType.mysqlType}");
  }
}

// See https://mariadb.com/kb/en/resultset-row/#binary-resultset-row
dynamic decode(MysqlType mysqlType, List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  switch (mysqlType.mysqlType) {
    case mysqlTypeDouble:
      return decodeDouble(buffer, cursor);

    case mysqlTypeLonglong:
      return decodeBigInt(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeLong:
      return decodeInteger(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeInt24:
      return decodeMediumInt(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeFloat:
      return decodeFloat(buffer, cursor);

    case mysqlTypeShort:
      return decodeSmallInt(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeYear:
      return decodeYear(buffer, cursor);

    case mysqlTypeTiny:
      return decodeTinyInt(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeDate:
      return decodeDate(buffer, cursor);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return decodeTimestamp(buffer, cursor);

    case mysqlTypeTime:
      return decodeTime(buffer, cursor);

    // TODO: requiring further research for decoding MYSQL_TYPE_DECIMAL
    case mysqlTypeDecimal:
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
    // TODO: requiring further research for decoding MYSQL_TYPE_BIT
    case mysqlTypeBit:
    // TODO: requiring further research for decoding MYSQL_TYPE_NEWDATE
    case mysqlTypeNewdate:
    // TODO: requiring further research for decoding MYSQL_TYPE_ENUM
    case mysqlTypeEnum:
    // TODO: requiring further research for decoding MYSQL_TYPE_SET
    case mysqlTypeSet:
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

final class MysqlType {
  final int mysqlType;

  final bool unsigned;

  final int decimals;

  const MysqlType(this.mysqlType, this.unsigned, this.decimals);
}

MysqlType _findBestMatchingMysqlType(dynamic value) {
  switch (value) {
    case final int value:
      switch (value.bitLength) {
        case 64:
          return MysqlType(mysqlTypeLonglong, true, 0);
        case 63:
          return MysqlType(mysqlTypeLonglong, false, 0);
        case 32:
          return MysqlType(mysqlTypeLong, true, 0);
        case 31:
          return MysqlType(mysqlTypeLong, false, 0);
        case 24:
          return MysqlType(mysqlTypeInt24, true, 0);
        case 23:
          return MysqlType(mysqlTypeInt24, false, 0);
        case 16:
          return MysqlType(mysqlTypeShort, true, 0);
        case 15:
          return MysqlType(mysqlTypeShort, false, 0);
        case 8:
          return MysqlType(mysqlTypeTiny, true, 0);
        case 7:
          return MysqlType(mysqlTypeTiny, false, 0);
        case > 32 && < 64:
          return MysqlType(mysqlTypeLonglong, false, 0);
        case > 16 && < 32:
          return MysqlType(mysqlTypeLong, false, 0);
        case > 8 && < 16:
          return MysqlType(mysqlTypeShort, false, 0);
        case >= 0 && < 8:
          return MysqlType(mysqlTypeTiny, false, 0);
        default:
          throw UnsupportedError(
              "unsupported integer with bit length ${value.bitLength}");
      }

    case final double _:
      return MysqlType(mysqlTypeDouble, false, 0);

    case final String _:
      return MysqlType(mysqlTypeString, false, 0);

    case final DateTime _:
      return MysqlType(mysqlTypeTimestamp, false, 0);

    case final List<int> _:
      return MysqlType(mysqlTypeBlob, false, 0);
  }

  throw UnsupportedError(
      "unsupported dart type ${value.runtimeType} to find best matching mysql type");
}

class MysqlTypedValue {
  final MysqlType mysqlType;

  final bool nullValue;

  final dynamic dartValue;

  const MysqlTypedValue(this.mysqlType, this.nullValue, this.dartValue);

  factory MysqlTypedValue.withBestMatchingType(dynamic value) {
    return switch (value) {
      // TODO: For null values, it seems that MYSQL_TYPE_NULL is not supported
      //  for direct usage in COM_STMT_EXECUTE. Instead, MYSQL_TYPE_TINY is
      //  adopted temporarily, requiring further research.
      null => MysqlTypedValue(MysqlType(mysqlTypeTiny, false, 0), true, null),
      _ => MysqlTypedValue(_findBestMatchingMysqlType(value), false, value)
    };
  }

  factory MysqlTypedValue.from(dynamic value) {
    return switch (value) {
      MysqlTypedValue value => value,
      _ => MysqlTypedValue.withBestMatchingType(value),
    };
  }

  // TODO: We temporarily adopt an empty list to represent null.
  List<int> get encoded =>
      nullValue ? Uint8List(0) : encode(mysqlType, dartValue);
}
