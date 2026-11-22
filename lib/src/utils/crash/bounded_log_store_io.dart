import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// A shared, bounded log ring. All file operations run asynchronously.
class BoundedLogStore {
  BoundedLogStore(
    this.path, {
    this.maxBytes = 20000000,
    this.segmentBytes = 2000000,
  }) {
    if (segmentBytes < 32 || maxBytes < segmentBytes) {
      throw ArgumentError('Invalid log budget');
    }
  }

  final String path;
  final int maxBytes;
  final int segmentBytes;
  bool _prepared = false;
  int get _archives => maxBytes ~/ segmentBytes - 1;
  String _name(int index) => index == 0 ? path : '$path.$index';

  Future<void> _check(String name) async {
    final type = await FileSystemEntity.type(name, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Log path must be a regular file', name);
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) async {
    await File(path).parent.create(recursive: true);
    final gate = File('$path.writer.$pid.lock');
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    var gated = false;
    RandomAccessFile? lock;
    var acquired = false;
    try {
      // Unix advisory locks belong to the process, not an isolate. Serialize
      // local isolates before opening another descriptor for the shared lock.
      if (!Platform.isWindows) {
        while (!gated) {
          try {
            await gate.create(exclusive: true);
            gated = true;
          } on FileSystemException {
            if (DateTime.now().isAfter(deadline)) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }
      }
      await _check('$path.lock');
      lock = await File('$path.lock').open(mode: FileMode.append);
      while (!acquired) {
        try {
          await lock.lock(FileLock.exclusive);
          acquired = true;
        } on FileSystemException {
          if (DateTime.now().isAfter(deadline)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      for (var i = 0; i <= _archives; i++) {
        await _check(_name(i));
      }
      if (!_prepared) {
        for (var i = 0; i <= _archives; i++) {
          final file = File(_name(i));
          if (await file.exists() && await file.length() > segmentBytes) {
            // Existing owned logs may come from an older, larger budget.
            final handle = await file.open();
            late List<int> tail;
            try {
              await handle.setPosition(await handle.length() - segmentBytes);
              tail = await handle.read(segmentBytes);
            } finally {
              await handle.close();
            }
            // Discard a partial record: its credential key may precede the tail.
            final newline = tail.indexOf(10);
            tail = newline < 0 ? [] : tail.sublist(newline + 1);
            await file.writeAsBytes(tail);
          }
        }
        _prepared = true;
      }
      return await action();
    } finally {
      try {
        if (lock != null) {
          try {
            if (acquired) await lock.unlock();
          } finally {
            await lock.close();
          }
        }
      } finally {
        if (gated) await gate.delete();
      }
    }
  }

  /// Scrub pre-existing owned logs once, without a second unbounded history.
  Future<void> sanitizeExisting(String Function(String) sanitize) =>
      _locked(() async {
        final marker = File('$path.migrated.lock');
        await _check(marker.path);
        if (await marker.exists()) return;
        for (var i = 0; i <= _archives; i++) {
          final file = File(_name(i));
          if (!await file.exists()) continue;
          var data = utf8.encode(sanitize(await file.readAsString()));
          if (data.length > segmentBytes) {
            var start = data.length - segmentBytes;
            while (start < data.length && data[start] & 0xc0 == 0x80) {
              start++;
            }
            data = data.sublist(start);
          }
          await file.writeAsBytes(data);
        }
        await marker.create();
      });

  /// Import only a bounded, complete tail; retain the source if persistence fails.
  Future<void> importLegacy(
    String legacyPath,
    String Function(String) sanitize,
  ) => _locked(() async {
    if (File(legacyPath).absolute.path == File(path).absolute.path) return;
    if (await FileSystemEntity.type(legacyPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final legacy = File(legacyPath);
    final handle = await legacy.open();
    late List<int> tail;
    try {
      final length = await handle.length();
      final clipped = length > 65536;
      await handle.setPosition(clipped ? length - 65536 : 0);
      tail = await handle.read(65536);
      if (clipped) {
        final newline = tail.indexOf(10);
        tail = newline < 0 ? [] : tail.sublist(newline + 1);
      }
    } finally {
      await handle.close();
    }
    await _append(sanitize(utf8.decode(tail, allowMalformed: true)));
    await legacy.delete();
  });

  Future<void> append(String content) => _locked(() => _append(content));

  Future<void> _append(String content) async {
    const marker = ' [truncated]\n';
    final limit = math.min(segmentBytes, 65536);
    // Bound encoding work even when a caller supplies a huge exception.
    final prefix = content.length > limit
        ? content.substring(0, limit)
        : content;
    List<int> data = utf8.encode(prefix.endsWith('\n') ? prefix : '$prefix\n');
    if (data.length > limit || prefix.length < content.length) {
      var end = math.min(data.length, limit - marker.length);
      while (end > 0 && data[end] & 0xc0 == 0x80) {
        end--;
      }
      data = [...data.take(end), ...utf8.encode(marker)];
    }
    final active = File(path);
    if (await active.exists() &&
        await active.length() + data.length > segmentBytes) {
      final oldest = File(_name(_archives));
      if (await oldest.exists()) await oldest.delete();
      for (var i = _archives - 1; i >= 0; i--) {
        final source = File(_name(i));
        if (await source.exists()) await source.rename(_name(i + 1));
      }
    }
    await active.writeAsBytes(data, mode: FileMode.append);
  }

  Future<String?> read() => _locked(() async {
    final text = StringBuffer();
    for (var i = _archives; i >= 0; i--) {
      final file = File(_name(i));
      if (await file.exists()) text.write(await file.readAsString());
    }
    return text.isEmpty ? null : text.toString();
  });

  Future<void> clear() => _locked(() async {
    for (var i = 0; i <= _archives; i++) {
      final file = File(_name(i));
      if (await file.exists()) await file.delete();
    }
  });
}
