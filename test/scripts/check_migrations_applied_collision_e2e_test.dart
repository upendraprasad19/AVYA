// test/scripts/check_migrations_applied_collision_e2e_test.dart
//
// END-TO-END: runs the REAL scripts/check_migrations_applied.dart (Gate 14)
// against a throwaway repo, proving the OI-255 collision check is actually
// WIRED into the gate binary, not just correct in the pure lib. The pure
// test (migration_collision_lib_test.dart) cannot prove that — it only
// proves the function is correct, not that main() calls it before exiting.
// Same rationale as retire_worktree_e2e_test.dart's header.
//
// Regression shape (rule 21): BEFORE this batch, two files sharing a bare
// numeric prefix each independently satisfied the "unapplied" check via
// `a.startsWith(prefix)` (either applied entry matches either file), so
// Gate 14 printed PASS for both `template-stable-identity`'s and
// `ops-alerting`'s 145/146 files right up until a human noticed during a
// `git pull` before a merge (OI-255). This test reproduces that shape with a
// NEW (non-grandfathered) prefix and asserts Gate 14 now fails it.

@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  final repoRoot = Directory.current.path;

  /// The Dart binary to spawn the gate with.
  ///
  /// NOT `Platform.resolvedExecutable`: under `flutter test` that resolves to
  /// the flutter_tester binary, not dart, so the spawn never returns and the
  /// suite HANGS rather than failing (test/scripts/oi_numbering_lib_test.dart
  /// documents this trap after it cost a >10-minute hang; the same fallback
  /// chain is reused verbatim from test/scripts/cron_registry_snapshot_gate_test.dart).
  String dartBinOf() {
    final override = Platform.environment['DART_BIN_OVERRIDE'];
    if (override != null && File(override).existsSync()) return override;
    final which = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      ['dart'],
      stdoutEncoding: utf8,
    );
    if (which.exitCode == 0) {
      final first = (which.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      if (first.isNotEmpty) {
        final dir = File(first).parent.path.replaceAll(r'\', '/');
        for (final c in [
          '$dir/cache/dart-sdk/bin/dart.exe',
          '$dir/cache/dart-sdk/bin/dart',
        ]) {
          if (File(c).existsSync()) return c;
        }
      }
    }
    return 'dart';
  }

  final dartBin = dartBinOf();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate14_collision_');
    Directory('${tmp.path}/supabase/migrations').createSync(recursive: true);
    Directory('${tmp.path}/backups').createSync(recursive: true);
    Directory('${tmp.path}/scripts').createSync(recursive: true);
    File('$repoRoot/scripts/check_migrations_applied.dart')
        .copySync('${tmp.path}/scripts/check_migrations_applied.dart');
    File('$repoRoot/scripts/migration_collision_lib.dart')
        .copySync('${tmp.path}/scripts/migration_collision_lib.dart');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void writeMigration(String name) {
    File('${tmp.path}/supabase/migrations/$name')
        .writeAsStringSync('-- test fixture, no-op\nselect 1;\n');
  }

  void writeAppliedSnapshot(List<String> migrationIds) {
    File('${tmp.path}/backups/applied_migrations.json').writeAsStringSync(jsonEncode([
      for (final id in migrationIds)
        {'migration': id, 'applied_at': '2026-09-28T00:00:00+05:30', 'hash': 'sha256:x'},
    ]));
  }

  ProcessResult runGate() => Process.runSync(
        dartBin,
        ['scripts/check_migrations_applied.dart'],
        workingDirectory: tmp.path,
      );

  test('THE OI-255 SCENARIO: two files sharing a NEW prefix, each with its '
      'own applied-snapshot entry, still FAILS the gate', () {
    // Before this fix, both of these independently satisfied the
    // "unapplied" check's `a.startsWith(prefix)` — that is precisely how the
    // real 145/146 collision passed Gate 14 twice.
    writeMigration('148_coach_extraction_locked_fields.sql');
    writeMigration('148_alert_sql_job_failures_v2.sql');
    writeAppliedSnapshot([
      '148_coach_extraction_locked_fields',
      '148_alert_sql_job_failures_v2',
    ]);

    final r = runGate();
    expect(r.exitCode, isNonZero,
        reason: 'a bare-prefix collision must fail even when both files are '
            'individually present in the applied snapshot — that is exactly '
            'the shape that let 145/146 through undetected');
    expect('${r.stderr}', contains('collision'));
    expect('${r.stderr}', contains('148_coach_extraction_locked_fields.sql'));
    expect('${r.stderr}', contains('148_alert_sql_job_failures_v2.sql'));
  });

  test('the known 145/146 grandfathered collisions do NOT fail the gate', () {
    writeMigration('145_alert_sql_job_failures.sql');
    writeMigration('145_workout_templates_stable_delete.sql');
    writeMigration('146_alert_cron_job_silent.sql');
    writeMigration('146_workout_templates_delete_trigger_insert_path.sql');
    writeAppliedSnapshot([
      '145_alert_sql_job_failures',
      '145_workout_templates_stable_delete',
      '146_alert_cron_job_silent',
      '146_workout_templates_delete_trigger_insert_path',
    ]);

    final r = runGate();
    expect(r.exitCode, isZero,
        reason: 'these four applied, immutable files must not start failing '
            'every future commit in the repo — see the grandfather list in '
            'scripts/migration_collision_lib.dart');
  });

  test('unique prefixes with no collision still pass as before (no '
      'regression on the existing happy path)', () {
    writeMigration('147_alert_client_errors_spike_breadth.sql');
    writeAppliedSnapshot(['147_alert_client_errors_spike_breadth']);

    final r = runGate();
    expect(r.exitCode, isZero);
    expect('${r.stdout}', contains('PASS'));
  });
}
