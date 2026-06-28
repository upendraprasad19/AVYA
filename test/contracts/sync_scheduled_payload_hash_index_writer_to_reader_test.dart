// H1b Part A — behavioral contract for the scheduled_workouts dirty-filter.
//
// The returning-login cost tax was ~96 `upsert_scheduled_workout` calls re-
// pushing a plan the cloud already held. `_syncScheduledWorkouts` now skips an
// unchanged PLANNED row whose payload fingerprint matches the last CONFIRMED
// push (index `sync_sched_payload_hash_index` in user-scoped workoutBox).
//
// The skip decision, fingerprint, and prune are pure statics on SyncService so
// the load-bearing semantics are behaviorally testable without a live backend
// (the method itself is private + Supabase-coupled). This FAILS if:
//   - A `completed` row is ever skipped (A-fix-1 P0 — cloud can be silently
//     stale per d9b2c5 and the resync migrator's one-shot flag makes a mis-skip
//     PERMANENT).
//   - An unchanged planned row stops skipping (the cost win) OR a changed row
//     skips (correctness).
//   - A null stored fingerprint skips (store-on-200-only — a failed push must
//     re-push next pass).
//   - The fingerprint stops being sensitive to a pushed field.
//   - Prune stops dropping a deleted date (A-fix-2).
//
// See docs/diagnoses/2026-06-27-sched-dirty-filter-b4f7e2.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  // Mirrors `_syncScheduledWorkouts`' `payload(tmplId)` builder: template_id is
  // OMITTED when null (not null-valued), matching the `if (tmplId != null)` map
  // spread in the production code.
  Map<String, dynamic> basePayload({
    String userId = 'user-1',
    String? templateId = 'tmpl-cloud-1',
    String date = '2026-06-20',
    Object? week = 2,
    Object? day = 6,
    String status = 'planned',
    String? completedAt,
  }) =>
      <String, dynamic>{
        'user_id': userId,
        if (templateId != null) 'template_id': templateId,
        'scheduled_date': date,
        'week_number': week,
        'day_of_week': day,
        'status': status,
        'completed_at': completedAt,
      };

  group('schedPayloadFingerprint — stable + field-sensitive', () {
    test('same payload → same fingerprint (deterministic / cross-VM stable)',
        () {
      final a = SyncService.schedPayloadFingerprint(basePayload());
      final b = SyncService.schedPayloadFingerprint(basePayload());
      expect(a, b);
      // 36-char UUID-v5 shape proves the deterministic (sha1) path — NOT a
      // VM-unstable String.hashCode (H-15).
      expect(a.length, 36);
    });

    test('every pushed field flips the fingerprint', () {
      final base = SyncService.schedPayloadFingerprint(basePayload());
      final variants = <String, String>{
        'user_id':
            SyncService.schedPayloadFingerprint(basePayload(userId: 'user-2')),
        'template_id': SyncService.schedPayloadFingerprint(
            basePayload(templateId: 'tmpl-cloud-2')),
        'template_absent':
            SyncService.schedPayloadFingerprint(basePayload(templateId: null)),
        'scheduled_date':
            SyncService.schedPayloadFingerprint(basePayload(date: '2026-06-21')),
        'week': SyncService.schedPayloadFingerprint(basePayload(week: 3)),
        'day': SyncService.schedPayloadFingerprint(basePayload(day: 7)),
        'status': SyncService.schedPayloadFingerprint(
            basePayload(status: 'completed')),
        'completed_at': SyncService.schedPayloadFingerprint(
            basePayload(completedAt: '2026-06-20T08:00:00.000')),
      };
      variants.forEach((field, fp) {
        expect(fp, isNot(base),
            reason: 'changing $field must flip the fingerprint → re-push');
      });
    });

    test('null template_id (orphan-fallback) differs from a resolved template',
        () {
      final orphan =
          SyncService.schedPayloadFingerprint(basePayload(templateId: null));
      final resolved = SyncService.schedPayloadFingerprint(
          basePayload(templateId: 'tmpl-cloud-1'));
      expect(orphan, isNot(resolved),
          reason: 'a later FK-resolve must re-push WITH the template');
    });
  });

  group('schedShouldSkipUpsert — A-fix-1 + skip/re-push semantics', () {
    final fp = SyncService.schedPayloadFingerprint(basePayload());

    test('A-fix-1 (P0): a completed row is NEVER skipped, even on a match', () {
      expect(
        SyncService.schedShouldSkipUpsert(
          killSwitchDisabled: false,
          status: 'completed',
          storedFingerprint: fp,
          currentFingerprint: fp,
        ),
        isFalse,
        reason:
            'completed rows must always re-push — cloud can be silently stale '
            '(d9b2c5) and a mis-skip is made PERMANENT by the resync migrator',
      );
    });

    test('planned + matching fingerprint → skip (the cost win)', () {
      expect(
        SyncService.schedShouldSkipUpsert(
          killSwitchDisabled: false,
          status: 'planned',
          storedFingerprint: fp,
          currentFingerprint: fp,
        ),
        isTrue,
      );
    });

    test('planned + changed fingerprint → re-push', () {
      expect(
        SyncService.schedShouldSkipUpsert(
          killSwitchDisabled: false,
          status: 'planned',
          storedFingerprint: 'stale-fp',
          currentFingerprint: fp,
        ),
        isFalse,
      );
    });

    test(
        'store-on-200-only: null stored fingerprint (never pushed / push threw) '
        '→ re-push', () {
      expect(
        SyncService.schedShouldSkipUpsert(
          killSwitchDisabled: false,
          status: 'planned',
          storedFingerprint: null,
          currentFingerprint: fp,
        ),
        isFalse,
        reason: 'a failed push leaves no entry → must re-push next pass',
      );
    });

    test('kill-switch disabled → never skip (verbatim pre-H1b sweep)', () {
      expect(
        SyncService.schedShouldSkipUpsert(
          killSwitchDisabled: true,
          status: 'planned',
          storedFingerprint: fp,
          currentFingerprint: fp,
        ),
        isFalse,
      );
    });
  });

  group('schedPrunedHashIndex — A-fix-2 delete handling', () {
    test('drops dates whose schedule row is gone, keeps live dates', () {
      final index = {
        '2026-06-20': 'fp-a',
        '2026-06-21': 'fp-b',
        '2026-06-22': 'fp-c',
      };
      final live = {'2026-06-20', '2026-06-22'};
      final pruned = SyncService.schedPrunedHashIndex(index, live);
      expect(pruned.keys.toSet(), {'2026-06-20', '2026-06-22'});
      expect(pruned['2026-06-21'], isNull,
          reason: 'deleted date dropped → a re-create re-pushes');
      expect(pruned['2026-06-20'], 'fp-a',
          reason: 'live entries survive with their fingerprint intact');
    });

    test('empty liveDates → empty index (all rows deleted)', () {
      final pruned = SyncService.schedPrunedHashIndex({'d': 'fp'}, <String>{});
      expect(pruned, isEmpty);
    });
  });

  group('source guards — store-on-200 placement + resetJourney clear', () {
    test('A-fix-3: resetJourney clears the fingerprint index key', () {
      final src =
          File('lib/features/dev/simulation_service.dart').readAsStringSync();
      expect(src.contains('sync_sched_payload_hash_index'), isTrue,
          reason:
              'sim reset must wipe the index or a survivor mis-skips the re-drive');
    });

    test('store-on-200-only: exactly 3 fingerprint writes (the 3 success points)',
        () {
      final src = File('lib/core/services/sync/sync_workout.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
      final writes =
          RegExp(r'schedHashIndex\[date\]\s*=\s*schedFp').allMatches(src).length;
      expect(writes, 3,
          reason:
              'the fingerprint must be stored ONLY after a confirmed 200 at the '
              '3 success points (plain / 23503-recovery / null-fallback)');
    });
  });

  // B-pass P1 — a real Hive put→get round-trip of the index map, not just the
  // pure statics. Catches a break in the runtime read-path (the dynamic-typed
  // Map reconstruction the loop head does) that the static tests would miss.
  group('Hive round-trip — fingerprint index survives put/get + drives the skip',
      () {
    late Directory tempDir;
    late Box box;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sched_fp_idx');
      Hive.init(tempDir.path);
      box = await Hive.openBox('rt_workout');
    });

    tearDown(() async {
      await box.close();
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('index map {date: fingerprint} round-trips and feeds schedShouldSkipUpsert',
        () async {
      const key = 'sync_sched_payload_hash_index';
      final fp = SyncService.schedPayloadFingerprint(basePayload());

      // Writer: store the index map exactly as _syncScheduledWorkouts does.
      await box.put(key, <String, String>{'2026-06-20': fp});

      // Reader: read back + reconstruct Map<String,String> (Hive returns a
      // dynamic-typed Map; this mirrors the method's load at the loop head).
      final raw = box.get(key);
      expect(raw, isA<Map>(),
          reason: 'index persists as a Map under the reserved key');
      final index = <String, String>{};
      (raw as Map).forEach((k, v) {
        if (k is String && v is String) index[k] = v;
      });

      expect(index['2026-06-20'], fp,
          reason: 'the fingerprint survives the Hive round-trip intact');
      expect(
        SyncService.schedShouldSkipUpsert(
          killSwitchDisabled: false,
          status: 'planned',
          storedFingerprint: index['2026-06-20'],
          currentFingerprint: fp,
        ),
        isTrue,
        reason: 'a planned row matching the PERSISTED index skips its re-upsert',
      );
    });
  });
}
