import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';

class SetOptionParams {
  final bool enableMultiStmts;

  const SetOptionParams({
    required this.enableMultiStmts,
  });
}

final class SetOption extends CommandBase<SetOptionParams, void> {
  SetOption(CommandContext context) : super(context);

  @override
  Future<void> execute(SetOptionParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x1B)
          ..addInteger(2, params.enableMultiStmts ? 0 : 1),
      ]);

      final packet = await socketReader.readPacket();
      if (packet[4] == 0xFE) {
        return;
      } else {
        final err = ErrPacket(readErrPacket(packet));
        throw MysqlExecutionException(
          err.errorCode,
          err.errorMessage,
          err.sqlState,
        );
      }
    } finally {
      release();
    }
  }
}
