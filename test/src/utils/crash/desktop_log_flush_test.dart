import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry_listener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'desktop close drains diagnostics before destroying the window',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final flushing = Completer<void>();
      final started = Completer<void>();
      final calls = <String>[];
      setDiagnosticSink(
        (line) => calls.add(line),
        flush: () {
          started.complete();
          return flushing.future;
        },
      );
      const channel = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'isMaximized') return false;
            if (call.method == 'getSize') {
              return {'width': 800.0, 'height': 600.0};
            }
            return null;
          });
      addTearDown(() {
        setDiagnosticSink(null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final closing = WindowGeometryListener(preferences).onWindowClose();
      await started.future.timeout(const Duration(seconds: 1));
      expect(calls, isNot(contains('destroy')));
      flushing.complete();
      await closing;
      expect(calls, contains('destroy'));
      expect(
        calls.where((call) => call.contains('window_close')),
        hasLength(1),
      );
      setDiagnosticSink((_) {}, flush: () async => throw StateError('disk unavailable'));
      await WindowGeometryListener(preferences).onWindowClose();
      expect(calls.where((call) => call == 'destroy'), hasLength(2));
    },
  );
}
