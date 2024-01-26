import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mysql_connector/src/commands/statement.dart';
import 'package:mysql_connector/src/datatype.dart';
import 'package:mysql_connector/src/resultset.dart';

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

  late Socket _rawSocket;

  late PacketSocket _socket;

  late ConnectionState _connectionState;

  late _SessionState _sessionState;

  late _CommandContext _commandContext;

  Connection(
    this._logger,
    this._packetCompressor,
    this._sequenceManager,
    this._connectOptions,
  );

  SessionState get sessionState => _sessionState;

  CommandContext get commandContext => _commandContext;

  void _setConnectionState(ConnectionState state) {
    _connectionState = state;
  }

  void _reset() {
    _sessionState = _SessionState();
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
      session: sessionState,
      rawSocket: rawSocket,
      receiveBufferSize: receiveBufferSize,
    );
  }

  Future<void> connect() async {
    _reset();

    _sessionState = _SessionState();
    _commandContext = _CommandContext(this);
    _rawSocket = await _createSocketAndConnect();
    _socket = _createPacketSocket(_rawSocket, 1024 * 1024 * 1);
    try {
      _setConnectionState(ConnectionState.connecting);
      final handshaker = Handshaker(
        _logger,
        _socket,
        _sessionState,
        _sessionState,
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
      maxPacketSize: _sessionState.compressionEnabled
          ? _sessionState.maxPacketSize - standardPacketHeaderLength
          : _sessionState.maxPacketSize,
    );
  }

  Future<void> ping() async {
    final command = Ping(commandContext);
    return command.execute(());
  }

  Future<dynamic> query(String sqlStatement) async {
    final command = Query(commandContext);
    return command.execute((sqlStatement: sqlStatement));
  }

  Future<PreparedStatement> prepare(String sqlStatement) async {
    final command = PrepareStmt(commandContext);
    return PreparedStatement(
      commandContext,
      await command.execute((sqlStatement: sqlStatement)),
    );
  }
}

class _SessionState implements SessionState, HandshakerDelegate {
  int _protocolVersion = 0;

  String _serverVersion = "";

  int _serverConnectionId = 0;

  int _serverDefaultCharset = 0;

  int _serverCapabilities = 0;

  int _clientCapabilities = 0;

  int _maxPacketSize = 0xffffff;

  int _charset = 0;

  bool _compressionEnabled = false;

  _SessionState();

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
  SessionState get session => connection.sessionState;

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

class PreparedStatement {
  final CommandContext _commandContext;

  final PrepareStmtResult _prepare;

  const PreparedStatement(this._commandContext, this._prepare);

  Future<void> close() async {
    final command = CloseStmt(_commandContext);
    return command.execute((statementId: _prepare.statementId));
  }

  Future<void> reset() async {
    final command = CloseStmt(_commandContext);
    return command.execute((statementId: _prepare.statementId));
  }

  Future<List<ResultSetBinaryRow>> fetch(int rowsToFetch) async {
    final command = FetchStmt(_commandContext);
    return command.execute((
      statementId: _prepare.statementId,
      rowsToFetch: rowsToFetch,
      numberOfColumns: _prepare.numberOfColumns,
      columns: _prepare.columns ?? [],
    ));
  }

  Future<void> execute([List<dynamic>? parameters]) async {
    final nullBitmap =
        parameters?.map((x) => x == null).toList().toBitmap().buffer;
    final ps = parameters?.map((x) => MysqlTypedValue.from(x)).toList();
    final command = ExecuteStmt(_commandContext);
    return command.execute((
      statementId: _prepare.statementId,
      flag: 0,
      hasParameters: parameters != null,
      nullBitmap: nullBitmap,
      sendType: true,
      types: ps
          ?.map((x) => [x.mysqlType.mysqlType, x.mysqlType.unsigned ? 128 : 0])
          .toList(),
      parameters: ps?.map((x) => x.encoded).toList(),
    ));
  }

  Future<void> bulkExecute() async {}
}
