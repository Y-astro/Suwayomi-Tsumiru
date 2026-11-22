import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';

import '../crash/diagnostics.dart';

/// Counts GraphQL operations in debug builds only.
class GraphQLRequestStats {
  static final Map<String, int> _counts = {};
  static int total = 0;

  static void record(String operation) {
    total++;
    _counts[operation] = (_counts[operation] ?? 0) + 1;
  }

  /// Call counts, most frequent first.
  static String report() {
    final sorted = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final lines = [
      for (final e in sorted.take(25))
        '  ${e.value.toString().padLeft(5)}  ${e.key}',
    ];
    return 'GraphQL: $total requests, ${_counts.length} distinct operations\n'
        '${lines.join('\n')}';
  }

  static void reset() {
    _counts.clear();
    total = 0;
  }
}

class LoggerLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    // Generated requests omit operationName; read it from the definition node.
    final name =
        request.operation.operationName ??
        request.operation.document.definitions
            .whereType<OperationDefinitionNode>()
            .firstOrNull
            ?.name
            ?.value ??
        'unnamed';
    final timer = Stopwatch()..start();
    final identifiers = <String>[];
    void collect(Map<String, dynamic> values) {
      for (final key in [
        'id',
        'mangaId',
        'chapterId',
        'categoryId',
        'mangaIds',
        'chapterIds',
      ]) {
        final value = values[key];
        if (value is int) identifiers.add('$key=$value');
        if (value is List && value.every((item) => item is int)) {
          identifiers.add('$key=${value.take(10).join(',')}');
        }
      }
    }

    collect(request.variables);
    final input = request.variables['input'];
    if (input is Map<String, dynamic>) collect(input);
    void event(String outcome) => recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] api operation=$name ${identifiers.join(' ')} '
      'elapsedMs=${timer.elapsedMilliseconds} outcome=$outcome\n',
    );
    if (kDebugMode) {
      // Generated requests omit operationName; read it from the definition node.
      GraphQLRequestStats.record(name);
    }
    event('start');
    var first = true;
    var failed = false;
    var completed = false;
    try {
      await for (final response in forward!(request)) {
        // Subscriptions can remain open indefinitely; log the first result,
        // then only the first error, never each payload or any response body.
        final errors = response.errors?.isNotEmpty ?? false;
        if (first || (errors && !failed)) event(errors ? 'error' : 'success');
        first = false;
        failed = failed || errors;
        yield response;
      }
      completed = true;
      if (first) event('empty');
    } catch (_) {
      failed = true;
      event('error');
      rethrow;
    } finally {
      if (!completed && !failed) event('cancelled');
    }
  }

  LoggerLink();
}
