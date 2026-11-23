import 'dart:convert';
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

  test(
    'a burst shares disk appends without losing ordered redacted records',
    () async {
      final active = _AppendCountingFile(File(path));
      final files = {
        for (var i = 1; i < 10; i++) '$path.$i': File('$path.$i'),
        '$path.lock': File('$path.lock'),
        '$path.writer.$pid.lock': File('$path.writer.$pid.lock'),
      };
      await IOOverrides.runZoned(() async {
        final writes = [
          for (var i = 0; i < 1000; i++)
            writeCrashLog(path, 'event=$i https://host?token=privateSecret'),
        ];
        await flushCrashLog(path);
        await Future.wait(writes);
      }, createFile: (name) => name == path ? active : files[name]!);
      final text = await File(path).readAsString();
      final lines = const LineSplitter().convert(text);
      expect(lines, hasLength(1000));
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i], startsWith('event=$i '));
      }
      expect(text, isNot(contains('privateSecret')));
      expect(active.appends, lessThanOrEqualTo(3));
    },
  );

  test('read and clear remain barriers between write batches', () async {
    final before = [
      for (var i = 0; i < 100; i++) writeCrashLog(path, 'before $i'),
    ];
    final snapshot = readCrashLog(path);
    final clear = clearCrashLog(path);
    final after = [
      for (var i = 0; i < 100; i++) writeCrashLog(path, 'after $i'),
    ];
    await flushCrashLog(path);
    expect(await snapshot, List.generate(100, (i) => 'before $i\n').join());
    await Future.wait([...before, clear, ...after]);
    expect(
      await readCrashLog(path),
      List.generate(100, (i) => 'after $i\n').join(),
    );
  });

  test(
    'byte-sized batches retain full records around oversized Unicode',
    () async {
      final writes = [
        writeCrashLog(path, 'before'),
        writeCrashLog(path, 'a' * 65535),
        writeCrashLog(path, '😀漢字' * 15000),
        writeCrashLog(path, 'after'),
      ];
      await flushCrashLog(path);
      await Future.wait(writes);
      final data = await File(path).readAsBytes();
      final text = utf8.decode(data);
      expect(text, startsWith('before\n${'a' * 65535}\n'));
      expect(text, endsWith(' [truncated]\nafter\n'));
      expect(text.length, lessThan(150000));
    },
  );

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

class _AppendCountingFile implements File {
  _AppendCountingFile(this.file);
  final File file;
  int appends = 0;

  @override
  Directory get parent => file.parent;

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<int> length() => file.length();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    if (mode == FileMode.append) appends++;
    return file.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
