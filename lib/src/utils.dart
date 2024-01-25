import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

const standardPacketHeaderLength = 4;
const compressedPacketHeaderLength = 7;

const standardPacketSequenceOffset = 3;
const compressedPacketSequenceOffset = 3;

const standardPacketPayloadOffset = 4;
const compressedPacketPayloadOffset = 7;

class Cursor {
  int _position;

  Cursor._internal(this._position);

  factory Cursor.zero() => Cursor._internal(0);

  factory Cursor.from(int position) => Cursor._internal(position);

  int get position => _position;

  void reset() {
    _position = 0;
  }

  Cursor clone() {
    return Cursor.from(position);
  }

  void setPosition(int position) {
    _position = position;
  }

  void increase(int delta) {
    _position = _position + delta;
  }

  int increaseAndGet(int delta) {
    increase(delta);
    return position;
  }

  int getAndIncrease(int delta) {
    final p = position;
    increase(delta);
    return p;
  }
}

List<int> readBytes(List<int> buffer, Cursor cursor, int length) {
  assert(cursor.position + length <= buffer.length);

  final result = buffer.sublist(cursor.position, cursor.position + length);
  cursor.increase(length);

  return result;
}

List<int>? readLengthEncodedBytes(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  final length = readLengthEncodedInteger(buffer, cursor);
  if (length == null) {
    return null;
  }
  return readBytes(buffer, cursor, length);
}

int readInteger(List<int> buffer, Cursor cursor, int length) {
  assert(const [1, 2, 3, 4, 8].contains(length));

  final bytes = readBytes(buffer, cursor, length);

  var result = 0;
  for (var i = 0; i < bytes.length; i++) {
    result = result + ((bytes[i] & 0xff) << (8 * i));
  }

  return result;
}

int? readLengthEncodedInteger(List<int> buffer, Cursor cursor) {
  final leadingByte = buffer[cursor.position];
  cursor.increase(1);

  if (leadingByte < 0xFB) {
    return leadingByte;
  } else if (leadingByte == 0xFB) {
    return null;
  } else if (leadingByte == 0xFC) {
    return readInteger(buffer, cursor, 2);
  } else if (leadingByte == 0xFD) {
    return readInteger(buffer, cursor, 3);
  } else if (leadingByte == 0xFE) {
    return readInteger(buffer, cursor, 8);
  } else {
    throw UnimplementedError(
        "unrecognized leading byte $leadingByte when reading length-encoded integer");
  }
}

String readString(
  List<int> buffer,
  Cursor cursor,
  int length, [
  Encoding encoding = utf8,
]) {
  return encoding.decode(readBytes(buffer, cursor, length));
}

String? readLengthEncodedString(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  final length = readLengthEncodedInteger(buffer, cursor);
  if (length == null) {
    return null;
  }
  return readString(buffer, cursor, length, encoding);
}

String readZeroTerminatedString(
  List<int> buffer,
  Cursor cursor, [
  Encoding encoding = utf8,
]) {
  final bytes = <int>[];

  for (int offset = 0;; offset++) {
    final curr = buffer[cursor.position + offset];
    if (curr == 0x00) {
      cursor.increase(offset + 1); // note: cursor should stop at after '\0'
      return encoding.decode(bytes);
    }

    bytes.add(curr);
  }
}

class Bitmap {
  static Bitmap from(List<int> buffer) {
    return Bitmap._internal(buffer.toUint8List());
  }

  // build a bitmap to indicate null where true is.
  static Bitmap build(List<bool> selector) {
    // invariant: bytes length = floor((bits + 7) / 8)

    final buffer = <int>[0x00];
    var i = 0;
    for (int j = 0;; j++) {
      for (int k = 0; k < 8; k++) {
        if (i == selector.length) {
          return from(buffer);
        }
        if (selector[i] == true) {
          buffer[j] |= 1 << k;
        }
        ++i;
      }
      buffer.add(0x00);
    }
  }

  final Uint8List _bitmap;

  const Bitmap._internal(this._bitmap);

  List<int> get buffer => UnmodifiableUint8ListView(_bitmap);

  bool at(int offset) {
    final i = (offset / 8).floor();
    final j = offset % 8;
    return (_bitmap[i] & (1 << j)) > 0;
  }

  @override
  String toString() {
    return _bitmap.map((x) => x.toRadixString(2).split('').reversed.join().padRight(8, '0')).join();
  }
}

int getPacketPayloadLength(List<int> buffer, Cursor cursor) {
  return readInteger(buffer, cursor.clone(), 3);
}

List<int> getRangeEfficiently(List<int> buffer, int start, int end) {
  if (buffer is Uint8List) {
    return Uint8List.sublistView(buffer, start, end);
  }
  return buffer.sublist(start, end);
}

extension IntListToUint8ListExtension on List<int> {
  Uint8List toUint8List() {
    if (this is Uint8List) {
      return this as Uint8List;
    }
    return Uint8List.fromList(this);
  }
}

bool _availableToReadPacketAtInternal(
  List<int> buffer,
  Cursor cursor,
  int headerLength,
) {
  if (buffer.isEmpty || cursor.position == buffer.length) {
    return false;
  }

  final sufficientToReadHeader =
      buffer.length - cursor.position >= headerLength;
  if (!sufficientToReadHeader) {
    return false;
  }

  final sufficientToReadPayload =
      buffer.length - cursor.position - headerLength >=
          getPacketPayloadLength(buffer, cursor);
  if (!sufficientToReadPayload) {
    return false;
  }

  return true;
}

abstract base class _PacketIteratorBase<T> implements Iterator<T> {
  final List<int> _buffer;

  final Cursor _cursor;
  final Cursor _current;

  final int _headerLength;

  _PacketIteratorBase(
    List<int> buffer,
    Cursor cursor,
    int headerLength,
  )   : _buffer = buffer,
        _cursor = cursor,
        _current = cursor.clone(),
        _headerLength = headerLength;

  List<int> get buffer => _buffer;

  Cursor get cursor => _cursor;

  bool _availableToReadPacketAt(Cursor cursor) {
    return _availableToReadPacketAtInternal(_buffer, cursor, _headerLength);
  }

  int get size {
    assert(_availableToReadPacketAt(_current));
    return getPacketPayloadLength(_buffer, _current) + _headerLength;
  }

  (int, int) get range => (_current.position, _current.position + size);

  @override
  bool moveNext() {
    if (!_availableToReadPacketAt(_cursor)) {
      return false;
    }
    _current.setPosition(_cursor.position);
    _cursor.increase(size);
    return true;
  }
}

final class _PacketRangeIterator extends _PacketIteratorBase<(int, int)>
    implements Iterator<(int, int)> {
  _PacketRangeIterator(
    List<int> buffer,
    Cursor cursor,
    int headerLength,
  ) : super(buffer, cursor, headerLength);

  @override
  (int, int) get current => range;
}

final class _PacketIterator extends _PacketIteratorBase<List<int>>
    implements Iterator<List<int>> {
  _PacketIterator(
    List<int> buffer,
    Cursor cursor,
    int headerLength,
  ) : super(buffer, cursor, headerLength);

  @override
  List<int> get current => getRangeEfficiently(buffer, range.$1, range.$2);
}

class StandardPacketRangeIterable
    with IterableMixin<(int, int)>
    implements Iterable<(int, int)> {
  final List<int> _buffer;

  final Cursor _cursor;

  StandardPacketRangeIterable(List<int> buffer, [Cursor? cursor])
      : _buffer = buffer,
        _cursor = cursor ?? Cursor.zero();

  @override
  Iterator<(int, int)> get iterator =>
      _PacketRangeIterator(_buffer, _cursor, standardPacketHeaderLength);
}

class CompressedPacketRangeIterable
    with IterableMixin<(int, int)>
    implements Iterable<(int, int)> {
  final List<int> _buffer;

  final Cursor _cursor;

  CompressedPacketRangeIterable(List<int> buffer, [Cursor? cursor])
      : _buffer = buffer,
        _cursor = cursor ?? Cursor.zero();

  @override
  Iterator<(int, int)> get iterator =>
      _PacketRangeIterator(_buffer, _cursor, compressedPacketHeaderLength);
}

class StandardPacketIterable
    with IterableMixin<List<int>>
    implements Iterable<List<int>> {
  final List<int> _buffer;

  final Cursor _cursor;

  StandardPacketIterable(List<int> buffer, [Cursor? cursor])
      : _buffer = buffer,
        _cursor = cursor ?? Cursor.zero();

  @override
  Iterator<List<int>> get iterator =>
      _PacketIterator(_buffer, _cursor, standardPacketHeaderLength);
}

class CompressedPacketIterable
    with IterableMixin<List<int>>
    implements Iterable<List<int>> {
  final List<int> _buffer;

  final Cursor _cursor;

  CompressedPacketIterable(List<int> buffer, [Cursor? cursor])
      : _buffer = buffer,
        _cursor = cursor ?? Cursor.zero();

  @override
  Iterator<List<int>> get iterator =>
      _PacketIterator(_buffer, _cursor, compressedPacketHeaderLength);
}

int countStandardPackets(List<int> buffer) {
  return StandardPacketIterable(buffer).length;
}

int countCompressedPackets(List<int> buffer) {
  return CompressedPacketIterable(buffer).length;
}

String formatSize(int size) {
  return "$size";
}
