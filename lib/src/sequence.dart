import 'utils.dart';

int _calculateNextSequence(int currentSequence) =>
    currentSequence == 0xff ? 0 : currentSequence + 1;

class PacketSequenceManager {
  late int _latestStandardPacketSequence;

  late int _latestCompressedPacketSequence;

  PacketSequenceManager() {
    resetSequence();
  }

  int get latestStandardPacketSequence => _latestStandardPacketSequence;

  int get latestCompressedPacketSequence => _latestCompressedPacketSequence;

  int get nextStandardPacketSequence => _calculateNextSequence(_latestStandardPacketSequence);

  int get nextCompressedPacketSequence => _calculateNextSequence(_latestCompressedPacketSequence);

  void resetSequence() {
    _latestStandardPacketSequence = -1;
    _latestCompressedPacketSequence = -1;
  }

  int incrementAndGetStandardPacketSequence() {
    return _latestStandardPacketSequence = nextStandardPacketSequence;
  }

  int incrementAndGetCompressedPacketSequence() {
    return _latestCompressedPacketSequence = nextCompressedPacketSequence;
  }

  void trackStandardPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    for (final (start, _) in traverseStandardPackets(buffer, cursor)) {
      _latestStandardPacketSequence =
          buffer[start + standardPacketSequenceOffset];
    }
  }

  void trackCompressedPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    for (final (start, _) in traverseCompressedPackets(buffer, cursor)) {
      _latestCompressedPacketSequence =
          buffer[start + compressedPacketSequenceOffset];
    }
  }

  void patchStandardPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    for (final (start, _) in traverseStandardPackets(buffer, cursor)) {
      buffer[start + standardPacketSequenceOffset] =
          incrementAndGetStandardPacketSequence();
    }
  }

  void patchCompressedPacketSequence(
    List<int> buffer, [
    Cursor? cursor,
  ]) {
    cursor ??= Cursor.zero();
    for (final (start, _) in traverseCompressedPackets(buffer, cursor)) {
      buffer[start + compressedPacketSequenceOffset] =
          incrementAndGetCompressedPacketSequence();
    }
  }
}
