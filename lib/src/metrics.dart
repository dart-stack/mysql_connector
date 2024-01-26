abstract interface class MetricsCollector {
  void incrementReceivedBytes(int delta);

  void incrementSentBytes(int delta);

  void incrementReceivedPackets(int delta);
}
