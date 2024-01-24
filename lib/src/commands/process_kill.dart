import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';

typedef ProcessKillParams = ({int processId});

final class SetOption extends CommandBase<ProcessKillParams, void> {
  SetOption(CommandContext context) : super(context);

  @override
  Future<void> execute(ProcessKillParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x0C)
          ..addInteger(4, params.processId),
      ]);

      final packet = await socketReader.readPacket();
      switch (packet[4]) {
        case 0x00:
          return;

        case 0xFF:
          final err = ErrPacket.from(packet, session);
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
