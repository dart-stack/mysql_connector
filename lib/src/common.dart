// Capabilities
import 'dart:io';

const kCapClientMysql = 1;
const kCapFoundRows = 2;
const kCapConnectWithDB = 8;
const kCapCompress = 32;
const kCapLocalFiles = 128;
const kCapIgnoreSpace = 256;
const kCapClientProtocol41 = 1 << 9;
const kCapClientInteractive = 1 << 10;
const kCapSsl = 1 << 11;
const kCapTransactions = 1 << 13;
const kCapSecureConnection = 1 << 15;
const kCapMultiStatements = 1 << 16;
const kCapMultiResults = 1 << 17;
const kCapPsMultiResults = 1 << 18;
const kCapPluginAuth = 1 << 19;
const kCapConnectAttrs = 1 << 20;
const kCapPluginAuthLenencClientData = 1 << 21;
const kCapClientCanHandleExpiredPasswords = 1 << 22;
const kCapClientSessionTrack = 1 << 23;
const kCapClientDeprecateEof = 1 << 24;
const kCapClientOptionalResultsetMetadata = 1 << 25;
const kCapClientZstdCompressionAlgorithm = 1 << 26;
const kCapClientCapabilityExtension = 1 << 29;
const kCapClientSslVerifyServerCert = 1 << 30;
const kCapClientRememberOptions = 1 << 31;
const kCapMariadbClientProgress = 1 << 32;
const kCapMariadbClientComMulti = 1 << 33;
const kCapMariadbClientStmtBulkOperations = 1 << 34;
const kCapMariadbClientExtendedTypeInfo = 1 << 35;
const kCapMariadbClientCacheMetadata = 1 << 36;

// Field types
const kMysqlTypeDecimal = 0;
const kMysqlTypeTiny = 1;
const kMysqlTypeShort = 2;
const kMysqlTypeLong = 3;
const kMysqlTypeFloat = 4;
const kMysqlTypeDouble = 5;
const kMysqlTypeNull = 6;
const kMysqlTypeTimestamp = 7;
const kMysqlTypeLonglong = 8;
const kMysqlTypeInt24 = 9;
const kMysqlTypeDate = 10;
const kMysqlTypeTime = 11;
const kMysqlTypeDatetime = 12;
const kMysqlTypeYear = 13;
const kMysqlTypeNewdate = 14;
const kMysqlTypeVarchar = 15;
const kMysqlTypeBit = 16;
const kMysqlTypeTimestamp2 = 17;
const kMysqlTypeDatetime2 = 18;
const kMysqlTypeTime2 = 19;
const kMysqlTypeJson = 245;
const kMysqlTypeNewdecimal = 246;
const kMysqlTypeEnum = 247;
const kMysqlTypeSet = 248;
const kMysqlTypeTinyBlob = 249;
const kMysqlTypeMediumBlob = 250;
const kMysqlTypeLongBlob = 251;
const kMysqlTypeBlob = 252;
const kMysqlTypeVarString = 253;
const kMysqlTypeString = 254;
const kMysqlTypeGeometry = 255;

// Field details flag
const kFieldNotNull = 1;
const kFieldPrimaryKey = 2;
const kFieldUniqueKey = 4;
const kFieldMultipleKey = 8;
const kFieldBlob = 16;
const kFieldUnsigned = 32;
const kFieldZeroFill = 64;
const kFieldBinaryCollation = 128;
const kFieldEnum = 256;
const kFieldAutoIncrement = 512;
const kFieldTimestamp = 1024;
const kFieldSet = 2048;
const kFieldNoDefaultValue = 4096;
const kFieldOnUpdateNow = 8192;
const kFieldNum = 32768;

class ConnectOptions {
  final String host;

  final int port;

  final String user;

  final String password;

  final String? database;

  final int charset;

  final bool enableCompression;

  final String authMethod;

  final int compressionThreshold;

  final int maxPacketSize;

  const ConnectOptions({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    this.database,
    this.charset = 45,
    this.enableCompression = true,
    this.authMethod = "mysql_native_password",
    this.compressionThreshold = 128,
    this.maxPacketSize = 0xffffff,
  });
}

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
    return "${sqlState == null ? "" : "$sqlState "}$message ($code)";
  }
}
