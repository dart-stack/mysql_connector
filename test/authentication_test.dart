import 'package:test/test.dart';

import 'package:mysql_connector/src/authentication.dart';

void main() {
  group("MysqlNativePassword", () {
    test("encrypt password", () {
      print(
          MysqlNativePasswordAuthPlugin.encrypt("root", '2"QP"S^\\515X<bZzwh%z')
              .toString());
    });
  });
}
