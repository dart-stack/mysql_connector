import 'package:mysql_connector/src/commands/debug.dart';
import 'package:mysql_connector/src/commands/ping.dart';
import 'package:mysql_connector/src/commands/quit.dart';
import 'package:mysql_connector/src/commands/set_option.dart';
import 'package:mysql_connector/src/commands/shutdown.dart';
import 'package:mysql_connector/src/commands/statement.dart';
import 'package:mysql_connector/src/commands/statistics.dart';
import 'package:mysql_connector/src/common.dart';
import 'package:mysql_connector/src/datatype.dart';
import 'package:mysql_connector/src/utils.dart';
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

      await Ping(conn.commandContext).execute(());
    });
  });

  group("COM_QUIT", () {
    test("should be successful", () async {
      final conn = await connect();

      await Quit(conn.commandContext).execute(());
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

      print(await Statistics(conn.commandContext).execute(()));
    });
  });

  group("COM_SET_OPTION", () {
    test("should be successful", () async {
      final conn = await connect();

      await SetOption(conn.commandContext)
          .execute((enableMultiStatements: true));
    });
  });

  group("COM_SHUTDOWN", () {
    test("should be successful", () async {
      final conn = await connect();

      await Shutdown(conn.commandContext).execute(());
    });
  });

  group("COM_DEBUG", () {
    test("should be successful", () async {
      final conn = await connect();

      await Debug(conn.commandContext).execute(());
    });
  });

  group("COM_STMT_PREPARE", () {
    group("without placeholder", () {
      test("should be successful", () async {
        final conn = await connect();

        final result = await PrepareStmt(conn.commandContext)
            .execute((sqlStatement: "SELECT * FROM users"));
        print(result.props);
      });
    });

    group("with placeholders", () {
      test("should be successful", () async {
        final conn = await connect();

        final result = await PrepareStmt(conn.commandContext)
            .execute((sqlStatement: "SELECT * FROM users WHERE id = ?"));
        print(result.props);
      });
    });
  });

  group("COM_STMT_CLOSE", () {
    test("should be successful", () async {
      final conn = await connect();

      final stmt = await PrepareStmt(conn.commandContext)
          .execute((sqlStatement: "SELECT * FROM users"));
      await CloseStmt(conn.commandContext)
          .execute((statementId: stmt.statementId));
    });
  });

  group("COM_STMT_RESET", () {
    test("should be successful", () async {
      final conn = await connect();

      final stmt = await PrepareStmt(conn.commandContext)
          .execute((sqlStatement: "SELECT * FROM users"));
      await ResetStmt(conn.commandContext)
          .execute((statementId: stmt.statementId));
    });
  });

  group("COM_STMT_EXECUTE", () {
    group("without placeholder", () {
      test("should be successful", () async {
        final conn = await connect();

        final stmt = await PrepareStmt(conn.commandContext)
            .execute((sqlStatement: "SELECT * FROM users"));
        await ExecuteStmt(conn.commandContext).execute((
          statementId: stmt.statementId,
          flag: 0,
          hasParameters: false,
          nullBitmap: null,
          sendType: null,
          types: null,
          parameters: null,
        ));
      });
    });

    group("with placeholders", () {
      test("should be successful", () async {
        final conn = await connect();

        final stmt = await PrepareStmt(conn.commandContext)
            .execute((sqlStatement: "SELECT * FROM users WHERE id = ?"));
        final rs = await ExecuteStmt(conn.commandContext).execute((
          statementId: stmt.statementId,
          flag: 0,
          hasParameters: true,
          nullBitmap: Bitmap.build([false]).buffer,
          sendType: true,
          types: [
            [mysqlTypeLong, 0]
          ],
          parameters: [encode(stmt.columns![0], 2)],
        ));
        print(rs);
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
