import 'dart:typed_data';

import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';
import 'package:mysql_connector/src/protocol.dart';
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
    SessionContext session,
  ) async {
    final props = <String, dynamic>{};
    // process first packet
    {
      final cursor = Cursor.zero();
      final buffer = await reader.readPacket();

      cursor.increase(standardPacketHeaderLength);
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
    if (props[fieldNumColumns] > 0) {
      props[fieldColumns] = [];
      for (int i = 0; i < props[fieldNumColumns]; i++) {
        props[fieldColumns]
            .add(await FieldDefinition.fromReader(reader, session));
      }
      if (!session.hasCapabilities(capClientDeprecateEof)) {
        await reader.readPacket();
      }
    }
    if (props[fieldNumPlaceholders] > 0) {
      props[fieldPlaceholders] = [];
      for (int i = 0; i < props[fieldNumPlaceholders]; i++) {
        props[fieldPlaceholders]
            .add(await FieldDefinition.fromReader(reader, session));
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

  List get columns => props[fieldColumns];

  List get placeholders => props[fieldPlaceholders];
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
  List<int>? types,
  List<int>? values,
});

final class ExecuteStmt extends CommandBase<ExecuteStmtParams, void> {
  ExecuteStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(ExecuteStmtParams params) async {
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
          command.addBytes(params.types!);
        }
        command.addBytes(params.values!);
      }
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
          socketReader.cursor.increase(-buffer.length);
          final result =
              await ResultSet.fromSocket(socketReader, session, true);
          print("${result.rows.length} rows was fetched");

          return;
      }
    } finally {
      release();
    }
  }
}

typedef FetchStmtParams = ({int statementId, int numberOfRows});

final class FetchStmt extends CommandBase<FetchStmtParams, void> {
  FetchStmt(CommandContext context) : super(context);

  @override
  Future<void> execute(FetchStmtParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x17)
          ..addInteger(4, params.statementId)
          ..addInteger(4, params.numberOfRows)
      ]);

      for (int i = 0;; i++) {
        final buffer = await socketReader.readPacket();
        switch (buffer[4]) {
          case 0xFE:
            logger.debug("$i rows was fetched");
            return;

          default:
            socketReader.cursor.increase(-buffer.length);
            // FIXME: temporary assigned value
            await BinaryResultRow.fromReader(socketReader, session, 2);
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
      ]);

      for (int i = 0;; i++) {
        final buffer = await socketReader.readPacket();
        switch (buffer[4]) {
          case 0xFE:
            logger.debug("$i rows was fetched");
            return;

          default:
            socketReader.cursor.increase(-buffer.length);
            // FIXME: temporary assigned value
            await BinaryResultRow.fromReader(socketReader, session, 2);
        }
      }
    } finally {
      release();
    }
  }
}
