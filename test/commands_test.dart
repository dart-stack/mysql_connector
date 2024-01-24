import 'package:mysql_connector/src/commands/debug.dart';
import 'package:mysql_connector/src/commands/ping.dart';
import 'package:mysql_connector/src/commands/set_option.dart';
import 'package:mysql_connector/src/commands/shutdown.dart';
import 'package:mysql_connector/src/commands/statistics.dart';
import 'package:test/test.dart';

import 'package:mysql_connector/src/connection.dart';

Future<Connection> connect() async {
  final fac = ConnectionFactory();
  final conn = await fac.connect(
    host: "127.0.0.1",
    port: 3306,
    user: "root",
    password: "root",
    database: "test",
    enableCompression: true,
    compressionThreshold: 0xffffff,
  );

  return conn;
}

void main() {
  group("COM_PING", () {
    test("should be successful", () async {
      final conn = await connect();

      await Ping(conn.commandContext).execute(PingParams());
    });
  });

  group("COM_QUERY", () {
    group("SELECT", () {
      test("should be successful", () async {
        final conn = await connect();

        await conn.query("SELECT * FROM users");
      }, timeout: Timeout(Duration(hours: 1)));
    });

    test("LOCAL INFILE", () async {
      final conn = await connect();

      await conn.query("LOAD DATA LOCAL INFILE 'users.csv' INTO TABLE users");
    });
  });

  group("COM_STATISTICS", () {
    test("should be successful", () async {
      final conn = await connect();

      print(await Statistics(conn.commandContext).execute(StatisticsParams()));
    });
  });

  group("COM_SET_OPTION", () {
    test("should be successful", () async {
      final conn = await connect();

      await SetOption(conn.commandContext)
          .execute(SetOptionParams(enableMultiStmts: true));
    });
  });

  group("COM_SHUTDOWN", () {
    test("should be successful", () async {
      final conn = await connect();

      await Shutdown(conn.commandContext).execute(ShutdownParams());
    });
  });

  group("COM_DEBUG", () {
    test("should be successful", () async {
      final conn = await connect();

      await Debug(conn.commandContext).execute(DebugParams());
    });
  });

  group("COM_STMT_PREPARE", () {
    test("should be successful", () {});
  });

  group("COM_STMT_CLOSE", () {
    test("should be successful", () {});
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
