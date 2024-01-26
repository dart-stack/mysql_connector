import '../command.dart';

typedef ResetConnectionParams = ();

final class ResetConnection extends CommandBase<ResetConnectionParams, void> {
  ResetConnection(CommandContext context) : super(context);

  @override
  Future<void> execute(ResetConnectionParams params) async {
    await acquire();
    try {
      sendCommand([
        createPacket()
          ..addByte(0x1F)
          ..terminated(),
      ]);
      await socketReader.readPacket();
    } finally {
      release();
    }
  }
}
