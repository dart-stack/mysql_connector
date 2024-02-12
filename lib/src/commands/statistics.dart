import 'package:mysql_connector/src/command.dart';
import 'package:mysql_connector/src/utils.dart';

typedef StatisticsParams = ();

final class Statistics extends CommandBase<StatisticsParams, String> {
  Statistics(CommandContext context) : super(context);

  @override
  Future<String> execute(StatisticsParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
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
      leave();
    }
  }
}
