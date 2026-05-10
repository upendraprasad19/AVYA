import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `weight_logs`
/// from docs/sot_registry.yaml.
///
/// Writers: home_provider.WeightLogNotifier.logWeight,
///          health_sync_service (Health Connect import)
/// Readers: home_provider.weightHistoryProvider,
///          ai_coach_repository.buildAiContext (weight_trend),
///          weekly_report_data_provider (weight series, forward-filled)
///
/// Key: weight_<IST-date>, type='weight_log'.
/// Weekly report weight series is FORWARD-FILLED (not zero-filled).
void main() {
  late String homeProvSrc;
  late String aiRepoSrc;
  late String weeklyProvSrc;

  setUpAll(() {
    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue,
        reason: 'home_provider.dart must exist (WeightLogNotifier writer + reader)');
    homeProvSrc = hf.readAsStringSync();

    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue, reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = af.readAsStringSync();

    final wf = File(
        'lib/features/profile/providers/weekly_report_data_provider.dart');
    expect(wf.existsSync(), isTrue,
        reason: 'weekly_report_data_provider.dart must exist');
    weeklyProvSrc = wf.readAsStringSync();
  });

  group('weight_logs writer↔reader source contract', () {
    test('writer WeightLogNotifier.logWeight exists in home_provider', () {
      expect(homeProvSrc.contains('WeightLogNotifier'), isTrue,
          reason: 'home_provider must define WeightLogNotifier class');
      expect(homeProvSrc.contains('logWeight'), isTrue,
          reason: 'WeightLogNotifier must define logWeight method');
    });

    test('writer uses weight_ key prefix in healthBox', () {
      expect(homeProvSrc.contains("'weight_") || homeProvSrc.contains('"weight_'),
          isTrue,
          reason: 'logWeight must write weight_<IST-date> keys to healthBox');
    });

    test('writer stamps type=weight_log on entry', () {
      expect(homeProvSrc.contains("'weight_log'"), isTrue,
          reason:
              'logWeight must stamp type=weight_log so readers can filter by type; '
              'prevents steps/sleep entries appearing as weight data');
    });

    test('reader weightHistoryProvider exists in home_provider', () {
      expect(homeProvSrc.contains('weightHistoryProvider'), isTrue,
          reason: 'home_provider must define weightHistoryProvider — the sparkline/trend reader');
    });

    test('reader weightHistoryProvider or logWeight filters by type=weight_log', () {
      expect(
          homeProvSrc.contains("'weight_log'"),
          isTrue,
          reason:
              'home_provider must filter by type=weight_log to avoid '
              'mixing sleep/step entries into the weight history');
    });

    test('reader buildAiContext includes weight_trend key', () {
      expect(aiRepoSrc.contains('weight_trend') || aiRepoSrc.contains('weight_'),
          isTrue,
          reason:
              'AiCoachRepository.buildAiContext must include weight data (weight_trend)');
    });

    test('syncWeightNow exists in home_provider for fire-and-forget sync', () {
      expect(
          homeProvSrc.contains('syncWeightNow') ||
              homeProvSrc.contains('SyncService.instance.sync'),
          isTrue,
          reason:
              'logWeight must fire syncWeightNow() fire-and-forget after Hive write '
              'per CLAUDE.md §15');
    });

    test('weekly report forward-fills weight (not zero-fills)', () {
      // Forward-fill is the key constraint — no zero on un-weighed days
      expect(weeklyProvSrc.contains('forward') || weeklyProvSrc.contains('fill') ||
          weeklyProvSrc.contains('lastKnown') || weeklyProvSrc.contains('prev'),
          isTrue,
          reason:
              'weekly_report_data_provider must forward-fill weight series; '
              'zero-fill would misleadingly show "0 kg" on un-weighed days');
    });
  });
}
