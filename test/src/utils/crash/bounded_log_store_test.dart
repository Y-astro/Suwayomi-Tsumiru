import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/crash/bounded_log_store_io.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('bounded-log-');
    path = '${directory.path}/app.log';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'legacy import discards partial old records before redaction and removes only its source',
    () async {
      final legacy = File('${directory.path}/legacy.log');
      await legacy.writeAsString('token=${'private' * 12000}\nrecent event\n');
      final store = BoundedLogStore(path);
      await store.importLegacy(
        legacy.path,
        (text) => text.replaceAll('private', '<redacted>'),
      );
      final text = await store.read();
      expect(text, contains('recent event'));
      expect(text, isNot(contains('private')));
      expect(await legacy.exists(), isFalse);
    },
  );

  test('failed legacy import keeps the source for a later retry', () async {
    final legacy = File('${directory.path}/legacy.log');
    await legacy.writeAsString('keep history');
    await Link(path).create(legacy.path);
    final store = BoundedLogStore(path);
    await expectLater(
      store.importLegacy(legacy.path, (text) => text),
      throwsA(isA<FileSystemException>()),
    );
    expect(await legacy.readAsString(), 'keep history');
  }, skip: Platform.isWindows);

  test('migration redacts old files once inside the same budget', () async {
    await File(path).writeAsString('historical token=oldSecret\n');
    final store = BoundedLogStore(path, maxBytes: 1000, segmentBytes: 100);
    await store.sanitizeExisting(
      (text) => text.replaceAll('oldSecret', '<redacted>'),
    );
    expect(await File(path).readAsString(), isNot(contains('oldSecret')));
    await store.append('new event');
    await store.sanitizeExisting((_) => 'must not run again');
    expect(await store.read(), contains('new event'));
  });

  test('default budget bounds actual 20 MB of retained segments', () async {
    final store = BoundedLogStore(path);
    for (var i = 0; i < 340; i++) {
      await store.append('event=$i ${'z' * 64000}');
    }
    var total = 0;
    await for (final file in directory.list()) {
      if (file is File) total += await file.length();
    }
    expect(total, lessThanOrEqualTo(20000000));
    expect(total, greaterThan(18000000));
    expect(await store.read(), contains('event=339'));
  });

  Future<int> bytes() async {
    var total = 0;
    await for (final file in directory.list()) {
      if (file is File &&
          file.path.contains('app.log') &&
          !file.path.endsWith('.lock')) {
        total += await file.length();
      }
    }
    return total;
  }

  test(
    'rotation stays within the aggregate cap and preserves newest entries after restart',
    () async {
      final store = BoundedLogStore(path, maxBytes: 1000, segmentBytes: 100);
      for (var i = 0; i < 80; i++) {
        await store.append('event $i ${'x' * 45}\n');
        expect(await bytes(), lessThanOrEqualTo(1000));
      }
      final restored = BoundedLogStore(path, maxBytes: 1000, segmentBytes: 100);
      final text = await restored.read();
      expect(text, contains('event 79'));
      expect(text, isNot(contains('event 0 ')));
      expect(text!.indexOf('event 78'), lessThan(text.indexOf('event 79')));
    },
  );

  test(
    'oversized Unicode records cannot exceed one segment or leave broken UTF-8',
    () async {
      final store = BoundedLogStore(path, maxBytes: 1000, segmentBytes: 100);
      await store.append('😀漢字' * 3000);
      expect(await bytes(), lessThanOrEqualTo(100));
      final data = await File(path).readAsBytes();
      expect(() => utf8.decode(data), returnsNormally);
      expect(await store.read(), contains('truncated'));
    },
  );

  test(
    'separate isolates serialize writes and retain valid bounded records',
    () async {
      await Future.wait([
        for (var writer = 0; writer < 3; writer++)
          Isolate.run(() async {
            final store = BoundedLogStore(
              path,
              maxBytes: 1000,
              segmentBytes: 100,
            );
            for (var i = 0; i < 12; i++) {
              await store.append('writer=$writer event=$i ${'z' * 20}\n');
            }
          }),
      ]);
      expect(await bytes(), lessThanOrEqualTo(1000));
      final text = await BoundedLogStore(
        path,
        maxBytes: 1000,
        segmentBytes: 100,
      ).read();
      expect(text, contains('event=11'));
      expect(
        text!.split('\n').where((line) => line.isNotEmpty),
        everyElement(startsWith('writer=')),
      );
    },
  );

  test(
    'clear removes active and rotated logs without deleting other files',
    () async {
      final store = BoundedLogStore(path, maxBytes: 1000, segmentBytes: 100);
      await File('${directory.path}/unrelated.txt').writeAsString('keep');
      for (var i = 0; i < 20; i++) {
        await store.append('event $i ${'a' * 40}');
      }
      await store.clear();
      expect(await store.read(), isNull);
      expect(await bytes(), 0);
      expect(
        await File('${directory.path}/unrelated.txt').readAsString(),
        'keep',
      );
      await store.append('after clear');
      expect(await store.read(), 'after clear\n');
    },
  );

  test(
    'rejects a linked log file instead of overwriting an unrelated target',
    () async {
      final outside = File('${directory.path}/outside');
      await outside.writeAsString('unchanged');
      await Link(path).create(outside.path);
      final store = BoundedLogStore(path, maxBytes: 1000, segmentBytes: 100);
      await expectLater(
        store.append('replace'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await outside.readAsString(), 'unchanged');
    },
    skip: Platform.isWindows,
  );
}
