import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/datatype.dart';

import 'session.dart';
import 'socket.dart';
import 'utils.dart';

class ResultSet {
  static const fieldNumColumns = "numColumns";
  static const fieldColumns = "columns";
  static const fieldRows = "rows";

  // TODO: Deprecate PacketSocketReader, and use Stream instead.
  static Future<ResultSet> fromSocket(
    PacketSocketReader reader,
    SessionState session,
    bool binary,
  ) async {
    final props = <String, dynamic>{};

    props[fieldNumColumns] = await _readColumnCount(reader, session);
    props[fieldColumns] = <ResultSetColumn>[];

    // TODO: if not (MARIADB_CLIENT_CACHE_METADATA capability set)
    //  OR (send metadata == 1)
    for (int i = 0; i < props[fieldNumColumns]; i++) {
      props[fieldColumns]
          .add(await ResultSetColumn.fromReader(reader, session));
    }
    if (!session.hasCapabilities(capClientDeprecateEof)) {
      await reader.readPacket();
    }
    props[fieldRows] = [];
    for (int i = 0;; i++) {
      final buffer = await reader.readPacket();
      switch (buffer[standardPacketPayloadOffset + 0]) {
        case 0xFE:
          return ResultSet._internal(props);

        case 0xFF:
          throw Exception("error!");

        default:
          reader.cursor.increment(-buffer.length);
          if (binary) {
            props[fieldRows].add(await ResultSetBinaryRow.fromReader(
              reader,
              session,
              props[fieldNumColumns],
              props[fieldColumns],
            ));
          } else {
            props[fieldRows].add(await ResultSetTextRow.fromReader(
              reader,
              session,
              props[fieldNumColumns],
            ));
          }
      }
    }
  }

  final Map<String, dynamic> props;

  const ResultSet._internal(this.props);

  int get numberOfColumns => props[fieldNumColumns];

  List<ResultSetColumn> get columns => props[fieldColumns];

  List get rows => props[fieldRows];

  @override
  String toString() {
    return props.toString();
  }
}

Future<int> _readColumnCount(
  PacketSocketReader reader,
  SessionState session,
) async {
  final buffer = await reader.readPacket();
  return readLengthEncodedInteger(
      buffer, Cursor.from(standardPacketPayloadOffset))!;
}

class ResultSetColumn {
  static const fieldCatalog = "catalog";
  static const fieldSchema = "schema";
  static const fieldTableName = "tableName";
  static const fieldOriginalTableName = "originalTableName";
  static const fieldFieldName = "fieldName";
  static const fieldOriginalFieldName = "originalFieldName";
  static const fieldNumExtendedInfo = "numExtendedInfo";
  static const fieldExtendedInfo = "extendedInfo";
  static const fieldExtendedInfoType = "extendedInfoType";
  static const fieldExtendedInfoValue = "extendedInfoValue";
  static const fieldLength = "length";
  static const fieldCharset = "charset";
  static const fieldMaxColumnSize = "maxColumnSize";
  static const fieldFieldType = "fieldType";
  static const fieldDetailFlag = "detailFlag";
  static const fieldDecimals = "decimals";

  static Future<ResultSetColumn> fromReader(
    PacketSocketReader reader,
    SessionState session,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.readPacket();

    cursor.increment(standardPacketHeaderLength);
    props[fieldCatalog] = readLengthEncodedString(buffer, cursor);
    props[fieldSchema] = readLengthEncodedString(buffer, cursor);
    props[fieldTableName] = readLengthEncodedString(buffer, cursor);
    props[fieldOriginalTableName] = readLengthEncodedString(buffer, cursor);
    props[fieldFieldName] = readLengthEncodedString(buffer, cursor);
    props[fieldOriginalFieldName] = readLengthEncodedString(buffer, cursor);
    if (session.hasCapabilities(capMariadbClientExtendedTypeInfo)) {
      props[fieldNumExtendedInfo] = readLengthEncodedInteger(buffer, cursor);
      props[fieldExtendedInfo] = <Map<String, dynamic>>[];
      for (int i = 0; i < props[fieldNumExtendedInfo]; i++) {
        props[fieldExtendedInfo].add({
          fieldExtendedInfoType: readInteger(buffer, cursor, 1),
          fieldExtendedInfoValue: readLengthEncodedString(buffer, cursor),
        });
      }
    }
    props[fieldLength] = readLengthEncodedInteger(buffer, cursor);
    props[fieldCharset] = readInteger(buffer, cursor, 2);
    props[fieldMaxColumnSize] = readInteger(buffer, cursor, 4);
    props[fieldFieldType] = readInteger(buffer, cursor, 1);
    props[fieldDetailFlag] = readInteger(buffer, cursor, 2);
    props[fieldDecimals] = readInteger(buffer, cursor, 1);

    return ResultSetColumn._internal(props);
  }

  final Map<String, dynamic> props;

  const ResultSetColumn._internal(this.props);

  String get catalog => props[fieldCatalog];

  String get schema => props[fieldSchema];

  String get fieldName => props[fieldFieldName];

  String get originalFieldName => props[fieldOriginalFieldName];

  String get tableName => props[fieldTableName];

  String get originalTableName => props[fieldOriginalTableName];

  int get charset => props[fieldCharset];

  int get fieldType => props[fieldFieldType];

  int get length => props[fieldLength];

  int get decimals => props[fieldDecimals];

  int get detailFlag => props[fieldDetailFlag];

  bool get unsigned => (detailFlag & fieldFlagUnsigned) > 0;

  MysqlType get mysqlType => MysqlType(fieldType, unsigned, decimals);

  @override
  String toString() {
    return props.toString();
  }
}

class ResultSetTextRow {
  static const fieldColumns = "columns";

  static Future<ResultSetTextRow> fromReader(
    PacketSocketReader reader,
    SessionState session,
    int numberOfColumns,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.readPacket();

    cursor.increment(standardPacketHeaderLength);
    props[fieldColumns] = [];
    for (int i = 0; i < numberOfColumns; i++) {
      props[fieldColumns].add(readLengthEncodedString(buffer, cursor));
    }

    return ResultSetTextRow._internal(props);
  }

  final Map<String, dynamic> props;

  const ResultSetTextRow._internal(this.props);

  List<dynamic> get columns => props[fieldColumns];

  @override
  String toString() {
    return props.toString();
  }
}

class ResultSetBinaryRow {
  static const fieldNullBitmap = "nullBitmap";
  static const fieldColumns = "columns";

  static Future<ResultSetBinaryRow> fromReader(
    PacketSocketReader reader,
    SessionState session,
    int numberOfColumns,
    List<ResultSetColumn> columns,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.readPacket();

    cursor.increment(standardPacketHeaderLength);
    cursor.increment(1); // discard leading byte
    props[fieldNullBitmap] = Bitmap.from(
      readBytes(buffer, cursor, ((numberOfColumns + 9) / 8).floor()),
    );
    props[fieldColumns] = [];
    for (int i = 0; i < numberOfColumns; i++) {
      // Note: For result set row, the first two bits are unused.
      if (props[fieldNullBitmap].at(2 + i)) {
        props[fieldColumns].add(null);
      } else {
        props[fieldColumns].add(decode(columns[i].mysqlType, buffer, cursor));
      }
    }

    return ResultSetBinaryRow._internal(props);
  }

  final Map<String, dynamic> props;

  const ResultSetBinaryRow._internal(this.props);

  Bitmap get nullBitmap => props[fieldNullBitmap];

  List<dynamic> get columns => props[fieldColumns];

  @override
  String toString() {
    return props.toString();
  }
}
