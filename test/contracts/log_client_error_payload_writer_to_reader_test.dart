import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `log_client_error_payload`
/// from docs/sot_registry.yaml.
///
/// Writer: error_telemetry.dart — ErrorTelemetry.recordNonFatal + logEvent
/// Reader: supabase/functions/log-client-error/index.ts (validates + inserts)
///
/// Required payload: error_code, op_type, error_message, platform, client_version.
/// The client_errors table was empty for the first 4 APK tests due to a payload
/// mismatch (Test #12.6 fix).
///
/// Note: error_telemetry_payload_contract_test.dart covers the payload shape.
/// This test covers the writer↔reader existence contract and key field names.
void main() {
  late String errorTelSrc;
  late String edgeFnSrc;

  setUpAll(() {
    final ef = File('lib/core/services/error_telemetry.dart');
    expect(ef.existsSync(), isTrue,
        reason: 'error_telemetry.dart must exist (writer for log_client_error_payload)');
    errorTelSrc = ef.readAsStringSync();

    final edgef =
        File('supabase/functions/log-client-error/index.ts');
    expect(edgef.existsSync(), isTrue,
        reason:
            'supabase/functions/log-client-error/index.ts must exist '
            '(reader/validator for log_client_error_payload)');
    edgeFnSrc = edgef.readAsStringSync();
  });

  group('log_client_error_payload writer↔reader source contract', () {
    test('writer ErrorTelemetry class exists', () {
      expect(errorTelSrc.contains('class ErrorTelemetry'), isTrue,
          reason: 'error_telemetry.dart must define ErrorTelemetry class');
    });

    test('writer recordNonFatal exists', () {
      expect(errorTelSrc.contains('recordNonFatal'), isTrue,
          reason: 'ErrorTelemetry must define recordNonFatal method');
    });

    test('writer logEvent exists', () {
      expect(errorTelSrc.contains('logEvent'), isTrue,
          reason: 'ErrorTelemetry must define logEvent method');
    });

    test('writer sends error_code (required by Edge Function)', () {
      expect(errorTelSrc.contains("'error_code'"), isTrue,
          reason:
              'ErrorTelemetry must send error_code field; '
              'log-client-error returns 400 "Missing error_code" otherwise (Test #12.9 telemetry blackout)');
    });

    test('writer sends op_type', () {
      expect(errorTelSrc.contains("'op_type'"), isTrue,
          reason: 'ErrorTelemetry must send op_type for client_errors.op_type column');
    });

    test('writer sends error_message', () {
      expect(errorTelSrc.contains("'error_message'"), isTrue,
          reason: 'ErrorTelemetry must send error_message field');
    });

    test('writer sends platform', () {
      expect(errorTelSrc.contains("'platform'"), isTrue,
          reason: 'ErrorTelemetry must send platform for client_errors.platform column');
    });

    test('writer sends client_version', () {
      expect(errorTelSrc.contains("'client_version'"), isTrue,
          reason: 'ErrorTelemetry must send client_version for validator');
    });

    test('reader Edge Function validates and inserts to client_errors', () {
      expect(edgeFnSrc.contains('client_errors'), isTrue,
          reason:
              'log-client-error Edge Function must insert to client_errors table');
    });

    test('reader Edge Function references required fields', () {
      expect(
          edgeFnSrc.contains('error_code') || edgeFnSrc.contains('op_type'),
          isTrue,
          reason:
              'log-client-error Edge Function must validate error_code / op_type fields');
    });

    test('writer never throws (silent telemetry)', () {
      // ErrorTelemetry must be wrapped in try/catch — telemetry must not crash callers
      expect(errorTelSrc.contains('try') && errorTelSrc.contains('catch'), isTrue,
          reason:
              'ErrorTelemetry must catch all exceptions internally; '
              'telemetry must be silent on failure per sot_registry.class_constraints');
    });
  });
}
