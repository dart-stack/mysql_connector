import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mysql_connector/src/session.dart';

import 'common.dart';
import 'utils.dart';
import 'packet.dart';
import 'authentication.dart';
import 'logging.dart';
import 'socket.dart';

abstract interface class HandshakeDelegate {
  void setProtocolVersion(int protocolVersion);

  void setServerVersion(String serverVersion);

  void setServerConnectionId(int serverConnectionId);

  void setServerDefaultCharset(int serverDefaultCharset);

  void setServerCapabilities(int serverCapabilities);

  void setClientCapabilities(int clientCapabilities);

  void setMaxPacketSize(int maxPacketSize);

  void setCharset(int charset);

  void setCompressionEnabled(bool compressionEnabled);
}

enum HandshakeState {
  awaitingInitialHandshake,
  awaitingAuthResponse,
  awaitingAuthSwitchResponse,
  completed
}

class Handshaker {
  final Logger _logger = LoggerFactory.createLogger(name: "Handshaker");

  final PacketWriter _writer;

  final PacketStreamReader _reader;

  final NegotiationState _negotiationState;

  final HandshakeDelegate _delegate;

  final ConnectOptions _connectOptions;

  HandshakeState _handshakeState = HandshakeState.awaitingInitialHandshake;

  late InitialHandshakePacket _initialHandshake;

  Handshaker(
    this._writer,
    this._reader,
    this._negotiationState,
    this._delegate,
    this._connectOptions,
  );

  void _setHandshakeState(HandshakeState handshakeState) {
    _handshakeState = handshakeState;
  }

  Future<void> process() async {
    if (_handshakeState == HandshakeState.completed) {
      return;
    }

    _logger.debug("handshaking is started");

    await processInitialHandshake(_reader);
    _logger.debug("initial handshake was received");
    sendClientHandshakeResponse();
    _logger.debug("client handshake was sent");
    await processHandshakeResult(_reader);

    // Note: packet socket is under controlled by [compressionEnabled]
    //  state, it must be postponed to set after handshake is complete.
    _delegate.setCompressionEnabled(_connectOptions.enableCompression);
  }

  Future<void> processHandshakeResult(PacketStreamReader reader) async {
    final packet = await reader.next();

    switch (packet[standardPacketPayloadOffset]) {
      case 0x00:
        final ok = OkPacket.parse(packet, _negotiationState);
        _logger.debug(ok);

        _setHandshakeState(HandshakeState.completed);
        _logger.info("handshaking was successful");
        return;

      case 0xFF:
        final err = ErrPacket.parse(packet, _negotiationState);
        _logger.debug(err);
        _setHandshakeState(HandshakeState.completed);
        _logger.info("handshaking was failed");
        err.throwIfError((error) =>
            MysqlHandshakeException(error.errorCode, error.errorMessage));

      case 0xFE:
        reader.index -= 1;
        await processAuthSwitchRequest(reader);
        return;
    }
  }

  Future<void> processAuthSwitchRequest(PacketStreamReader reader) async {
    final req = await AuthSwitchRequest.readAndParse(reader);
    _logger.debug(req);

    sendAuthSwitchResponse(req.authPluginName, req.authPluginData);
    await processAuthSwitchResult(reader);
  }

  Future<void> processAuthSwitchResult(PacketStreamReader reader) async {
    final message = await reader.next();
    switch (message[standardPacketPayloadOffset]) {
      case 0x00:
        final ok = OkPacket.parse(message, _negotiationState);
        _logger.debug(ok);
        _logger.debug("authentication was successful");

        _setHandshakeState(HandshakeState.completed);
        _logger.debug("handshaking was successful");

        return;

      case 0xFF:
        final err = ErrPacket.parse(message, _negotiationState);
        _logger.debug(err);
        _logger.debug("authentication was failed");

        _setHandshakeState(HandshakeState.completed);
        _logger.debug("handshaking was failed");

        err.throwIfError((error) =>
            MysqlHandshakeException(error.errorCode, error.errorMessage));
    }
  }

  void _pack(List<int> buffer, int sequence) {
    final length = buffer.length - standardPacketHeaderLength;

    buffer[0] = length & 0xff;
    buffer[1] = (length >> 8) & 0xff;
    buffer[2] = (length >> 16) & 0xff;
    buffer[3] = sequence & 0xff;
  }

  Future<void> processInitialHandshake(PacketStreamReader reader) async {
    final packet = await InitialHandshakePacket.readAndParse(reader);

    _initialHandshake = packet;
    _delegate.setProtocolVersion(packet.protocolVersion);
    _delegate.setServerVersion(packet.serverVersion);
    _delegate.setServerConnectionId(packet.connectionId);
    _delegate.setServerDefaultCharset(packet.serverDefaultCollation);
    _delegate.setServerCapabilities(packet.serverCapabilities);

    _logger.debug(packet.toString());
  }

  void sendClientHandshakeResponse() {
    final builder = BytesBuilder();
    builder.add([0x00, 0x00, 0x00, 0x00]);

    var clientCaps = 0;
    clientCaps |= capClientProtocol41;
    clientCaps |= capLocalFiles;
    // _clientCaps |= kCapSecureConnection;

    clientCaps |= capPluginAuth;

    if (_connectOptions.enableCompression) {
      clientCaps |= capCompress;
    }

    if (_connectOptions.database != null) {
      clientCaps |= capConnectWithDB;
    }

    writeInteger(builder, 4, clientCaps & 0xffffffff);
    writeInteger(builder, 4, _connectOptions.maxPacketSize);
    writeInteger(builder, 1, _connectOptions.charset);
    writeBytes(builder, List.filled(19, 0));
    if ((clientCaps & capClientMysql) == 0) {
      writeInteger(builder, 4, (clientCaps >> 32) & 0xffffffff);
    } else {
      writeBytes(builder, List.filled(4, 0));
    }
    writeZeroTerminatingString(builder, _connectOptions.user);

    var encodedPassword = MysqlNativePasswordAuthPlugin.encrypt(
      _connectOptions.password,
      _initialHandshake.scramble,
    );
    if ((clientCaps & capPluginAuthLenencClientData) != 0) {
      writeLengthEncodedBytes(builder, encodedPassword);
    } else if ((clientCaps & capSecureConnection) != 0) {
      writeInteger(builder, 1, encodedPassword.length);
      writeBytes(builder, encodedPassword);
    } else {
      writeZeroTerminatingBytes(builder, []);
    }
    if ((clientCaps & capConnectWithDB) != 0) {
      writeZeroTerminatingString(builder, _connectOptions.database!);
    }
    if ((clientCaps & capPluginAuth) != 0) {
      writeZeroTerminatingString(builder, _connectOptions.authMethod);
    }
    if ((clientCaps & capConnectAttrs) != 0) {
      writeLengthEncodedInteger(builder, 0);
      // for (int i = 0; i < 1; i++) {
      //   writeLengthEncodedString(data, "key");
      //   writeLengthEncodedString(data, "value");
      // }
    }

    final buffer = builder.takeBytes();
    _pack(buffer, 1);
    _writer.writePacket(buffer);

    _delegate.setClientCapabilities(clientCaps);
    _delegate.setMaxPacketSize(_connectOptions.maxPacketSize);
    _delegate.setCharset(_connectOptions.charset);
    _logger.debug(buffer);
  }

  void sendAuthSwitchResponse(String pluginName, List<int> pluginData) {
    var builder = BytesBuilder();
    builder.add([0x00, 0x00, 0x00, 0x00]);

    writeBytes(
      builder,
      MysqlNativePasswordAuthPlugin.encrypt(
        _connectOptions.password,
        pluginData,
      ),
    );

    final buffer = builder.takeBytes();
    _pack(buffer, 3);

    _logger.debug(buffer);
    _writer.writePacket(buffer);
  }
}

class InitialHandshakePacket {
  static const fieldProtocolVersion = "protocolVersion";
  static const fieldServerVersion = "serverVersion";
  static const fieldConnectionId = "connectionId";
  static const fieldScramblePart1 = "scramblePart1";
  static const fieldServerCapabilitiesPart1 = "serverCapabilitiesPart1";
  static const fieldServerDefaultCollation = "serverDefaultCollation";
  static const fieldStatusFlags = "statusFlags";
  static const fieldServerCapabilitiesPart2 = "serverCapabilitiesPart2";
  static const fieldAuthPluginDataLength = "authPluginDataLength";
  static const fieldServerCapabilitiesPart3 = "serverCapabilitiesPart3";
  static const fieldScramblePart2 = "scramblePart2";
  static const fieldAuthPluginName = "authPluginName";
  static const fieldServerCapabilities = "serverCapabilities";
  static const fieldScramble = "scramble";

  static Future<InitialHandshakePacket> readAndParse(
    PacketStreamReader reader,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    cursor.increment(standardPacketHeaderLength);

    final packet = await reader.next();
    props[fieldProtocolVersion] = readInteger(packet, cursor, 1);
    props[fieldServerVersion] = readZeroTerminatingString(packet, cursor);
    props[fieldConnectionId] = readInteger(packet, cursor, 4);
    props[fieldScramblePart1] = readBytes(packet, cursor, 8);
    props[fieldScramble] = <int>[];
    props[fieldScramble] += props[fieldScramblePart1];
    readBytes(packet, cursor, 1);
    props[fieldServerCapabilitiesPart1] = readInteger(packet, cursor, 2);
    props[fieldServerDefaultCollation] = readInteger(packet, cursor, 1);
    props[fieldStatusFlags] = readInteger(packet, cursor, 2);
    props[fieldServerCapabilitiesPart2] = readInteger(packet, cursor, 2);
    props[fieldServerCapabilities] = 0;
    props[fieldServerCapabilities] |= props[fieldServerCapabilitiesPart1];
    props[fieldServerCapabilities] |= props[fieldServerCapabilitiesPart2] << 16;
    if ((props[fieldServerCapabilities] & capPluginAuth) != 0) {
      props[fieldAuthPluginDataLength] = readInteger(packet, cursor, 1);
    } else {
      readInteger(packet, cursor, 1);
    }
    readString(packet, cursor, 6);
    if ((props[fieldServerCapabilities] & capClientMysql) != 0) {
      readString(packet, cursor, 4);
    } else {
      props[fieldServerCapabilitiesPart3] = readInteger(packet, cursor, 4);
      props[fieldServerCapabilities] |=
          props[fieldServerCapabilitiesPart3] << 24;
    }
    if ((props[fieldServerCapabilities] & capSecureConnection) != 0) {
      props[fieldScramblePart2] = readBytes(
          packet, cursor, max(12, props[fieldAuthPluginDataLength] - 9));
      props[fieldScramble] += props[fieldScramblePart2];
      readBytes(packet, cursor, 1);
    }
    if ((props[fieldServerCapabilities] & capPluginAuth) != 0) {
      props[fieldAuthPluginName] = readZeroTerminatingString(packet, cursor);
    }

    return InitialHandshakePacket(props);
  }

  final Map<String, dynamic> _props;

  InitialHandshakePacket(this._props);

  int get protocolVersion => _props[fieldProtocolVersion];

  String get serverVersion => _props[fieldServerVersion];

  int get connectionId => _props[fieldConnectionId];

  List<int> get scramble => _props[fieldScramble];

  int get serverCapabilities => _props[fieldServerCapabilities];

  int get serverDefaultCollation => _props[fieldServerDefaultCollation];

  int get statusFlags => _props[fieldStatusFlags];

  int get authPluginDataLength => _props[fieldAuthPluginDataLength];

  int get authPluginName => _props[fieldAuthPluginName];

  @override
  String toString() {
    return _props.toString();
  }
}

class AuthSwitchRequest {
  static const fieldAuthPluginName = "authPluginName";
  static const fieldAuthPluginData = "authPluginData";

  static Future<AuthSwitchRequest> readAndParse(
    PacketStreamReader reader,
  ) async {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();
    cursor.increment(standardPacketHeaderLength);
    cursor.increment(1);

    final packet = await reader.next();
    props[fieldAuthPluginName] = readZeroTerminatingString(packet, cursor);
    // Note: I don't know why there is a '\0' at the end of the packet,
    //  refers to the protocol documentation, that there should be
    //  a string<EOF>.
    props[fieldAuthPluginData] =
        readBytes(packet, cursor, packet.length - cursor.position - 1);

    return AuthSwitchRequest(props);
  }

  final Map<String, dynamic> _props;

  AuthSwitchRequest(this._props);

  String get authPluginName => _props[fieldAuthPluginName];

  List<int> get authPluginData => _props[fieldAuthPluginData];

  @override
  String toString() {
    return _props.toString();
  }
}
