import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/crash/crash_log_io.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('crashlog-');
    path = '${directory.path}/crash.log';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'writes are ordered before reads and credentials never reach disk',
    () async {
      final writes = [
        for (var i = 0; i < 20; i++)
          writeCrashLog(path, 'event=$i https://host?token=privateSecret'),
      ];
      final text = await readCrashLog(path);
      await Future.wait(writes);
      expect(text, contains('event=19'));
      expect(text, isNot(contains('privateSecret')));
      expect(text!.indexOf('event=0 '), lessThan(text.indexOf('event=19 ')));
      expect(await File(path).readAsString(), isNot(contains('privateSecret')));
    },
  );

  test('clear follows queued writes and new writes survive', () async {
    final before = writeCrashLog(path, 'before clear');
    final clear = clearCrashLog(path);
    final after = writeCrashLog(path, 'after clear');
    await Future.wait([before, clear, after]);
    expect(await readCrashLog(path), 'after clear\n');
  });

  test('overload stays bounded and reports dropped events', () async {
    final writes = [
      for (var i = 0; i < 300; i++)
        writeCrashLog(path, 'event=$i ${'x' * 10000}'),
    ];
    await Future.wait(writes);
    final text = await readCrashLog(path);
    expect(text, contains('event=299'));
    expect(text, contains('logging: dropped'));
    expect(text!.length, lessThan(400000));
  });

  test(
    'missing or unwritable paths never escape into app error handlers',
    () async {
      await writeCrashLog(null, 'ignored');
      expect(await readCrashLog(null), isNull);
      await clearCrashLog(null);
      final obstacle = File('${directory.path}/file');
      await obstacle.writeAsString('unchanged');
      await writeCrashLog('${obstacle.path}/log', 'failure');
      expect(await readCrashLog('${obstacle.path}/log'), isNull);
      expect(await obstacle.readAsString(), 'unchanged');
    },
  );
}
