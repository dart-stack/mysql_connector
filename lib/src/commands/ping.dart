import '../command.dart';

typedef PingParams = ();

final class Ping extends CommandBase<PingParams, void> {
  Ping(CommandContext context) : super(context);

  @override
  Future<void> execute(PingParams params) async {
    await acquire();

    try {
      sendCommand([
        createPacket()
          ..addByte(0x0e)
          ..terminated(),
      ]);

      print(await socketReader.packetReader.readInteger(1));
    } finally {
      release();
    }
  }
}
