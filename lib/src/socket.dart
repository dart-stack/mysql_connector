import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'compression.dart';
import 'logging.dart';
import 'packet.dart';
import 'sequence.dart';
import 'lock.dart';
import 'session.dart';
import 'utils.dart';

abstract interface class PacketBuffer {
  List<int> get buffer;

  Cursor get cursor;

  Future<void> loadPacket();

  Future<List<int>> readPacket();

  Future<List<int>> peekPacket();

  void gc();
}

class PacketSocket implements PacketBuffer {
  final Logger _logger;

  final PacketCompressor _packetCompressor;

  final PacketSequenceManager _sequenceManager;

  final SessionContext _session;

  final _StatCollector _statCollector;

  final _PacketReceiver _packetReceiver;

  final Socket _rawSocket;

  final Cursor _cursor = Cursor.zero();

  late StreamSubscription _subscription;

  PacketSocket._internal(
    this._logger,
    this._packetCompressor,
    this._sequenceManager,
    this._session,
    this._statCollector,
    this._packetReceiver,
    this._rawSocket,
  ) {
    _subscription = _rawSocket.listen(_onData);
  }

  factory PacketSocket({
    required Logger logger,
    required PacketCompressor packetCompressor,
    required PacketSequenceManager sequenceManager,
    required SessionContext session,
    required Socket rawSocket,
    required int receiveBufferSize,
  }) {
    final statCollector = _StatCollector(true);

    return PacketSocket._internal(
      logger,
      packetCompressor,
      sequenceManager,
      session,
      statCollector,
      _PacketReceiver(
        logger,
        session,
        packetCompressor,
        sequenceManager,
        statCollector,
        receiveBufferSize,
      ),
      rawSocket,
    );
  }

  @override
  List<int> get buffer => _packetReceiver.buffer;

  @override
  Cursor get cursor => _cursor;

  int get maxPacketSize => _session.maxPacketSize;

  bool get compressionEnabled => _session.compressionEnabled;

  void _onData(List<int> data) {
    _packetReceiver.onData(data);
  }

  void write(List<int> data) {
    assert(data.isNotEmpty);
    _rawSocket.add(data);
  }

  @override
  void gc() {
    _packetReceiver.release();
    _cursor.reset();
  }

  bool _availableToReadNextPacket() {
    if (buffer.length - _cursor.position < 3) {
      return false;
    }
    final len = getPacketPayloadLength(buffer, _cursor);
    return buffer.length - _cursor.position - standardPacketHeaderLength >= len;
  }

  Future<void> _receivePacket() async {
    if (_availableToReadNextPacket()) {
      return;
    }

    final completer = Completer.sync();

    _packetReceiver.onPacketReceived(() {
      if (_availableToReadNextPacket()) {
        completer.complete();
        return true;
      }
      return false;
    });
    _packetReceiver.processUnread();

    await completer.future;
  }

  List<int> _readPacketFromBuffer(bool moveCursor) {
    final len = readInteger(buffer, _cursor.clone(), 3);
    final start = _cursor.position;
    final end = _cursor.position + len + 4;

    final packet = buffer.getRange(start, end).toList();
    if (moveCursor) {
      _cursor.increase(len + 4);
    }

    return packet;
  }

  @override
  Future<void> loadPacket() async {
    await _receivePacket();
  }

  @override
  Future<List<int>> readPacket() async {
    await _receivePacket();
    return _readPacketFromBuffer(true);
  }

  @override
  Future<List<int>> peekPacket() async {
    await _receivePacket();
    return _readPacketFromBuffer(false);
  }

  void sendPacket(List<int> buffer) {
    write(buffer);
  }

  void _patchStandardPacketSequence(List<int> buffer) {
    _sequenceManager.patchStandardPacketSequence(buffer);
  }

  void _patchCompressedPacketSequence(List<int> buffer) {
    _sequenceManager.patchCompressedPacketSequence(buffer);
  }

  void _sendStandardPacket(List<int> buffer) {
    _patchStandardPacketSequence(buffer);
    sendPacket(buffer);
  }

  void _sendCompressedPacket(List<int> buffer) {
    _patchCompressedPacketSequence(buffer);
    sendPacket(buffer);
  }

  Future<void> sendCommand(List<PacketBuilder> commands) async {
    final builder = BytesBuilder();
    for (final command in commands) {
      builder.add(command.build());
    }

    final buffer = builder.takeBytes();
    if (compressionEnabled) {
      _patchStandardPacketSequence(buffer);
      _sendCompressedPacket(_packetCompressor.compress(
        buffer,
        0,
        0xffffff,
        maxPacketSize: _session.maxPacketSize,
      ));
    } else {
      _sendStandardPacket(buffer);
    }
  }
}

enum _ReadState { readHeader, readPayload }

class _PacketReceiver {
  final Logger _logger;

  final SessionContext _session;

  final PacketCompressor _packetCompressor;

  final PacketSequenceManager _sequenceManager;

  final _StatCollector _statCollector;

  final int _maxBufferSize;

  final QueueLock _lock = QueueLock();

  final List<bool Function()> _onPacketReceivedCallbacks = [];

  List<int> _unread = <int>[];

  int _offset = 0;

  final BytesBuilder _bufferBuilder = BytesBuilder(copy: false);

  Uint8List _buffer = Uint8List(0);

  _ReadState _readState = _ReadState.readHeader;

  Uint8List _header = Uint8List(0);

  int _payloadLength = 0;

  final BytesBuilder _payloadChunks = BytesBuilder();

  _PacketReceiver(
    this._logger,
    this._session,
    this._packetCompressor,
    this._sequenceManager,
    this._statCollector,
    this._maxBufferSize,
  );

  bool get compressionEnabled => _session.compressionEnabled;

  List<int> get buffer => _buffer;

  void release() {
    _logger.debug(
        "buffered packets will be released (size=${formatSize(_buffer.length)})");
    _bufferBuilder.clear();
    _buffer = Uint8List(0);
  }

  void _writeToBuffer(List<int> data) {
    _bufferBuilder.add(data);
    _buffer = _bufferBuilder.toBytes();

    if (_statCollector.enabled) {
      _statCollector.increaseBufferedPackets(countStandardPackets(data));
    }
  }

  void onData(List<int> data) {
    _unread.addAll(data);
    processUnread();
  }

  void _trackStandardPacketSequence(List<int> buffer) {
    _sequenceManager.trackStandardPacketSequence(buffer);
  }

  void _trackCompressedPacketSequence(List<int> buffer) {
    _sequenceManager.trackCompressedPacketSequence(buffer);
  }

  int get _available => _unread.length - _offset;

  int _getPayloadLength(List<int> header) {
    return (header[0] & 0xff) +
        ((header[1] & 0xff) << 8) +
        ((header[2] & 0xff) << 16);
  }

  void processUnread() async {
    await _lock.acquire();

    for (; _available > 0;) {
      if (_offset > _maxBufferSize) {
        _logger.debug(
            "unread buffer will be released (bufferSize=${formatSize(_maxBufferSize)}, unread=${formatSize(_unread.length)}, released=${formatSize(_offset)})");
        _unread = _unread.getRange(_offset, _unread.length).toList();
        _offset = 0;
      }
      if (compressionEnabled) {
        switch (_readState) {
          case _ReadState.readHeader:
            if (_available >= compressedPacketHeaderLength) {
              _header = Uint8List.fromList(_unread
                  .getRange(_offset, _offset + compressedPacketHeaderLength)
                  .toList());
              _payloadLength = _getPayloadLength(_header);

              _offset += compressedPacketHeaderLength;
              _readState = _ReadState.readPayload;
            }

          case _ReadState.readPayload:
            final remaining = _payloadLength - _payloadChunks.length;
            final available = _available;
            final read = available > remaining ? remaining : available;
            _payloadChunks
                .add(_unread.getRange(_offset, _offset + read).toList());
            _offset += read;

            if (_payloadChunks.length == _payloadLength) {
              final bytesBuilder = BytesBuilder(copy: false)
                ..add(_header)
                ..add(_payloadChunks.takeBytes());
              final buffer = bytesBuilder.takeBytes();

              _trackCompressedPacketSequence(buffer);
              final decompressed = _packetCompressor.decompress(buffer);
              _writeToBuffer(decompressed);
              _trackStandardPacketSequence(decompressed);
              if (_statCollector.enabled) {
                _statCollector.increaseReceivedPackets();
              }

              _flushOnPacketReceivedCallbacks();
              _readState = _ReadState.readHeader;
            }
        }
      } else {
        switch (_readState) {
          case _ReadState.readHeader:
            if (_available >= standardPacketHeaderLength) {
              _header = Uint8List.fromList(_unread
                  .getRange(_offset, _offset + standardPacketHeaderLength)
                  .toList());
              _payloadLength = _getPayloadLength(_header);

              _offset += standardPacketHeaderLength;
              _readState = _ReadState.readPayload;
            }

          case _ReadState.readPayload:
            final remaining = _payloadLength - _payloadChunks.length;
            final available = _available;
            final read = available > remaining ? remaining : available;
            _payloadChunks
                .add(_unread.getRange(_offset, _offset + read).toList());
            _offset += read;

            if (_payloadChunks.length == _payloadLength) {
              final bytesBuilder = BytesBuilder(copy: false)
                ..add(_header)
                ..add(_payloadChunks.takeBytes());
              final buffer = bytesBuilder.takeBytes();

              _writeToBuffer(buffer);
              _trackStandardPacketSequence(buffer);
              if (_statCollector.enabled) {
                _statCollector.increaseReceivedPackets();
              }

              _flushOnPacketReceivedCallbacks();
              _readState = _ReadState.readHeader;
            }
        }
      }
    }

    _lock.release();
  }

  void _flushOnPacketReceivedCallbacks() {
    final callbacks = _onPacketReceivedCallbacks.toList(growable: false);

    for (final callback in callbacks) {
      if (callback.call() == true) {
        _onPacketReceivedCallbacks.remove(callback);
      }
    }
  }

  void onPacketReceived(bool Function() callback) {
    _onPacketReceivedCallbacks.add(callback);
  }
}

class _StatCollector {
  final bool enabled;

  int _bufferedPackets = 0;

  int _receivedPackets = 0;

  _StatCollector(this.enabled);

  int get bufferedPackets => _bufferedPackets;

  int get receivedPackets => _receivedPackets;

  void increaseBufferedPackets([int delta = 1]) {
    _bufferedPackets += delta;
  }

  void increaseReceivedPackets([int delta = 1]) {
    _receivedPackets += delta;
  }

  @override
  String toString() {
    return "receivedPackets = $receivedPackets, bufferedPackets = $bufferedPackets";
  }
}
