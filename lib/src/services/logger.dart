import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A simple logger class that prints messages to the console.
class Logger {
  /// Create a new logger.
  void info(String message) {
    print(message); // ignore: avoid_print
  }

  /// Log an error message.
  void err(String message) {
    print('ERROR: $message'); // ignore: avoid_print
  }

  /// Log a warning message.
  void warn(String message) {
    print('WARNING: $message'); // ignore: avoid_print
  }
}

/// A reference to the global logger using package:scoped to create.
final loggerRef = create(Logger.new);

/// A getter for the global logger using package:scoped to read.
/// This is a getter so that it cannot be replaced directly, if you wish
/// to mock the logger use runScoped with override values.
Logger get logger => read(loggerRef);

/// Run [fn] with the global logger replaced with [logger].
@visibleForTesting
R runWithLogger<R>(Logger logger, R Function() fn) {
  return runScoped(fn, values: {loggerRef.overrideWith(() => logger)});
}
