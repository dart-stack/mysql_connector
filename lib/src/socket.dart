import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mysql_connector/src/metrics.dart';
import 'package:typed_data/typed_data.dart';

import 'logging.dart';
import 'packet.dart';
import 'sequence.dart';
import 'session.dart';
import 'utils.dart';

abstract interface class SocketWriter {
  void write(List<int> data);
}

abstract interface class PacketWriter {
  void writePacket(List<int> buffer);

  void writePacketWithBuilder(PacketBuilder builder);
}

class PacketSocket implements SocketWriter, PacketWriter {
  final Logger _logger = LoggerFactory.createLogger(name: "Socket");

  final PacketSequenceManager _sequenceManager;

  final NegotiationState _negotiationState;

  final bool _metricsEnabled;

  final _MetricsCollector _metricsCollector;

  final Socket _rawSocket;

  late StreamController<List<int>> _packetReadChannel;

  late StreamController<List<int>> _packetWriteChannel;

  late StreamSubscription _writeSubscription;

  late StreamSubscription _socketSubscription;

  factory PacketSocket({
    required PacketSequenceManager sequenceManager,
    required NegotiationState negotiationState,
    required Socket rawSocket,
    required int receiveBufferSize,
  }) {
    final metricsCollector = _MetricsCollector();

    return PacketSocket._internal(
      sequenceManager,
      negotiationState,
      false,
      metricsCollector,
      rawSocket,
    );
  }

  PacketSocket._internal(
    this._sequenceManager,
    this._negotiationState,
    this._metricsEnabled,
    this._metricsCollector,
    this._rawSocket,
  ) {
    _packetReadChannel = StreamController();
    _packetWriteChannel = StreamController();
    _writeSubscription = _packetWriteChannel.stream
        .transform(OutboundPacketStreamTransformer(
          _negotiationState,
          _sequenceManager,
          _metricsEnabled,
          _metricsCollector,
        ))
        .listen(_rawSocket.add);
    _socketSubscription = _rawSocket.listen(
      _onSocketReceived,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: true,
    );
  }

  Stream<List<int>> get stream =>
      _packetReadChannel.stream.transform(InboundPacketStreamTransformer(
        _negotiationState,
        _sequenceManager,
        _metricsEnabled,
        _metricsCollector,
        0xffffffff,
      ));

  void _onSocketReceived(List<int> event) {
    _packetReadChannel.add(event);
  }

  void _onSocketDone() {
    _packetReadChannel.close();
    _packetWriteChannel.close();
    _logger.info("socket was closed");
  }

  void _onSocketError(Object error, [StackTrace? stackTrace]) {
    _packetReadChannel.addError(error, stackTrace);
    _packetWriteChannel.addError(error, stackTrace);
    _logger.warn(error);
  }

  @override
  void write(List<int> data) {
    assert(data.isNotEmpty);
    _rawSocket.add(data);
  }

  @override
  void writePacket(List<int> buffer) {
    _packetWriteChannel.add(buffer);
  }

  @override
  void writePacketWithBuilder(PacketBuilder builder) {
    writePacket(builder.build());
  }
}

class _MetricsCollector implements MetricsCollector {
  int _receivedBytes = 0;

  int _sentBytes = 0;

  int _receivedPackets = 0;

  _MetricsCollector();

  int get receivedBytes => _receivedBytes;

  int get sentBytes => _sentBytes;

  int get receivedPackets => _receivedPackets;

  @override
  void incrementReceivedBytes(int delta) {
    _receivedBytes += delta;
  }

  @override
  void incrementSentBytes(int delta) {
    _sentBytes += delta;
  }

  @override
  void incrementReceivedPackets(int delta) {
    _receivedPackets += delta;
  }

  @override
  String toString() {
    return "receivedBytes=$receivedBytes, sentBytes=$sentBytes, receivedPackets=$receivedPackets";
  }
}

void _memmove(List<int> mem, int from, int to, int length) {
  assert(mem.length - from >= length);
  mem.setRange(to, to + length, mem.getRange(from, from + length));
}

class InboundPacketStreamTransformer
    extends StreamTransformerBase<List<int>, List<int>> {
  final NegotiationState _negotiationState;

  final PacketSequenceManager _sequenceManager;

  final bool _metricsEnabled;

  final MetricsCollector _metricsCollector;

  final int _bufferSize;

  const InboundPacketStreamTransformer(
    this._negotiationState,
    this._sequenceManager,
    this._metricsEnabled,
    this._metricsCollector,
    this._bufferSize,
  );

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) => Stream.eventTransformed(
        stream,
        (sink) => InboundPacketProcessor(
          sink,
          _negotiationState,
          _sequenceManager,
          _metricsEnabled,
          _metricsCollector,
          _bufferSize,
        ),
      );
}

class InboundPacketProcessor implements EventSink<List<int>> {
  final EventSink<List<int>> _outputSink;

  final NegotiationState _negotiationState;

  final PacketSequenceManager _sequenceManager;

  final bool _metricsEnabled;

  final MetricsCollector _metricsCollector;

  final int _bufferSize;

  final Uint8Buffer _unreadBuffer = Uint8Buffer();

  final Uint8Buffer _packetBuffer = Uint8Buffer();

  InboundPacketProcessor(
    this._outputSink,
    this._negotiationState,
    this._sequenceManager,
    this._metricsEnabled,
    this._metricsCollector,
    this._bufferSize,
  );

  @override
  void add(List<int> event) {
    _unreadBuffer.addAll(event);
    _processUnread();
    _processBufferedPacket();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outputSink.addError(error, stackTrace);
  }

  @override
  void close() {
    _outputSink.close();
  }

  bool get _compressionEnabled => _negotiationState.compressionEnabled;

  void _trackStandardPacketSequence(List<int> buffer) {
    _sequenceManager.trackStandardPacketSequence(buffer);
  }

  void _trackCompressedPacketSequence(List<int> buffer) {
    _sequenceManager.trackCompressedPacketSequence(buffer);
  }

  void _processUnread() {
    if (_compressionEnabled) {
      final cursor = Cursor.zero();
      for (final (start, end)
          in traverseCompressedPackets(_unreadBuffer, cursor)) {
        final packet =
            getUnmodifiableRangeEfficiently(_unreadBuffer, start, end);
        _trackCompressedPacketSequence(packet);
        final needDecompression =
            readInteger(_unreadBuffer, Cursor.from(start + 4), 3) != 0;
        final payload = getUnmodifiableRangeEfficiently(
            packet, compressedPacketHeaderLength, packet.length);
        if (needDecompression) {
          _packetBuffer.addAll(zlib.decode(payload));
        } else {
          _packetBuffer.addAll(payload);
        }
      }
      final remaining = _unreadBuffer.length - cursor.position;
      _memmove(_unreadBuffer, cursor.position, 0, remaining);
      _unreadBuffer.length = remaining;
    } else {
      _packetBuffer.addAll(_unreadBuffer);
      _unreadBuffer.clear();
    }
  }

  void _processBufferedPacket() {
    final cursor = Cursor.zero();
    for (final (start, end) in traverseStandardPackets(_packetBuffer, cursor)) {
      final packet = getUnmodifiableRangeEfficiently(_packetBuffer, start, end);
      _trackStandardPacketSequence(packet);
      _outputSink.add(packet);
    }
    final remaining = _packetBuffer.length - cursor.position;
    _memmove(_packetBuffer, cursor.position, 0, remaining);
    _packetBuffer.length = remaining;
  }
}

class OutboundPacketStreamTransformer
    extends StreamTransformerBase<List<int>, List<int>> {
  final NegotiationState _negotiationState;

  final PacketSequenceManager _sequenceManager;

  final bool _metricsEnabled;

  final MetricsCollector _metricsCollector;

  const OutboundPacketStreamTransformer(
    this._negotiationState,
    this._sequenceManager,
    this._metricsEnabled,
    this._metricsCollector,
  );

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) => Stream.eventTransformed(
        stream,
        (sink) => OutboundPacketProcessor(
          sink,
          _negotiationState,
          _sequenceManager,
          _metricsEnabled,
          _metricsCollector,
        ),
      );
}

class OutboundPacketProcessor implements EventSink<List<int>> {
  final EventSink<List<int>> _outputSink;

  final NegotiationState _negotiationState;

  final PacketSequenceManager _sequenceManager;

  final bool _metricsEnabled;

  final MetricsCollector _metricsCollector;

  OutboundPacketProcessor(
    this._outputSink,
    this._negotiationState,
    this._sequenceManager,
    this._metricsEnabled,
    this._metricsCollector,
  );

  void _patchStandardPacketSequence(List<int> buffer) {
    _sequenceManager.patchStandardPacketSequence(buffer);
  }

  void _patchCompressedPacketSequence(List<int> buffer) {
    _sequenceManager.patchCompressedPacketSequence(buffer);
  }

  List<int> _makeCompressedPacket(
    int sequence,
    List<int> payload,
    bool needCompressPayload,
  ) {
    final writer = BytesBuilder();
    if (needCompressPayload) {
      final originalPayloadLength = payload.length;
      final compressedPayload = zlib.encode(payload);
      writeInteger(writer, 3, compressedPayload.length);
      writeInteger(writer, 1, sequence);
      writeInteger(writer, 3, originalPayloadLength);
      writeBytes(writer, compressedPayload);
    } else {
      writeInteger(writer, 3, payload.length);
      writeInteger(writer, 1, sequence);
      writeInteger(writer, 3, 0);
      writeBytes(writer, payload);
    }
    return writer.takeBytes();
  }

  @override
  void add(List<int> packetsToSend) {
    const thresholdToCompress = 256;

    if (_negotiationState.compressionEnabled) {
      final cursor = Cursor.zero();
      final bufferWriter = BytesBuilder();
      for (final (start, end)
          in traverseStandardPackets(packetsToSend, cursor)) {
        final packet =
            getUnmodifiableRangeEfficiently(packetsToSend, start, end);
        _patchStandardPacketSequence(packet);
        if (bufferWriter.length + packet.length > 0xffffff) {
          final packet = _makeCompressedPacket(
            0,
            bufferWriter.takeBytes(),
            bufferWriter.length > thresholdToCompress,
          );
          _patchCompressedPacketSequence(packet);
          _outputSink.add(packet);
        }
        bufferWriter.add(packet);
      }
      final packet = _makeCompressedPacket(
        0,
        bufferWriter.takeBytes(),
        bufferWriter.length > thresholdToCompress,
      );
      _patchCompressedPacketSequence(packet);
      _outputSink.add(packet);
    } else {
      _patchStandardPacketSequence(packetsToSend);
      _outputSink.add(packetsToSend);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outputSink.addError(error, stackTrace);
  }

  @override
  void close() {
    _outputSink.close();
  }
}
