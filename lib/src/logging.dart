
abstract interface class Logger {
  void verbose(Object object);

  void debug(Object object);

  void info(Object object);

  void warn(Object object);

  void error(Object object);
}

class ConsoleLogger implements Logger {
  @override
  void verbose(Object object) {
    //TODO: implement log level

    // print(object);
  }

  @override
  void debug(Object object) {
    print(object);
  }

  @override
  void info(Object object) {
    print(object);
  }

  @override
  void warn(Object object) {
    print(object);
  }

  @override
  void error(Object object) {
    print(object);
  }
}
