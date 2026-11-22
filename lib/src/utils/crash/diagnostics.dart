// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'redact_tokens.dart';

/// Shared crash-log sink; callers cannot await the log path resolved at startup.
typedef DiagnosticSink = void Function(String line);

DiagnosticSink? _sink;
Future<void> Function()? _flush;

void setDiagnosticSink(DiagnosticSink? sink, {Future<void> Function()? flush}) {
  _sink = sink;
  _flush = flush;
}

Future<void> flushDiagnostics() async {
  try {
    await _flush?.call();
  } catch (_) {
    // A failed log flush must not prevent normal application shutdown.
  }
}

void recordDiagnostic(String line) {
  try {
    _sink?.call(redactTokens(line));
  } catch (_) {
    // Diagnostics must never interrupt the operation being logged.
  }
}
