import 'package:mysql_connector/src/common.dart';

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
    SessionContext session,
    bool binary,
  ) async {
    final props = <String, dynamic>{};

    props[fieldNumColumns] = await _readColumnCount(reader, session);
    props[fieldColumns] = [];

    // TODO: if not (MARIADB_CLIENT_CACHE_METADATA capability set)
    //  OR (send metadata == 1)
    for (int i = 0; i < props[fieldNumColumns]; i++) {
      props[fieldColumns]
          .add(await FieldDefinition.fromReader(reader, session));
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
          reader.cursor.increase(-buffer.length);
          if (binary) {
            props[fieldRows].add(await BinaryResultRow.fromReader(
              reader,
              session,
              props[fieldNumColumns],
            ));
          } else {
            props[fieldRows].add(await TextResultRow.fromReader(
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

  List<FieldDefinition> get columns => props[fieldColumns];

  List get rows => props[fieldRows];
}

Future<int> _readColumnCount(
  PacketSocketReader reader,
  SessionContext session,
) async {
  final buffer = await reader.readPacket();
  return readLengthEncodedInteger(
      buffer, Cursor.from(standardPacketPayloadOffset))!;
}

class FieldDefinition {
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
  static const fieldDetailsFlag = "detailsFlag";
  static const fieldDecimals = "decimals";

  static Future<FieldDefinition> fromReader(
    PacketSocketReader reader,
    SessionContext session,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.readPacket();

    cursor.increase(standardPacketHeaderLength);
    props[fieldCatalog] = readLengthEncodedString(buffer, cursor);
    props[fieldSchema] = readLengthEncodedString(buffer, cursor);
    props[fieldTableName] = readLengthEncodedString(buffer, cursor);
    props[fieldOriginalTableName] = readLengthEncodedString(buffer, cursor);
    props[fieldFieldName] = readLengthEncodedString(buffer, cursor);
    props[fieldOriginalFieldName] = readLengthEncodedString(buffer, cursor);
    if (session.hasCapabilities(capMariadbClientExtendedTypeInfo)) {
      props[fieldNumExtendedInfo] = readLengthEncodedInteger(buffer, cursor);
      props[fieldExtendedInfo] = [];
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
    props[fieldDetailsFlag] = readInteger(buffer, cursor, 2);
    props[fieldDecimals] = readInteger(buffer, cursor, 1);

    return FieldDefinition._internal(props);
  }

  final Map<String, dynamic> props;

  const FieldDefinition._internal(this.props);

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

  int get detailsFlag => props[fieldDetailsFlag];

  @override
  String toString() {
    return props.toString();
  }
}

class TextResultRow {
  static const fieldColumns = "columns";
  static const fieldColumnData = "columnData";

  static Future<TextResultRow> fromReader(
    PacketSocketReader reader,
    SessionContext session,
    int numberOfColumns,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.readPacket();

    cursor.increase(standardPacketHeaderLength);
    props[fieldColumns] = [];
    for (int i = 0; i < numberOfColumns; i++) {
      props[fieldColumns].add({
        fieldColumnData: readLengthEncodedString(buffer, cursor),
      });
    }

    return TextResultRow._internal(props);
  }

  final Map<String, dynamic> props;

  const TextResultRow._internal(this.props);

  String get data => props[fieldColumnData];
}

class BinaryResultRow {
  static const fieldNullBitmap = "nullBitmap";
  static const fieldColumns = "columns";
  static const fieldColumnData = "columnData";

  static Future<BinaryResultRow> fromReader(
    PacketSocketReader reader,
    SessionContext session,
    int numberOfColumns,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.readPacket();

    cursor.increase(standardPacketHeaderLength);
    props[fieldNullBitmap] =
        readBytes(buffer, cursor, ((numberOfColumns + 9) / 8).floor());
    props[fieldColumns] = [];
    for (int i = 0; i < numberOfColumns; i++) {
      props[fieldColumns].add({
        fieldColumnData: null,
      });
    }

    return BinaryResultRow._internal(props);
  }

  final Map<String, dynamic> props;

  const BinaryResultRow._internal(this.props);

  List<int> get nullBitmap => props[fieldNullBitmap];
}
