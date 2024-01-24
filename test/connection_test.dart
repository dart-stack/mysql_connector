import 'package:test/test.dart';

import 'package:mysql_connector/src/connection.dart';

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
  });
}