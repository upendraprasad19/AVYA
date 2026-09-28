// day-swapper+sync-load Task 16 — behavioral contract for the
// workout_templates push, routed through SyncSkipIndex (domain `template`).
// The header upsert, the per-exercise upsert loop and the tail-vacuum DELETE
// are now ONE bundle per template: any failure inside the
// bundle returns false (unconfirmed), so the WHOLE bundle retries next pass
// (every write inside is already idempotent, so a retry is cheap and safe).
// This is a deliberate tightening vs. the pre-Task-16 code, which continued
// past a single failed exercise upsert.
//
// The pure fingerprint algorithm and the FK/tail-vacuum literals this
// bundle preserves are pinned separately by
// test/contracts/template_exercises_tail_vacuum_test.dart and
// test/contracts/template_exercises_upsert_test.dart (source-grep,
// unaffected by this task; re-run as part of Step 5 below).
//
// Merge of origin/main (2026-09-28, OI-252 f4a8c2): a template's cloud id is
// now minted on the phone and lives in its Hive key (`tmpl_<uuid>`), so the
// header upsert carries `id` directly (`onConflict: 'id'`) and the old id
// SELECT is gone. The fixtures use real `templateKeyFor(<uuid>)` keys: a
// legacy `tmpl_1` key has no recoverable cloud id and is skipped entirely
// (`cloudIdFromKey` returns null), which is correct and is what these tests
// hit (pushed 0, skipped 0) before this repoint. B2a-2b (also from main):
// `_reportSyncFailure` now writes ONE client_errors row per failure, not two.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/template_identity.dart';

import '../sync/sync_domain_skip_harness.dart';

/// Every log-client-error request carrying [opType]. `_reportSyncFailure` is
/// fired `unawaited`, so its POSTs can land a few ticks after the push
/// returns: wait until at least [atLeast] have arrived, then a short settle so
/// a surplus (a flood) is also visible before the caller counts. Same filter
/// as the exlog/nlog siblings: `recordNonFatal` posts with its own internal
/// `reason` as op_type, so only the domain op string is matched.
///
/// Fix round 2 (F3, 2026-09-27): already counts to [atLeast] rather than
/// stopping on the first match (the nlog sibling's bug this fix round
/// addresses), so this file was never exposed to that failure mode -- but
/// its 1000ms deadline is not "generous" under full-suite contention.
/// Raised to 10s for parity; the happy path (plus the 150ms flood-settle
/// below) is unaffected.
Future<List<dynamic>> _logClientErrorReports(SyncHarness h, String opType,
    {int atLeast = 1, int maxWaitMs = 10000}) async {
  List<dynamic> matches() => h.server.requests
      .where((r) =>
          r.path == '/functions/v1/log-client-error' &&
          r.body is Map &&
          (r.body as Map)['op_type'] == opType)
      .toList();
  final deadline = DateTime.now().add(Duration(milliseconds: maxWaitMs));
  while (matches().length < atLeast && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
  await Future.delayed(const Duration(milliseconds: 150));
  return matches();
}

const _id1 = '11111111-2222-3333-4444-555555555555';
const _id2 = '66666666-7777-8888-9999-aaaaaaaaaaaa';
final _key1 = templateKeyFor(_id1);
final _key2 = templateKeyFor(_id2);

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<void> seed() async {
    await HiveService.instance.workoutBox.put(_key1, {
      'id': _key1,
      'type': 'template',
      'name': 'Push Day A',
      'workout_focus': 'push',
      'created_at': '2026-08-01T00:00:00.000Z',
      'exercises': [
        {'exercise_name': 'Bench Press', 'sets': 4, 'reps': '8'},
      ],
    });
  }

  Future<void> editOne(int generation) async {
    final box = HiveService.instance.workoutBox;
    final raw = Map<String, dynamic>.from(box.get(_key1) as Map);
    final exercises = (raw['exercises'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    exercises[0]['sets'] = 4 + generation;
    raw['exercises'] = exercises;
    await box.put(_key1, raw);
  }

  test('the full contract: first push (header+exercise+vacuum), unchanged skip, edit '
      're-sends the whole bundle, retry after failure, kill switch', () async {
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.template,
      table: 'workout_templates',
      seed: seed,
      editOne: editOne,
      runPass: () => SyncService.instance.pushWorkoutTemplatesForSyncDomain(),
      writesPerRow: 1,
    );
  });

  test('a template header write, once confirmed, also sent the exercise + the tail vacuum in the '
      'same pass', () async {
    h.server.clear();
    await seed();
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(h.server.writesTo('workout_templates'), hasLength(1));
    final header = h.server.writesTo('workout_templates').single.body;
    final headerRow = (header is List ? header.single : header) as Map;
    expect(headerRow['id'], _id1,
        reason: 'OI-252: the header carries the cloud id derived from the '
            'Hive key, so a delete-then-recreate with the same name can never '
            'collide with the old row');
    expect(h.server.writesTo('template_exercises').where((r) => r.method == 'POST'), hasLength(1));
    expect(h.server.writesTo('template_exercises').where((r) => r.method == 'DELETE'), hasLength(1));
  });

  test('a mid-bundle exercise upsert failure leaves the WHOLE bundle unconfirmed (bundle atomicity)',
      () async {
    h.server.clear();
    h.server.failWritesTo.add('template_exercises');
    await seed();
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(
        SyncSkipIndex.readIndex(HiveService.instance.workoutBox, SyncSkipDomain.template.indexKey)
            .containsKey(_key1),
        isFalse,
        reason: 'the header upsert succeeded but the bundle is not confirmed until the exercises '
            'and the tail vacuum also succeed');
    h.server
      ..clear()
      ..failWritesTo.remove('template_exercises');
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(h.server.writesTo('workout_templates'), hasLength(1),
        reason: 'the WHOLE bundle retries, including the header upsert (idempotent, harmless)');
  });

  test('abandon-on-first-failure with TWO exercises: exercise 1 and the vacuum are never '
      'attempted, and exactly one upsert_template_exercise report is sent', () async {
    // Two exercises on purpose (the nlog sibling's shape). With ONE exercise
    // the test above cannot tell "return false in the exercise catch" from
    // "swallow and fall through": `failWritesTo` fails the whole
    // template_exercises table, so the tail-vacuum DELETE also fails and its
    // own `return false;` leaves the bundle unconfirmed either way (Task 16
    // mutation 3 reddened zero tests until this leg existed).
    h.server.clear();
    await HiveService.instance.workoutBox.put(_key2, {
      'id': _key2,
      'type': 'template',
      'name': 'Pull Day A',
      'workout_focus': 'pull',
      'created_at': '2026-08-01T00:00:00.000Z',
      'exercises': [
        {'exercise_name': 'Row', 'sets': 4, 'reps': '8'},
        {'exercise_name': 'Curl', 'sets': 3, 'reps': '12'},
      ],
    });
    h.server.failWritesTo.add('template_exercises');
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(h.server.writesTo('template_exercises'), hasLength(1),
        reason: 'exercise 0 fails and the bundle stops: exercise 1 (POST) and the tail '
            'vacuum (DELETE) must never be attempted -- "try every exercise" sends 3');
    expect(
        SyncSkipIndex.readIndex(HiveService.instance.workoutBox, SyncSkipDomain.template.indexKey)
            .containsKey(_key2),
        isFalse);
    // `_reportSyncFailure` is the only path to the server-side client_errors
    // row, so the exercise catch keeps it. Since main's B2a-2b dual-write fix
    // its internal recordNonFatal passes skipServerPost:true, so ONE failure
    // == ONE request. Fixed at 1 regardless of exercise count is the
    // no-flood property.
    final reports = await _logClientErrorReports(h, 'upsert_template_exercise');
    expect(reports, hasLength(1),
        reason: 'one _reportSyncFailure call, one client_errors row, for the '
            'whole failed bundle');
    h.server
      ..clear()
      ..failWritesTo.remove('template_exercises');
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(h.server.writesTo('workout_templates'), hasLength(1));
    expect(h.server.writesTo('template_exercises'), hasLength(3),
        reason: 'the whole bundle re-pushes: both exercise upserts + the tail vacuum');
  });
}
