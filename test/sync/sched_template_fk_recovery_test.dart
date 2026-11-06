// B-pass R1-F1 (day-swapper + sync-load): the scheduled_workouts FK self-heal
// re-runs _syncWorkoutTemplates so the missing parent row exists again. Once
// templates went through SyncSkipIndex, that re-run SKIPPED the template (its
// fingerprint was confirmed on an earlier pass), so the cloud row was never
// recreated and the schedule row fell to the orphan fallback — on every pass.
// This drives the real SyncService against the local stub: the cloud "loses"
// the template after the first pass, and the recovery must re-push exactly
// that template and link the row to it.
//
// OI-252 (merged from main 2026-09-28): template keys are `tmpl_<uuid>` and
// the cloud id comes from the key, with no SELECT. So "the cloud lost it" is
// modelled the way the real server signals it: a 23503 FK violation on the
// scheduled_workouts upsert until the template row is written again, not an
// empty template SELECT, which the sync no longer makes. The first version
// of this test used legacy `tmpl_1` keys and a SELECT responder that answered
// one id for every name, which made the legacy-key migrator fold both
// templates into one key.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/template_identity.dart';

import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _cloudTemplateId = '11111111-2222-4333-8444-555555555555';
const _otherTemplateId = '66666666-7777-4888-9999-aaaaaaaaaaaa';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('FK recovery re-pushes the lost template (and only it) and links the row',
      () async {
    h.server.clear();
    final wb = HiveService.instance.workoutBox;
    final keyA = templateKeyFor(_cloudTemplateId);
    await wb.put(keyA, {
      'type': 'template',
      'id': keyA,
      'name': 'Push A',
      'exercises': <dynamic>[],
    });
    final keyB = templateKeyFor(_otherTemplateId);
    await wb.put(keyB, {
      'type': 'template',
      'id': keyB,
      'name': 'Pull B',
      'exercises': <dynamic>[],
    });

    // null = the cloud has the template; an int = the request index at
    // which the cloud lost it (it exists again only after a later write).
    int? lostAt;
    bool templateWrittenSinceLoss() => h.server.requests
        .skip(lostAt!)
        .any((r) =>
            r.isWrite &&
            r.table == 'workout_templates' &&
            r.rows.any((row) => row['id'] == _cloudTemplateId));
    h.server.writeFailers['scheduled_workouts'] = (req) {
      final linksLost =
          req.rows.any((row) => row['template_id'] == _cloudTemplateId);
      if (lostAt == null || !linksLost || templateWrittenSinceLoss()) {
        return null;
      }
      return {
        'code': '23503',
        'message': 'insert or update on table "scheduled_workouts" violates '
            'foreign key constraint "scheduled_workouts_template_id_fkey"',
      };
    };

    // Pass 1: both templates confirmed and recorded in the skip index.
    await SyncService.instance.pushWorkoutTemplatesForSyncDomain();
    expect(
        h.server.writesTo('workout_templates').map((r) => r.rows.single['name']),
        containsAll(<String>['Push A', 'Pull B']));

    // The cloud loses Push A (outage restore / manual delete). The phone's
    // index still says "confirmed".
    lostAt = h.server.requests.length;
    await wb.put('schedule_2026-09-21', {
      'date': '2026-09-21',
      'template_id': keyA,
      'status': 'planned',
      'week': 1,
      'day_of_week': 0,
    });

    await SyncService.instance.pushScheduledWorkoutsForSyncDomain();

    final recoveryTemplateWrites = h.server.requests
        .skip(lostAt)
        .where((r) => r.isWrite && r.table == 'workout_templates')
        .expand((r) => r.rows)
        .map((row) => row['name'])
        .toList();
    expect(recoveryTemplateWrites, ['Push A'],
        reason: 'the recovery re-pushes the lost template, not every template');

    final schedWrites = h.server.writesTo('scheduled_workouts');
    expect(schedWrites, isNotEmpty);
    expect(schedWrites.last.rows.single['template_id'], _cloudTemplateId,
        reason: 'the row is linked to the recreated template, not orphaned');

    // Pass 3: nothing changed — the row was confirmed, so nothing is sent.
    final beforeQuiet = h.server.requests.length;
    await SyncService.instance.pushScheduledWorkoutsForSyncDomain();
    final quiet = h.server.requests
        .skip(beforeQuiet)
        .where((r) =>
            r.isWrite &&
            (r.table == 'scheduled_workouts' || r.table == 'workout_templates'))
        .toList();
    expect(quiet, isEmpty, reason: 'a healed row is not re-pushed every pass');

    expectWritesMatchLiveSchema(h.server);
  });
}
