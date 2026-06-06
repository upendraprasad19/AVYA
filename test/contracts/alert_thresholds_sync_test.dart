import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins the `client_errors_spike` alert config (diagnose f0b9d3).
///
/// Two defects motivated this:
///   1. The cron counted ALL `client_errors` rows — including `error_code`
///      'event'/'info' telemetry breadcrumbs (~81.5% of rows) — so alert #24
///      paged critical for the founder's own reinstall/restore burst.
///   2. `alerts/_thresholds.yaml` documents the thresholds but is NOT the
///      runtime source of truth (those live in the cron SQL of a migration),
///      and nothing pinned the two together → silent-drift vector.
///
/// This test asserts, source-grep style:
///   (a) the yaml documents the breadcrumb exclusion;
///   (b) the yaml's info/warn/critical numbers EQUAL the gates in the migration
///       it names (`defined_in_migration`) — bump one without the other and this
///       goes red;
///   (c) that migration's count query actually excludes `event`/`info` (the
///       regression for defect #1 — RED against the old unfiltered 076 body).
void main() {
  late final String block;

  setUpAll(() {
    final yaml = File('alerts/_thresholds.yaml').readAsStringSync();
    final start = yaml.indexOf('client_errors_spike:');
    expect(start, greaterThanOrEqualTo(0),
        reason: 'client_errors_spike block must exist in _thresholds.yaml');
    final end = yaml.indexOf('edge_function_health:', start);
    block = yaml.substring(start, end == -1 ? yaml.length : end);
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

  test('yaml thresholds equal the defining migration gates + migration excludes '
      'breadcrumbs (no silent drift)', () {
    final info = yamlNum('info_at');
    final warn = yamlNum('warn_at');
    final crit = yamlNum('critical_at');

    final migMatch =
        RegExp(r'defined_in_migration:\s*"([^"]+)"').firstMatch(block);
    expect(migMatch, isNotNull,
        reason: 'client_errors_spike must name its defining migration');
    final migFile =
        File('supabase/migrations/${migMatch!.group(1)}');
    expect(migFile.existsSync(), isTrue,
        reason: '${migFile.path} must exist');
    final sql = migFile.readAsStringSync();

    // The cron CASE maps cnt -> severity; the WHERE floor is the info gate.
    expect(sql.contains('cnt >= $crit'), isTrue,
        reason: 'migration critical gate must equal yaml critical_at=$crit');
    expect(sql.contains('cnt >= $warn'), isTrue,
        reason: 'migration warn gate must equal yaml warn_at=$warn');
    expect(sql.contains('c.cnt >= $info'), isTrue,
        reason: 'migration fire-floor must equal yaml info_at=$info');

    // Breadcrumb exclusion present in the count query (regression for f0b9d3).
    expect(sql.contains("error_code IS DISTINCT FROM 'event'"), isTrue,
        reason: 'count query must exclude event breadcrumbs');
    expect(sql.contains("error_code IS DISTINCT FROM 'info'"), isTrue,
        reason: 'count query must exclude info breadcrumbs');
  });
}
