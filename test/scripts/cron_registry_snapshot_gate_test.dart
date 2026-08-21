@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Rule 24 mutation proof for Gate 31's snapshot input (OI-132).
///
/// Gate 31 originally enforced cron-registry parity by scanning
/// `supabase/migrations/*.sql` for `cron.schedule(...)`. That input has a
/// structural blind spot: a migration applied WITHOUT a file is not merely
/// un-gated, it is unseeable, and the gate reports green. That is not
/// hypothetical — `log_table_retention` ran on prod 2026-08-15 and left no
/// file, and four cron jobs (two row-destructive) went unregistered for five
/// days while Gate 31 passed.
///
/// These tests run the REAL gate against REAL temp repos and assert it goes
/// RED. A test that only asserts the happy path would be the Gate-44 shape the
/// gate itself is being hardened against.
void main() {
  late Directory tmp;
  final repoRoot = Directory.current.path;
  /// The Dart binary to spawn the gate with.
  ///
  /// NOT `Platform.resolvedExecutable`: under `flutter test` that resolves to
  /// the flutter_tester binary, not dart, so the spawn never returns and the
  /// suite HANGS rather than failing. The repo already documents this trap at
  /// test/scripts/oi_numbering_lib_test.dart:284 after it cost that suite a
  /// >10-minute hang — and it cost this one another before the note was found.
  /// Prefer the SDK exe beside the Flutter wrapper (the wrapper takes the SDK
  /// update lock and shells out to git on EVERY call); fall back to `dart`.
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
    tmp = Directory.systemTemp.createTempSync('gate31_');
    Directory('${tmp.path}/supabase/migrations').createSync(recursive: true);
    Directory('${tmp.path}/docs/operations').createSync(recursive: true);
    Directory('${tmp.path}/backups').createSync(recursive: true);
    Directory('${tmp.path}/scripts').createSync(recursive: true);
    File('${repoRoot}/scripts/check_cron_registry.dart')
        .copySync('${tmp.path}/scripts/check_cron_registry.dart');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void writeSnapshot(List<String> names) {
    File('${tmp.path}/backups/live_cron_jobs.json').writeAsStringSync(jsonEncode({
      'jobs': [
        for (final n in names)
          {'jobid': 1, 'jobname': n, 'schedule': '0 0 * * *', 'active': true}
      ]
    }));
  }

  void writeRegistry(List<String> names) {
    File('${tmp.path}/docs/operations/CRON_REGISTRY.md')
        .writeAsStringSync('# Cron Job Registry\n\n${names.map((n) => '| x | `$n` |').join('\n')}\n');
  }

  ProcessResult runGate() => Process.runSync(
        dartBin,
        ['scripts/check_cron_registry.dart'],
        workingDirectory: tmp.path,
      );

  test('THE OI-132 SCENARIO: a job live in the snapshot with NO migration file '
      'and no registry entry is caught', () {
    // No .sql file at all — exactly what log_table_retention left behind.
    writeSnapshot(['jrd_retention_daily', 'already_registered']);
    writeRegistry(['already_registered']);

    final r = runGate();
    expect(r.exitCode, isNonZero,
        reason: 'the whole point of the snapshot input: a fileless migration '
            'must not be able to hide a live cron job from this gate');
    expect('${r.stderr}', contains('jrd_retention_daily'));
    expect('${r.stderr}', contains('LIVE on the project'),
        reason: 'the message must tell the reader WHICH input caught it, '
            'otherwise they will look in the migrations and find nothing');
  });

  test('a MISSING snapshot fails loudly rather than silently downgrading to '
      'the migration scan alone', () {
    writeRegistry(['anything']);
    File('${tmp.path}/supabase/migrations/001_x.sql')
        .writeAsStringSync("select cron.schedule('anything','0 0 * * *',\$\$select 1;\$\$);");
    // deliberately no backups/live_cron_jobs.json

    final r = runGate();
    expect(r.exitCode, isNonZero,
        reason: 'failing open here would restore the exact blind spot the '
            'snapshot was added to close — a gate that passes because one of '
            'its two inputs quietly vanished');
    expect('${r.stderr}', contains('live_cron_jobs.json'));
  });

  test('an EMPTY snapshot is refused, not treated as "nothing to check"', () {
    writeSnapshot(<String>[]);
    writeRegistry(['anything']);

    final r = runGate();
    expect(r.exitCode, isNonZero,
        reason: 'a vacuous snapshot would make every snapshot assertion pass '
            'by checking nothing — the Gate-44 shape');
    expect('${r.stderr}', contains('zero jobs'));
  });

  test('a MALFORMED snapshot is refused', () {
    File('${tmp.path}/backups/live_cron_jobs.json').writeAsStringSync('{not json');
    writeRegistry(['anything']);

    final r = runGate();
    expect(r.exitCode, isNonZero);
    expect('${r.stderr}', contains('unreadable'));
  });

  test('green path: every snapshot job registered -> exit 0', () {
    writeSnapshot(['a_job', 'b_job']);
    writeRegistry(['a_job', 'b_job']);

    final r = runGate();
    expect(r.exitCode, 0, reason: 'stdout: ${r.stdout}\nstderr: ${r.stderr}');
    expect('${r.stdout}', contains('PASS'));
  });

  test('NO supabase/migrations directory at all still enforces input B', () {
    // Input A's "migrations dir absent -> SKIP" used to sit ABOVE the snapshot
    // read and exit 0, so a tree without that directory passed having consulted
    // neither input — the never-ran-so-it-passed shape input B exists to close,
    // reintroduced by the edit that added it. Ordering is the fix; this is its
    // mutation proof (move the snapshot read back below the SKIP and this
    // reddens, while every other test stays green).
    tmp.deleteSync(recursive: true);
    tmp = Directory.systemTemp.createTempSync('gate31_');
    Directory('${tmp.path}/docs/operations').createSync(recursive: true);
    Directory('${tmp.path}/backups').createSync(recursive: true);
    Directory('${tmp.path}/scripts').createSync(recursive: true);
    File('$repoRoot/scripts/check_cron_registry.dart')
        .copySync('${tmp.path}/scripts/check_cron_registry.dart');
    // deliberately NO supabase/migrations
    writeSnapshot(['live_but_unregistered']);
    writeRegistry(['something_else']);

    final r = runGate();
    expect(r.exitCode, isNonZero,
        reason: 'a tree with no migrations directory must still be judged by '
            'the live snapshot, not waved through');
    expect('${r.stderr}', contains('live_but_unregistered'));
  });

  test('the migration-scan input still works and is NOT masked by a clean '
      'snapshot', () {
    // Regression guard for the re-scope itself: adding input B must not make
    // input A vacuous. A job declared in a migration but absent from the
    // registry must still fail, even when the snapshot is entirely clean.
    writeSnapshot(['registered_job']);
    writeRegistry(['registered_job']);
    File('${tmp.path}/supabase/migrations/001_x.sql').writeAsStringSync(
        "select cron.schedule('unregistered_from_file','0 0 * * *',\$\$select 1;\$\$);");

    final r = runGate();
    expect(r.exitCode, isNonZero);
    expect('${r.stderr}', contains('unregistered_from_file'));
    expect('${r.stderr}', contains('declared in a migration file'));
  });
}
