import 'dart:io';
import 'dart:typed_data';

import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/logging.dart';
import 'package:mysql_connector/src/protocols/protocol.dart';
import 'package:mysql_connector/src/session.dart';
import 'package:mysql_connector/src/utils.dart';
import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/packet.dart';

final class MariaDbLowLevelProtocol implements LowLevelProtocol {
  final Logger _logger =
      LoggerFactory.createLogger(name: "MariaDbLowLevelProtocol");

  final CommandContext _context;

  final Directory _rootDir;

  MariaDbLowLevelProtocol(
    this._context,
    this._rootDir,
  );

  NegotiationState get negotiationState => _context.negotiationState;

  PacketStreamReader get reader => _context.reader;

  Future<void> _enterCommand() async {
    await _context.beginCommand();
  }

  void _leaveCommand() {
    _context.endCommand();
  }

  void _send(PacketBuilder builder) {
    _context.sendPacket(builder);
  }

  PacketBuilder _newPacket() {
    return _context.createPacket();
  }

  Future<void> debug() async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x0D)
          ..terminate(),
      );

      final packet = await reader.next();
      switch (packet[4]) {
        case 0x00:
          return;

        case 0xFF:
          final err = ErrPacket.parse(packet, negotiationState);
          err.throwIfError((error) => MysqlExecutionException(
                err.errorCode,
                err.errorMessage,
                err.sqlState,
              ));
      }
    } finally {
      _leaveCommand();
    }
  }

  Future<void> ping() async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x0e)
          ..terminate(),
      );

      _logger.debug(await reader.next());
    } finally {
      _leaveCommand();
    }
  }

  Future<void> setOption(int option) async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x1B)
          ..addInteger(2, option)
          ..terminate(),
      );

      final packet = await reader.next();
      switch (packet[4]) {
        case 0x00:
          return;

        case 0xFF:
          final err = ErrPacket.parse(packet, negotiationState);
          err.throwIfError((error) => MysqlExecutionException(
                err.errorCode,
                err.errorMessage,
                err.sqlState,
              ));
      }
    } finally {
      _leaveCommand();
    }
  }

  Future<void> quit() async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x01)
          ..terminate(),
      );
    } finally {
      _leaveCommand();
    }
  }

  Future<void> resetConnection() async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x1F)
          ..terminate(),
      );
      await reader.next();
    } finally {
      _leaveCommand();
    }
  }

  Future<void> shutdown() async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x0A)
          ..addByte(0x00)
          ..terminate(),
      );
      await reader.next();
    } finally {
      _leaveCommand();
    }
  }

  Future<String> stat() async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x09)
          ..terminate(),
      );

      final packet = await reader.next();
      return readString(
        packet,
        Cursor.from(standardPacketHeaderLength),
        packet.length - standardPacketHeaderLength,
      );
    } finally {
      _leaveCommand();
    }
  }

  Future<dynamic> query(String sqlStmt) async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x03)
          ..addString(sqlStmt)
          ..terminate(),
      );

      List<int> packet = await reader.next();
      switch (packet[4]) {
        case 0x00:
          final result = OkPacket.parse(packet, negotiationState);
          _logger.debug(result);
          return;

        case 0xFF:
          final props = ErrPacket.parse(packet, negotiationState);
          _logger.debug(props);

          return Future.error(MysqlExecutionException(
            props.errorCode,
            props.errorMessage,
            props.sqlState,
          ));

        case 0xFB:
          final props = readLocalInfilePacket(packet);
          _logger.debug(props);

          final file = File("${_rootDir.path}/${props["filename"]}");
          if (!await file.exists()) {
            throw FileSystemException(
              "file cannot be found",
              "${_rootDir.path}/${props["filename"]}",
            );
          }

          _send(
            _newPacket()
              ..addBytes(await file.readAsBytes())
              ..terminate(),
          );
          _send(
            _newPacket()..terminate(),
          );

          packet = await reader.next();
          switch (packet[4]) {
            case 0x00:
              final ok = OkPacket.parse(packet, negotiationState);
              _logger.debug(ok);
              return;

            case 0xFF:
              final err = ErrPacket.parse(packet, negotiationState);
              _logger.debug(err);
              err.throwIfError((e) => MysqlExecutionException(
                    e.errorCode,
                    e.errorMessage,
                    e.sqlState,
                  ));
          }

        default:
          reader.index -= 1;
          final rs =
              await ResultSet.readAndParse(reader, negotiationState, false);
          _logger.debug("${rs.rows.length} rows was fetched");
          return rs;
      }
    } finally {
      _leaveCommand();
    }
  }

  Future<PrepareStmtResult> prepare(String preparedStmt) async {
    await _enterCommand();
    try {
      _send(_newPacket()
        ..addByte(0x16)
        ..addString(preparedStmt)
        ..terminate());
      return await PrepareStmtResult.readAndParse(reader, negotiationState);
    } finally {
      _leaveCommand();
    }
  }

  Future<void> closeStatement(int statementId) async {
    await _enterCommand();
    try {
      _send(_newPacket()
        ..addByte(0x19)
        ..addInteger(4, statementId)
        ..terminate());
    } finally {
      _leaveCommand();
    }
  }

  Future<void> resetStatement(int statementId) async {
    await _enterCommand();
    try {
      _send(_newPacket()
        ..addByte(0x1A)
        ..addInteger(4, statementId)
        ..terminate());

      final buffer = await reader.next();
      switch (buffer[4]) {
        case 0x00:
          final ok = OkPacket.parse(buffer, negotiationState);
          _logger.debug(ok);
          return;

        case 0xff:
          final err = ErrPacket.parse(buffer, negotiationState);
          _logger.debug(err);

          err.throwIfError((error) => MysqlExecutionException(
              error.errorCode, error.errorMessage, error.sqlState));
          return;
      }
    } finally {
      _leaveCommand();
    }
  }

  Future<dynamic> execute(
    int statementId, {
    required int flag,
    required bool hasParameters,
    List<int>? nullBitmap,
    bool? sendType,
    List<List<int>>? types,
    List<List<int>>? parameters,
  }) async {
    await _enterCommand();
    try {
      final command = _newPacket()
        ..addByte(0x17)
        ..addInteger(4, statementId)
        ..addInteger(1, flag)
        ..addInteger(4, 1);
      if (hasParameters) {
        command.addBytes(nullBitmap ?? []);
        if (sendType == true) {
          command.addByte(1);
          final writer = BytesBuilder();
          for (final type in types!) {
            writer.add(type);
          }
          command.addBytes(writer.takeBytes());
        } else {
          command.addByte(0);
        }
        final writer = BytesBuilder();
        for (final param in parameters!) {
          writer.add(param);
        }
        command.addBytes(writer.takeBytes());
      }
      command.terminate();
      _send(command);

      final buffer = await reader.next();
      switch (buffer[4]) {
        case 0x00:
          final ok = OkPacket.parse(buffer, negotiationState);
          _logger.debug(ok);
          return;

        case 0xff:
          final err = ErrPacket.parse(buffer, negotiationState);
          _logger.debug(err);

          err.throwIfError((error) => MysqlExecutionException(
              error.errorCode, error.errorMessage, error.sqlState));
          return;

        default:
          // TODO: handle multiple result sets
          reader.index -= 1;
          final result =
              await ResultSet.readAndParse(reader, negotiationState, true);
          _logger.debug("${result.rows.length} rows was fetched");

          return result;
      }
    } finally {
      _leaveCommand();
    }
  }

  Future<List<ResultSetBinaryRow>> fetch(
    int statementId,
    int rowsToFetch,
    int numberOfColumns,
    List<ResultSetColumn> columns,
  ) async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x17)
          ..addInteger(4, statementId)
          ..addInteger(4, rowsToFetch)
          ..terminate(),
      );

      final rows = <ResultSetBinaryRow>[];
      for (int i = 0;; i++) {
        final buffer = await reader.next();
        switch (buffer[4]) {
          case 0xFE:
            _logger.debug("$i rows was fetched");
            return rows;

          default:
            reader.index -= 1;
            rows.add(await ResultSetBinaryRow.readAndParse(
              reader,
              negotiationState,
              numberOfColumns,
              columns,
            ));
        }
      }
    } finally {
      _leaveCommand();
    }
  }

  Future<void> sendLongData(
    int statementId,
    int parameterPosition,
    List<int> data,
  ) async {
    await _enterCommand();
    try {
      _send(
        _newPacket()
          ..addByte(0x18)
          ..addInteger(4, statementId)
          ..addInteger(2, parameterPosition)
          ..addBytes(data)
          ..terminate(),
      );
    } finally {
      _leaveCommand();
    }
  }
}

class PrepareStmtResult {
  static const fieldStatementId = "statementId";
  static const fieldNumColumns = "numColumns";
  static const fieldNumPlaceholders = "numPlaceholders";
  static const fieldColumns = "columns";
  static const fieldPlaceholders = "placeholders";

  static Future<PrepareStmtResult> readAndParse(
    PacketStreamReader reader,
    NegotiationState negotiationState,
  ) async {
    final props = <String, dynamic>{};
    // process first packet
    {
      final cursor = Cursor.zero();
      final buffer = await reader.next();

      cursor.increment(standardPacketHeaderLength);
      switch (readInteger(buffer, cursor, 1)) {
        case 0x00:
          props[fieldStatementId] = readInteger(buffer, cursor, 4);
          props[fieldNumColumns] = readInteger(buffer, cursor, 2);
          props[fieldNumPlaceholders] = readInteger(buffer, cursor, 2);
          break;

        case 0xFF:
          throw Exception("error!");
      }
    }
    if (props[fieldNumPlaceholders] > 0) {
      props[fieldPlaceholders] = <ResultSetColumn>[];
      for (int i = 0; i < props[fieldNumPlaceholders]; i++) {
        props[fieldPlaceholders]
            .add(await ResultSetColumn.readAndParse(reader, negotiationState));
      }
      if (!negotiationState.hasCapabilities(capClientDeprecateEof)) {
        await reader.next();
      }
    }
    if (props[fieldNumColumns] > 0) {
      props[fieldColumns] = <ResultSetColumn>[];
      for (int i = 0; i < props[fieldNumColumns]; i++) {
        props[fieldColumns]
            .add(await ResultSetColumn.readAndParse(reader, negotiationState));
      }
      if (!negotiationState.hasCapabilities(capClientDeprecateEof)) {
        await reader.next();
      }
    }

    return PrepareStmtResult(props);
  }

  final Map<String, dynamic> props;

  const PrepareStmtResult(this.props);

  int get statementId => props[fieldStatementId];

  int get numberOfColumns => props[fieldNumColumns];

  int get numberOfPlaceholders => props[fieldNumPlaceholders];

  List<ResultSetColumn>? get columns => props[fieldColumns];

  List<ResultSetColumn>? get placeholders => props[fieldPlaceholders];
}
