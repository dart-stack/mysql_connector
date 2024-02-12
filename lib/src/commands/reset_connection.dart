import '../command.dart';

typedef ResetConnectionParams = ();

final class ResetConnection extends CommandBase<ResetConnectionParams, void> {
  ResetConnection(CommandContext context) : super(context);

  @override
  Future<void> execute(ResetConnectionParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x1F)
          ..terminate(),
      );
      await reader.next();
    } finally {
      leave();
    }
  }
}
