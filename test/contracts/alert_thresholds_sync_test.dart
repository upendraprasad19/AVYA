import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins the `client_errors_spike` alert config (diagnose f0b9d3, and its
/// 2026-09-27 recurrence diagnose d2c9f4 fixed by migration 147).
///
/// Defects motivated this:
///   1. (f0b9d3) The cron counted ALL `client_errors` rows — including
///      `error_code` 'event'/'info' telemetry breadcrumbs (~81.5% of rows) —
///      so alert #24 paged critical for the founder's own reinstall/restore
///      burst.
///   2. `alerts/_thresholds.yaml` documents the thresholds but is NOT the
///      runtime source of truth (those live in the cron SQL of a migration),
///      and nothing pinned the two together → silent-drift vector.
///   3. (d2c9f4, migration 147) The count was raw ROWS, not distinct events,
///      so a single client's retry storm could inflate it; there was no
///      offline-noise exclusion, no per-user breadth arm, and no
///      server-error-class arm — a device losing signal on a train and a
///      genuine server incident were indistinguishable to the alert.
///
/// This test asserts, source-grep style:
///   (a) the yaml documents the breadcrumb exclusion + the new distinct-event/
///       offline/breadth/server fields;
///   (b) the yaml's numbers EQUAL the gates in the migration it names
///       (`defined_in_migration`) — bump one without the other and this goes
///       red;
///   (c) that migration's count query actually excludes `event`/`info` (the
///       regression for defect #1 — RED against the old unfiltered 076 body).
///
/// Structural assertions for the new (147) shape — offline exclusion, the
/// EXCEPTION-SHAPED users filter, the server-error regex, and the
/// parenthesized fire condition — live in the dedicated
/// `ops_alerts_spike_breadth_test.dart` instead, which mutation-proves each
/// one; this file stays scoped to the yaml<->migration numeric-drift contract
/// it has always owned.
void main() {
  late final String block;
  late final String sql;

  setUpAll(() {
    final yaml = File('alerts/_thresholds.yaml').readAsStringSync();
    final start = yaml.indexOf('client_errors_spike:');
    expect(start, greaterThanOrEqualTo(0),
        reason: 'client_errors_spike block must exist in _thresholds.yaml');
    final end = yaml.indexOf('edge_function_health:', start);
    block = yaml.substring(start, end == -1 ? yaml.length : end);

    final migMatch =
        RegExp(r'defined_in_migration:\s*"([^"]+)"').firstMatch(block);
    expect(migMatch, isNotNull,
        reason: 'client_errors_spike must name its defining migration');
    final migFile = File('supabase/migrations/${migMatch!.group(1)}');
    expect(migFile.existsSync(), isTrue,
        reason: '${migFile.path} must exist');
    sql = migFile.readAsStringSync();
  });

  int yamlNum(String key) {
    final m = RegExp('$key:\\s*(\\d+)').firstMatch(block);
    expect(m, isNotNull, reason: 'yaml client_errors_spike.$key missing');
    return int.parse(m!.group(1)!);
  }

  test('yaml documents the event+info breadcrumb exclusion', () {
    expect(
      block.contains(RegExp(r'excludes_error_codes:\s*\[\s*event\s*,\s*info\s*\]')),
      isTrue,
      reason: 'client_errors_spike must declare excludes_error_codes: [event, info]',
    );
  });

  test('yaml documents the 147 distinct-event + offline-exclusion redesign',
      () {
    expect(block.contains('counts_distinct_events: true'), isTrue,
        reason: 'yaml must document that the count is DISTINCT events, not '
            'raw rows (the d2c9f4 recurrence class)');
    expect(block.contains('excludes_offline_noise: true'), isTrue,
        reason: 'yaml must document the offline-noise exclusion');
  });

  test('yaml distinct-event thresholds equal the defining migration gates '
      '+ migration excludes breadcrumbs (no silent drift)', () {
    final info = yamlNum('info_at');
    final warn = yamlNum('warn_at');
    final crit = yamlNum('critical_at');

    // Anchored to `raw.cnt >= N` — the 147 severity CASE reads from the `raw`
    // subquery alias, not a bare `cnt` (which no longer exists as a top-level
    // column reference — `feedback_green_check_input_set_width`-class: a
    // stale anchor from before the subquery was introduced would silently
    // match nothing and this test would go permanently, invisibly green).
    expect(sql.contains('raw.cnt >= $crit'), isTrue,
        reason: 'migration critical gate must equal yaml critical_at=$crit');
    expect(sql.contains('raw.cnt >= $warn'), isTrue,
        reason: 'migration warn gate must equal yaml warn_at=$warn');
    expect(sql.contains('(c.cnt >= $info'), isTrue,
        reason: 'migration fire-floor must equal yaml info_at=$info');
    expect(info < warn && warn < crit, isTrue,
        reason: 'thresholds must strictly increase (info<warn<crit)');

    // Breadcrumb exclusion present in the count query (regression for f0b9d3).
    expect(sql.contains("error_code IS DISTINCT FROM 'event'"), isTrue,
        reason: 'count query must exclude event breadcrumbs');
    expect(sql.contains("error_code IS DISTINCT FROM 'info'"), isTrue,
        reason: 'count query must exclude info breadcrumbs');
    // Failure-shaped events MUST be re-included (P0 f0b9d3 — 086 went blind to
    // logEvent-coded failures like *_failed / widget_error_fallback, which the
    // client stamps with error_code='event'). op_type carries the severity.
    expect(sql.contains('op_type ~*'), isTrue,
        reason: 'failure-shaped op_types must be re-included into the count');
  });

  test('yaml users/server breadth thresholds equal the migration gates '
      '(147, no silent drift)', () {
    final usersWarn = yamlNum('breadth_warn_users');
    final usersCrit = yamlNum('breadth_critical_users');
    final serverWarn = yamlNum('server_warn_events');
    final serverCrit = yamlNum('server_critical_events');

    expect(sql.contains('raw.users >= $usersCrit'), isTrue,
        reason: 'migration critical users gate must equal yaml '
            'breadth_critical_users=$usersCrit');
    expect(sql.contains('raw.users >= $usersWarn'), isTrue,
        reason: 'migration warn users gate must equal yaml '
            'breadth_warn_users=$usersWarn');
    expect(sql.contains('c.users >= $usersWarn'), isTrue,
        reason: 'migration fire-floor users arm must equal yaml '
            'breadth_warn_users=$usersWarn');

    expect(sql.contains('raw.server_events >= $serverCrit'), isTrue,
        reason: 'migration critical server-events gate must equal yaml '
            'server_critical_events=$serverCrit');
    expect(sql.contains('raw.server_events >= $serverWarn'), isTrue,
        reason: 'migration warn server-events gate must equal yaml '
            'server_warn_events=$serverWarn');
    expect(sql.contains('c.server_events >= $serverWarn'), isTrue,
        reason: 'migration fire-floor server-events arm must equal yaml '
            'server_warn_events=$serverWarn');

    expect(usersWarn < usersCrit, isTrue,
        reason: 'users thresholds must strictly increase (warn<crit)');
    expect(serverWarn < serverCrit, isTrue,
        reason: 'server-event thresholds must strictly increase (warn<crit)');
  });
}
