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

abstract interface class HandshakerDelegate {
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
  final Logger _logger;

  final PacketSocket _socket;

  final SessionContext _session;

  final HandshakerDelegate _delegate;

  final ConnectOptions _connectOptions;

  HandshakeState _handshakeState = HandshakeState.awaitingInitialHandshake;

  late String _scramble;

  Handshaker(
    this._logger,
    this._socket,
    this._session,
    this._delegate,
    this._connectOptions,
  );

  void _setHandshakeState(HandshakeState handshakeState) {
    _handshakeState = handshakeState;
  }

  Future<void> perform() async {
    if (_handshakeState == HandshakeState.completed) {
      return;
    }

    _logger.debug("handshaking was started");

    readInitialHandshake(await _socket.readPacket());
    _logger.debug("initial handshake was received");

    sendClientHandshakeResponse();
    _logger.debug("client handshake was sent");

    await handleAuthResponse(await _socket.readPacket());

    // Note: packet socket is under controlled by [compressionEnabled]
    //  state, it must be postponed to set after handshake is complete.
    _delegate.setCompressionEnabled(_connectOptions.enableCompression);
  }

  Future<void> handleAuthResponse(List<int> message) async {
    switch (message[4]) {
      case 0x00:
        final ok = OkPacket.from(message, _session);
        _logger.debug(ok);
        _logger.debug("authentication was successful");

        _setHandshakeState(HandshakeState.completed);
        _logger.info("handshaking was successful");
        return;

      case 0xFF:
        final err = ErrPacket.from(message, _session);
        _logger.debug(err);
        _logger.debug("authentication was failed");

        _setHandshakeState(HandshakeState.completed);
        _logger.info("handshaking was failed");

        err.throwIfError((error) =>
            MysqlHandshakeException(error.errorCode, error.errorMessage));

      case 0xFE:
        await handleAuthSwitchRequest(message);

        return;
    }
  }

  Future<void> handleAuthSwitchRequest(List<int> message) async {
    final req = readAuthSwitchRequest(message);
    _logger.debug(req);

    sendAuthSwitchResponse(req["authPluginName"], req["authPluginData"]);
    await handleAuthSwitchResult(await _socket.readPacket());
  }

  Future<void> handleAuthSwitchResult(List<int> message) async {
    switch (message[4]) {
      case 0x00:
        final ok = OkPacket.from(message, _session);
        _logger.debug(ok);
        _logger.debug("authentication was successful");

        _setHandshakeState(HandshakeState.completed);
        _logger.info("handshaking was successful");

        return;

      case 0xFF:
        final err = ErrPacket.from(message, _session);
        _logger.debug(err);
        _logger.debug("authentication was failed");

        _setHandshakeState(HandshakeState.completed);
        _logger.info("handshaking was failed");

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

  void readInitialHandshake(List<int> message) {
    final cursor = Cursor.zero();
    final props = <String, dynamic>{};

    cursor.increase(standardPacketHeaderLength);

    props["protocolVersion"] = readInteger(message, cursor, 1);
    props["serverVersion"] = readZeroTerminatedString(message, cursor);
    props["connectionId"] = readInteger(message, cursor, 4);
    props["scramble1"] = readString(message, cursor, 8);
    props["reserved1"] = readBytes(message, cursor, 1);
    props["serverCaps1"] = readInteger(message, cursor, 2);
    props["serverDefaultCollation"] = readInteger(message, cursor, 1);
    props["statusFlags"] = readInteger(message, cursor, 2);
    props["serverCaps2"] = readInteger(message, cursor, 2);
    props["serverCaps"] = props["serverCaps1"] + (props["serverCaps2"] << 16);
    if ((props["serverCaps"] & capPluginAuth) != 0) {
      props["pluginDataLength"] = readInteger(message, cursor, 1);
    } else {
      props["reserved2"] = readInteger(message, cursor, 1);
    }
    props["filter"] = readString(message, cursor, 6);
    if ((props["serverCaps"] & capClientMysql) != 0) {
      props["filter2"] = readString(message, cursor, 4);
    } else {
      props["serverCaps3"] = readInteger(message, cursor, 4);
      props["serverCaps"] = props["serverCaps"] + (props["serverCaps3"] << 24);
    }
    if ((props["serverCaps"] & capSecureConnection) != 0) {
      props["scramble2"] =
          readString(message, cursor, max(12, props["pluginDataLength"] - 9));
      props["reserved3"] = readBytes(message, cursor, 1);
    }
    if ((props["serverCaps"] & capPluginAuth) != 0) {
      props["authenticationPluginName"] =
          readZeroTerminatedString(message, cursor);
    }

    _scramble = props["scramble1"] + props["scramble2"];

    _delegate.setProtocolVersion(props["protocolVersion"]);
    _delegate.setServerVersion(props["serverVersion"]);
    _delegate.setServerConnectionId(props["connectionId"]);
    _delegate.setServerDefaultCharset(props["serverDefaultCollation"]);
    _delegate.setServerCapabilities(props["serverCaps"]);
    _logger.debug(props);
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
    writeZeroTerminatedString(builder, _connectOptions.user);

    var encodedPassword = MysqlNativePasswordAuthPlugin.encrypt(
      _connectOptions.password,
      _scramble,
    );
    if ((clientCaps & capPluginAuthLenencClientData) != 0) {
      writeLengthEncodedBytes(builder, encodedPassword);
    } else if ((clientCaps & capSecureConnection) != 0) {
      writeInteger(builder, 1, encodedPassword.length);
      writeBytes(builder, encodedPassword);
    } else {
      writeZeroTerminatedBytes(builder, []);
    }
    if ((clientCaps & capConnectWithDB) != 0) {
      writeZeroTerminatedString(builder, _connectOptions.database!);
    }
    if ((clientCaps & capPluginAuth) != 0) {
      writeZeroTerminatedString(builder, _connectOptions.authMethod);
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
    _socket.write(buffer);

    _delegate.setClientCapabilities(clientCaps);
    _delegate.setMaxPacketSize(_connectOptions.maxPacketSize);
    _delegate.setCharset(_connectOptions.charset);
    _logger.debug(buffer);
  }

  Map<String, dynamic> readAuthSwitchRequest(List<int> message) {
    final props = <String, dynamic>{};
    final cursor = Cursor.zero();

    final payloadLength = readInteger(message, cursor, 3);
    cursor.increase(1);

    if (message[cursor.position] != 0xFE) {
      throw AssertionError(
        "Auth Switch Request must with a leading byte 0xFE, but got ${message[cursor.position].toRadixString(16)}",
      );
    }
    cursor.increase(1); // skip leading byte
    props["authPluginName"] = readZeroTerminatedString(message, cursor);
    // FIXME: I don't know why there is a '\0' at the end of the packet,
    //  refers to the protocol documentation, that there should be
    //  a string<EOF>.
    props["authPluginData"] = readString(message, cursor,
        standardPacketHeaderLength + payloadLength - cursor.position - 1);

    return props;
  }

  void sendAuthSwitchResponse(String pluginName, String pluginData) {
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

    print(buffer);
    _socket.write(buffer);
  }
}
