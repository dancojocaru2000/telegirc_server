import 'dart:io';

void lError({required String function, required String message}) => log(function: function, message: message, type: LogType.error);
void lWarn({required String function, required String message}) => log(function: function, message: message, type: LogType.warn);
void lInfo({required String function, required String message}) => log(function: function, message: message, type: LogType.info);
void lDebug({required String function, required String message}) => log(function: function, message: message, type: LogType.debug);

void log({required String function, required String message, LogType type = LogType.info}) {
  final useColor = stderr.hasTerminal && Platform.environment['NO_COLOR'] == null;

  if (!_maxLogType.allowedTypes.contains(type)) {
    return;
  }

  if (useColor) {
    stderr.write('\e[${type.ansiColor}m');
  }
  stderr.write(type.badge);
  stderr.write(' ');
  stderr.write('($function)');
  if (useColor) {
    stderr.write('\e30m');
  }
  stderr.write(' ');

  stderr.writeln(message);
}

LogType get _maxLogType {
  final logEnv = Platform.environment['LOG']?.toLowerCase();
  if (logEnv == null) {
    return LogType.error;
  }
  else if (logEnv == 'e' || logEnv == 'error') {
    return LogType.error;
  }
  else if (logEnv == 'w' || logEnv == 'warn') {
    return LogType.warn;
  }
  else if (logEnv == 'i' || logEnv == 'info') {
    return LogType.info;
  }
  else if (logEnv == 'd' || logEnv == 'debug') {
    return LogType.debug;
  }
  else {
    return LogType.error;
  }
}

enum LogType {
  error,
  warn,
  info,
  debug,
}

extension AllowedTypes on LogType {
  List<LogType> get allowedTypes {
    final idx = LogType.values.indexOf(this);
    return LogType.values.sublist(0, idx + 1);
  }
}

extension ColorOfType on LogType {
  int get ansiColor {
    switch (this) {
      case LogType.error:
        return 91;
      case LogType.warn:
        return 93;
      case LogType.info:
        return 94;
      case LogType.debug:
        return 33;
    }
  }
}

extension BadgeString on LogType {
  String get badge {
    switch (this) {
      case LogType.error:
        return '[E]';
      case LogType.warn:
        return '[W]';
      case LogType.info:
        return '[I]';
      case LogType.debug:
        return '[D]';
    }
  }
}
