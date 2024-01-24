import 'dart:async';
import 'dart:typed_data';

import '../command.dart';
import '../common.dart';
import '../packet.dart';
import '../resultset.dart';

typedef QueryParams = ({String sqlStatement});

final class Query extends CommandBase<QueryParams, dynamic> {
  Query(CommandContext context) : super(context);

  @override
  Future<dynamic> execute(QueryParams params) async {
    await acquire();

    sendCommand([
      createPacket()
        ..addByte(0x03)
        ..addString(params.sqlStatement),
    ]);

    return handleResponse();
  }

  Future handleResponse() async {
    var packet = await socketReader.readPacket();
    switch (packet[4]) {
      case 0x00:
        final props = OkPacket.from(packet, session);
        logger.debug(props);

        release();

        return;

      case 0xFF:
        final props = ErrPacket.from(packet, session);
        logger.debug(props);

        release();

        return Future.error(MysqlExecutionException(
          props.errorCode,
          props.errorMessage,
          props.sqlState,
        ));

      case 0xFB:
        final props = readLocalInfilePacket(packet);
        logger.debug(props);

        final fileBuffer = BytesBuilder();

        writeString(fileBuffer, "id email");
        for (int i = 1; fileBuffer.length < 0xffffff + 0xff; i++) {
          writeString(fileBuffer, "\n$i admin@example.com");
        }

        sendCommand([
          createPacket()..addBytes(fileBuffer.takeBytes()),
          createPacket(),
        ]);

        packet = await socketReader.readPacket();
        switch (packet[4]) {
          case 0x00:
            final ok = OkPacket.from(packet, session);
            logger.debug(ok);

            release();
            return Future.value(ok);

          case 0xFF:
            final err = ErrPacket.from(packet, session);
            logger.debug(err);

            release();
            return Future.error(err.errorCode);
        }

      default:
        socketReader.cursor.increase(-packet.length);
        final result = await ResultSet.fromSocket(socketReader, session, false);
        print("${result.rows.length} rows was fetched");

        release();
        return result;
    }
  }
}
