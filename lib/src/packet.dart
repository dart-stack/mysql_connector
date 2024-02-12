import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mysql_connector/src/lock.dart';
import 'package:mysql_connector/src/logging.dart';

import 'common.dart';
import 'datatype.dart';
import 'session.dart';
import 'utils.dart';

class PacketBuilder {
  final BytesBuilder _payloadWriter = BytesBuilder();

  final List<(int, int)> _payloadRanges = [];

  final Encoding _encoding;

  final int _maxPacketSize;

  int _lastTerminatedAt = 0;

  PacketBuilder({
    Encoding encoding = utf8,
    int maxPacketSize = 0xffffff,
  })  : _encoding = encoding,
        _maxPacketSize = maxPacketSize;

  int get length =>
      _payloadWriter.length +
      min(1, (_payloadWriter.length / _maxPacketSize).ceil()) * 4;

  void addByte(int byte) {
    _payloadWriter.addByte(byte);
  }

  void addBytes(List<int> bytes) {
    _payloadWriter.add(bytes);
  }

  void addInteger(int length, int value) {
    assert(const [1, 2, 3, 4, 6, 8].contains(length));

    for (int i = 0; i < length; i++) {
      _payloadWriter.addByte((value >> (i * 8)) & 0xff);
    }
  }

  void addString(String value) {
    _payloadWriter.add(_encoding.encode(value));
  }

  void addLengthEncodedInteger(int? value) {
    if (value == null) {
      _payloadWriter.addByte(0xFB);
      return;
    }
    if (value < 0xfb) {
      _payloadWriter.addByte(value);
    } else if (value <= 0xffff) {
      _payloadWriter.addByte(0xFC);
      _payloadWriter.addByte((value >> 0) & 0xff);
      _payloadWriter.addByte((value >> 8) & 0xff);
    } else if (value <= 0xffffff) {
      _payloadWriter.addByte(0xFD);
      _payloadWriter.addByte((value >> 0) & 0xff);
      _payloadWriter.addByte((value >> 8) & 0xff);
      _payloadWriter.addByte((value >> 16) & 0xff);
    } else {
      _payloadWriter.addByte(0xFE);
      _payloadWriter.addByte((value >> 0) & 0xff);
      _payloadWriter.addByte((value >> 8) & 0xff);
      _payloadWriter.addByte((value >> 16) & 0xff);
      _payloadWriter.addByte((value >> 24) & 0xff);
      _payloadWriter.addByte((value >> 32) & 0xff);
      _payloadWriter.addByte((value >> 40) & 0xff);
      _payloadWriter.addByte((value >> 48) & 0xff);
      _payloadWriter.addByte((value >> 56) & 0xff);
    }
  }

  void addLengthEncodedString(String? value) {
    if (value == null) {
      addLengthEncodedInteger(null);
      return;
    }
    final encoded = _encoding.encode(value);
    addLengthEncodedInteger(encoded.length);
    _payloadWriter.add(encoded);
  }

  void addZeroTerminatingString(String value) {
    _payloadWriter.add(_encoding.encode(value));
    _payloadWriter.addByte(0x00);
  }

  void terminate() {
    final start = _lastTerminatedAt;
    final end = _payloadWriter.length;
    _payloadRanges.add((start, end));
    _lastTerminatedAt = end;
  }

  Uint8List _buildPacketLength(int length) {
    final buffer = Uint8List(3);
    buffer[0] = (length >> 0) & 0xff;
    buffer[1] = (length >> 8) & 0xff;
    buffer[2] = (length >> 16) & 0xff;

    return buffer;
  }

  Uint8List _splitAndBuild() {
    if (_payloadWriter.isEmpty) {
      return Uint8List(4)..setRange(0, 4, const [0x00, 0x00, 0x00, 0x00]);
    }
    final packetBuffer = BytesBuilder();
    final payloadBuffer = _payloadWriter.toBytes();

    int sequence = 0;
    bool appendEmptyPacket = false;
    for (final payloadRange in _payloadRanges) {
      int offset = payloadRange.$1;
      for (;;) {
        if (offset == payloadRange.$2) {
          // Note: once the length of last packet's payload reaches 0xffffff,
          //  it is required to append an empty packet to indicate the packet
          //  is terminated.
          // See https://mariadb.com/kb/en/0-packet/#packet-splitting
          if (appendEmptyPacket) {
            packetBuffer.add(const [0x00, 0x00, 0x00]);
            packetBuffer.addByte(sequence++);
          }
          break;
        }
        if (payloadRange.$2 - offset > _maxPacketSize) {
          packetBuffer.add(_buildPacketLength(_maxPacketSize));
          packetBuffer.addByte(sequence++);
          packetBuffer
              .add(payloadBuffer.sublist(offset, offset + _maxPacketSize));
          offset += _maxPacketSize;
          appendEmptyPacket = true;
        } else {
          packetBuffer.add(_buildPacketLength(payloadRange.$2 - offset));
          packetBuffer.addByte(sequence++);
          packetBuffer.add(payloadBuffer.sublist(offset, payloadRange.$2));
          offset = payloadRange.$2;
          appendEmptyPacket = false;
        }
        // reset sequence if sequence is exceeded.
        if (sequence == 0xff + 1) {
          sequence = 0;
        }
      }
    }
    return packetBuffer.takeBytes();
  }

  Uint8List build() {
    return _splitAndBuild();
  }
}

typedef _PendingEntry = (int, Completer<List<int>>);

class PacketStreamReader {
  final Logger _logger = LoggerFactory.createLogger(name: "PacketStreamReader");

  final QueueLock _lock = QueueLock();

  final Stream<List<int>> _stream;

  final List<List<int>> _buffer = [];

  final List<_PendingEntry> _pendings = [];

  late StreamSubscription _subscription;

  int _index = 0;

  PacketStreamReader(this._stream) {
    _subscription = _stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  void _onData(List<int> packet) async {
    _buffer.add(packet);
    _processPendings();
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    _processPendings();
    for (; _pendings.isNotEmpty;) {
      final pending = _pendings.removeAt(0);
      pending.$2.completeError(error, stackTrace);
    }
  }

  void _onDone() {
    _processPendings();
    for (; _pendings.isNotEmpty;) {
      final pending = _pendings.removeAt(0);
      pending.$2.completeError(MysqlConnectionException(
          "cannot read any more from the stream when the socket was closed"));
    }
  }

  bool _processing = false;

  void _processPendings() {
    if (_processing) {
      return;
    }
    _processing = true;
    final pendings = _pendings.toList();
    for (final pending in pendings) {
      if (_buffer.length > pending.$1) {
        pending.$2.complete(_buffer[pending.$1]);
        _pendings.remove(pending);
      }
    }
    _processing = false;
  }

  int get index => _index;

  set index(int newIndex) {
    assert(newIndex >= 0);
    _index = newIndex;
  }

  Future<List<int>> next() async {
    final completer = Completer<List<int>>();
    _pendings.add((_index++, completer));
    _processPendings();

    return completer.future;
  }
}

Map<String, dynamic> readLocalInfilePacket(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();

  final props = <String, dynamic>{};

  cursor.increment(4);
  cursor.increment(1);
  props["filename"] =
      readString(buffer, cursor, buffer.length - cursor.position);

  return props;
}

sealed class Packet {
  const Packet();
}

class OkPacket extends Packet {
  static const fieldAffectedRows = "affectedRows";
  static const fieldLastInsertId = "lastInsertId";
  static const fieldServerStatus = "serverStatus";
  static const fieldNumWarning = "numWarning";
  static const fieldInfo = "info";
  static const fieldSessionStateInfo = "sessionStateInfo";

  static OkPacket parse(
    List<int> buffer,
    NegotiationState negotiationState, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increment(standardPacketHeaderLength + 1);
    props[fieldAffectedRows] = readLengthEncodedInteger(buffer, cursor);
    props[fieldLastInsertId] = readLengthEncodedInteger(buffer, cursor);
    props[fieldServerStatus] = readInteger(buffer, cursor, 2);
    props[fieldNumWarning] = readInteger(buffer, cursor, 2);
    if (cursor.position < buffer.length) {
      props[fieldInfo] = readLengthEncodedString(buffer, cursor);
      if (negotiationState.hasCapabilities(capClientSessionTrack) &&
          (props[fieldServerStatus] & serverSessionStateChanged) > 0) {
        props[fieldSessionStateInfo] = readLengthEncodedString(buffer, cursor);
      }
    }

    return OkPacket._internal(props);
  }

  static Future<OkPacket> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
  ) async {
    return parse(await reader.next(), negotiationState);
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

class ErrPacket extends Packet {
  static const fieldErrorCode = "errorCode";
  static const fieldStage = "stage";
  static const fieldMaxStage = "maxStage";
  static const fieldProgress = "progress";
  static const fieldProgressInfo = "progressInfo";
  static const fieldSqlState = "sqlState";
  static const fieldErrorMessage = "errorMessage";

  static ErrPacket parse(
    List<int> buffer,
    NegotiationState negotiationState, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increment(standardPacketHeaderLength + 1);
    props[fieldErrorCode] = readInteger(buffer, cursor, 2);
    if (props[fieldErrorCode] == 0xffffff) {
      props[fieldStage] = readInteger(buffer, cursor, 1);
      props[fieldMaxStage] = readInteger(buffer, cursor, 1);
      props[fieldProgress] = readInteger(buffer, cursor, 3);
      props[fieldProgressInfo] = readLengthEncodedString(buffer, cursor);
    } else {
      if (buffer[cursor.position] == 35) {
        cursor.increment(1);
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

  static Future<ErrPacket> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
  ) async {
    return parse(await reader.next(), negotiationState);
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

class EofPacket extends Packet {
  static const fieldNumWarnings = "numWarnings";
  static const fieldServerStatus = "serverStatus";

  static EofPacket parse(
    List<int> buffer,
    NegotiationState negotiationState, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increment(standardPacketHeaderLength + 1);
    props[fieldNumWarnings] = readInteger(buffer, cursor, 2);
    props[fieldServerStatus] = readInteger(buffer, cursor, 2);

    return EofPacket._internal(props);
  }

  static Future<EofPacket> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
  ) async {
    return parse(await reader.next(), negotiationState);
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

class ResultSet {
  static const fieldNumColumns = "numColumns";
  static const fieldColumns = "columns";
  static const fieldRows = "rows";

  // TODO: Deprecate PacketSocketReader, and use Stream instead.
  static Future<ResultSet> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
    bool binary,
  ) async {
    final props = <String, dynamic>{};

    props[fieldNumColumns] =
        readLengthEncodedInteger(await reader.next(), Cursor.from(4))!;

    props[fieldColumns] = <ResultSetColumn>[];

    // TODO: if not (MARIADB_CLIENT_CACHE_METADATA capability set)
    //  OR (send metadata == 1)
    for (int i = 0; i < props[fieldNumColumns]; i++) {
      props[fieldColumns]
          .add(await ResultSetColumn.readAndParse(reader, negotiationState));
    }
    if (!negotiationState.hasCapabilities(capClientDeprecateEof)) {
      await reader.next();
    }
    props[fieldRows] = [];
    for (int i = 0;; i++) {
      final buffer = await reader.next();
      switch (buffer[standardPacketPayloadOffset + 0]) {
        case 0xFE:
          return ResultSet._internal(props);

        case 0xFF:
          throw Exception("error!");

        default:
          reader.index -= 1;
          if (binary) {
            props[fieldRows].add(await ResultSetBinaryRow.readAndParse(
              reader,
              negotiationState,
              props[fieldNumColumns],
              props[fieldColumns],
            ));
          } else {
            props[fieldRows].add(await ResultSetTextRow.readAndParse(
              reader,
              negotiationState,
              props[fieldNumColumns],
              props[fieldColumns],
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

  static Future<ResultSetColumn> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.next();

    cursor.increment(standardPacketHeaderLength);
    props[fieldCatalog] = readLengthEncodedString(buffer, cursor);
    props[fieldSchema] = readLengthEncodedString(buffer, cursor);
    props[fieldTableName] = readLengthEncodedString(buffer, cursor);
    props[fieldOriginalTableName] = readLengthEncodedString(buffer, cursor);
    props[fieldFieldName] = readLengthEncodedString(buffer, cursor);
    props[fieldOriginalFieldName] = readLengthEncodedString(buffer, cursor);
    if (negotiationState.hasCapabilities(capMariadbClientExtendedTypeInfo)) {
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

  MysqlType get mysqlType => MysqlType(fieldType, unsigned, length, decimals);

  @override
  String toString() {
    return props.toString();
  }
}

class ResultSetTextRow {
  static const fieldColumns = "columns";

  static Future<ResultSetTextRow> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
    int numberOfColumns,
    List<ResultSetColumn> columns,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.next();

    cursor.increment(standardPacketHeaderLength);
    props[fieldColumns] = <dynamic>[];
    for (int i = 0; i < numberOfColumns; i++) {
      props[fieldColumns]
          .add(decodeForText(buffer, columns[i].mysqlType, cursor));
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

  static Future<ResultSetBinaryRow> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
    int numberOfColumns,
    List<ResultSetColumn> columns,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    final buffer = await reader.next();

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
        props[fieldColumns]
            .add(decodeForBinary(buffer, columns[i].mysqlType, cursor));
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
