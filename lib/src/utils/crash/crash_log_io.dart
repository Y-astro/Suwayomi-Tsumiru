// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bounded_log_store_io.dart';
import 'redact_tokens.dart';

const _queueBytes = 256 * 1024;
final _queues = <String, _LogQueue>{};

_LogQueue _queue(String path) =>
    _queues.putIfAbsent(path, () => _LogQueue(path));

/// Prepare the activity log; null on failure. The override also applies in release builds.
Future<String?> initCrashLog() async {
  try {
    final override = Platform.environment['TSUMIRU_LOG_DIR'];
    final support = await getApplicationSupportDirectory();
    final logDir = Directory(
      override == null || override.isEmpty ? '${support.path}/logs' : override,
    );
    await logDir.create(recursive: true);
    final path = '${logDir.path}/crash.log';
    await _queue(path).store.sanitizeExisting(redactTokens);
    // Import only the old owned crash file. Delete it only after a successful
    // sanitized append, so failed storage cannot erase the previous history.
    await _queue(
      path,
    ).store.importLegacy('${support.path}/logs/crash.log', redactTokens);
    _queue(path);
    return path;
  } catch (_) {
    return null;
  }
}

/// No-op on missing path or write failure; crash reporting must never throw.
Future<void> writeCrashLog(String? path, String content) async {
  if (path != null) await _queue(path).write(content);
}

/// Read the crash log; null when missing or empty.
Future<String?> readCrashLog(String? path) async => path == null
    ? null
    : _queue(path).enqueue<String?>(
        () async => redactNullable(await _queue(path).store.read()),
      );

String? redactNullable(String? text) =>
    text == null ? null : redactTokens(text);

/// Delete the log; no-op for a missing path/file and never throws.
Future<void> clearCrashLog(String? path) async {
  if (path != null) await _queue(path).enqueue(_queue(path).store.clear);
}

/// Await all writes queued before this call, including background diagnostics.
Future<void> flushCrashLog(String? path) async {
  if (path != null) await _queue(path).enqueue(() async {});
}

class _Operation {
  _Operation(this.run, this.drop, this.bytes);
  final Future<void> Function() run;
  final void Function() drop;
  final int bytes;
}

class _LogQueue {
  _LogQueue(String path) : store = BoundedLogStore(path);
  final BoundedLogStore store;
  final _pending = Queue<_Operation>();
  int _bytes = 0;
  int _dropped = 0;
  bool _draining = false;

  Future<void> write(String content) {
    final bounded = content.length > 65536
        ? '${content.substring(0, 65536)} [truncated]'
        : content;
    final safe = redactTokens(bounded);
    final size = utf8.encode(safe).length;
    while (_bytes + size > _queueBytes) {
      final oldest = _pending.where((op) => op.bytes > 0).firstOrNull;
      if (oldest == null) break;
      _pending.remove(oldest);
      _bytes -= oldest.bytes;
      _dropped++;
      oldest.drop();
    }
    return enqueue(() => store.append(safe), bytes: size).then((_) {});
  }

  Future<T?> enqueue<T>(Future<T> Function() action, {int bytes = 0}) {
    final done = Completer<T?>();
    _pending.add(
      _Operation(
        () async {
          try {
            done.complete(await action());
          } catch (_) {
            // Logging is best effort; disk failures never become app failures.
            done.complete(null);
          }
        },
        () => done.complete(null),
        bytes,
      ),
    );
    _bytes += bytes;
    if (!_draining) unawaited(_drain());
    return done.future;
  }

  Future<void> _drain() async {
    _draining = true;
    while (_pending.isNotEmpty) {
      final operation = _pending.removeFirst();
      _bytes -= operation.bytes;
      if (_dropped > 0) {
        final count = _dropped;
        _dropped = 0;
        try {
          await store.append(
            '[${DateTime.now().toIso8601String()}] logging: dropped $count queued events',
          );
        } catch (_) {}
      }
      await operation.run();
    }
    _draining = false;
  }
}
