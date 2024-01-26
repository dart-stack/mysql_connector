import 'package:test/test.dart';

import 'package:mysql_connector/src/connection.dart';

import 'server.dart';

void main() {
  group("Connection", () {
    test("connect to server", () async {
      final fac = ConnectionFactory();
      await fac.connect(
        host: "127.0.0.1",
        port: 3306,
        user: "root",
        password: "root",
        database: "test",
        enableCompression: true,
      );
    });

    group(".prepare()", () {
      test("should be successful", () async {
        final conn = await connectToServer();

        await conn.prepare("SELECT * FROM users");
      });
    });
  });

  group("PreparedStatement", () {
    group(".execute()", () {
      group("without parameters", () {
        test("should be successful", () async {
          final conn = await connectToServer();

          final stmt = await conn.prepare("SELECT * FROM users");
          await stmt.execute();
        });
      });

      group("with parameters", () {
        test("should be successful", () async {
          final conn = await connectToServer();

          final stmt = await conn.prepare("SELECT * FROM users WHERE id = ?");
          await stmt.execute([null]);
        });
      });
    });
  });
}
