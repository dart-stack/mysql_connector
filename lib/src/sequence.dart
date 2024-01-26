import 'utils.dart';

class PacketSequenceManager {
  late int _latestStandardPacketSequence;

  late int _latestCompressedPacketSequence;

  PacketSequenceManager() {
    resetSequence();
  }

  int get latestStandardPacketSequence => _latestStandardPacketSequence;

  int get latestCompressedPacketSequence => _latestCompressedPacketSequence;

  int get nextStandardPacketSequence {
    if (_latestStandardPacketSequence == 0xff) {
      return 0;
    }
    return _latestStandardPacketSequence + 1;
  }

  int get nextCompressedPacketSequence {
    if (_latestCompressedPacketSequence == 0xff) {
      return 0;
    }
    return _latestCompressedPacketSequence + 1;
  }

  void resetSequence() {
    _latestStandardPacketSequence = -1;
    _latestCompressedPacketSequence = -1;
  }

  int increaseAndGetStandardPacketSequence() {
    if (_latestStandardPacketSequence == 0xff) {
      _latestStandardPacketSequence = 0;
    } else {
      _latestStandardPacketSequence += 1;
    }
    return _latestStandardPacketSequence;
  }

  int increaseAndGetCompressedPacketSequence() {
    if (_latestCompressedPacketSequence == 0xff) {
      _latestCompressedPacketSequence = 0;
    } else {
      _latestCompressedPacketSequence += 1;
    }
    return _latestCompressedPacketSequence;
  }

  void trackStandardPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();

    final ranges = IterableStandardPacketRanges(buffer, cursor);
    for (final range in ranges) {
      _latestStandardPacketSequence =
          buffer[range.$1 + standardPacketSequenceOffset];
    }
  }

  void trackCompressedPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();

    final ranges = CompressedPacketRangeIterable(buffer, cursor);
    for (final range in ranges) {
      _latestCompressedPacketSequence =
          buffer[range.$1 + compressedPacketSequenceOffset];
    }
  }

  void patchStandardPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();

    final ranges = IterableStandardPacketRanges(buffer, cursor);
    for (final range in ranges) {
      buffer[range.$1 + standardPacketSequenceOffset] =
          increaseAndGetStandardPacketSequence();
    }
  }

  void patchCompressedPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();

    final ranges = CompressedPacketRangeIterable(buffer, cursor);
    for (final range in ranges) {
      buffer[range.$1 + compressedPacketSequenceOffset] =
          increaseAndGetCompressedPacketSequence();
    }
  }
}
