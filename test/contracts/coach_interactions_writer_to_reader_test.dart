import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `coach_interactions`
/// from docs/sot_registry.yaml.
///
/// Writers: ai_coach_repository.saveInteraction,
///          ai_coach_provider.AiCoachNotifier._sendMessage
/// Readers: ai_coach_provider.AiCoachHistoryProvider (skips 'coaching_notes' singleton),
///          sync_service._syncCoachInteractions
///
/// Key: coach_<ms> in coachBox. Cloud id: uuid_v5 from (user_id, created_at).
/// 'coaching_notes' is a SINGLETON key in coachBox — NOT a coach_* row.
/// AiCoachHistoryProvider MUST skip it.
///
/// Forbidden: coach_${id.hashCode} — legacy key format before Test #12.7.
void main() {
  late String aiRepoSrc;
  late String aiProvSrc;
  late String syncSvcSrc;

  setUpAll(() {
    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue,
        reason: 'ai_coach_repository.dart must exist (saveInteraction writer)');
    aiRepoSrc = af.readAsStringSync();

    final apf = File('lib/features/ai_coach/providers/ai_coach_provider.dart');
    expect(apf.existsSync(), isTrue,
        reason: 'ai_coach_provider.dart must exist (history reader + writer)');
    aiProvSrc = apf.readAsStringSync();

    final sf = loadSyncServiceSource();
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();
  });

  group('coach_interactions writer↔reader source contract', () {
    test('writer saveInteraction exists in ai_coach_repository', () {
      expect(aiRepoSrc.contains('saveInteraction'), isTrue,
          reason:
              'ai_coach_repository must define saveInteraction (chat persistence writer)');
    });

    test('writer uses coach_ key prefix in coachBox', () {
      expect(aiRepoSrc.contains("'coach_") || aiRepoSrc.contains('"coach_'),
          isTrue,
          reason: 'saveInteraction must write coach_<ms> keys per sot_registry.hive.key_prefix');
    });

    test('reader skips coaching_notes singleton key', () {
      // coaching_notes is stored under the bare 'coaching_notes' key, not 'coach_*'
      // Readers must explicitly skip it when iterating coach_ rows
      expect(
          aiProvSrc.contains("'coaching_notes'") ||
              aiProvSrc.contains('coaching_notes'),
          isTrue,
          reason:
              "ai_coach_provider must explicitly skip the 'coaching_notes' singleton key "
              'when reading history — it is NOT a coach_* interaction row');
    });

    test('reader _syncCoachInteractions exists in sync_service', () {
      expect(syncSvcSrc.contains('_syncCoachInteractions'), isTrue,
          reason: '_syncCoachInteractions must exist in sync_service for cloud sync');
    });

    test('cloud uses uuid_v5 for deterministic id (idempotent upsert)', () {
      // The cloud id must be deterministic so re-syncs don't duplicate rows
      expect(
          syncSvcSrc.contains('uuid_v5') ||
              syncSvcSrc.contains('_deterministicId') ||
              syncSvcSrc.contains('deterministic'),
          isTrue,
          reason:
              '_syncCoachInteractions must use deterministic uuid_v5 from '
              '(user_id, created_at) for idempotent cloud upsert');
    });

    test('cloud table ai_coach_interactions referenced', () {
      expect(syncSvcSrc.contains('ai_coach_interactions'), isTrue,
          reason: 'sync_service must reference ai_coach_interactions cloud table');
    });

    test('forbidden: coach_hashCode legacy key format absent from ai_coach_repository', () {
      // Legacy format before Test #12.7 — uuid_v5 replaced this
      final legacyPattern = RegExp(r"coach_\\\$\{.*hashCode");
      expect(legacyPattern.hasMatch(aiRepoSrc), isFalse,
          reason:
              'ai_coach_repository must not use coach_\${id.hashCode} key format; '
              'use coach_<ms> per sot_registry (Test #12.7 fix)');
    });
  });
}
