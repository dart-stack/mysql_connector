import 'packet.dart';
import 'session.dart';
import 'socket.dart';

abstract interface class CommandContext {
  NegotiationState get negotiationState;

  PacketWriter get writer;

  PacketStreamReader get reader;

  PacketBuilder createPacket();

  Future<void> beginCommand();

  void endCommand();

  void sendPacket(PacketBuilder commands);
}

abstract base class _CommandBase {
  final CommandContext _context;

  PacketStreamReader? _reader;

  _CommandBase(this._context);

  NegotiationState get negotiationState => _context.negotiationState;

  PacketStreamReader get reader => _context.reader;

  Future<void> enter() async {
    await _context.beginCommand();
  }

  void leave() {
    _context.endCommand();
  }

  void sendPacket(PacketBuilder builder) {
    _context.sendPacket(builder);
  }

  PacketBuilder createPacket() {
    return _context.createPacket();
  }
}

abstract base class CommandBase<P, T> extends _CommandBase {
  CommandBase(CommandContext context) : super(context);

  Future<T> execute(P params);
}
