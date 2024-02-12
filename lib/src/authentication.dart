import 'package:crypto/crypto.dart';

class MysqlNativePasswordAuthPlugin {
  static List<int> encrypt(String password, List<int> salt) {
    final u = sha1.convert(password.codeUnits).bytes;
    final v = sha1.convert(u).bytes;
    final w = sha1.convert(salt + v).bytes;
    return _xor(u, w);
  }

  static List<int> _xor(List<int> a, List<int> b) {
    assert(a.length == b.length);

    if (a.length != b.length) {
      throw ArgumentError("two vectors have must with the same length");
    }

    final result = List.filled(a.length, 0);
    for (int i = 0; i < a.length; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }
}
