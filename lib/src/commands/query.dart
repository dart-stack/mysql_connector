import 'dart:async';
import 'dart:typed_data';

import '../command.dart';
import '../common.dart';
import '../packet.dart';
import '../resultset.dart';

class QueryParams {
  final String sql;

  const QueryParams({
    required this.sql,
  });
}

final class Query extends CommandBase<QueryParams, dynamic> {
  Query(CommandContext context) : super(context);

  @override
  Future<dynamic> execute(QueryParams params) async {
    await acquire();

    sendCommand([
      createPacket()
        ..addByte(0x03)
        ..addString(params.sql),
    ]);

    return handleResponse();
  }

  Future handleResponse() async {
    var packet = await socketReader.readPacket();
    switch (packet[4]) {
      case 0x00:
        final props = readOkPacket(packet);
        logger.debug(props);

        release();

        return;

      case 0xFF:
        final props = readErrPacket(packet);
        logger.debug(props);

        release();

        return Future.error(MysqlExecutionException(
          props["errorCode"],
          props["message"],
          props["sqlState"],
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
            final props = readOkPacket(packet);
            logger.debug(props);

            release();
            return Future.value(props);

          case 0xFF:
            final props = readErrPacket(packet);
            logger.debug(props);

            release();
            return Future.error(props["message"]);
        }

      default:
        socketReader.cursor.increase(-packet.length);
        final result = await readResultSet(socketReader, session, false);
        print("result set was fetched ${result.rows.length} rows");

        release();
        return result;
    }
  }
}
