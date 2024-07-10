import 'dart:io';
import 'package:logging/logging.dart';

class FileLogHandler {
  FileLogHandler(String fileName1, String fileName2) {
    _setupLogFile(fileName1, fileName2);
  }

  void _setupLogFile(String fileName1, String fileName2) {
    final directory = Directory.current;
    final logFile1 = File('${directory.path}/$fileName1');
    final logFile2 = File('${directory.path}/$fileName2');

    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'pathImitationLogger') {
        final log = '${record.message}\n';
        logFile1.writeAsStringSync(log, mode: FileMode.append);
      } else if (record.loggerName == 'objErrorsLogger') {
        final log =
            'Log type: ${record.level.name}\nLog time: ${record.time}\nLog message: ${record.message}\n';
        logFile2.writeAsStringSync(log, mode: FileMode.append);
      }
    });
  }

  void pathImitationLogger(String message, {Level level = Level.INFO}) {
    Logger('pathImitationLogger').log(level, message);
  }

  void objErrorsLogger(String message, {Level level = Level.INFO}) {
    Logger('objErrorsLogger').log(level, message);
  }
}
