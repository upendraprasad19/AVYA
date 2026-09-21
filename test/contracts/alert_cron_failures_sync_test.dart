import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins the `alert_cron_failures` 6th alert cron job (B4,
/// observation-batch-and-digest-redesign, 2026-09-21) — mirrors
/// `alert_thresholds_sync_test.dart`'s established shape for its sibling
/// `client_errors_spike` job: the YAML documents the threshold, the migration
/// SQL implements it, and this test is what keeps the two from silently
/// drifting apart (the class `alert_thresholds_sync_test.dart`'s own header
/// exists to prevent).
///
/// Also pins that this job reuses the SAME acknowledged-based dedup
/// convention the 5 pre-existing alert_* jobs share, not
/// `gemini_failure_alert.ts`'s resolved_at+severity-downgrade convention —
/// this table must not grow a third dedup convention.
void main() {
  late final String yaml;
  late final String yamlBlock;
  /// The full migration file text — used only for locating the SQL body.
  late final String fileText;
  /// ONLY the dollar-quoted `cron.schedule(...)` body: the actual SQL the
  /// database executes. Header-comment prose (which explains the dedup
  /// choice by NAMING the convention it deliberately avoids) must never leak
  /// into a substring check — checking the whole file text would let this
  /// migration's own explanatory comment about `resolved_at` (written to
  /// justify NOT using it) satisfy a check for its ABSENCE, the exact
  /// feedback_green_check_input_set_width class.
  late final String sql;

  setUpAll(() {
    yaml = File('alerts/_thresholds.yaml').readAsStringSync();
    final start = yaml.indexOf('cron_failures:');
    expect(start, greaterThanOrEqualTo(0),
        reason: 'cron_failures block must exist in _thresholds.yaml');
    // Last section in the file today, so bound the block at the trailing
    // comment header rather than a next-section key that may not exist yet.
    final end = yaml.indexOf('# Notes on suppression', start);
    yamlBlock = yaml.substring(start, end == -1 ? yaml.length : end);

    final migMatch =
        RegExp(r'defined_in_migration:\s*"([^"]+)"').firstMatch(yamlBlock);
    expect(migMatch, isNotNull,
        reason: 'cron_failures must name its defining migration');
    final migFile = File('supabase/migrations/${migMatch!.group(1)}');
    expect(migFile.existsSync(), isTrue, reason: '${migFile.path} must exist');
    fileText = migFile.readAsStringSync();

    final bodyStart = fileText.indexOf(r'$$');
    final bodyEnd = fileText.indexOf(r'$$', bodyStart + 2);
    expect(bodyStart >= 0 && bodyEnd > bodyStart, isTrue,
        reason: 'could not locate the dollar-quoted cron.schedule() body');
    sql = fileText.substring(bodyStart, bodyEnd);
  });

  test('yaml fire_at threshold equals the migration gate (no silent drift)',
      () {
    final m = RegExp(r'fire_at:\s*(\d+)').firstMatch(yamlBlock);
    expect(m, isNotNull, reason: 'yaml cron_failures.fire_at missing');
    final fireAt = int.parse(m!.group(1)!);
    expect(sql.contains('WHERE c.cnt >= $fireAt'), isTrue,
        reason: 'migration fire-floor must equal yaml fire_at=$fireAt');
  });

  test('migration query counts failed (1h) OR currently-stuck rows — each '
      'branch with its OWN time bound, no shared outer window', () {
    expect(
      sql.contains(
        "(status = 'failed' AND started_at >= now() - interval '1 hour')",
      ),
      isTrue,
      reason: 'a failed row must self-resolve after ~1h (its own lookback '
          '== the dedup window), matching alert_client_errors_spike\'s '
          'working 1h:1h ratio — not a 24h window borrowed from a daily '
          'digest metric paired with a 1h dedup, which re-pages hourly for '
          'up to 24h after an already-resolved single failure.',
    );
    expect(
      sql.contains(
        "(status = 'started' AND started_at < now() - interval '1 hour')",
      ),
      isTrue,
      reason: 'a stuck job is an ONGOING condition, not a discrete past '
          'event — it must have NO upper time bound, or a job stuck for '
          'longer than that bound would become permanently invisible once '
          'its started_at ages past it, which is worse than the re-paging '
          'bug a shared bound would have been patching around.',
    );
  });

  test('the failed-row check and the dedup window use the SAME duration '
      '(self-resolving, no re-page storm on an already-fixed failure)', () {
    final failedWindow = RegExp(
      r"status = 'failed' AND started_at >= now\(\) - interval '(\d+) hour",
    ).firstMatch(sql);
    final dedupWindow =
        RegExp(r"detected_at > now\(\) - interval '(\d+) hour").firstMatch(sql);
    expect(failedWindow, isNotNull);
    expect(dedupWindow, isNotNull);
    expect(failedWindow!.group(1), dedupWindow!.group(1),
        reason: 'if these ever diverge again (the exact regression this '
            'test exists to catch), a single already-resolved failure can '
            'outlive its own dedup suppression and re-page the founder '
            'hourly for the gap between the two windows.');
  });

  test('no shared 24h (or any other) outer bound wraps BOTH branches — the '
      'design this migration originally shipped with, corrected same day '
      'by the self-triggered B-pass review', () {
    expect(sql.contains("started_at >= now() - interval '24 hours'"), isFalse,
        reason: 'this was the original, corrected-away design: one 24h '
            'outer bound shared by both branches, borrowed from '
            "founder_metrics_ops()'s daily-digest cron_failures_24h column "
            '— right for a once-a-day summary, wrong for a 15-min paging '
            'alert with a 1h dedup window.');
  });

  test('uses the acknowledged-based dedup convention, not a resolved_at one',
      () {
    expect(sql.contains("source = 'alert_cron_failures'"), isTrue);
    expect(sql.contains('acknowledged = false'), isTrue,
        reason: 'must use the same dedup convention as the 5 existing '
            'alert_* jobs, not gemini_failure_alert.ts\'s resolved_at one');
    expect(sql.contains('resolved_at'), isFalse,
        reason: 'this table must not grow a THIRD dedup convention — '
            'resolved_at belongs to gemini_failure_alert.ts only');
  });

  test('pages immediately (critical severity, wired to '
      'trg_dispatch_critical_alert_notify by severity alone)', () {
    expect(sql.contains("'alert_cron_failures',\n    'critical',"), isTrue,
        reason: 'a single-tier alert must page unconditionally, not sit at '
            'info/warn where trg_dispatch_critical_alert_notify never fires');
  });

  test('scheduled via cron.schedule, not a new Edge Function', () {
    // Checked against the FULL file, not the inner body — `cron.schedule(`
    // wraps the `$$...$$` block from outside it.
    expect(fileText.contains('cron.schedule('), isTrue);
    expect(fileText.contains('net.http_post'), isFalse,
        reason: 'B4 corrected design: no new Edge Function, plain SQL only, '
            'matching the 5 pre-existing alert_* jobs\' idiom');
  });
}
