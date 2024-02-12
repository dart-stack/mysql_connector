enum LogLevel implements Comparable<LogLevel> {
  slient(0, "SLIENT"),
  fatal(1, "FATAL"),
  error(2, "ERROR"),
  warn(3, "WARN"),
  info(4, "INFO"),
  debug(5, "DEBUG"),
  trace(6, "TRACE");

  final int order;

  final String label;

  const LogLevel(this.order, this.label);

  @override
  int compareTo(LogLevel other) => order - other.order;

  bool shouldReport(LogLevel other) => order >= other.order;
}

abstract interface class Logger {
  void trace(Object object);

  void debug(Object object);

  void info(Object object);

  void warn(Object object);

  void error(Object object, {Object? error, StackTrace? stackTrace});

  void fatal(Object object, {Object? error, StackTrace? stackTrace});
}

class LoggingConfig {
  static LogLevel level = LogLevel.trace;

  LoggingConfig._();
}

class LoggerFactory {
  static Logger createLogger({
    String? name,
    LogLevel? level,
  }) {
    return ConsoleLogger(name, level);
  }
}

class ConsoleLogger implements Logger {
  final String? _name;

  LogLevel? _level;

  ConsoleLogger(this._name, this._level);

  LogLevel get level => _level ?? LoggingConfig.level;

  set level(LogLevel level) => _level = level;

  bool _shouldReport(LogLevel target) => level.shouldReport(target);

  void formatAndOutput(LogLevel level, Object object) {
    print("${level.label} ${DateTime.now().toIso8601String()} $_name: $object");
  }

  @override
  void trace(Object object) {
    if (!_shouldReport(LogLevel.trace)) {
      return;
    }
    formatAndOutput(LogLevel.trace, object);
  }

  @override
  void debug(Object object) {
    if (!_shouldReport(LogLevel.debug)) {
      return;
    }
    formatAndOutput(LogLevel.debug, object);
  }

  @override
  void info(Object object) {
    if (!_shouldReport(LogLevel.info)) {
      return;
    }
    formatAndOutput(LogLevel.info, object);
  }

  @override
  void warn(Object object) {
    if (!_shouldReport(LogLevel.warn)) {
      return;
    }
    formatAndOutput(LogLevel.warn, object);
  }

  @override
  void error(Object object, {Object? error, StackTrace? stackTrace}) {
    if (!_shouldReport(LogLevel.error)) {
      return;
    }
    formatAndOutput(LogLevel.error, object);
  }

  @override
  void fatal(Object object, {Object? error, StackTrace? stackTrace}) {
    if (!_shouldReport(LogLevel.fatal)) {
      return;
    }
    formatAndOutput(LogLevel.fatal, object);
  }
}
