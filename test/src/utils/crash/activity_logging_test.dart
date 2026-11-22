import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';
import 'package:tsumiru/src/utils/logger/logger.dart';
import 'package:tsumiru/src/utils/logger/logger_link.dart';

void main() {
  late List<String> persisted;
  late List<String> console;
  late DebugPrintCallback originalPrint;
  setUp(() {
    persisted = [];
    console = [];
    setDiagnosticSink(persisted.add);
    originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => console.add(message ?? '');
  });
  tearDown(() {
    setDiagnosticSink(null);
    debugPrint = originalPrint;
  });

  Request request() => Request(
    operation: Operation(
      document: parseString('query ReadStatus { __typename }'),
    ),
    variables: {
      'mangaId': 42,
      'password': 'privatePassword',
      'input': {'chapterId': 7},
    },
  );

  test(
    'cancellation reaches the upstream subscription and is recorded',
    () async {
      var cancelled = false;
      final controller = StreamController<Response>(
        onCancel: () => cancelled = true,
      );
      final first = Completer<void>();
      final subscription = LoggerLink()
          .request(request(), (_) => controller.stream)
          .listen((_) => first.complete());
      controller.add(const Response(response: {}, data: {}));
      await first.future;
      await subscription.cancel();
      expect(cancelled, isTrue);
      expect(persisted.join(), contains('outcome=cancelled'));
      await controller.close();
    },
  );

  test(
    'GraphQL errors retain their response and log only the error outcome',
    () async {
      final response = Response(
        response: {},
        errors: [const GraphQLError(message: 'privateServerResponse')],
      );
      final result = await LoggerLink()
          .request(request(), (_) => Stream.value(response))
          .single;
      expect(identical(result, response), isTrue);
      expect(persisted.join(), contains('outcome=error'));
      expect(persisted.join(), isNot(contains('privateServerResponse')));
    },
  );

  test('info uses a release-capable filter and sanitizes both outputs', () {
    logger.i('request failed https://host?token=privateToken');
    expect(persisted.join(), contains('request failed'));
    expect(persisted.join(), isNot(contains('privateToken')));
    expect(console.join(), isNot(contains('privateToken')));
  });

  test(
    'GraphQL logs metadata and outcomes without variables or response bodies',
    () async {
      final response = Response(
        response: {},
        data: {'privateResponse': 'secretBody'},
      );
      final result = await LoggerLink()
          .request(request(), (_) => Stream.value(response))
          .single;
      expect(identical(result, response), isTrue);
      final text = persisted.join();
      expect(text, contains('ReadStatus'));
      expect(text, contains('mangaId=42'));
      expect(text, contains('chapterId=7'));
      expect(text, contains('elapsedMs='));
      expect(text, contains('outcome=success'));
      expect(text, isNot(contains('privatePassword')));
      expect(text, isNot(contains('secretBody')));
    },
  );

  test('transport errors still reach callers and record failure', () async {
    final error = StateError('transport failed');
    await expectLater(
      LoggerLink().request(request(), (_) => Stream.error(error)),
      emitsError(same(error)),
    );
    expect(persisted.join(), contains('outcome=error'));
  });

  test(
    'subscription payloads do not create per-message activity floods',
    () async {
      final controller = StreamController<Response>();
      final subscription = LoggerLink()
          .request(request(), (_) => controller.stream)
          .listen((_) {});
      for (var i = 0; i < 100; i++) {
        controller.add(Response(response: {}, data: {'value': i}));
      }
      await controller.close();
      await subscription.cancel();
      expect(persisted.length, lessThanOrEqualTo(3));
    },
  );
}
