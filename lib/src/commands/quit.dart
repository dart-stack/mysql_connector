import '../command.dart';

class QuitParams {
  const QuitParams();
}

final class Quit extends CommandBase<QuitParams, void> {
  Quit(CommandContext context) : super(context);

  @override
  Future<void> execute(QuitParams params) async {
    await acquire();

    sendCommand([
      createPacket()..addByte(0x01),
    ]);

    await socketReader.readPacket();

    release();
  }
}
