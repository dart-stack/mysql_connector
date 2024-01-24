import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';

class PrepareStmtParams {
  final String sql;

  const PrepareStmtParams({
    required this.sql,
  });
}

final class PrepareStmt
    extends CommandBase<PrepareStmtParams, PreparedStmtResult> {
  PrepareStmt(CommandContext context) : super(context);

  @override
  Future<PreparedStmtResult> execute(PrepareStmtParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x16)
          ..addString(params.sql)
      ]);

      final packet = await socketReader.readPacket();
      switch (packet[4]) {
        case 0x00:
          return PreparedStmtResult();

        case 0xFF:
          final err = ErrPacket(readErrPacket(packet));
          throw MysqlExecutionException(
            err.errorCode,
            err.errorMessage,
            err.sqlState,
          );
      }
      throw StateError("unrecognized response from server");
    } finally {
      release();
    }
  }
}

class PreparedStmtResult {}
