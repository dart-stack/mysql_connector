abstract interface class SessionState {
  int get protocolVersion;

  String get serverVersion;

  int get serverConnectionId;

  int get serverDefaultCharset;

  int get serverCapabilities;

  int get clientCapabilities;

  int get maxPacketSize;

  bool get compressionEnabled;

  int get charset;

  bool hasCapabilities(int capabilities);
}
