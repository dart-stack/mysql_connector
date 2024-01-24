import '../command.dart';

class ShutdownParams {
  const ShutdownParams();
}

final class Shutdown extends CommandBase<ShutdownParams, void> {
  Shutdown(CommandContext context) : super(context);

  @override
  Future<void> execute(ShutdownParams params) async {
    await acquire();

    sendCommand([
      createPacket()
        ..addByte(0x0A)
        ..addByte(0x00),
    ]);

    await socketReader.readPacket();

    release();
  }
}
