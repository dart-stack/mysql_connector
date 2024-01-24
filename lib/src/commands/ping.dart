import '../command.dart';

class PingParams {
  const PingParams();
}

final class Ping extends CommandBase<PingParams, void> {
  Ping(CommandContext context) : super(context);

  @override
  Future<void> execute(PingParams params) async {
    await acquire();

    sendCommand([
      createPacket()..addByte(0x0e),
    ]);

    await buffer.readPacket();

    release();
  }
}
