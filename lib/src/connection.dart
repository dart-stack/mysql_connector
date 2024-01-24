import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'command.dart';
import 'commands/ping.dart';
import 'commands/query.dart';
import 'common.dart';
import 'handshake.dart';
import 'packet.dart';
import 'compression.dart';
import 'logging.dart';
import 'sequence.dart';
import 'session.dart';
import 'socket.dart';
import 'lock.dart';
import 'utils.dart';

// extension ConnContexAwaredDataReaderExtension on ConnectionContext {
//   Map<String, dynamic> readColumnDefinition(List<int> data, [Cursor? cursor]) {
//     cursor ??= Cursor.zero();

//     final props = <String, dynamic>{};

//     readPacketHeader(data, cursor);

//     props["catalog"] = readLengthEncodedString(data, cursor);
//     props["schema"] = readLengthEncodedString(data, cursor);
//     props["table"] = readLengthEncodedString(data, cursor);
//     props["orgTable"] = readLengthEncodedString(data, cursor);
//     props["name"] = readLengthEncodedString(data, cursor);
//     props["orgName"] = readLengthEncodedString(data, cursor);
//     if (isSupportCapabilities(kCapMariadbClientExtendedTypeInfo)) {
//       final v1 = readLengthEncodedInteger(data, cursor)!;
//       for (int j = 0; j < v1; j++) {
//         readInteger(data, cursor, 1);
//         readLengthEncodedString(data, cursor);
//       }
//     }
//     props["length"] = readLengthEncodedInteger(data, cursor);
//     props["charsetNumber"] = readInteger(data, cursor, 2);
//     props["length"] = readInteger(data, cursor, 4);
//     props["type"] = readInteger(data, cursor, 1);
//     props["flags"] = readInteger(data, cursor, 2);
//     props["decimals"] = readInteger(data, cursor, 1);
//     props["unused"] = readInteger(data, cursor, 2);

//     return props;
//   }

//   dynamic _readTextResultWithConversion(
//     List<int> data,
//     Cursor cursor,
//     FieldDefinition field,
//   ) {
//     return readLengthEncodedString(data, cursor);
//   }

//   dynamic _readBinaryResultWithConversion(
//     List<int> data,
//     Cursor cursor,
//     FieldDefinition field,
//   ) {
//     switch (field.type) {
//       case kMysqlTypeInt24:
//       case kMysqlTypeLong:
//         cursor.increase(4);
//         return 0;
//     }
//   }

//   Map<String, dynamic> readResultRow(
//     List<int> data,
//     List<FieldDefinition> columns,
//     bool isBinaryRow, [
//     Cursor? cursor,
//   ]) {
//     cursor ??= Cursor.zero();

//     final props = <String, dynamic>{};
//     final columnsInRow = <dynamic>[];

//     readPacketHeader(data, cursor);

//     if (!isBinaryRow) {
//       for (int j = 0; j < columns.length; j++) {
//         columnsInRow
//             .add(_readTextResultWithConversion(data, cursor, columns[j]));
//       }
//     } else {
//       cursor.increase(1); // skip 0x00 leading byte

//       // note: null-bitmap starts at 3rd bit.
//       props["nullBitmap"] =
//           readInteger(data, cursor, ((columns.length + 9) / 8).floor());
//       for (int j = 0; j < columns.length; j++) {
//         if (((props["nullBitmap"] >> (j + 2)) & 1) != 0) {
//           columnsInRow.add(null);
//           continue;
//         }
//         columnsInRow
//             .add(_readBinaryResultWithConversion(data, cursor, columns[j]));
//       }
//     }

//     props["columns"] = columnsInRow;

//     return props;
//   }

//   Map<String, dynamic> readResultSet(
//     List<int> data,
//     bool isBinaryRow, [
//     Cursor? cursor,
//   ]) {
//     cursor ??= Cursor.zero();

//     final props = <String, dynamic>{};

//     // read metadata packet
//     readPacketHeader(data, cursor);
//     props["columnCount"] = readLengthEncodedInteger(data, cursor)!;

//     // read column definitions
//     props["columns"] = <FieldDefinition>[];
//     for (int i = 0; i < props["columnCount"]; i++) {
//       props["columns"].add(FieldDefinition(readColumnDefinition(data, cursor)));
//     }

//     // intermediate EOF packet
//     if (!isSupportCapabilities(kCapClientDeprecateEof)) {
//       readEofPacket(data, cursor);
//     }

//     // read result rows
//     props["rows"] = [];
//     for (int i = 0;; i++) {
//       if (data[cursor.position + 4] == 0xFE ||
//           data[cursor.position + 4] == 0xFF) {
//         break;
//       }
//       props["rows"]
//           .add(readResultRow(data, props["columns"], isBinaryRow, cursor));
//     }

//     if (data[cursor.position + 4] == 0xFF) {
//       readErrPacket(data, cursor);
//     } else {
//       if (isSupportCapabilities(kCapClientDeprecateEof)) {
//         readOkPacket(data, cursor);
//       } else {
//         readEofPacket(data, cursor);
//       }
//     }

//     return props;
//   }

//   Map<String, dynamic> readPrepareOk(List<int> data, [Cursor? cursor]) {
//     cursor ??= Cursor.zero();

//     final props = <String, dynamic>{};

//     readPacketHeader(data, cursor);
//     cursor.increase(1);

//     props["statementId"] = readInteger(data, cursor, 4);
//     props["numColumns"] = readInteger(data, cursor, 2);
//     props["numPlaceholders"] = readInteger(data, cursor, 2);
//     readString(data, cursor, 1);
//     props["numWarnings"] = readInteger(data, cursor, 2);

//     return props;
//   }
// }

class ConnectionFactory {
  Future<Connection> connect({
    required String host,
    required int port,
    required String user,
    required String password,
    String? database,
    bool enableCompression = true,
    int compressionThreshold = 128,
    int maxPacketSize = 0xffffff,
  }) async {
    final conn = Connection(
      ConsoleLogger(),
      PacketCompressor(),
      PacketSequenceManager(),
      ConnectOptions(
        host: host,
        port: port,
        user: user,
        password: password,
        database: database,
        enableCompression: enableCompression,
        compressionThreshold: compressionThreshold,
        maxPacketSize: maxPacketSize,
      ),
    );
    await conn.connect();

    return conn;
  }
}

enum ConnectionState {
  connecting,
  active,
  closed,
}

class Connection {
  final Logger _logger;

  final PacketCompressor _packetCompressor;

  final PacketSequenceManager _sequenceManager;

  final ConnectOptions _connectOptions;

  final QueueLock _writeLock = QueueLock();

  final QueueLock _readLock = QueueLock();

  _SessionContext _session = _SessionContext();

  late Socket _rawSocket;

  late PacketSocket _socket;

  late ConnectionState _connectionState;

  Connection(
    this._logger,
    this._packetCompressor,
    this._sequenceManager,
    this._connectOptions,
  );

  SessionContext get sessionContext => _session;

  CommandContext get commandContext => _CommandContext(this);

  void _setConnectionState(ConnectionState state) {
    _connectionState = state;
  }

  void _reset() {
    _session = _SessionContext();
    _connectionState = ConnectionState.connecting;

    final ex = MysqlConnectionResetException();
    _readLock.reset(ex);
    _writeLock.reset(ex);
  }

  Future<Socket> _createSocketAndConnect() async {
    return Socket.connect(
      _connectOptions.host,
      _connectOptions.port,
    );
  }

  PacketSocket _createPacketSocket(Socket rawSocket, int receiveBufferSize) {
    return PacketSocket(
      logger: _logger,
      packetCompressor: _packetCompressor,
      sequenceManager: _sequenceManager,
      session: sessionContext,
      rawSocket: rawSocket,
      receiveBufferSize: receiveBufferSize,
    );
  }

  Future<void> connect() async {
    _reset();

    _rawSocket = await _createSocketAndConnect();
    _socket = _createPacketSocket(_rawSocket, 1024 * 1024 * 1);
    try {
      _setConnectionState(ConnectionState.connecting);
      final handshaker = Handshaker(
        _logger,
        _socket,
        _session,
        _connectOptions,
      );
      await handshaker.perform();

      _setConnectionState(ConnectionState.active);
    } on MysqlHandshakeException {
      _setConnectionState(ConnectionState.closed);

      rethrow;
    }
  }

  Future<void> beginCommand() async {
    await _writeLock.acquire();
    _sequenceManager.resetSequence();
  }

  void endCommand() {
    _socket.gc();
    _sequenceManager.resetSequence();
    _writeLock.release();
  }

  void sendCommand(List<PacketBuilder> commands) {
    _socket.sendCommand(commands);
  }

  PacketBuilder createPacket() {
    return PacketBuilder(
      encoding: utf8,
      maxPacketSize: _session.compressionEnabled
          ? _session.maxPacketSize - standardPacketHeaderLength
          : _session.maxPacketSize,
    );
  }

  Future<void> ping() async {
    final command = Ping(commandContext);
    final params = PingParams();

    return command.execute(params);
  }

  Future<dynamic> query(String sql) async {
    final command = Query(commandContext);
    final params = QueryParams(
      sql: sql,
    );

    return command.execute(params);
  }

  // Future<PreparedStatement> prepare(String sql) async {
  //   await acquireWriteLock();
  //   startConversation();

  //   final payload = <int>[];

  //   writeBytes(payload, [0x16]);
  //   writeString(payload, sql);

  //   return sendCommand(
  //     buildPacket(payload),
  //     handler: _handleStmtPrepareResponse,
  //     debugName: "COM_STMT_PREPARE",
  //   );
  // }

  // Future<PreparedStatement> _handleStmtPrepareResponse(
  //   ConversationContext context,
  //   List<int> message,
  // ) {
  //   switch (message[4]) {
  //     case 0xFF:
  //       final props = readErrPacket(message);
  //       _logger.debug(props);

  //       releaseWriteLock();
  //       return Future.error(props["message"]);

  //     default:
  //       final cursor = Cursor.zero();
  //       final props = readPrepareOk(message, cursor);
  //       final columnDefinitions = [];
  //       final placeholderDefinitions = [];

  //       _logger.debug(props);
  //       if (props["numColumns"] > 0) {
  //         for (int i = 0; i < props["numColumns"]; i++) {
  //           columnDefinitions.add(readColumnDefinition(message, cursor));
  //         }
  //         if (!isSupportCapabilities(kCapClientDeprecateEof)) {
  //           readEofPacket(message, cursor);
  //         }
  //       }
  //       if (props["numPlaceholders"] > 0) {
  //         for (int i = 0; i < props["numPlaceholders"]; i++) {
  //           placeholderDefinitions.add(readColumnDefinition(message, cursor));
  //         }
  //         if (!isSupportCapabilities(kCapClientDeprecateEof)) {
  //           readEofPacket(message, cursor);
  //         }
  //       }

  //       releaseWriteLock();
  //       return Future.value(PreparedStatement(
  //         _logger,
  //         this,
  //         this,
  //         this,
  //         props,
  //         columnDefinitions.map((props) => FieldDefinition(props)).toList(),
  //         placeholderDefinitions
  //             .map((props) => FieldDefinition(props))
  //             .toList(),
  //       ));
  //   }
  // }
}

class _SessionContext implements SessionContext, HandshakeDelegate {
  int _protocolVersion = 0;

  String _serverVersion = "";

  int _serverConnectionId = 0;

  int _serverDefaultCharset = 0;

  int _serverCapabilities = 0;

  int _clientCapabilities = 0;

  int _maxPacketSize = 0xffffff;

  int _charset = 0;

  bool _compressionEnabled = false;

  _SessionContext();

  @override
  int get protocolVersion => _protocolVersion;

  @override
  String get serverVersion => _serverVersion;

  @override
  int get serverConnectionId => _serverConnectionId;

  @override
  int get serverDefaultCharset => _serverDefaultCharset;

  @override
  int get serverCapabilities => _serverCapabilities;

  @override
  int get clientCapabilities => _clientCapabilities;

  @override
  int get maxPacketSize => _maxPacketSize;

  @override
  bool get compressionEnabled => _compressionEnabled;

  @override
  int get charset => _charset;

  @override
  bool hasCapabilities(int capabilities) {
    return clientCapabilities & serverCapabilities & capabilities > 0;
  }

  @override
  void setProtocolVersion(int protocolVersion) {
    _protocolVersion = protocolVersion;
  }

  @override
  void setServerVersion(String serverVersion) {
    _serverVersion = serverVersion;
  }

  @override
  void setServerConnectionId(int serverConnectionId) {
    _serverConnectionId = serverConnectionId;
  }

  @override
  void setServerDefaultCharset(int serverDefaultCharset) {
    _serverDefaultCharset = serverDefaultCharset;
  }

  @override
  void setServerCapabilities(int serverCapabilities) {
    _serverCapabilities = serverCapabilities;
  }

  @override
  void setClientCapabilities(int clientCapabilities) {
    _clientCapabilities = clientCapabilities;
  }

  @override
  void setMaxPacketSize(int maxPacketSize) {
    _maxPacketSize = maxPacketSize;
  }

  @override
  void setCharset(int charset) {
    _charset = charset;
  }

  @override
  void setCompressionEnabled(bool compressionEnabled) {
    _compressionEnabled = compressionEnabled;
  }
}

class _CommandContext implements CommandContext {
  final Connection connection;

  const _CommandContext(this.connection);

  @override
  Logger get logger => connection._logger;

  @override
  SessionContext get session => connection.sessionContext;

  @override
  PacketSocketReader get socketReader => connection._socket;

  @override
  PacketBuilder createPacket() {
    return connection.createPacket();
  }

  @override
  Future<void> beginCommand() {
    return connection.beginCommand();
  }

  @override
  void endCommand() {
    return connection.endCommand();
  }

  @override
  void sendCommand(List<PacketBuilder> commands) {
    return connection.sendCommand(commands);
  }
}

// class PreparedStatement {
//   final Logger _logger;

//   final ConnectionContext _connection;

//   final CommandContext _commander;

//   final PacketBuilder _packetBuilder;

//   final Map<String, dynamic> _statement;

//   int get statementId => _statement["statementId"];

//   final List<FieldDefinition> _columns;

//   final List<FieldDefinition> _placeholders;

//   PreparedStatement(
//     this._logger,
//     this._connection,
//     this._commander,
//     this._packetBuilder,
//     this._statement,
//     this._columns,
//     this._placeholders,
//   );

//   Future<dynamic> execute(List<dynamic> boundParameters) async {
//     await _connection.acquireWriteLock();
//     _connection.startConversation();

//     final payload = <int>[];

//     writeBytes(payload, [0x17]);
//     writeInteger(payload, 4, statementId);
//     writeInteger(payload, 1, 0x00);
//     writeInteger(payload, 4, 1);
//     if (boundParameters.isNotEmpty) {
//       writeBytes(payload,
//           buildNullBitmap(boundParameters.map((x) => x == null).toList()));
//       final sendType = false;
//       writeInteger(payload, 1, sendType ? 1 : 0);
//       if (sendType) {
//         for (int i = 0; i < boundParameters.length; i++) {
//           writeInteger(payload, 1, kMysqlTypeTiny);
//           writeInteger(payload, 1, 0);
//         }
//       }
//       for (int i = 0; i < boundParameters.length; i++) {
//         writeInteger(payload, 1, 0);
//       }
//     }
//     for (int i = 0; i < boundParameters.length; i++) {}

//     return _commander.sendCommand(
//       _packetBuilder.buildPacket(payload),
//       handler: _handleStmtExecuteResponse,
//       debugName: "COM_STMT_EXECUTE",
//     );
//   }

//   Future<dynamic> _handleStmtExecuteResponse(
//     ConversationContext context,
//     List<int> message,
//   ) {
//     switch (message[4]) {
//       case 0x00:
//         final props = readOkPacket(message);
//         _logger.debug(props);

//         _connection.releaseWriteLock();
//         return Future.value(props);

//       case 0xFF:
//         final props = readErrPacket(message);
//         _logger.debug(props);

//         _connection.releaseWriteLock();
//         return Future.error(props["message"]);

//       default:
//         final props = _connection.readResultSet(message, true);
//         _logger.debug(props);

//         _connection.releaseWriteLock();
//         return Future.value(props);
//     }
//   }

//   Future<dynamic> fetch(int rowsToFetch) async {
//     await _connection.acquireWriteLock();
//     _connection.startConversation();

//     final payload = <int>[];

//     writeBytes(payload, [0x1C]);
//     writeInteger(payload, 4, statementId);
//     writeInteger(payload, 4, rowsToFetch);

//     return _commander.sendCommand(
//       _packetBuilder.buildPacket(payload),
//       handler: _handleStmtFetchResponse,
//       debugName: "COM_STMT_FETCH",
//     );
//   }

//   Future<dynamic> _handleStmtFetchResponse(
//     ConversationContext context,
//     List<int> message,
//   ) {
//     switch (message[4]) {
//       case 0xFF:
//         final props = readErrPacket(message);

//         _connection.releaseWriteLock();
//         return Future.error(props["message"]);
//     }

//     final cursor = Cursor.zero();
//     final result = [];
//     for (;;) {
//       if (message[cursor.position + 4] == 0xFE) {
//         readEofPacket(message, cursor);
//         break;
//       }
//       result.add(_connection.readResultRow(message, _columns, true));
//     }

//     _connection.releaseWriteLock();
//     return Future.value(result);
//   }

//   Future<void> close() async {
//     await _connection.acquireWriteLock();
//     _connection.startConversation();

//     final buffer = <int>[];
//     buffer.addAll([0x00, 0x00, 0x00, 0x00]);

//     writeBytes(buffer, [0x19]);
//     writeInteger(buffer, 4, statementId);

//     return _commander.sendCommand(
//       buffer,
//       hasResponse: true,
//       onSent: () {
//         _connection.releaseWriteLock();
//       },
//       debugName: "COM_STMT_CLOSE",
//     );
//   }
// }
