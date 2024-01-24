import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';

class DebugParams {
  const DebugParams();
}

final class Debug extends CommandBase<DebugParams, void> {
  Debug(CommandContext context) : super(context);

  @override
  Future<void> execute(DebugParams params) async {
    await acquire();
    try {
      sendCommand([createPacket()..addByte(0x0D)]);

      final packet = await socketReader.readPacket();
      switch (packet[4]) {
        case 0x00:
          return;

        case 0xFF:
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