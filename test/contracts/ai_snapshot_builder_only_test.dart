// Tech-debt audit 2026-05-20 finding A10 — behavioral contract for
// AiSnapshotBuilder.buildAiContext.
//
// Pre-A10 the buildAiContext entry lived inside AiCoachRepository
// alongside the chat persistence + identity-signal + coaching-notes
// surfaces — one 2127-line class. Test #8's "4 ai_coach_repository
// drift fixes" all landed there because every snapshot field flows
// through one builder. The A10 split moves buildAiContext into the
// dedicated AiSnapshotBuilder service so the writer/reader-drift blast
// radius is scoped to a single read-only surface.
//
// This test is BEHAVIORAL (per CLAUDE.md feedback_source_grep_
// false_confidence.md) — it spins up Hive on a temp dir, seeds a
// couple of canonical Hive shapes, and asserts the snapshot map has
// the expected top-level keys + a few key value pass-throughs. The
// snapshot contract gate (`scripts/check_snapshot_contract.dart` +
// `docs/snapshot_contract.yaml`) enforces full per-key coverage.
//
// Run: flutter test test/contracts/ai_snapshot_builder_only_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp =
        Directory.systemTemp.createTempSync('ai_snapshot_builder_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
    // Open shared/global boxes that the snapshot builder reads but
    // HiveUserSession does not manage (configBox lives outside the
    // user-scoped namespace per hive_user_session.dart:20).
    if (!Hive.isBoxOpen('configBox')) {
      await Hive.openBox('configBox');
    }
    await HiveService.instance.userBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.nutritionBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.customBox.clear();
    await HiveService.instance.configBox.clear();
  });

  group('AiSnapshotBuilder — behavioral contract', () {
    test('buildAiContext returns a map with all canonical top-level keys',
        () async {
      await HiveService.instance.userBox.put('profile', {
        'id': 'user-1',
        'full_name': 'Lt Cdr Test',
        'gender': 'male',
        'height_cm': 175,
        'current_weight_kg': 80,
        'target_weight_kg': 75,
        'primary_goal': 'muscle_gain',
        'fitness_experience': 'intermediate',
        'days_per_week': 4,
        'tdee': 2400,
        'bmr': 1700,
      });
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 1,
        'current_week': 1,
        'total_workouts_done': 0,
        'current_streak_weeks': 0,
      });

      final ctx = AiSnapshotBuilder.instance.buildAiContext();

      // A handful of must-have top-level keys per docs/snapshot_contract.yaml
      // — the full per-key gate runs in scripts/check_snapshot_contract.dart.
      const expectedTopLevel = [
        'is_first_ever_message',
        'profile',
        'progress',
        'current_streak_weeks',
        'today_nutrition',
        'this_week_workouts',
        'today_steps',
        'step_history_7d',
        'latest_weight',
        'personal_records',
        'coaching_notes',
        'meals_today',
        'nutrition_trend_7d',
        'today_workout',
        'yesterday_workout',
        'week_lookahead',
        'current_plan_summary',
        'sleep_7d',
        'water_7d',
        'subscription',
        'current_rank',
        'next_rank',
        'cadence',
        'pr_timeline_summary',
        'recent_meal_deletes',
      ];
      for (final k in expectedTopLevel) {
        expect(ctx.containsKey(k), isTrue,
            reason: 'snapshot must include top-level key "$k" — '
                'docs/snapshot_contract.yaml claims it');
      }
    });

    test('profile sub-map pass-through reflects userBox shape', () async {
      await HiveService.instance.userBox.put('profile', {
        'id': 'user-2',
        'full_name': 'A',
        'gender': 'female',
        'height_cm': 162,
        'current_weight_kg': 60,
        'target_weight_kg': 55,
        'primary_goal': 'fat_loss',
        'fitness_experience': 'beginner',
        'tdee': 1900,
        'bmr': 1400,
      });

      final ctx = AiSnapshotBuilder.instance.buildAiContext();
      final profile = ctx['profile'] as Map<String, dynamic>;
      expect(profile['name'], 'A');
      expect(profile['gender'], 'female');
      expect(profile['height_cm'], 162);
      expect(profile['primary_goal'], 'fat_loss');
      expect(profile['bmr'], 1400);
      expect(profile['tdee'], 1900);
    });

    test('is_first_ever_message reflects coachBox emptiness', () async {
      // No coach_* rows → first-ever.
      final ctx1 = AiSnapshotBuilder.instance.buildAiContext();
      expect(ctx1['is_first_ever_message'], isTrue);

      // After one coach row exists with a user_message → no longer first-ever.
      await HiveService.instance.coachBox.put('coach_1', {
        'id': 'coach_1',
        'user_message': 'hi',
        'ai_response': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      });
      final ctx2 = AiSnapshotBuilder.instance.buildAiContext();
      expect(ctx2['is_first_ever_message'], isFalse);
    });

    test('enrichContextForQuery is a non-destructive pass-through', () {
      final base = <String, dynamic>{'profile': {}, 'progress': {}};
      final enriched =
          AiSnapshotBuilder.instance.enrichContextForQuery('how am I doing', base);
      // Enrichment must return a usable map (may be the same map).
      expect(enriched, isA<Map<String, dynamic>>());
      // The base keys survive.
      expect(enriched.containsKey('profile'), isTrue);
      expect(enriched.containsKey('progress'), isTrue);
    });
  });
}
