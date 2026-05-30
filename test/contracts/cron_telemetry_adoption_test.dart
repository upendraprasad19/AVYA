// Contract test — every deployed cron Edge Function MUST call
// `logCronStart` / `logCronEnd` from `_shared/cron_telemetry.ts`.
//
// Closes OI-15 — without this gate, a new cron function can ship without
// telemetry and resume the silent-401 class (Test #16 P1-D root cause +
// audit 2026-05-17 OI-11 cause).
//
// **Scope:** functions that have already been wired in this batch
// (`pr-detection`, `evaluate-rank-promotions`, `clean-orphan-media`,
// `promote-community-item`). The remaining 8 cron functions are tracked
// as OI-21 follow-up and explicitly EXCLUDED from this test until they
// migrate; adding them prematurely would break CI before the deploys ship.
//
// When a new cron function is wired:
//   1. Add its slug to `_wiredCronFunctions` below.
//   2. Ensure its `index.ts` imports `cron_telemetry.ts` AND calls both
//      `logCronStart` (at handler top) and `logCronEnd` (on every exit
//      path).
//
// Verification is source-grep (no Deno runtime / no live HTTP). Cheap +
// runs in pre-commit + /build-apk gates.

import 'dart:io';
import 'package:test/test.dart';

const _wiredCronFunctions = <String>[
  // Wired in 2026-05-17 OI-15 batch (commit 35005b3):
  'pr-detection',
  'evaluate-rank-promotions',
  'clean-orphan-media',
  'promote-community-item',
  // Wired in 2026-05-17 OI-21 batch (this commit):
  'morning-alert',
  're-engagement',
  'plateau-alert',
  'protein-gap-alert',
  'workout-window-closing',
  'i-see-you-callout',
  'rolling-context',
  'streak-guardian',
  'weekly-recap-ready',
  'expiry-reminder',
  // Wired 2026-05-30 (audit-2026-05-29 EF-2 / OI-21 closure): weekly-recalc
  // now emits cron_call_log telemetry so alert_edge_function_health (076/077)
  // can see its failures.
  'weekly-recalc',
];

const _functionsDir = 'supabase/functions';

void main() {
  group('cron_telemetry adoption contract', () {
    test('_shared/cron_telemetry.ts exists with expected exports', () {
      final helper = File('$_functionsDir/_shared/cron_telemetry.ts');
      expect(helper.existsSync(), isTrue,
          reason: 'cron_telemetry.ts helper missing — OI-15 regression');
      final src = helper.readAsStringSync();
      expect(src, contains('export async function logCronStart'),
          reason: 'logCronStart export missing');
      expect(src, contains('export async function logCronEnd'),
          reason: 'logCronEnd export missing');
    });

    for (final slug in _wiredCronFunctions) {
      group(slug, () {
        final indexPath = '$_functionsDir/$slug/index.ts';

        test('imports cron_telemetry helper', () {
          final f = File(indexPath);
          expect(f.existsSync(), isTrue,
              reason: '$slug/index.ts not found');
          final src = f.readAsStringSync();
          expect(
            src,
            anyOf(
              contains("from '../_shared/cron_telemetry.ts'"),
              contains('from "../_shared/cron_telemetry.ts"'),
            ),
            reason:
                '$slug missing cron_telemetry import — telemetry will be silent',
          );
        });

        test('calls logCronStart at handler entry', () {
          final src = File(indexPath).readAsStringSync();
          expect(src, contains('logCronStart('),
              reason:
                  '$slug never calls logCronStart — cron_call_log row never written');
        });

        test('calls logCronEnd on at least one exit path', () {
          final src = File(indexPath).readAsStringSync();
          expect(src, contains('logCronEnd('),
              reason:
                  '$slug never calls logCronEnd — started rows never resolved to success/failed');
        });

        test('records failed status in error path', () {
          final src = File(indexPath).readAsStringSync();
          final hasSingle = src.contains("logCronEnd(logId, 'failed'");
          final hasDouble = src.contains('logCronEnd(logId, "failed"');
          expect(hasSingle || hasDouble, isTrue,
              reason:
                  '$slug catch block must call logCronEnd(_, "failed"|\'failed\', ...) so failures show up in cron_call_log');
        });
      });
    }
  });
}
