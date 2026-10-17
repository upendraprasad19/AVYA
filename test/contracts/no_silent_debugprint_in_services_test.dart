// H-42 (audit-2026-05-11) — guardrail against silent error swallow
// in `lib/core/services/` and `lib/shared/repositories/`.
//
// The bug class: `catch (e) { debugPrint('...'); }` patterns log to
// the device console but emit NO Crashlytics signal and NO
// `client_errors` row. Production users hit the bug, the dev never
// sees it. Multiple instances over the Test #12 series + audit
// findings (Bug A, C-2, rank_service hot path) trace back to this
// pattern.
//
// Contract: any catch block in a file under those two directories
// that calls `debugPrint(...)` must ALSO call
// `ErrorTelemetry.recordNonFatal(...)` or `ErrorTelemetry.logEvent(...)`
// in the same catch body — OR be explicitly grandfathered in the
// `_grandfathered` set below.
//
// **`_grandfathered` is the visible tech-debt ledger.** New code is
// not allowed to add entries — the test fails when a file outside the
// allowlist matches the bad pattern. Phase 8 cleanup retrofits these
// one file at a time and removes them from the list.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files where the silent debugPrint-only catch pattern is currently
/// tolerated. Retrofit and remove the entry, do NOT add new entries.
///
/// H-42 (audit-2026-05-11) — initial snapshot taken from a sweep of
/// the two scoped directories. The audit's prioritised hot-path site
/// (`rank_service.dart`) has been retrofitted and is intentionally
/// absent from this list — the test would fail if it regressed.
const _grandfathered = <String>{
  // ── core/services ─────────────────────────────────────────────
  // Retrofitted (NOT grandfathered — must stay clean):
  //   rank_service.dart                            (H-42 first batch)
  //   health_sync_service.dart                     (Phase 8 batch)
  //   stat_snapshot_service.dart                   (Phase 8 batch)
  //   subscription_service.dart                    (Phase 8 batch)
  //   razorpay_service.dart                        (Phase 8 batch)
  // Cohort 1 retrofitted (NOT grandfathered):
  //   exlog_key_migrator.dart                      (H-42 7ad0e0 cohort 1)
  //   logging_type_repair_migrator.dart            (H-42 7ad0e0 cohort 1)
  //   migrated_key.dart                            (H-42 7ad0e0 cohort 1)
  //   nlog_key_migrator.dart                       (H-42 7ad0e0 cohort 1)
  //   scheduled_workouts_resync_migrator.dart      (H-42 7ad0e0 cohort 1)
  //   user_config_migrator.dart                    (H-42 7ad0e0 cohort 1)
  // Cohort 2 retrofitted (NOT grandfathered):
  //   nutrition_write_service.dart                 (H-42 7ad0e0 cohort 2)
  //   workout_write_service.dart                   (H-42 7ad0e0 cohort 2)
  //   sync_queue.dart                              (H-42 7ad0e0 cohort 2)
  // Cohort 3 retrofitted (NOT grandfathered):
  //   guarded_box.dart                             (H-42 7ad0e0 cohort 3)
  //   hive_service.dart                            (H-42 7ad0e0 cohort 3)
  //   hive_user_session.dart                       (H-42 7ad0e0 cohort 3)
  //   seed_service.dart                            (H-42 7ad0e0 cohort 3)
  // Cohort 4 retrofitted (NOT grandfathered):
  //   ai_service.dart                              (H-42 7ad0e0 cohort 4)
  //   prediction_service.dart                      (H-42 7ad0e0 cohort 4)
  //   barcode_service.dart                         (H-42 7ad0e0 cohort 4)
  // Cohort 5 retrofitted (NOT grandfathered):
  //   sync_service.dart                            (H-42 7ad0e0 cohort 5)
  //   supabase_service.dart                        (H-42 7ad0e0 cohort 5)
  //   workout_schedule_service.dart                (H-42 7ad0e0 cohort 5)
  //   app_events_service.dart                      (H-42 7ad0e0 cohort 5)
  // ── shared/repositories ───────────────────────────────────────
  // Retrofitted (NOT grandfathered):
  //   plan_engine/progression_resolver.dart         (H-42 first batch)
  // Cohort 6 retrofitted (NOT grandfathered):
  //   user_repository.dart                         (H-42 7ad0e0 cohort 6)
  //   exercise_repository.dart                     (H-42 7ad0e0 cohort 6)
  //   food_repository.dart                         (H-42 7ad0e0 cohort 6)
  //   submissions_repository.dart                  (H-42 7ad0e0 cohort 6)
};

String _norm(String p) => p.replaceAll('\\', '/');

Iterable<File> _scopedDartFiles() sync* {
  for (final dir in const [
    'lib/core/services',
    'lib/shared/repositories',
  ]) {
    final root = Directory(dir);
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }
}

/// Returns true if [body] contains a `catch (...) { ... debugPrint(...) ... }`
/// block that does NOT also call `ErrorTelemetry.recordNonFatal` or
/// `ErrorTelemetry.logEvent` somewhere in the same block.
///
/// We walk the source character-by-character to find catch braces and
/// extract their body. Imperfect on deeply nested catches but
/// sufficient for the audit-grade source-grep guardrail this test
/// represents.
bool _hasSilentDebugPrintCatch(String src) {
  final catchRe = RegExp(r'\}\s*catch\s*\(\s*[A-Za-z_][A-Za-z0-9_, ]*\)\s*\{');
  for (final m in catchRe.allMatches(src)) {
    final start = m.end - 1; // position of opening `{`
    var depth = 1;
    var i = start + 1;
    while (i < src.length && depth > 0) {
      final ch = src[i];
      if (ch == '{') depth++;
      if (ch == '}') depth--;
      i++;
    }
    final body = src.substring(start + 1, i - 1);
    final hasDebugPrint = body.contains('debugPrint(');
    final hasTelemetry =
        body.contains('ErrorTelemetry.recordNonFatal') ||
            body.contains('ErrorTelemetry.logEvent') ||
            // Allow rethrow as the recovery (caller handles).
            body.contains('rethrow');
    if (hasDebugPrint && !hasTelemetry) {
      return true;
    }
  }
  return false;
}

void main() {
  group('H-42 no silent debugPrint catch in services/repositories', () {
    test(
      'Scoped files outside the grandfathered list must pair debugPrint with ErrorTelemetry',
      () {
        final offenders = <String>[];
        for (final file in _scopedDartFiles()) {
          final relPath = _norm(file.path);
          if (_grandfathered.any((g) => relPath.endsWith(g))) continue;
          final src = file.readAsStringSync();
          if (_hasSilentDebugPrintCatch(src)) {
            offenders.add(relPath);
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'These files in lib/core/services/ or lib/shared/repositories/ '
              'have at least one `catch (e) { debugPrint(...); }` block that '
              'does NOT also call ErrorTelemetry.recordNonFatal / .logEvent '
              '(or rethrow). The silent-swallow pattern is the H-42 bug '
              'class — production users hit the bug, devs never see it. '
              'Pair the debugPrint with ErrorTelemetry.recordNonFatal in '
              'the same catch body.\n\n'
              'Offenders:\n${offenders.join("\n")}',
        );
      },
    );

    test(
      'rank_service.dart MUST NOT regress (audit-prioritised hot path)',
      () {
        // The audit specifically called out rank_service.dart:121-124 as
        // the splash + post-workout fire path that needed retrofit first.
        // Even though the broader sweep is grandfathered, rank_service
        // itself must stay clean.
        final src =
            File('lib/core/services/rank_service.dart').readAsStringSync();
        expect(
          _hasSilentDebugPrintCatch(src),
          isFalse,
          reason:
              'rank_service.dart must keep its catch blocks paired with '
              'ErrorTelemetry.recordNonFatal — fired from splash + every '
              'workout completion + cron evaluator. Silent failure here = '
              'rank promotions silently dropped in production.',
        );
      },
    );
  });
}
