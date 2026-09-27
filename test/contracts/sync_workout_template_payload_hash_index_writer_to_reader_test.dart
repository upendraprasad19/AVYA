// day-swapper+sync-load Task 16 — behavioral contract for the
// workout_templates push, routed through SyncSkipIndex (domain `template`).
// The header upsert, the id SELECT, the per-exercise upsert loop and the
// tail-vacuum DELETE are now ONE bundle per template: any failure inside the
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

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

/// Every log-client-error request carrying [opType]. `_reportSyncFailure` is
/// fired `unawaited`, so its POSTs can land a few ticks after the push
/// returns: wait until at least [atLeast] have arrived, then a short settle so
/// a surplus (a flood) is also visible before the caller counts. Same filter
/// as the exlog/nlog siblings: `recordNonFatal` posts with its own internal
/// `reason` as op_type, so only the domain op string is matched.
Future<List<dynamic>> _logClientErrorReports(SyncHarness h, String opType,
    {int atLeast = 1, int maxWaitMs = 1000}) async {
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

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<void> seed() async {
    await HiveService.instance.workoutBox.put('tmpl_1', {
      'id': 'tmpl_1',
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
    final raw = Map<String, dynamic>.from(box.get('tmpl_1') as Map);
    final exercises = (raw['exercises'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    exercises[0]['sets'] = 4 + generation;
    raw['exercises'] = exercises;
    await box.put('tmpl_1', raw);
  }

  test('the full contract: first push (header+id-select+exercise+vacuum), unchanged skip, edit '
      're-sends the whole bundle, retry after failure, kill switch', () async {
    h.server.getResponders['workout_templates'] = (_) => [
          {'id': 'tmpl-cloud-1'}
        ];
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
    h.server.getResponders['workout_templates'] = (_) => [
          {'id': 'tmpl-cloud-1'}
        ];
    await seed();
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(h.server.writesTo('workout_templates'), hasLength(1));
    expect(h.server.writesTo('template_exercises').where((r) => r.method == 'POST'), hasLength(1));
    expect(h.server.writesTo('template_exercises').where((r) => r.method == 'DELETE'), hasLength(1));
  });

  test('a mid-bundle exercise upsert failure leaves the WHOLE bundle unconfirmed (bundle atomicity)',
      () async {
    h.server.clear();
    h.server.getResponders['workout_templates'] = (_) => [
          {'id': 'tmpl-cloud-1'}
        ];
    h.server.failWritesTo.add('template_exercises');
    await seed();
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(
        SyncSkipIndex.readIndex(HiveService.instance.workoutBox, SyncSkipDomain.template.indexKey)
            .containsKey('tmpl_1'),
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
    h.server.getResponders['workout_templates'] = (_) => [
          {'id': 'tmpl-cloud-1'}
        ];
    await HiveService.instance.workoutBox.put('tmpl_2', {
      'id': 'tmpl_2',
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
            .containsKey('tmpl_2'),
        isFalse);
    // `_reportSyncFailure` is the only path to the server-side client_errors
    // row (recordNonFatal is Crashlytics-only), so the exercise catch keeps
    // it. One call dual-posts by design (its own functions.invoke + its
    // internal recordNonFatal(reason: opType)), so ONE failure == 2 requests.
    // Fixed at 2 regardless of exercise count is the no-flood property.
    final reports =
        await _logClientErrorReports(h, 'upsert_template_exercise', atLeast: 2);
    expect(reports, hasLength(2),
        reason: 'one _reportSyncFailure call (dual-posted) for the whole failed bundle');
    h.server
      ..clear()
      ..failWritesTo.remove('template_exercises');
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(h.server.writesTo('workout_templates'), hasLength(1));
    expect(h.server.writesTo('template_exercises'), hasLength(3),
        reason: 'the whole bundle re-pushes: both exercise upserts + the tail vacuum');
  });
}
