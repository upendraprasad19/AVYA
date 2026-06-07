import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `weight_logs`
/// from docs/sot_registry.yaml.
///
/// CANONICAL WRITER: health_write_service.HealthWriteService.logWeight
///   builds the `weight_<IST-date>` key, stamps type='weight_log', and fires
///   syncWeightNow() fire-and-forget. (home_provider.WeightLogNotifier.logWeight
///   is a PASS-THROUGH delegate that just calls
///   HealthWriteService.instance.logWeight — it is NOT the real writer.)
/// Also-writer: health_sync_service (Health Connect import).
/// Readers: home_provider.weightHistoryProvider (filters type=='weight_log'),
///          ai_coach_repository.buildAiContext (weight_trend),
///          weekly_report_data_provider (weight series, forward-filled).
///
/// Key: `weight_<IST-date>`, type='weight_log'.
/// Weekly report weight series is FORWARD-FILLED (not zero-filled).
///
/// F5 (2026-06-07): WRITER assertions retargeted from home_provider (a
/// delegating wrapper) to health_write_service (the canonical writer). The
/// home_provider grep was passing on the pass-through wrapper, which would NOT
/// fail if the real key/type/sync logic in HealthWriteService drifted.

/// Strip Dart line + block comments so a contract token mentioned only in a
/// comment can't satisfy a `.contains` assertion (feedback_source_grep_strip_
/// comments_first.md).
String _stripComments(String src) {
  // Remove /* ... */ block comments (non-greedy, across newlines).
  var out = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  // Remove // ... line comments.
  out = out.replaceAll(RegExp(r'//[^\n]*'), '');
  return out;
}

void main() {
  late String healthWriteSrc;
  late String homeProvSrc;
  late String aiRepoSrc;
  late String weeklyProvSrc;

  setUpAll(() {
    final hw = File('lib/core/services/health_write_service.dart');
    expect(hw.existsSync(), isTrue,
        reason: 'health_write_service.dart must exist (canonical weight writer)');
    healthWriteSrc = _stripComments(hw.readAsStringSync());

    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue,
        reason: 'home_provider.dart must exist (weightHistoryProvider reader)');
    homeProvSrc = _stripComments(hf.readAsStringSync());

    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue, reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = _stripComments(af.readAsStringSync());

    final wf = File(
        'lib/features/profile/providers/weekly_report_data_provider.dart');
    expect(wf.existsSync(), isTrue,
        reason: 'weekly_report_data_provider.dart must exist');
    weeklyProvSrc = _stripComments(wf.readAsStringSync());
  });

  group('weight_logs writer↔reader source contract', () {
    // ── WRITER: health_write_service (canonical) ──────────────────
    test('canonical writer HealthWriteService.logWeight exists', () {
      expect(healthWriteSrc.contains('logWeight'), isTrue,
          reason: 'HealthWriteService must define logWeight — the canonical '
              'weight_<IST-date> writer');
    });

    test('writer builds the weight_ key prefix in healthBox', () {
      expect(
          healthWriteSrc.contains("'weight_") ||
              healthWriteSrc.contains('"weight_'),
          isTrue,
          reason: 'logWeight must build weight_<IST-date> keys for healthBox');
    });

    test('writer stamps type=weight_log on the entry', () {
      expect(healthWriteSrc.contains("'weight_log'"), isTrue,
          reason:
              'logWeight must stamp type=weight_log so readers can filter by '
              'type; prevents steps/sleep entries appearing as weight data');
    });

    test('writer fires syncWeightNow() fire-and-forget after the Hive write',
        () {
      expect(healthWriteSrc.contains('syncWeightNow'), isTrue,
          reason:
              'logWeight must fire syncWeightNow() fire-and-forget after the '
              'Hive write per CLAUDE.md §15 (Hive-first, cloud async)');
    });

    // ── READER: home_provider weightHistoryProvider ───────────────
    test('reader weightHistoryProvider exists in home_provider', () {
      expect(homeProvSrc.contains('weightHistoryProvider'), isTrue,
          reason:
              'home_provider must define weightHistoryProvider — the '
              'sparkline/trend reader');
    });

    test('reader filters by type==weight_log', () {
      expect(homeProvSrc.contains("'weight_log'"), isTrue,
          reason:
              'home_provider weightHistoryProvider must filter by '
              'type==weight_log to avoid mixing sleep/step entries into the '
              'weight history');
    });

    test('reader buildAiContext includes weight_trend data', () {
      expect(aiRepoSrc.contains('weight_trend') || aiRepoSrc.contains('weight_'),
          isTrue,
          reason:
              'AiCoachRepository.buildAiContext must include weight data '
              '(weight_trend)');
    });

    test('weekly report forward-fills weight (not zero-fills)', () {
      // Forward-fill is the key constraint — no zero on un-weighed days.
      expect(
          weeklyProvSrc.contains('forward') ||
              weeklyProvSrc.contains('fill') ||
              weeklyProvSrc.contains('lastKnown') ||
              weeklyProvSrc.contains('prev'),
          isTrue,
          reason:
              'weekly_report_data_provider must forward-fill weight series; '
              'zero-fill would misleadingly show "0 kg" on un-weighed days');
    });
  });
}
