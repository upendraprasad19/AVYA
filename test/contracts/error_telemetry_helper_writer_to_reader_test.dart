import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `error_telemetry_helper`
/// from docs/sot_registry.yaml.
///
/// Writer: error_telemetry.dart — ErrorTelemetry (whole class)
/// Readers: sync_service._reportSyncFailure (canonical funnel — all sync failures),
///          hive_user_session.dart (lifecycle events),
///          subscription_service.dart (refresh + verify events),
///          auth_provider.dart (auth lifecycle events)
///
/// _reportSyncFailure in SyncService is the canonical funnel for sync failures.
/// Do NOT call ErrorTelemetry.recordNonFatal directly from sync methods.
///
/// Forbidden: debugPrint.*error (use ErrorTelemetry._reportSyncFailure instead)
void main() {
  late String errorTelSrc;
  late String syncSvcSrc;
  late String hiveSessionSrc;
  late String subSvcSrc;
  late String authProvSrc;

  setUpAll(() {
    final ef = File('lib/core/services/error_telemetry.dart');
    expect(ef.existsSync(), isTrue,
        reason: 'error_telemetry.dart must exist');
    errorTelSrc = ef.readAsStringSync();

    final sf = loadSyncServiceSource();
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();

    final hvf = File('lib/core/services/hive_user_session.dart');
    expect(hvf.existsSync(), isTrue,
        reason: 'hive_user_session.dart must exist (lifecycle events reader)');
    hiveSessionSrc = hvf.readAsStringSync();

    final ssf = File('lib/core/services/subscription_service.dart');
    expect(ssf.existsSync(), isTrue, reason: 'subscription_service.dart must exist');
    subSvcSrc = ssf.readAsStringSync();

    final apf = File('lib/features/auth/providers/auth_provider.dart');
    expect(apf.existsSync(), isTrue, reason: 'auth_provider.dart must exist');
    authProvSrc = apf.readAsStringSync();
  });

  group('error_telemetry_helper writer↔reader source contract', () {
    test('writer ErrorTelemetry class exists with recordNonFatal + logEvent', () {
      expect(errorTelSrc.contains('class ErrorTelemetry'), isTrue,
          reason: 'ErrorTelemetry class must exist');
      expect(errorTelSrc.contains('recordNonFatal'), isTrue,
          reason: 'ErrorTelemetry must have recordNonFatal method');
      expect(errorTelSrc.contains('logEvent'), isTrue,
          reason: 'ErrorTelemetry must have logEvent method');
    });

    test('canonical funnel _reportSyncFailure exists in sync_service', () {
      expect(syncSvcSrc.contains('_reportSyncFailure'), isTrue,
          reason:
              'sync_service must define _reportSyncFailure — canonical funnel for all '
              'sync failures routing through ErrorTelemetry');
    });

    test('_reportSyncFailure calls ErrorTelemetry', () {
      final body = _methodBody(syncSvcSrc, '_reportSyncFailure');
      expect(
          body.contains('ErrorTelemetry') || body.contains('logEvent') ||
              body.contains('recordNonFatal'),
          isTrue,
          reason:
              '_reportSyncFailure must delegate to ErrorTelemetry for cloud visibility');
    });

    test('reader hive_user_session uses ErrorTelemetry for lifecycle events', () {
      expect(
          hiveSessionSrc.contains('ErrorTelemetry') ||
              hiveSessionSrc.contains('logEvent'),
          isTrue,
          reason:
              'hive_user_session must use ErrorTelemetry.logEvent for lifecycle '
              'events (open/close) per sot_registry.telemetry.success_op_types');
    });

    test('reader subscription_service uses ErrorTelemetry for refresh events', () {
      expect(
          subSvcSrc.contains('ErrorTelemetry') ||
              subSvcSrc.contains('logEvent'),
          isTrue,
          reason:
              'subscription_service must use ErrorTelemetry for refresh + verify '
              'events (subscription_refresh_success, subscription_verify_non_200)');
    });

    test('reader auth_provider uses ErrorTelemetry for auth lifecycle events', () {
      expect(
          authProvSrc.contains('ErrorTelemetry') ||
              authProvSrc.contains('logEvent'),
          isTrue,
          reason:
              'auth_provider must use ErrorTelemetry for auth lifecycle events '
              '(auth_signed_in, auth_signed_up, auth_signed_out, auth_user_ensured)');
    });

    test('ErrorTelemetry never throws — must be silent on failure', () {
      // All public methods must have internal try/catch
      expect(errorTelSrc.contains('try') && errorTelSrc.contains('catch'), isTrue,
          reason:
              'ErrorTelemetry must catch all exceptions internally; '
              'telemetry must never crash callers per sot_registry.class_constraints');
    });

    test('key success op_types are referenced somewhere in callers', () {
      final requiredOpTypes = [
        'auth_signed_in',
        'restore_started',
        'restore_completed',
      ];
      // At least one caller should reference each key op_type
      for (final opType in requiredOpTypes) {
        final appearsAnywhere = authProvSrc.contains(opType) ||
            syncSvcSrc.contains(opType) ||
            subSvcSrc.contains(opType) ||
            hiveSessionSrc.contains(opType);
        expect(appearsAnywhere, isTrue,
            reason:
                'op_type "$opType" must appear in at least one caller file '
                'per sot_registry.telemetry.success_op_types');
      }
    });
  });
}

String _methodBody(String src, String methodName) {
  // Find method regardless of return type (Future<void>, void, etc.)
  final pattern = RegExp(methodName + r'\s*\([^)]*\)\s*(?:async\s*)?\{');
  final match = pattern.firstMatch(src);
  if (match == null) return '';
  final start = match.end - 1;
  var depth = 1;
  var i = start + 1;
  while (i < src.length && depth > 0) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') depth--;
    i++;
  }
  return src.substring(start, i);
}
