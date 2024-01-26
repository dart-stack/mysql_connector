import '../command.dart';

typedef QuitParams = ();

final class Quit extends CommandBase<QuitParams, void> {
  Quit(CommandContext context) : super(context);

  @override
  Future<void> execute(QuitParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x01)
          ..terminated(),
      ]);

      await socketReader.readPacket();
    } finally {
      release();
    }
  }
}
