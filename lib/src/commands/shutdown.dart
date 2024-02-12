import '../command.dart';

typedef ShutdownParams = ();

final class Shutdown extends CommandBase<ShutdownParams, void> {
  Shutdown(CommandContext context) : super(context);

  @override
  Future<void> execute(ShutdownParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x0A)
          ..addByte(0x00)
          ..terminate(),
      );
      await reader.next();
    } finally {
      leave();
    }
  }
}
