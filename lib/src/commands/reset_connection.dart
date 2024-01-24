import '../command.dart';

class ResetConnectionParams {
  const ResetConnectionParams();
}

final class ResetConnection extends CommandBase<ResetConnectionParams, void> {
  ResetConnection(CommandContext context) : super(context);

  @override
  Future<void> execute(ResetConnectionParams params) async {
    await acquire();

    sendCommand([
      createPacket()..addByte(0x1F),
    ]);

    await socketReader.readPacket();

    release();
  }
}
