import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/utils.dart';

typedef StatisticsParams = ();

final class Statistics extends CommandBase<StatisticsParams, String> {
  Statistics(CommandContext context) : super(context);

  @override
  Future<String> execute(StatisticsParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x09)
          ..terminated(),
      ]);

      final packet = await socketReader.readPacket();
      return readString(
        packet,
        Cursor.from(standardPacketHeaderLength),
        packet.length - standardPacketHeaderLength,
      );
    } finally {
      release();
    }
  }
}
