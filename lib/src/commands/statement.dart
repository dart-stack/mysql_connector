import 'dart:typed_data';

import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/logging.dart';
import 'package:mysql_connector/src/packet.dart';
import 'package:mysql_connector/src/resultset.dart';
import 'package:mysql_connector/src/session.dart';
import 'package:mysql_connector/src/utils.dart';

typedef PrepareStmtParams = ({String sqlStatement});

final class PrepareStmt
    extends CommandBase<PrepareStmtParams, PrepareStmtResult> {
  PrepareStmt(CommandContext context) : super(context);

  @override
  Future<PrepareStmtResult> execute(PrepareStmtParams params) async {
    await enter();
    try {
      sendPacket(createPacket()
        ..addByte(0x16)
        ..addString(params.sqlStatement)
        ..terminate());
      return await PrepareStmtResult.readAndParse(reader, negotiationState);
    } finally {
      leave();
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

typedef CloseStmtParams = ({int statementId});

final class CloseStmt extends CommandBase<CloseStmtParams, void> {
  CloseStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(CloseStmtParams params) async {
    await enter();
    try {
      sendPacket(createPacket()
        ..addByte(0x19)
        ..addInteger(4, params.statementId)
        ..terminate());
    } finally {
      leave();
    }
  }
}

typedef ResetStmtParams = ({int statementId});

final class ResetStmt extends CommandBase<ResetStmtParams, void> {
  final Logger _logger = LoggerFactory.createLogger(name: "ResetStmt");

  ResetStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(ResetStmtParams params) async {
    await enter();
    try {
      sendPacket(createPacket()
        ..addByte(0x1A)
        ..addInteger(4, params.statementId)
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
      leave();
    }
  }
}

// TODO: To design a data-type abstraction mechanism to adapt variant
//  platform types.
typedef ExecuteStmtParams = ({
  int statementId,
  int flag,
  bool hasParameters,
  List<int>? nullBitmap,
  bool? sendType,
  List<List<int>>? types,
  List<List<int>>? parameters,
});

final class ExecuteStmt extends CommandBase<ExecuteStmtParams, void> {
  final Logger _logger = LoggerFactory.createLogger(name: "ExecuteStmt");

  ExecuteStmt(CommandContext context) : super(context);

  @override
  Future<dynamic> execute(ExecuteStmtParams params) async {
    await enter();
    try {
      final command = createPacket()
        ..addByte(0x17)
        ..addInteger(4, params.statementId)
        ..addInteger(1, params.flag)
        ..addInteger(4, 1);
      if (params.hasParameters) {
        command.addBytes(params.nullBitmap ?? []);
        if (params.sendType == true) {
          command.addByte(1);
          final writer = BytesBuilder();
          for (final type in params.types!) {
            writer.add(type);
          }
          command.addBytes(writer.takeBytes());
        } else {
          command.addByte(0);
        }
        final writer = BytesBuilder();
        for (final param in params.parameters!) {
          writer.add(param);
        }
        command.addBytes(writer.takeBytes());
      }
      command.terminate();
      sendPacket(command);

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
          final result = await ResultSet.readAndParse(reader, negotiationState, true);
          _logger.debug("${result.rows.length} rows was fetched");

          return result;
      }
    } finally {
      leave();
    }
  }
}

typedef FetchStmtParams = ({
  int statementId,
  int rowsToFetch,
  int numberOfColumns,
  List<ResultSetColumn> columns,
});

final class FetchStmt
    extends CommandBase<FetchStmtParams, List<ResultSetBinaryRow>> {
  final Logger _logger = LoggerFactory.createLogger(name: "FetchStmt");

  FetchStmt(CommandContext context) : super(context);

  @override
  Future<List<ResultSetBinaryRow>> execute(FetchStmtParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x17)
          ..addInteger(4, params.statementId)
          ..addInteger(4, params.rowsToFetch)
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
              params.numberOfColumns,
              params.columns,
            ));
        }
      }
    } finally {
      leave();
    }
  }
}

typedef SendLongDataStmtParams = ({
  int statementId,
  int parameter,
  int numberOfColumns,
  List<ResultSetColumn> columns,
});

final class SendLongDataStmt extends CommandBase<SendLongDataStmtParams, void> {
  final Logger _logger = LoggerFactory.createLogger(name: "SendLongDataStmt");

  SendLongDataStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(SendLongDataStmtParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x17)
          ..addInteger(4, params.statementId)
          ..addInteger(4, params.parameter)
          ..terminate(),
      );

      for (int i = 0;; i++) {
        final buffer = await reader.next();
        switch (buffer[4]) {
          case 0xFE:
            _logger.debug("$i rows was fetched");
            return;

          default:
            reader.index -= 1;
            await ResultSetBinaryRow.readAndParse(
              reader,
              negotiationState,
              params.numberOfColumns,
              params.columns,
            );
        }
      }
    } finally {
      leave();
    }
  }
}
