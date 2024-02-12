import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/datatype.dart';
import 'package:mysql_connector/src/protocols/mariadb.dart';
import 'package:mysql_connector/src/utils.dart';
import 'package:test/test.dart';

import '../common.dart';
import '../logging.dart';
import '../server.dart';

void main() {
  group("MariaDbLowLevelProtocol", () {
    group("COM_PING", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        await protocol.ping();
      });
    });

    group("COM_QUIT", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        await protocol.quit();
      });
    });

    group("COM_QUERY", () {
      test(
        "SELECT * FROM users",
        () async {
          final conn = await connectToServer();
          final protocol =
              MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

          await protocol.query("SELECT * FROM users");
        },
        timeout: Timeout(Duration(hours: 1)),
      );

      test(
        "SELECT * FROM tbl1",
        () async {
          final conn = await connectToServer();
          final protocol =
              MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

          await protocol.query("SELECT * FROM tbl1");
        },
        timeout: Timeout(Duration(hours: 1)),
      );

      test("LOAD DATA LOCAL INFILE 'users.csv' INTO TABLE users", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        await protocol
            .query("LOAD DATA LOCAL INFILE 'users.csv' INTO TABLE users");
      });
    });

    group("COM_STATISTICS", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        logger.debug(await protocol.stat());
      });
    });

    group("COM_SET_OPTION", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        await protocol.setOption(1);
      });
    });

    group("COM_SHUTDOWN", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        await protocol.shutdown();
      });
    });

    group("COM_DEBUG", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        await protocol.debug();
      });
    });

    group("COM_STMT_PREPARE", () {
      test("SELECT * FROM users", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        final result = await protocol.prepare("SELECT * FROM users");
        logger.debug(result);
      });

      test("SELECT * FROM users WHERE id = ?", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        final result =
            await protocol.prepare("SELECT * FROM users WHERE id = ?");
        logger.debug(result.props);
      });
    });

    group("COM_STMT_CLOSE", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        final stmt = await protocol.prepare("SELECT * FROM users");
        await protocol.closeStatement(stmt.statementId);
      });
    });

    group("COM_STMT_RESET", () {
      test("should be successful", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        final stmt = await protocol.prepare("SELECT * FROM users");
        await protocol.resetStatement(stmt.statementId);
      });
    });

    group("COM_STMT_EXECUTE", () {
      test("SELECT * FROM users", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        final stmt = await protocol.prepare("SELECT * FROM users");
        await protocol.execute(
          stmt.statementId,
          flag: 0,
          hasParameters: false,
          nullBitmap: null,
          sendType: null,
          types: null,
          parameters: null,
        );
      });

      test("SELECT * FROM users WHERE id = ?", () async {
        final conn = await connectToServer();
        final protocol = MariaDbLowLevelProtocol(conn.commandContext, generatedDataDir);

        final stmt = await protocol.prepare("SELECT * FROM users WHERE id = ?");
        final rs = await protocol.execute(
          stmt.statementId,
          flag: 0,
          hasParameters: true,
          nullBitmap: Bitmap.build([false]).buffer,
          sendType: true,
          types: [
            [mysqlTypeLong, 0]
          ],
          parameters: [encodeForBinary(stmt.columns![0].mysqlType, 2)],
        );
        logger.debug(rs);
      });
    });
  });

  // test("COM_STMT_PREPARE", () async {
  //   final fac = ConnectionFactory();
  //   final conn = await fac.connect(
  //     host: "127.0.0.1",
  //     port: 3306,
  //     user: "root",
  //     password: "root",
  //     database: "test",
  //   );

  //   await conn.prepare("SELECT * FROM users");
  // });

  // test("COM_STMT_EXECUTE", () async {
  //   final fac = ConnectionFactory();
  //   final conn = await fac.connect(
  //     host: "127.0.0.1",
  //     port: 3306,
  //     user: "root",
  //     password: "root",
  //     database: "test",
  //   );

  //   final stmt = await conn.prepare("SELECT * FROM users");
  //   await stmt.execute([]);
  //   await stmt.close();
  // });

  // test("COM_STMT_CLOSE", () async {
  //   final fac = ConnectionFactory();
  //   final conn = await fac.connect(
  //     host: "127.0.0.1",
  //     port: 3306,
  //     user: "root",
  //     password: "root",
  //     database: "test",
  //   );

  //   final stmt = await conn.prepare("SELECT * FROM users");
  //   await stmt.execute([]);
  //   await stmt.execute([]);
  //   await stmt.execute([]);
  //   await stmt.close();
  // });

  // test("COM_STMT_FETCH", () async {
  //   final fac = ConnectionFactory();
  //   final conn = await fac.connect(
  //     host: "127.0.0.1",
  //     port: 3306,
  //     user: "root",
  //     password: "root",
  //     database: "test",
  //   );

  //   final stmt = await conn.prepare("SELECT * FROM users");
  //   await stmt.execute([]);
  //   await stmt.fetch(10);
  // });
}
