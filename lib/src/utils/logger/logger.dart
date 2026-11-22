import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as l;
import 'package:logger/web.dart';

import '../crash/diagnostics.dart';
import '../crash/redact_tokens.dart';

class Logger {
  static final l.Logger _logger = l.Logger(
    filter: l.ProductionFilter(),
    level: l.Level.info,
    printer: l.PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 30,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: MyConsoleOutput(),
  );

  const Logger._();

  static l.Logger get instance => _logger;
}

l.Logger get logger => Logger.instance;

class MyConsoleOutput extends ConsoleOutput {
  @override
  void output(OutputEvent event) {
    for (int i = 0; i < event.lines.length; i++) {
      debugPrint(redactTokens(event.lines[i]));
    }
    // Persist warnings/errors so background and release failures appear in the copied crash log.
    // Info events also describe normal release activity, with the same redaction.
    if (event.level.index >= l.Level.info.index) {
      final ts = DateTime.now().toIso8601String();
      for (final line in event.lines) {
        recordDiagnostic('[$ts] ${redactTokens(line)}\n');
      }
    }
  }
}
