import 'package:mysql_connector/src/logging.dart';

import '../command.dart';

typedef PingParams = ();

final class Ping extends CommandBase<PingParams, void> {
  final Logger _logger = LoggerFactory.createLogger(name: "Ping");

  Ping(CommandContext context) : super(context);

  @override
  Future<void> execute(PingParams params) async {
    await enter();

    try {
      sendPacket(
        createPacket()
          ..addByte(0x0e)
          ..terminate(),
      );

      _logger.debug(await reader.next());
    } finally {
      leave();
    }
  }
}
