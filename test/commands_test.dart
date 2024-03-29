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

import 'logging.dart';
import 'server.dart';

void main() {
  group("COM_PING", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      await Ping(conn.commandContext).execute(());
    });
  });

  group("COM_QUIT", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      await Quit(conn.commandContext).execute(());
    });
  });

  group("COM_QUERY", () {
    test(
      "SELECT * FROM users",
      () async {
        final conn = await connectToServer();

        await conn.query("SELECT * FROM users");
      },
      timeout: Timeout(Duration(hours: 1)),
    );

    test(
      "SELECT * FROM tbl1",
      () async {
        final conn = await connectToServer();

        await conn.query("SELECT * FROM tbl1");
      },
      timeout: Timeout(Duration(hours: 1)),
    );
    

    test("LOCAL INFILE", () async {
      final conn = await connectToServer();

      await conn.query("LOAD DATA LOCAL INFILE 'users.csv' INTO TABLE users");
    });
  });

  group("COM_STATISTICS", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      logger.debug(await Statistics(conn.commandContext).execute(()));
    });
  });

  group("COM_SET_OPTION", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      await SetOption(conn.commandContext)
          .execute((enableMultiStatements: true));
    });
  });

  group("COM_SHUTDOWN", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      await Shutdown(conn.commandContext).execute(());
    });
  });

  group("COM_DEBUG", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      await Debug(conn.commandContext).execute(());
    });
  });

  group("COM_STMT_PREPARE", () {
    group("without placeholder", () {
      test("should be successful", () async {
        final conn = await connectToServer();

        final result = await PrepareStmt(conn.commandContext)
            .execute((sqlStatement: "SELECT * FROM users"));
        logger.debug(result.props);
      });
    });

    group("with placeholders", () {
      test("should be successful", () async {
        final conn = await connectToServer();

        final result = await PrepareStmt(conn.commandContext)
            .execute((sqlStatement: "SELECT * FROM users WHERE id = ?"));
        logger.debug(result.props);
      });
    });
  });

  group("COM_STMT_CLOSE", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      final stmt = await PrepareStmt(conn.commandContext)
          .execute((sqlStatement: "SELECT * FROM users"));
      await CloseStmt(conn.commandContext)
          .execute((statementId: stmt.statementId));
    });
  });

  group("COM_STMT_RESET", () {
    test("should be successful", () async {
      final conn = await connectToServer();

      final stmt = await PrepareStmt(conn.commandContext)
          .execute((sqlStatement: "SELECT * FROM users"));
      await ResetStmt(conn.commandContext)
          .execute((statementId: stmt.statementId));
    });
  });

  group("COM_STMT_EXECUTE", () {
    group("without placeholder", () {
      test("should be successful", () async {
        final conn = await connectToServer();

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
        final conn = await connectToServer();

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
          parameters: [encodeForBinary(stmt.columns![0].mysqlType, 2)],
        ));
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
