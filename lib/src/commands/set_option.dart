import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/packet.dart';

typedef SetOptionParams = ({bool enableMultiStatements});

final class SetOption extends CommandBase<SetOptionParams, void> {
  SetOption(CommandContext context) : super(context);

  @override
  Future<void> execute(SetOptionParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x1B)
          ..addInteger(2, params.enableMultiStatements ? 0 : 1)
          ..terminate(),
      );

      final packet = await reader.next();
      if (packet[4] == 0xFE) {
        return;
      } else {
        final err = ErrPacket.parse(packet, negotiationState);
        throw MysqlExecutionException(
          err.errorCode,
          err.errorMessage,
          err.sqlState,
        );
      }
    } finally {
      leave();
    }
  }
}
