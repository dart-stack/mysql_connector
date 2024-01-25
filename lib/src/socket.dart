import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'compression.dart';
import 'logging.dart';
import 'packet.dart';
import 'sequence.dart';
import 'lock.dart';
import 'session.dart';
import 'utils.dart';

abstract interface class PacketSocketReader {
  List<int> get buffer;

  Cursor get cursor;

  AsyncPacketReader get packetReader;

  Future<Uint8List> read(int length);

  Future<List<int>> readPacket();

  void gc();
}

class PacketSocket implements PacketSocketReader {
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
    _subscription = _rawSocket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
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

  int get maxPacketSize => _session.maxPacketSize;

  bool get compressionEnabled => _session.compressionEnabled;

  @override
  List<int> get buffer => _packetReceiver.packetBuffer;

  @override
  Cursor get cursor => _cursor;

  @override
  AsyncPacketReader get packetReader => _AsyncPacketReader(this);

  void _onData(List<int> data) {
    _packetReceiver.onData(data);
  }

  void _onDone() {
    _packetReceiver.onDone();
    print("socket is closed");
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    print(error);
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
    if (buffer.length - _cursor.position < standardPacketHeaderLength) {
      return false;
    }
    return buffer.length - _cursor.position >=
        standardPacketHeaderLength + getPacketPayloadLength(buffer, _cursor);
  }

  Future<void> _receivePacketIfNeeded() async {
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

  List<int> _readPacketFromBuffer(Cursor cursor) {
    assert(_availableToReadNextPacket());

    final payloadLength = getPacketPayloadLength(buffer, cursor);

    final start = cursor.position;
    final end = cursor.position + standardPacketHeaderLength + payloadLength;
    final packet = getRangeEfficiently(buffer, start, end);

    cursor.increase(standardPacketHeaderLength + payloadLength);
    return packet;
  }

  @override
  Future<List<int>> readPacket() async {
    await _receivePacketIfNeeded();
    return _readPacketFromBuffer(_cursor);
  }

  List<int> _read = [];

  int _offset = 0;

  @override
  Future<Uint8List> read(int length) async {
    assert(length > 0);

    final writer = BytesBuilder();
    int remaining = length;
    for (;;) {
      if (remaining == 0) {
        return writer.takeBytes();
      }

      // Note: sometimes may receive empty packet, which not contains
      //  any payload. if it is currently read, skip it and read next
      //  packet until non-empty packet is appeared.
      for (;;) {
        assert(_offset <= _read.length);
        if (_offset < _read.length) {
          break;
        }
        await _receivePacketIfNeeded();
        _read = _readPacketFromBuffer(_cursor);
        _offset += standardPacketHeaderLength;
      }

      final available = _read.length - _offset;
      final bytesToRead = available < remaining ? available : remaining;

      writer.add(getRangeEfficiently(_read, _offset, _offset + bytesToRead));
      remaining -= bytesToRead;
      _offset += bytesToRead;
    }
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

  final List<int> _unreadBuffer = <int>[];

  int _unreadOffset = 0;

  final BytesBuilder _packetBufferWriter = BytesBuilder(copy: false);

  Uint8List _packetBuffer = Uint8List(0);

  _ReadState _readState = _ReadState.readHeader;

  final BytesBuilder _bufferedPacketWriter = BytesBuilder();

  int _bufferedHeaderLength = 0;

  int _payloadLength = 0;

  _PacketReceiver(
    this._logger,
    this._session,
    this._packetCompressor,
    this._sequenceManager,
    this._statCollector,
    this._maxBufferSize,
  );

  bool get compressionEnabled => _session.compressionEnabled;

  Uint8List get packetBuffer => _packetBuffer;

  void onData(List<int> data) async {
    _writeToUnreadBuffer(data);
    _logger.verbose(
        "${data.length} bytes has been received and written to unread buffer (bufferSize=${_unreadBuffer.length}, written=${data.length})");

    processUnread();
  }

  void onDone() {}

  void _writeToUnreadBuffer(List<int> buffer) {
    _unreadBuffer.addAll(buffer);
  }

  void _writeToPacketBuffer(List<int> data) {
    _packetBufferWriter.add(data);
    _packetBuffer = _packetBufferWriter.toBytes();

    if (_statCollector.enabled) {
      _statCollector.increaseBufferedPackets(countStandardPackets(data));
    }
  }

  void _releasePacketBuffer() {
    _logger.verbose(
        "buffered packets will be released (size=${formatSize(_packetBuffer.length)})");
    _packetBufferWriter.clear();
    _packetBuffer = Uint8List(0);
  }

  void _releaseUnreadBufferIfNeeded() {
    if (_unreadOffset > _maxBufferSize) {
      _logger.verbose(
          "unread buffer will be released (bufferSize=${formatSize(_maxBufferSize)}, unread=${formatSize(_unreadBuffer.length)})");
      _unreadBuffer.removeRange(0, _unreadOffset);
      _unreadOffset = 0;
    }
  }

  void release() {
    _releasePacketBuffer();
  }

  void _trackStandardPacketSequence(List<int> buffer) {
    _sequenceManager.trackStandardPacketSequence(buffer);
  }

  void _trackCompressedPacketSequence(List<int> buffer) {
    _sequenceManager.trackCompressedPacketSequence(buffer);
  }

  int _getPayloadLength(List<int> header) {
    return (header[0] & 0xff) +
        ((header[1] & 0xff) << 8) +
        ((header[2] & 0xff) << 16);
  }

  int get _available => _unreadBuffer.length - _unreadOffset;

  int get _payloadRemaining =>
      _payloadLength - _bufferedPacketWriter.length + _bufferedHeaderLength;

  bool get _payloadHasFullReceived =>
      _bufferedPacketWriter.length - _bufferedHeaderLength == _payloadLength;

  void processUnread() async {
    await _lock.acquire();

    for (; _available > 0;) {
      _releaseUnreadBufferIfNeeded();
      if (compressionEnabled) {
        switch (_readState) {
          case _ReadState.readHeader:
            if (_available >= compressedPacketHeaderLength) {
              final bufferedHeader = _unreadBuffer
                  .sublist(
                    _unreadOffset,
                    _unreadOffset + compressedPacketHeaderLength,
                  )
                  .toUint8List();
              _bufferedHeaderLength = compressedPacketHeaderLength;
              _payloadLength = _getPayloadLength(bufferedHeader);
              _bufferedPacketWriter.add(bufferedHeader);

              _unreadOffset += compressedPacketHeaderLength;
              _readState = _ReadState.readPayload;
            }

          case _ReadState.readPayload:
            final available = _available;
            final remaining = _payloadRemaining;
            final bytesToRead = available < remaining ? available : remaining;
            _bufferedPacketWriter.add(_unreadBuffer.sublist(
              _unreadOffset,
              _unreadOffset + bytesToRead,
            ));
            _unreadOffset += bytesToRead;

            if (_payloadHasFullReceived) {
              final buffer = _bufferedPacketWriter.takeBytes();
              _trackCompressedPacketSequence(buffer);
              final decompressed = _packetCompressor.decompress(buffer);
              _writeToPacketBuffer(decompressed);
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
              final bufferedHeader = _unreadBuffer
                  .sublist(
                    _unreadOffset,
                    _unreadOffset + standardPacketHeaderLength,
                  )
                  .toUint8List();
              _bufferedHeaderLength = standardPacketHeaderLength;
              _payloadLength = _getPayloadLength(bufferedHeader);
              _bufferedPacketWriter.add(bufferedHeader);

              _unreadOffset += standardPacketHeaderLength;
              _readState = _ReadState.readPayload;
            }

          case _ReadState.readPayload:
            final available = _available;
            final remaining = _payloadRemaining;
            final bytesToRead = available > remaining ? remaining : available;
            _bufferedPacketWriter.add(_unreadBuffer.sublist(
              _unreadOffset,
              _unreadOffset + bytesToRead,
            ));
            _unreadOffset += bytesToRead;

            if (_payloadHasFullReceived) {
              final buffer = _bufferedPacketWriter.takeBytes();
              _writeToPacketBuffer(buffer);
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

abstract interface class AsyncPacketReader {
  Future<List<int>> readBytes(int length);

  Future<int> readInteger(int length);

  Future<int?> readLengthEncodedInteger();

  Future<String> readString(int length, [Encoding encoding = utf8]);

  Future<String?> readLengthEncodedString([Encoding encoding = utf8]);

  Future<String> readZeroTerminatedString([Encoding encoding = utf8]);
}

class _AsyncPacketReader implements AsyncPacketReader {
  final PacketSocket _socket;

  _AsyncPacketReader(this._socket);

  @override
  Future<List<int>> readBytes(int length) async {
    return _socket.read(length);
  }

  @override
  Future<int> readInteger(int length) async {
    assert(const [1, 2, 3, 4, 8].contains(length));

    final bytes = await _socket.read(length);
    var result = 0;
    for (int i = 0; i < length; i++) {
      result |= (bytes[i] & 0xff) << (i * 8);
    }
    return result;
  }

  @override
  Future<int?> readLengthEncodedInteger() async {
    final leadingByte = (await _socket.read(1))[0];
    if (leadingByte == 0xFB) {
      return null;
    }
    if (leadingByte < 0xFB) {
      return leadingByte;
    }
    switch (leadingByte) {
      case == 0xFB:
        return null;

      case < 0xFB:
        return leadingByte;

      case == 0xFC:
        final bytes = await _socket.read(2);
        return ((bytes[0] & 0xff) << 0) | ((bytes[1] & 0xff) << 8);

      case == 0xFD:
        final bytes = await _socket.read(3);
        return ((bytes[0] & 0xff) << 0) |
            ((bytes[1] & 0xff) << 8) |
            ((bytes[2] & 0xff) << 16);

      case == 0xFE:
        final bytes = await _socket.read(3);
        return ((bytes[0] & 0xff) << 0) |
            ((bytes[1] & 0xff) << 8) |
            ((bytes[2] & 0xff) << 16) |
            ((bytes[3] & 0xff) << 24) |
            ((bytes[4] & 0xff) << 32) |
            ((bytes[5] & 0xff) << 40) |
            ((bytes[6] & 0xff) << 48) |
            ((bytes[7] & 0xff) << 56);

      default:
        throw StateError(
            "malformed length-encoded integer with leading byte $leadingByte");
    }
  }

  @override
  Future<String> readString(int length, [Encoding encoding = utf8]) async {
    return encoding.decode(await _socket.read(length));
  }

  @override
  Future<String?> readLengthEncodedString([Encoding encoding = utf8]) async {
    final length = await readLengthEncodedInteger();
    if (length == null) {
      return null;
    }
    return readString(length, encoding);
  }

  @override
  Future<String> readZeroTerminatedString([Encoding encoding = utf8]) async {
    final bytes = <int>[];
    for (;;) {
      final byte = (await _socket.read(1))[0];
      if (byte == 0x00) {
        return encoding.decode(bytes);
      }
      bytes.add(byte);
    }
  }
}

// TODO(archartist): Implement fixed-size buffer to optimize the performance 
//  of socket receiving and packet buffering.