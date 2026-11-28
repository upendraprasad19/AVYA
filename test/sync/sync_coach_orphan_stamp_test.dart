// OI-204 write-amplification fix (day-swapper + sync-load Task 19, spec §5.9
// "Coach"): `_syncCoachInteractions`'s orphan branch (sync_coach.dart:196-209)
// upserted a deterministic cloud id but never wrote it back into the Hive
// row, so the SAME entry re-upserted the SAME row every sync pass forever
// (the entry's rawId stayed non-UUID, so the guard at :148-150 never caught
// it). The fix stamps the cloud id back, exactly like the dedup-hit branch
// eight lines above already does (:186-191).
//
// Also pins the §5.12 fix: the orphan's `created_at` fallback derives from
// the `coach_<ms>` Hive key instead of `DateTime.now()` — the key IS the
// creation timestamp (coach_interaction_repository.dart:70-77 mints it), so
// deriving from it is the recorded value, not a guess.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<void> seedOrphan(String key, Map<String, dynamic> entry) =>
      HiveService.instance.coachBox.put(key, entry);

  test(
      'a confirmed orphan upsert stamps the cloud id back onto the Hive row, '
      'so the next pass sends nothing (closes OI-204 write amplification)',
      () async {
    h.server.getResponders['ai_coach_interactions'] = (_) => [];
    await seedOrphan('coach_1758901234567', {
      'user_message': 'how many sets today',
      'ai_response': 'three',
      'model_used': 'gemini-2.5-flash',
    });

    await SyncService.instance.pushCoachInteractionsForSyncDomain();
    expect(h.server.writesTo('ai_coach_interactions'), hasLength(1));
    expectWritesMatchLiveSchema(h.server);

    final stamped =
        HiveService.instance.coachBox.get('coach_1758901234567') as Map;
    expect((stamped['id'] as String?), isNotEmpty,
        reason: 'the cloud id must be written back, exactly like the '
            'dedup-hit branch already does at sync_coach.dart:186-191');

    h.server.clear();
    await SyncService.instance.pushCoachInteractionsForSyncDomain();
    expect(h.server.writesTo('ai_coach_interactions'), isEmpty,
        reason: 'a stamped row is now caught by the existing rawId UUID '
            'guard (sync_coach.dart:148-150) — it must not re-upsert forever');
  });

  test('the orphan created_at derives from the coach_<ms> key, never "now"',
      () async {
    h.server.clear(); // shared server across tests in this file.
    h.server.getResponders['ai_coach_interactions'] = (_) => [];
    // No 'created_at' field at all — the key is the only source.
    await seedOrphan('coach_1758901234567', {
      'user_message': 'log my run',
      'ai_response': 'logged',
      'model_used': 'gemini-2.5-flash',
    });
    await SyncService.instance.pushCoachInteractionsForSyncDomain();
    final write = h.server.writesTo('ai_coach_interactions').single;
    expect(
      write.rows.single['created_at'],
      DateTime.fromMillisecondsSinceEpoch(1758901234567, isUtc: true)
          .toIso8601String(),
    );
  });

  test(
      'omits created_at entirely when the key has no parseable ms and the '
      'entry has none either (never fabricates "now")', () async {
    h.server.clear(); // shared server across tests in this file.
    h.server.getResponders['ai_coach_interactions'] = (_) => [];
    await seedOrphan('coach_not_a_number', {
      'user_message': 'x',
      'ai_response': 'y',
      'model_used': 'z',
    });
    await SyncService.instance.pushCoachInteractionsForSyncDomain();
    final write = h.server.writesTo('ai_coach_interactions').single;
    expect(write.rows.single.containsKey('created_at'), isFalse);
  });
}
