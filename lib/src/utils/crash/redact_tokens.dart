// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Auth query parameters must never appear in copyable logs.
final _sensitiveParam = RegExp(
  '([?&](?:token|access_?token|refresh_?token|api_?key|password|client_secret|auth)=)[^&;\\s"\']+',
  caseSensitive: false,
);

final _headers = RegExp(
  r'((?:authorization|proxy-authorization|cookie|set-cookie)\s*[:=]\s*)[^\r\n]+',
  caseSensitive: false,
);
final _assignments = RegExp(
  r'''(["']?(?:password|passwd|access_?token|refresh_?token|token|api_?key|client_secret)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;&}\]\r\n]+)''',
  caseSensitive: false,
);
final _auth = RegExp(r'\b(Bearer|Basic)\s+[^\s,;"\x27]+', caseSensitive: false);
final _userinfo = RegExp(r'(https?://)[^/\s@]+@', caseSensitive: false);

/// Remove credentials before either persistence or console output.
String redactTokens(String input) {
  var result = input.replaceAllMapped(_userinfo, (m) => '${m[1]}<redacted>@');
  for (final pattern in [_sensitiveParam, _assignments, _headers, _auth]) {
    result = result.replaceAllMapped(pattern, (m) => '${m[1]}<redacted>');
  }
  return result;
}
