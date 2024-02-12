import '../command.dart';

typedef QuitParams = ();

final class Quit extends CommandBase<QuitParams, void> {
  Quit(CommandContext context) : super(context);

  @override
  Future<void> execute(QuitParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x01)
          ..terminate(),
      );
    } finally {
      leave();
    }
  }
}
