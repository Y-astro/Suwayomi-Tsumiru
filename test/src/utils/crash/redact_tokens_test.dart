import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/crash/redact_tokens.dart';

void main() {
  test('removes query credentials, headers, assignments, and URL userinfo', () {
    const secrets = [
      'querySecret',
      'bearerSecret',
      'cookieSecret',
      'jsonSecret',
      'basicSecret',
      'urlSecret',
      'apiSecret',
    ];
    final output = redactTokens('''
GET https://name:urlSecret@host/path?access_token=querySecret&page=2
Authorization: Bearer bearerSecret
Cookie: session=cookieSecret; other=1
{"password": "jsonSecret", "api_key": "apiSecret"}
failed with Basic basicSecret
''');
    for (final secret in secrets) {
      expect(output, isNot(contains(secret)));
    }
    expect(output, contains('page=2'));
    expect(output, contains('host/path'));
    expect(output, contains('<redacted>'));
  });

  test('preserves ordinary operation metadata and is idempotent', () {
    const text = 'operation=UpdateChapter mangaId=42 elapsedMs=12 success=true';
    expect(redactTokens(text), text);
    final redacted = redactTokens('https://host?token=secret&chapterId=7');
    expect(redactTokens(redacted), redacted);
    expect(redacted, contains('chapterId=7'));
  });
}
