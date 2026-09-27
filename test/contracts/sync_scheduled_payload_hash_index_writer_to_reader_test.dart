// H1b Part A / day-swapper+sync-load Task 15 — behavioral contract for the
// scheduled_workouts skip decision, now routed through SyncSkipIndex (domain
// `sched`) instead of the bespoke schedShouldSkipUpsert/schedPrunedHashIndex
// pair (both deleted by this task).
//
// A-fix-1 (a `completed` row never skips) is SUPERSEDED here: migration 147
// (Task 7) adds a server-side guard that rejects a stale client overwrite of
// a completed row's identity columns, so a fingerprint-matched completed row
// is exactly as safe to skip as a fingerprint-matched planned row. See
// docs/diagnoses/2026-06-27-sched-dirty-filter-b4f7e2.md (A-fix-1's origin)
// and this batch's own diagnose-doc as the record of the supersession.
//
// schedPayloadFingerprint itself is UNCHANGED (still pinned by
// test/sync/sync_skip_index_test.dart's cross-check against SyncFingerprint).
//
// See docs/diagnoses/2026-09-26-sync-write-amplification-a9d3f6.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  // Mirrors _syncScheduledWorkouts' payload(tmplId) builder for the
  // fingerprint-only unit tests below (the domain enum key stays
  // 'sync_sched_payload_hash_index' — Task 4 pins the three shipped domains'
  // names byte-identical to today's).
  Map<String, dynamic> basePayload({
    String userId = 'user-1',
    bool includeTemplateKey = true,
    String? templateId = 'tmpl-cloud-1',
    String date = '2026-06-20',
    Object? week = 2,
    Object? day = 6,
    String status = 'planned',
    String? completedAt,
  }) =>
      <String, dynamic>{
        'user_id': userId,
        if (includeTemplateKey) 'template_id': templateId,
        'scheduled_date': date,
        'week_number': week,
        'day_of_week': day,
        'status': status,
        if (completedAt != null) 'completed_at': completedAt,
      };

  group('schedPayloadFingerprint — stable + field-sensitive (unchanged)', () {
    test('same payload -> same fingerprint (deterministic / cross-VM stable)', () {
      final a = SyncService.schedPayloadFingerprint(basePayload());
      final b = SyncService.schedPayloadFingerprint(basePayload());
      expect(a, b);
      expect(a.length, 36);
    });

    test('every pushed field flips the fingerprint', () {
      final base = SyncService.schedPayloadFingerprint(basePayload());
      final variants = <String, String>{
        'user_id': SyncService.schedPayloadFingerprint(basePayload(userId: 'user-2')),
        'template_id': SyncService.schedPayloadFingerprint(basePayload(templateId: 'tmpl-cloud-2')),
        'template_key_absent': SyncService.schedPayloadFingerprint(
            basePayload(includeTemplateKey: false)),
        'template_value_null': SyncService.schedPayloadFingerprint(basePayload(templateId: null)),
        'scheduled_date': SyncService.schedPayloadFingerprint(basePayload(date: '2026-06-21')),
        'week': SyncService.schedPayloadFingerprint(basePayload(week: 3)),
        'day': SyncService.schedPayloadFingerprint(basePayload(day: 7)),
        'status': SyncService.schedPayloadFingerprint(basePayload(status: 'completed')),
        'completed_at':
            SyncService.schedPayloadFingerprint(basePayload(completedAt: '2026-06-20T08:00:00.000')),
      };
      variants.forEach((field, fp) {
        expect(fp, isNot(base), reason: 'changing $field must flip the fingerprint -> re-push');
      });
    });

    test('an explicit null template_id (local row has no template) differs from an OMITTED key '
        '(orphan) — the T15 payload-shape distinction', () {
      final explicitNull = SyncService.schedPayloadFingerprint(basePayload(templateId: null));
      final omitted = SyncService.schedPayloadFingerprint(basePayload(includeTemplateKey: false));
      expect(explicitNull, isNot(omitted),
          reason: 'PostgREST treats an explicit null and an absent key differently on upsert; '
              'the fingerprint must too, or an orphan-then-resolved row could mis-skip');
    });
  });

  group('scheduled_workouts skip contract (SyncSkipIndex domain: sched)', () {
    Future<void> seed() async {
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_2026-09-21', {
        'date': '2026-09-21',
        'type': 'workout',
        'workout_name': 'Push A',
        'status': 'planned',
        'day_of_week': 0,
        'week': 3,
      });
    }

    Future<void> editOne(int generation) async {
      final box = HiveService.instance.workoutBox;
      final raw = Map<String, dynamic>.from(box.get('schedule_2026-09-21') as Map);
      // `workout_name` is NOT part of the scheduled_workouts payload (see
      // buildPayload in _syncScheduledWorkouts) so editing it would never
      // flip the fingerprint; `week` IS (-> `week_number`), so use that.
      raw['week'] = 3 + generation;
      await box.put('schedule_2026-09-21', raw);
    }

    test('the full contract: first push, unchanged skip, edit re-sends, retry after failure, kill switch',
        () async {
      await expectSkipContract(
        h: h,
        domain: SyncSkipDomain.sched,
        table: 'scheduled_workouts',
        seed: seed,
        editOne: editOne,
        runPass: () => SyncService.instance.pushScheduledWorkoutsForSyncDomain(),
      );
    });

    test('a completed row that matches its stored fingerprint now skips too (A-fix-1 superseded)',
        () async {
      h.server.clear();
      h.server.getResponders.clear();
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_2026-09-22', {
        'date': '2026-09-22',
        'type': 'workout',
        'workout_name': 'Pull A',
        'status': 'completed',
        'completed_at_ms': DateTime.utc(2026, 9, 22, 7).millisecondsSinceEpoch,
        'day_of_week': 1,
        'week': 3,
      });
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      expect(h.server.writesTo('scheduled_workouts'), hasLength(1));
      h.server.clear();
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      expect(h.server.writesTo('scheduled_workouts'), isEmpty,
          reason: 'a completed row is no longer special-cased; migration 147 (Task 7) protects it '
              'server-side, so a fingerprint match skips exactly like a planned row');
    });

    test('a local row with no template_id sends an EXPLICIT null, confirmed', () async {
      h.server.clear();
      h.server.getResponders.clear();
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_2026-09-23', {
        'date': '2026-09-23',
        'type': 'rest',
        'status': 'planned',
        'day_of_week': 2,
        'week': 3,
      });
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      final writes = h.server.writesTo('scheduled_workouts');
      expect(writes, hasLength(1));
      expect(writes.single.rows.single.containsKey('template_id'), isTrue);
      expect(writes.single.rows.single['template_id'], isNull);
      expect(
          SyncSkipIndex.readIndex(HiveService.instance.workoutBox, SyncSkipDomain.sched.indexKey)
              .containsKey('2026-09-23'),
          isTrue,
          reason: 'a resolved (here: genuinely template-less) row is recorded as confirmed');
    });

    test('case 2 — the template row is not on this phone: key omitted, CONFIRMED, and the '
        "template's later arrival re-pushes WITH the cloud id", () async {
      h.server.clear();
      h.server.getResponders.clear();
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_2026-09-24', {
        'date': '2026-09-24',
        'type': 'custom_template',
        'template_id': 'tmpl_missing',
        'status': 'planned',
        'day_of_week': 3,
        'week': 3,
      });
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      final writes = h.server.writesTo('scheduled_workouts');
      expect(writes, hasLength(1), reason: 'status still reaches cloud');
      expect(writes.single.rows.single.containsKey('template_id'), isFalse,
          reason: 'an unresolvable template_id is OMITTED, never guessed');
      expect(
          SyncSkipIndex.readIndex(box, SyncSkipDomain.sched.indexKey).containsKey('2026-09-24'),
          isTrue,
          reason: 'confirmed: an unconfirmed row would re-push every pass while the template is missing');
      expect(
          h.server.requests.where((r) => r.method == 'GET' && r.table == 'workout_templates'),
          isEmpty,
          reason: 'no cloud lookup when the local template row is absent');

      h.server.clear();
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      expect(h.server.writesTo('scheduled_workouts'), isEmpty, reason: 'unchanged: skipped');

      // The template arrives on this phone -> template_name enters the fingerprint.
      await box.put('tmpl_missing', {'id': 'tmpl_missing', 'name': 'Arms'});
      h.server.getResponders['workout_templates'] = (_) => [
            {'id': 'cloud-tmpl-arms'}
          ];
      h.server.clear();
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      final healed = h.server.writesTo('scheduled_workouts');
      expect(healed, hasLength(1));
      expect(healed.single.rows.single['template_id'], 'cloud-tmpl-arms');
    });

    test('case 3 — local template present but its cloud id is unresolvable: written without '
        'template_id, UNCONFIRMED, retried next pass; resolves once the cloud id exists', () async {
      h.server.clear();
      h.server.getResponders.clear();
      final box = HiveService.instance.workoutBox;
      await box.put('tmpl_legs', {'id': 'tmpl_legs', 'name': 'Legs'});
      await box.put('schedule_2026-09-25', {
        'date': '2026-09-25',
        'type': 'custom_template',
        'template_id': 'tmpl_legs',
        'status': 'planned',
        'day_of_week': 4,
        'week': 3,
      });
      // No workout_templates responder: the stub answers [] -> maybeSingle null.
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      final writes = h.server.writesTo('scheduled_workouts');
      expect(writes, hasLength(1));
      expect(writes.single.rows.single.containsKey('template_id'), isFalse);
      expect(
          SyncSkipIndex.readIndex(box, SyncSkipDomain.sched.indexKey).containsKey('2026-09-25'),
          isFalse,
          reason: 'unconfirmed: the next pass retries the resolve');

      h.server.getResponders['workout_templates'] = (_) => [
            {'id': 'cloud-tmpl-legs'}
          ];
      h.server.clear();
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      final retried = h.server.writesTo('scheduled_workouts');
      expect(retried, hasLength(1));
      expect(retried.single.rows.single['template_id'], 'cloud-tmpl-legs');
      expect(
          SyncSkipIndex.readIndex(box, SyncSkipDomain.sched.indexKey).containsKey('2026-09-25'),
          isTrue);
    });

    test('a skipped row makes NO workout_templates lookup (spec §14)', () async {
      h.server.clear();
      h.server.getResponders.clear();
      final box = HiveService.instance.workoutBox;
      await box.put('tmpl_push', {'id': 'tmpl_push', 'name': 'Push'});
      await box.put('schedule_2026-09-26', {
        'date': '2026-09-26',
        'type': 'custom_template',
        'template_id': 'tmpl_push',
        'status': 'planned',
        'day_of_week': 5,
        'week': 3,
      });
      h.server.getResponders['workout_templates'] = (_) => [
            {'id': 'cloud-tmpl-push'}
          ];
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      h.server.clear();
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      expect(h.server.writesTo('scheduled_workouts'), isEmpty);
      expect(
          h.server.requests.where((r) => r.method == 'GET' && r.table == 'workout_templates'),
          isEmpty,
          reason: 'resolveCloudTemplateId runs only inside the push closure');
    });

    test('a deleted schedule row leaves the index on the next pass (liveKeys prune)', () async {
      h.server.clear();
      h.server.getResponders.clear();
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_2026-09-27', {
        'date': '2026-09-27',
        'type': 'rest',
        'status': 'rest',
        'day_of_week': 6,
        'week': 3,
      });
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.sched.indexKey).containsKey('2026-09-27'),
          isTrue);
      await box.delete('schedule_2026-09-27');
      await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
      expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.sched.indexKey).containsKey('2026-09-27'),
          isFalse);
    });
  });

  // Day-swapper + sync-load Task 20 (coordinator addendum) — Task 15 left
  // resetJourney's sched literal untouched (its own "Notes for the
  // coordinator" section names Task 20 as where the conversion lands), and
  // this file carried no "resetJourney clears the index" test to repoint —
  // this is therefore the FIRST such test for sched, added for parity with
  // the exlog/nlog sibling tests in the two sibling contract files.
  group('resetJourney clears the index (source contract)', () {
    test(
        'sched is cleared by resetJourney via SyncSkipIndex.clearAll '
        '(see the exlog sibling test for the full rationale, including why '
        'the check traces through clearJourneyLocalState)', () {
      final src = File('lib/features/dev/simulation_service.dart').readAsStringSync();
      final rjStart = src.indexOf('Future<void> resetJourney(');
      expect(rjStart, isNot(-1), reason: 'resetJourney must exist at this name');
      final rjEnd = src.indexOf('\n  }\n', rjStart);
      final rjBody = src.substring(rjStart, rjEnd == -1 ? src.length : rjEnd);
      expect(rjBody, contains('clearJourneyLocalState()'),
          reason: 'a stale fingerprint entry survives a sim reset and mis-skips the '
              're-drive push unless resetJourney routes through the Hive-only '
              'reset helper');

      final clStart = src.indexOf('Future<void> clearJourneyLocalState(');
      expect(clStart, isNot(-1),
          reason: 'clearJourneyLocalState must exist at this name');
      final clEnd = src.indexOf('\n  }\n', clStart);
      final clBody = src.substring(clStart, clEnd == -1 ? src.length : clEnd);
      expect(clBody, contains('SyncSkipIndex.clearAll('),
          reason: 'clearJourneyLocalState must clear every domain via the '
              'shared helper, not just exlog/sched/nlog individually');
    });
  });
}
