import 'dart:typed_data';

import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';
import 'package:mysql_connector/src/resultset.dart';
import 'package:mysql_connector/src/session.dart';
import 'package:mysql_connector/src/socket.dart';
import 'package:mysql_connector/src/utils.dart';

typedef PrepareStmtParams = ({String sqlStatement});

final class PrepareStmt
    extends CommandBase<PrepareStmtParams, PrepareStmtResult> {
  PrepareStmt(CommandContext context) : super(context);

  @override
  Future<PrepareStmtResult> execute(PrepareStmtParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x16)
          ..addString(params.sqlStatement)
          ..terminated()
      ]);
      return await PrepareStmtResult.fromReader(socketReader, session);
    } finally {
      release();
    }
  }
}

class PrepareStmtResult {
  static const fieldStatementId = "statementId";
  static const fieldNumColumns = "numColumns";
  static const fieldNumPlaceholders = "numPlaceholders";
  static const fieldColumns = "columns";
  static const fieldPlaceholders = "placeholders";

  static Future<PrepareStmtResult> fromReader(
    PacketSocketReader reader,
    SessionState session,
  ) async {
    final props = <String, dynamic>{};
    // process first packet
    {
      final cursor = Cursor.zero();
      final buffer = await reader.readPacket();

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
            .add(await ResultSetColumn.fromReader(reader, session));
      }
      if (!session.hasCapabilities(capClientDeprecateEof)) {
        await reader.readPacket();
      }
    }
    if (props[fieldNumColumns] > 0) {
      props[fieldColumns] = <ResultSetColumn>[];
      for (int i = 0; i < props[fieldNumColumns]; i++) {
        props[fieldColumns]
            .add(await ResultSetColumn.fromReader(reader, session));
      }
      if (!session.hasCapabilities(capClientDeprecateEof)) {
        await reader.readPacket();
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
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x19)
          ..addInteger(4, params.statementId)
          ..terminated()
      ]);
    } finally {
      release();
    }
  }
}

typedef ResetStmtParams = ({int statementId});

final class ResetStmt extends CommandBase<ResetStmtParams, void> {
  ResetStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(ResetStmtParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x1A)
          ..addInteger(4, params.statementId)
          ..terminated()
      ]);

      final buffer = await socketReader.readPacket();
      switch (buffer[4]) {
        case 0x00:
          final ok = OkPacket.from(buffer, session);
          logger.debug(ok);
          return;

        case 0xff:
          final err = ErrPacket.from(buffer, session);
          logger.debug(err);

          err.throwIfError((error) => MysqlExecutionException(
              error.errorCode, error.errorMessage, error.sqlState));
          return;
      }
    } finally {
      release();
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
  ExecuteStmt(CommandContext context) : super(context);

  @override
  Future<dynamic> execute(ExecuteStmtParams params) async {
    await acquire();
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
      command.terminated();
      sendCommand([command]);

      final buffer = await socketReader.readPacket();
      switch (buffer[4]) {
        case 0x00:
          final ok = OkPacket.from(buffer, session);
          logger.debug(ok);
          return;

        case 0xff:
          final err = ErrPacket.from(buffer, session);
          logger.debug(err);

          err.throwIfError((error) => MysqlExecutionException(
              error.errorCode, error.errorMessage, error.sqlState));
          return;

        default:
          // TODO: handle multiple result sets
          socketReader.cursor.increment(-buffer.length);
          final result =
              await ResultSet.fromSocket(socketReader, session, true);
          print("${result.rows.length} rows was fetched");

          return result;
      }
    } finally {
      release();
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
  FetchStmt(CommandContext context) : super(context);

  @override
  Future<List<ResultSetBinaryRow>> execute(FetchStmtParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x17)
          ..addInteger(4, params.statementId)
          ..addInteger(4, params.rowsToFetch)
          ..terminated(),
      ]);

      final rows = <ResultSetBinaryRow>[];
      for (int i = 0;; i++) {
        final buffer = await socketReader.readPacket();
        switch (buffer[4]) {
          case 0xFE:
            logger.debug("$i rows was fetched");
            return rows;

          default:
            socketReader.cursor.increment(-buffer.length);
            rows.add(await ResultSetBinaryRow.fromReader(
              socketReader,
              session,
              params.numberOfColumns,
              params.columns,
            ));
        }
      }
    } finally {
      release();
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
  SendLongDataStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(SendLongDataStmtParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x17)
          ..addInteger(4, params.statementId)
          ..addInteger(4, params.parameter)
          ..terminated(),
      ]);

      for (int i = 0;; i++) {
        final buffer = await socketReader.readPacket();
        switch (buffer[4]) {
          case 0xFE:
            logger.debug("$i rows was fetched");
            return;

          default:
            socketReader.cursor.increment(-buffer.length);
            await ResultSetBinaryRow.fromReader(
              socketReader,
              session,
              params.numberOfColumns,
              params.columns,
            );
        }
      }
    } finally {
      release();
    }
  }
}
