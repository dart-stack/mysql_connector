import 'package:test/test.dart';

import 'package:mysql_connector/src/authentication.dart';

import 'logging.dart';

void main() {
  group("MysqlNativePassword", () {
    test("encrypt password", () {
      logger.debug(
          MysqlNativePasswordAuthPlugin.encrypt("root", '2"QP"S^\\515X<bZzwh%z'.codeUnits)
              .toString());
    });
  });
}
