import 'dart:io';

class MysqlHandshakeException implements IOException {
  final int code;

  final String message;

  const MysqlHandshakeException(this.code, this.message);

  @override
  String toString() {
    return "$message ($code)";
  }
}

class MysqlConnectionException implements IOException {
  final int? code;

  final String message;

  const MysqlConnectionException([this.message = "", this.code]);

  @override
  String toString() {
    return "$message${code == null ? "" : " ($code)"}";
  }
}

class MysqlConnectionResetException implements IOException {}

class MysqlExecutionException implements IOException {
  final int code;

  final String message;

  final String? sqlState;

  const MysqlExecutionException(this.code, this.message, this.sqlState);

  @override
  String toString() {
    return "$code $message${sqlState == null ? "" : " ($sqlState)"}";
  }
}

class MysqlCommandException implements IOException {
  final int code;

  final String message;

  final String? sqlState;

  const MysqlCommandException(this.code, this.message, this.sqlState);

  @override
  String toString() {
    return "$code $message${sqlState == null ? "" : " ($sqlState)"}";
  }
}
