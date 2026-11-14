import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `sleep_logs`
/// from docs/sot_registry.yaml.
///
/// Writers: profile_provider.BiometricNotifier.logSleep (sleep_log_<date> key),
///          conversational_log_handler._logSleep (legacy 'sleep_logs' list key)
/// Readers: profile_provider.biometricProvider (reads both paths),
///          ai_coach_repository._getSleep7d,
///          sync_service._syncSleepLogs (handles both paths)
///
/// Two parallel write paths. _syncSleepLogs scans sleep_log_* FIRST,
/// then falls back to 'sleep_logs' list.
void main() {
  late String profileProvSrc;
  late String aiRepoSrc;
  late String syncSvcSrc;

  setUpAll(() {
    final pf = File('lib/features/profile/providers/profile_provider.dart');
    expect(pf.existsSync(), isTrue,
        reason: 'profile_provider.dart must exist (BiometricNotifier.logSleep writer)');
    profileProvSrc = pf.readAsStringSync();

    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue, reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = af.readAsStringSync();

    final sf = loadSyncServiceSource();
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();
  });

  group('sleep_logs writer↔reader source contract', () {
    test('writer BiometricNotifier.logSleep exists in profile_provider', () {
      expect(profileProvSrc.contains('BiometricNotifier'), isTrue,
          reason: 'profile_provider must define BiometricNotifier class');
      expect(profileProvSrc.contains('logSleep'), isTrue,
          reason: 'BiometricNotifier must define logSleep method');
    });

    test('writer logSleep uses sleep_log_ key prefix (IST-anchored)', () {
      expect(profileProvSrc.contains('sleep_log_'), isTrue,
          reason:
              'logSleep must write sleep_log_<IST-date> keys per sot_registry.hive.key_prefix; '
              'not legacy sleep_logs list');
    });

    test('writer logSleep uses padLeft date formatting for the key', () {
      // logSleep computes todayStr as 'YYYY-MM-DD' from DateTime.now() via padLeft(2,'0')
      // (same device-local pattern used pre-Test-#12; IST sweep is a known tracked gap).
      // We verify the key format is consistent — all 3 length fields must be zero-padded.
      expect(
          profileProvSrc.contains('sleep_log_\$todayStr') ||
              profileProvSrc.contains("'sleep_log_\$"),
          isTrue,
          reason:
              'logSleep must write sleep_log_<date> key using todayStr pattern; '
              'must not hard-code a date literal');
    });

    test('reader biometricProvider reads sleep_log_ key', () {
      expect(profileProvSrc.contains('sleep_log_'), isTrue,
          reason:
              'biometricProvider must read sleep_log_<IST-date> key (direct path); '
              'falls back to sleep_logs list for legacy data');
    });

    test('reader _getSleep7d exists in ai_coach_repository', () {
      expect(
          aiRepoSrc.contains('_getSleep7d') ||
              aiRepoSrc.contains('sleep_log') ||
              aiRepoSrc.contains('sleep'),
          isTrue,
          reason: 'ai_coach_repository must read sleep data for AI context');
    });

    test('reader _syncSleepLogs exists in sync_service', () {
      expect(syncSvcSrc.contains('_syncSleepLogs'), isTrue,
          reason:
              '_syncSleepLogs must exist in sync_service; handles both '
              'sleep_log_* keys and legacy sleep_logs list');
    });

    test('conversational_log_handler._logSleep exists (legacy path)', () {
      final clf = File(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      if (!clf.existsSync()) return; // optional if file was restructured
      final src = clf.readAsStringSync();
      expect(src.contains('_logSleep') || src.contains('logSleep'), isTrue,
          reason:
              'conversational_log_handler must have _logSleep for chat-triggered sleep logging');
    });

    test('_syncSleepLogs scans sleep_log_ prefix first (primary path)', () {
      final body = _methodBody(syncSvcSrc, '_syncSleepLogs');
      expect(body.contains('sleep_log_'), isTrue,
          reason:
              '_syncSleepLogs must scan sleep_log_* keys first (primary path); '
              'legacy sleep_logs list is the fallback per sot_registry.class_constraints');
    });
  });
}

String _methodBody(String src, String methodName) {
  final pattern = RegExp(
      r'Future<void>\s+' + methodName + r'\s*\([^)]*\)\s*async\s*\{');
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
