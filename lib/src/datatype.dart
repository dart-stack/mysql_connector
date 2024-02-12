import 'dart:typed_data';

import 'package:mysql_connector/src/wkb.dart';

import 'common.dart';
import 'utils.dart';

// TODO: adopt `Codec` of `dart:convert`

// See https://mariadb.com/kb/en/result-set-packets/#field-types
List<int> encodeForBinary(MysqlType mysqlType, dynamic value) {
  switch (mysqlType.mysqlType) {
    case mysqlTypeDouble:
      return encodeDoubleForBinary(value);

    case mysqlTypeLonglong:
      return encodeBigIntForBinary(value, mysqlType.unsigned);

    case mysqlTypeLong:
      return encodeIntForBinary(value, mysqlType.unsigned);

    case mysqlTypeInt24:
      return encodeIntForBinary(value, mysqlType.unsigned);

    case mysqlTypeFloat:
      return encodeFloatForBinary(value);

    case mysqlTypeShort:
      return encodeSmallIntForBinary(value, mysqlType.unsigned);

    case mysqlTypeYear:
      return encodeYearForBinary(value);

    case mysqlTypeTiny:
      return encodeTinyIntForBinary(value, mysqlType.unsigned);

    case mysqlTypeDate:
      return encodeDateForBinary(value);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return encodeTimestampForBinary(value);

    case mysqlTypeTime:
      return encodeTimeForBinary(value);

    // TODO: requiring further research for encoding MYSQL_TYPE_DECIMAL
    case mysqlTypeDecimal:
    case mysqlTypeNewdecimal:
      return encodeDecimalForBinary(value, mysqlType.decimals);

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
dynamic decodeForBinary(
  List<int> buffer,
  MysqlType mysqlType, [
  Cursor? cursor,
]) {
  cursor ??= Cursor.zero();
  switch (mysqlType.mysqlType) {
    case mysqlTypeDouble:
      return decodeDoubleForBinary(buffer, cursor);

    case mysqlTypeLonglong:
      return decodeBigIntForBinary(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeLong:
      return decodeIntForBinary(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeInt24:
      return decodeMediumIntForBinary(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeFloat:
      return decodeFloatForBinary(buffer, cursor);

    case mysqlTypeShort:
      return decodeSmallIntForBinary(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeYear:
      return decodeYearForBinary(buffer, cursor);

    case mysqlTypeTiny:
      return decodeTinyIntForBinary(buffer, mysqlType.unsigned, cursor);

    case mysqlTypeDate:
      return decodeDateForBinary(buffer, cursor);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return decodeTimestampForBinary(buffer, cursor);

    case mysqlTypeTime:
      return decodeTimeForBinary(buffer, cursor);

    case mysqlTypeDecimal:
    case mysqlTypeNewdecimal:
      return decodeDecimalForBinary(buffer, cursor);

    case mysqlTypeTinyBlob:
    case mysqlTypeMediumBlob:
    case mysqlTypeLongBlob:
    case mysqlTypeBlob:
      return readLengthEncodedBytes(buffer, cursor);

    case mysqlTypeString:
    case mysqlTypeVarchar:
    case mysqlTypeVarString:
      return readLengthEncodedString(buffer, cursor);

    case mysqlTypeEnum:
    case mysqlTypeSet:
      return readLengthEncodedString(buffer, cursor);

    case mysqlTypeBit:
      return decodeBits(buffer, cursor);

    case mysqlTypeGeometry:
      return decodeGeometry(buffer, cursor);
  }
}

dynamic decodeForText(
  List<int> buffer,
  MysqlType mysqlType, [
  Cursor? cursor,
]) {
  cursor ??= Cursor.zero();
  switch (mysqlType.mysqlType) {
    case mysqlTypeDouble:
    case mysqlTypeFloat:
    case mysqlTypeDecimal:
    case mysqlTypeNewdecimal:
      return decodeDoubleForText(buffer, cursor);

    case mysqlTypeLonglong:
    case mysqlTypeLong:
    case mysqlTypeInt24:
    case mysqlTypeShort:
    case mysqlTypeTiny:
      return decodeIntForText(buffer, cursor);

    case mysqlTypeYear:
      return decodeYearForText(buffer, cursor);

    case mysqlTypeDate:
      return decodeDateForText(buffer, cursor);

    case mysqlTypeTimestamp:
    case mysqlTypeDatetime:
      return decodeDateTimeForText(buffer, cursor);

    case mysqlTypeTime:
      return decodeTimeForText(buffer, cursor);

    case mysqlTypeEnum:
    case mysqlTypeSet:
      return readLengthEncodedString(buffer, cursor);

    case mysqlTypeBit:
      return decodeBits(buffer, cursor);

    case mysqlTypeTinyBlob:
    case mysqlTypeMediumBlob:
    case mysqlTypeLongBlob:
    case mysqlTypeBlob:
      return readLengthEncodedBytes(buffer, cursor);

    case mysqlTypeString:
    case mysqlTypeVarchar:
    case mysqlTypeVarString:
      return readLengthEncodedString(buffer, cursor);

    case mysqlTypeGeometry:
      return decodeGeometry(buffer, cursor);
  }
}

// ----------------------
//  Binary data encoders
// ----------------------

// See https://mariadb.com/kb/en/resultset-row/#decimal-binary-encoding
List<int> encodeDecimalForBinary(double value, int decimals) {
  final writer = BytesBuilder();
  writeLengthEncodedString(writer, value.toStringAsFixed(decimals));
  return writer.takeBytes();
}

List<int> encodeDoubleForBinary(double value) {
  final data = ByteData(8);
  data.setFloat64(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> encodeBigIntForBinary(int value, bool unsigned) {
  final data = ByteData(8);
  if (unsigned) {
    data.setUint64(0, value, Endian.little);
  } else {
    data.setInt64(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeIntForBinary(int value, bool unsigned) {
  final data = ByteData(4);
  if (unsigned) {
    data.setUint32(0, value, Endian.little);
  } else {
    data.setInt32(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeMediumIntForBinary(int value, bool unsigned) {
  final data = ByteData(4);
  if (unsigned) {
    data.setUint32(0, value, Endian.little);
  } else {
    data.setInt32(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeFloatForBinary(double value) {
  final data = ByteData(4);
  data.setFloat32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> encodeSmallIntForBinary(int value, bool unsigned) {
  final data = ByteData(2);
  if (unsigned) {
    data.setUint16(0, value, Endian.little);
  } else {
    data.setInt16(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> encodeYearForBinary(int value) {
  return encodeSmallIntForBinary(value, false);
}

List<int> encodeTinyIntForBinary(int value, bool unsigned) {
  final data = ByteData(1);
  if (unsigned) {
    data.setUint8(0, value);
  } else {
    data.setInt8(0, value);
  }
  return data.buffer.asUint8List();
}

List<int> encodeDateForBinary(
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

List<int> encodeTimestampForBinary(
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

List<int> encodeTimeForBinary(
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

double decodeDecimalForBinary(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = readLengthEncodedString(buffer, cursor);
  return double.parse(data!);
}

double decodeDoubleForBinary(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final buf = readBytes(buffer, cursor, 8);
  final data = ByteData.sublistView(buf.toUint8List());
  return data.getFloat64(0, Endian.little);
}

int decodeBigIntForBinary(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 8).toUint8List());
  if (unsigned) {
    return data.getUint64(0, Endian.little);
  } else {
    return data.getInt64(0, Endian.little);
  }
}

int decodeIntForBinary(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 4).toUint8List());
  if (unsigned) {
    return data.getUint32(0, Endian.little);
  } else {
    return data.getInt32(0, Endian.little);
  }
}

int decodeMediumIntForBinary(List<int> buffer, bool unsigned,
    [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 4).toUint8List());
  if (unsigned) {
    return data.getUint32(0, Endian.little);
  } else {
    return data.getInt32(0, Endian.little);
  }
}

double decodeFloatForBinary(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 4).toUint8List());
  return data.getFloat32(0);
}

int decodeSmallIntForBinary(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 2).toUint8List());
  if (unsigned) {
    return data.getUint16(0);
  } else {
    return data.getInt16(0);
  }
}

DateTime decodeYearForBinary(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final yearInText = decodeSmallIntForBinary(buffer, true, cursor);
  return DateTime(yearInText, 0, 0, 0, 0, 0, 0, 0);
}

int decodeTinyIntForBinary(List<int> buffer, bool unsigned, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final data = ByteData.sublistView(readBytes(buffer, cursor, 1).toUint8List());
  if (unsigned) {
    return data.getUint8(0);
  } else {
    return data.getInt8(0);
  }
}

DateTime decodeDateForBinary(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final length = readBytes(buffer, cursor, 1)[0];
  if (length == 0) {
    return DateTime(0, 0, 0, 0, 0, 0, 0, 0);
  }

  final data =
      ByteData.sublistView(readBytes(buffer, cursor, length).toUint8List());

  return DateTime(data.getUint16(0), data.getUint8(2), data.getUint8(3));
}

DateTime decodeTimestampForBinary(List<int> buffer, [Cursor? cursor]) {
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

DateTime decodeTimeForBinary(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final length = readBytes(buffer, cursor, 1)[0];
  if (length == 0) {
    return DateTime(0, 0, 0, 0, 0, 0, 0, 0);
  }

  // TODO: negative time support
  cursor.increment(1);

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

double? decodeDoubleForText(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final doubleInText = readLengthEncodedString(buffer, cursor);
  if (doubleInText == null) {
    return null;
  }
  return double.parse(doubleInText);
}

int? decodeIntForText(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final intInText = readLengthEncodedString(buffer, cursor);
  if (intInText == null) {
    return null;
  }
  return int.parse(intInText);
}

DateTime? decodeYearForText(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final yearInText = readLengthEncodedString(buffer, cursor);
  if (yearInText == null) {
    return null;
  }
  return DateTime(
    int.parse(yearInText),
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  );
}

DateTime? decodeTimeForText(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final timeInText = readLengthEncodedString(buffer, cursor);
  if (timeInText == null) {
    return null;
  }
  return DateTime(
    0,
    0,
    0,
    int.parse(timeInText.substring(0, 2)),
    int.parse(timeInText.substring(3, 5)),
    int.parse(timeInText.substring(6, 8)),
    0,
    0,
  );
}

DateTime? decodeDateForText(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final dateInText = readLengthEncodedString(buffer, cursor);
  if (dateInText == null) {
    return null;
  }
  return DateTime(
    int.parse(dateInText.substring(0, 4)),
    int.parse(dateInText.substring(5, 7)),
    int.parse(dateInText.substring(8, 10)),
    0,
    0,
    0,
    0,
    0,
  );
}

DateTime? decodeDateTimeForText(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final dateTimeInText = readLengthEncodedString(buffer, cursor);
  if (dateTimeInText == null) {
    return null;
  }
  return DateTime(
    int.parse(dateTimeInText.substring(0, 4)),
    int.parse(dateTimeInText.substring(5, 7)),
    int.parse(dateTimeInText.substring(8, 10)),
    int.parse(dateTimeInText.substring(11, 13)),
    int.parse(dateTimeInText.substring(14, 16)),
    int.parse(dateTimeInText.substring(17, 19)),
    0,
    0,
  );
}

Bitmap? decodeBits(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final data = readLengthEncodedBytes(buffer, cursor);
  if(data == null) {
    return null;
  }
  return Bitmap.from(data);
}

dynamic decodeGeometry(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final data = readLengthEncodedBytes(buffer, cursor);
  if (data == null) {
    return null;
  }
  return parseWkbGeometry(data, Cursor.from(4));
}

final class MysqlType {
  final int mysqlType;

  final bool unsigned;

  final int length;

  final int decimals;

  const MysqlType(this.mysqlType, this.unsigned, this.length, this.decimals);
}

MysqlType _findBestMatchingMysqlType(dynamic value) {
  switch (value) {
    case final int value:
      switch (value.bitLength) {
        case 64:
          return MysqlType(mysqlTypeLonglong, true, 0, 0);
        case 63:
          return MysqlType(mysqlTypeLonglong, false, 0, 0);
        case 32:
          return MysqlType(mysqlTypeLong, true, 0, 0);
        case 31:
          return MysqlType(mysqlTypeLong, false, 0, 0);
        case 24:
          return MysqlType(mysqlTypeInt24, true, 0, 0);
        case 23:
          return MysqlType(mysqlTypeInt24, false, 0, 0);
        case 16:
          return MysqlType(mysqlTypeShort, true, 0, 0);
        case 15:
          return MysqlType(mysqlTypeShort, false, 0, 0);
        case 8:
          return MysqlType(mysqlTypeTiny, true, 0, 0);
        case 7:
          return MysqlType(mysqlTypeTiny, false, 0, 0);
        case > 32 && < 64:
          return MysqlType(mysqlTypeLonglong, false, 0, 0);
        case > 16 && < 32:
          return MysqlType(mysqlTypeLong, false, 0, 0);
        case > 8 && < 16:
          return MysqlType(mysqlTypeShort, false, 0, 0);
        case >= 0 && < 8:
          return MysqlType(mysqlTypeTiny, false, 0, 0);
        default:
          throw UnsupportedError(
              "unsupported integer with bit length ${value.bitLength}");
      }

    case final double _:
      return MysqlType(mysqlTypeDouble, false, 0, 0);

    case final String _:
      return MysqlType(mysqlTypeString, false, 0, 0);

    case final DateTime _:
      return MysqlType(mysqlTypeTimestamp, false, 0, 0);

    case final List<int> _:
      return MysqlType(mysqlTypeBlob, false, 0, 0);
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
      null =>
        MysqlTypedValue(MysqlType(mysqlTypeTiny, false, 0, 0), true, null),
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
      nullValue ? Uint8List(0) : encodeForBinary(mysqlType, dartValue);
}