import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// APK Test #12.9 — pin `error_telemetry.dart` payload shape against the
/// `log-client-error` Edge Function contract.
///
/// Pre-Test-#12.9 the Flutter helper sent `{error_type, message, source}`
/// while the function required `{error_code, op_type, error_message,
/// client_version, platform}`. Every Agent-B `logEvent` call from APK 12.6
/// onward was rejected with HTTP 400 ("Missing error_code") — telemetry
/// blackout despite the validator widening shipped in Test #12.4.
///
/// Source-grep contract: cheap, durable, catches the regression class
/// without spinning up the runtime.
void main() {
  final file = File('lib/core/services/error_telemetry.dart');
  late final String source;

  setUpAll(() {
    expect(file.existsSync(), isTrue,
        reason: 'error_telemetry.dart must exist at lib/core/services/');
    source = file.readAsStringSync();
  });

  group('error_telemetry.dart payload shape', () {
    test('sends error_code (NOT error_type) — log-client-error required field',
        () {
      expect(source.contains("'error_code'"), isTrue,
          reason:
              'Must send error_code; log-client-error returns 400 "Missing error_code" otherwise');
      expect(source.contains("'error_type'"), isFalse,
          reason:
              'Legacy field name — function does not read this; rename to error_code');
    });

    test('sends op_type (NOT source)', () {
      expect(source.contains("'op_type'"), isTrue,
          reason: 'Must send op_type for client_errors.op_type column');
      expect(source.contains("'source'"), isFalse,
          reason: 'Legacy field name — function does not read this');
    });

    test('sends error_message (NOT bare message)', () {
      // `'message'` may legitimately appear inside other contexts; we
      // require explicit error_message key in the JSON payload.
      expect(source.contains("'error_message'"), isTrue,
          reason: 'Must send error_message for client_errors.error_message');
    });

    test('sends client_version + platform — required by validator', () {
      expect(source.contains("'client_version'"), isTrue,
          reason:
              'log-client-error returns 400 "Invalid client_version" if missing');
      expect(source.contains("'platform'"), isTrue,
          reason: 'log-client-error returns 400 "Invalid platform" if missing');
    });

    test('sends retry_count (defaultable to 0 for ad-hoc events)', () {
      expect(source.contains("'retry_count'"), isTrue,
          reason: 'Validator: retry_count must be 0..1000');
    });

    test('platform helper covers android/ios/web', () {
      expect(source.contains("Platform.isAndroid"), isTrue);
      expect(source.contains("Platform.isIOS"), isTrue);
      expect(source.contains("kIsWeb"), isTrue);
    });
  });
}
