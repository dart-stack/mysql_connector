import 'package:test/test.dart';

import 'package:mysql_connector/src/connection.dart';

void main() {
  group("COM_PING", () {
    test("should be successful", () async {
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

      await conn.ping();
    });
  });

  group("COM_QUERY", () {
    group("SELECT", () {
      test("should be successful", () async {
        final fac = ConnectionFactory();
        final conn = await fac.connect(
          host: "127.0.0.1",
          port: 3306,
          user: "root",
          password: "root",
          database: "test",
          enableCompression: true,
        );

        await conn.query("SELECT * FROM users");
      });
    });

    test("LOCAL INFILE", () async {
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

      await conn.query("LOAD DATA LOCAL INFILE 'users.csv' INTO TABLE users");
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
