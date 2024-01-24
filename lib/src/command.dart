import 'logging.dart';
import 'packet.dart';
import 'session.dart';
import 'socket.dart';

abstract interface class CommandContext {
  Logger get logger;

  SessionContext get session;

  PacketSocketReader get socketReader;

  PacketBuilder createPacket();

  Future<void> beginCommand();

  void endCommand();

  void sendCommand(List<PacketBuilder> commands);
}

abstract base class CommandBase<P, T> {
  final CommandContext _context;

  CommandBase(this._context);

  Logger get logger => _context.logger;

  SessionContext get session => _context.session;

  PacketSocketReader get socketReader => _context.socketReader;

  AsyncPacketReader get packetReader => socketReader.packetReader;

  Future<void> acquire() async {
    await _context.beginCommand();
  }

  void release() {
    _context.endCommand();
  }

  void sendCommand(List<PacketBuilder> commands) {
    _context.sendCommand(commands);
  }

  PacketBuilder createPacket() {
    return _context.createPacket();
  }

  Future<T> execute(P params);
}
