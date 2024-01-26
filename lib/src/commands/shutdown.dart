import '../command.dart';

typedef ShutdownParams = ();

final class Shutdown extends CommandBase<ShutdownParams, void> {
  Shutdown(CommandContext context) : super(context);

  @override
  Future<void> execute(ShutdownParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x0A)
          ..addByte(0x00)
          ..terminated(),
      ]);
      await socketReader.readPacket();
    } finally {
      release();
    }
  }
}
