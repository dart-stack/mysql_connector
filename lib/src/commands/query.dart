import 'dart:async';
import 'dart:typed_data';

import 'package:mysql_connector/src/logging.dart';

import '../command.dart';
import '../common.dart';
import '../packet.dart';
import '../resultset.dart';
import '../utils.dart';

typedef QueryParams = ({String sqlStatement});

final class Query extends CommandBase<QueryParams, dynamic> {
  final Logger _logger = LoggerFactory.createLogger(name: "Query");

  Query(CommandContext context) : super(context);

  @override
  Future<dynamic> execute(QueryParams params) async {
    await enter();
    try {
      sendPacket(
        createPacket()
          ..addByte(0x03)
          ..addString(params.sqlStatement)
          ..terminate(),
      );

      List<int> packet = await reader.next();
      switch (packet[4]) {
        case 0x00:
          final result = OkPacket.parse(packet, negotiationState);
          _logger.debug(result);
          return;

        case 0xFF:
          final props = ErrPacket.parse(packet, negotiationState);
          _logger.debug(props);

          return Future.error(MysqlExecutionException(
            props.errorCode,
            props.errorMessage,
            props.sqlState,
          ));

        case 0xFB:
          final props = readLocalInfilePacket(packet);
          _logger.debug(props);

          final fileBuffer = BytesBuilder();

          writeString(fileBuffer, "id email");
          for (int i = 1; fileBuffer.length < 0xffffff + 0xff; i++) {
            writeString(fileBuffer, "\n$i admin@example.com");
          }

          sendPacket(
            createPacket()
              ..addBytes(fileBuffer.takeBytes())
              ..terminate(),
          );
          sendPacket(
            createPacket()..terminate(),
          );

          packet = await reader.next();
          switch (packet[4]) {
            case 0x00:
              final result = OkPacket.parse(packet, negotiationState);
              _logger.debug(result);
              return;

            case 0xFF:
              final props = ErrPacket.parse(packet, negotiationState);
              _logger.debug(props);

              return Future.error(MysqlExecutionException(
                props.errorCode,
                props.errorMessage,
                props.sqlState,
              ));
          }

        default:
          reader.index -= 1;
          final rs = await ResultSet.readAndParse(reader, negotiationState, false);
          _logger.debug("${rs.rows.length} rows was fetched");
          return rs;
      }
    } finally {
      leave();
    }
  }
}
