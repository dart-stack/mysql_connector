import 'dart:io';

// Capabilities
const capClientMysql = 1;
const capFoundRows = 2;
const capConnectWithDB = 8;
const capCompress = 32;
const capLocalFiles = 128;
const capIgnoreSpace = 256;
const capClientProtocol41 = 1 << 9;
const capClientInteractive = 1 << 10;
const capSsl = 1 << 11;
const capTransactions = 1 << 13;
const capSecureConnection = 1 << 15;
const capMultiStatements = 1 << 16;
const capMultiResults = 1 << 17;
const capPsMultiResults = 1 << 18;
const capPluginAuth = 1 << 19;
const capConnectAttrs = 1 << 20;
const capPluginAuthLenencClientData = 1 << 21;
const capClientCanHandleExpiredPasswords = 1 << 22;
const capClientSessionTrack = 1 << 23;
const capClientDeprecateEof = 1 << 24;
const capClientOptionalResultsetMetadata = 1 << 25;
const capClientZstdCompressionAlgorithm = 1 << 26;
const capClientCapabilityExtension = 1 << 29;
const capClientSslVerifyServerCert = 1 << 30;
const capClientRememberOptions = 1 << 31;
const capMariadbClientProgress = 1 << 32;
const capMariadbClientComMulti = 1 << 33;
const capMariadbClientStmtBulkOperations = 1 << 34;
const capMariadbClientExtendedTypeInfo = 1 << 35;
const capMariadbClientCacheMetadata = 1 << 36;

// TODO: These data-types is only for MariaDB, considering supports MySQL
//  separately.
// Field types
const mysqlTypeDecimal = 0;
const mysqlTypeTiny = 1;
const mysqlTypeShort = 2;
const mysqlTypeLong = 3;
const mysqlTypeFloat = 4;
const mysqlTypeDouble = 5;
const mysqlTypeNull = 6;
const mysqlTypeTimestamp = 7;
const mysqlTypeLonglong = 8;
const mysqlTypeInt24 = 9;
const mysqlTypeDate = 10;
const mysqlTypeTime = 11;
const mysqlTypeDatetime = 12;
const mysqlTypeYear = 13;
const mysqlTypeNewdate = 14;
const mysqlTypeVarchar = 15;
const mysqlTypeBit = 16;
const mysqlTypeTimestamp2 = 17;
const mysqlTypeDatetime2 = 18;
const mysqlTypeTime2 = 19;
const mysqlTypeJson = 245;
const mysqlTypeNewdecimal = 246;
const mysqlTypeEnum = 247;
const mysqlTypeSet = 248;
const mysqlTypeTinyBlob = 249;
const mysqlTypeMediumBlob = 250;
const mysqlTypeLongBlob = 251;
const mysqlTypeBlob = 252;
const mysqlTypeVarString = 253;
const mysqlTypeString = 254;
const mysqlTypeGeometry = 255;

// Field details flag
const fieldFlagNotNull = 1;
const fieldFlagPrimaryKey = 2;
const fieldFlagUniqueKey = 4;
const fieldFlagMultipleKey = 8;
const fieldFlagBlob = 16;
const fieldFlagUnsigned = 32;
const fieldFlagZerofillFlag = 64;
const fieldFlagBinaryCollation = 128;
const fieldFlagEnum = 256;
const fieldFlagAutoIncrement = 512;
const fieldFlagTimestamp = 1024;
const fieldFlagSet = 2048;
const fieldFlagNoDefaultValueFlag = 4096;
const fieldFlagOnUpdateNowFlag = 8192;
const fieldFlagNumFlag = 32768;

// Server status flag
const serverStatusInTrans = 1;
const serverStatusAutocommit = 2;
const serverMoreResultsExists = 8;
const serverQueryNoGoodIndexUsed = 16;
const serverQueryNoIndexUsed = 32;
const serverStatusCursorExists = 64;
const serverStatusLastRowSent = 128;
const serverStatusDbDropped = 1 << 8;
const serverStatusNoBackslashEscapes = 1 << 9;
const serverStatusMetadataChanged = 1 << 10;
const serverQueryWasSlow = 1 << 11;
const serverPsOutParams = 1 << 12;
const serverStatusInTransReadonly = 1 << 13;
const serverSessionStateChanged = 1 << 14;

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
    return "$code $message${sqlState == null ? "" : " ($sqlState)"}";
  }
}
