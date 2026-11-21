// test/scripts/check_migration_number_reserved_e2e_test.dart
//
// END-TO-END for scripts/check_migration_number_reserved.dart (OI-263): the REAL gate binary
// against a scratch clone of a scratch bare origin, so the git plumbing (three-dot range, staged
// adds, `--no-renames`, ls-tree at origin/main, local reservation refs, the bounded ls-remote
// fallback, the offline skip) is exercised rather than assumed.
//
// FIXTURE vs HISTORY: origin/main holds 001-003 plus a timestamp file and a `041_chunks/` file,
// the shapes that broke naive parsing in the real repo.

@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

ProcessResult _run(String exe, List<String> args, String cwd) => runSpawn(exe, args,
    why: '$exe ${args.join(' ')} (scratch clone of a scratch bare origin)',
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8);

String _fileUri(String p) => 'file:///${p.replaceAll('\\', '/')}';

void main() {
  late Directory tmp;
  late String remote;
  late String work;
  final repoRoot = Directory.current.path;
  final dart = dartBin();

  ProcessResult git(List<String> args, {String? cwd}) => _run('git', args, cwd ?? work);

  void must(ProcessResult r, String what) {
    if (r.exitCode != 0) throw StateError('$what failed: ${r.stdout}${r.stderr}');
  }

  void put(String rel, [String body = 'select 1;\n']) {
    final f = File('$work/$rel')..createSync(recursive: true);
    f.writeAsStringSync(body);
  }

  ProcessResult gate([List<String> extra = const []]) =>
      _run(dart, ['scripts/check_migration_number_reserved.dart', ...extra], work);

  /// Reserve N on origin (as the mint does) and fetch it into refs/remotes/origin/mig/N.
  void reserve(int n, {bool fetchLocally = true}) {
    must(git(['push', '-q', 'origin', 'HEAD:refs/heads/mig/$n']), 'reserve $n');
    if (fetchLocally) {
      must(git(['fetch', '-q', 'origin', '+refs/heads/mig/$n:refs/remotes/origin/mig/$n']), 'fetch mig/$n');
    } else {
      // A push to refs/heads/mig/N opportunistically updates refs/remotes/origin/mig/N under the
      // default refspec; drop it so the fixture really is "reserved on the remote only".
      git(['update-ref', '-d', 'refs/remotes/origin/mig/$n']);
    }
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mig_reserved_');
    remote = '${tmp.path}/remote.git';
    work = '${tmp.path}/work';
    Directory(remote).createSync(recursive: true);
    must(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote), 'bare init');
    Directory(work).createSync();
    must(_run('git', ['clone', '-q', _fileUri(remote), '.'], work), 'clone');
    git(['config', 'user.email', 't@example.invalid']);
    git(['config', 'user.name', 'T']);
    for (final n in ['001_a.sql', '002_b.sql', '003_c.sql', '20260331000001_early_timestamp.sql']) {
      put('supabase/migrations/$n');
    }
    put('supabase/migrations/041_chunks/041_01_rows.sql');
    put('backups/applied_migrations.json', jsonEncode([
      for (final id in ['001', '002', '003'])
        {'migration': id, 'applied_at': 'x', 'hash': 'sha256:x', 'applier': 't'},
    ]));
    Directory('$work/scripts').createSync(recursive: true);
    for (final f in [
      'check_migration_number_reserved.dart',
      'migration_number_reserved_lib.dart',
      'migration_collision_lib.dart',
    ]) {
      File('$repoRoot/scripts/$f').copySync('$work/scripts/$f');
    }
    must(git(['add', '-A']), 'seed add');
    must(git(['commit', '-q', '-m', 'seed']), 'seed commit');
    must(git(['push', '-q', '-u', 'origin', 'main']), 'seed push');
    must(git(['checkout', '-q', '-b', 'feature']), 'branch');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('nothing added: passes at once (vacuous, and it must not need the network)', () {
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('no added allocated-number migration files'));
  });

  test('a NEW file with NO mig/N reservation FAILS', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    final r = gate();
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('mig/4'));
  });

  test('the same file WITH a local reservation ref passes', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    reserve(4);
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('a reservation that exists ONLY on the remote (no local tracking ref) passes via the bounded ls-remote fallback', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    reserve(4, fetchLocally: false);
    expect(git(['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/mig/4']).exitCode, isNot(0),
        reason: 'fixture: there must be no local ref');
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    // A SKIP also exits 0, so exit code alone cannot tell "found it on the remote" from "could not
    // look". The fallback is only proven if the reservation lookup was NOT skipped.
    expect('${r.stdout}', isNot(contains('SKIPPED')));
    expect('${r.stdout}', contains('PASS'));
  });

  test('OFFLINE with no local ref: SKIPS the reservation check, says so, exits 0 (fail-open, never a silent pass)', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    Directory(remote).renameSync('$remote.gone');
    final r = gate();
    Directory('$remote.gone').renameSync(remote);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('SKIPPED'));
  });

  test('a COMMITTED (not staged) new file on the branch is caught through the three-dot range', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    must(git(['commit', '-q', '-m', 'add 004']), 'commit');
    final r = gate();
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
  });

  test('a FAILED committed-range diff (orphan branch, no merge base) is a SKIP that says so — never the "no added files" PASS', () {
    must(git(['checkout', '-q', '--orphan', 'orph']), 'orphan');
    must(git(['rm', '-rq', '--cached', '.']), 'unstage all');
    put('supabase/migrations/777_orphan.sql');
    must(git(['add', 'supabase/migrations/777_orphan.sql']), 'add');
    must(git(['commit', '-q', '-m', 'orphan add']), 'orphan commit');
    expect(git(['diff', '--name-only', '--diff-filter=A', 'origin/main...HEAD']).exitCode, isNot(0),
        reason: 'fixture: the three-dot diff must actually fail (no merge base)');
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('SKIP'));
    expect('${r.stdout}', isNot(contains('PASS: no added allocated-number migration files')),
        reason: 'an unreadable range is not "nothing added"');
  });

  test('a COMMITTED rename cannot dodge the range check either: `git mv 003 004` + commit is an ADD of 004 (B-pass F1)', () {
    must(git(['mv', 'supabase/migrations/003_c.sql', 'supabase/migrations/004_c.sql']), 'mv');
    must(git(['commit', '-q', '-m', 'renumber 003 -> 004']), 'commit rename');
    final r = gate();
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('004_c.sql'));
  });

  test('THREE-dot range: a file origin/main DELETED after the fork is not "added" on this branch (B-pass F2)', () {
    final other = '${tmp.path}/other';
    Directory(other).createSync();
    must(_run('git', ['clone', '-q', _fileUri(remote), '.'], other), 'other clone');
    _run('git', ['config', 'user.email', 't@example.invalid'], other);
    _run('git', ['config', 'user.name', 'T'], other);
    must(_run('git', ['rm', '-q', 'supabase/migrations/003_c.sql'], other), 'other rm');
    must(_run('git', ['commit', '-q', '-m', 'delete 003 on main'], other), 'other commit');
    must(_run('git', ['push', '-q', 'origin', 'main'], other), 'other push');
    must(git(['fetch', '-q', 'origin']), 'fetch');
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    must(git(['commit', '-q', '-m', 'add 004']), 'commit 004');
    reserve(4);
    final r = gate();
    // A two-dot (tree-to-tree) diff would report 003_c.sql as ADDED here and demand a mig/3.
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('a reservation present as a LOCAL ref is honoured with the remote UNREACHABLE — and not reported as skipped (B-pass B14)', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    reserve(4);
    Directory(remote).renameSync('$remote.gone');
    final r = gate();
    Directory('$remote.gone').renameSync(remote);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', isNot(contains('SKIPPED')), reason: 'the local ref must answer without touching the network');
    expect('${r.stdout}', contains('PASS'));
  });

  test('same number as a DIFFERENT file on origin/main FAILS even though mig/2 is reserved', () {
    put('supabase/migrations/002_other.sql');
    must(git(['add', '-A']), 'add');
    reserve(2);
    final r = gate();
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('002_b.sql'));
  });

  test('a RENAME cannot dodge the check: `git mv 003 004` is an ADD of 004 (before: --diff-filter=A alone read it as R)', () {
    must(git(['mv', 'supabase/migrations/003_c.sql', 'supabase/migrations/004_c.sql']), 'mv');
    final r = gate();
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('004_c.sql'));
  });

  test('MERGE of main into the branch: files that arrive from origin/main are published, not "unreserved"', () {
    // Another clone lands 004 on main. Its reservation is pruned after merge, exactly as in life.
    final other = '${tmp.path}/other';
    Directory(other).createSync();
    must(_run('git', ['clone', '-q', _fileUri(remote), '.'], other), 'other clone');
    _run('git', ['config', 'user.email', 't@example.invalid'], other);
    _run('git', ['config', 'user.name', 'T'], other);
    File('$other/supabase/migrations/004_landed_elsewhere.sql').writeAsStringSync('select 1;\n');
    must(_run('git', ['add', '-A'], other), 'other add');
    must(_run('git', ['commit', '-q', '-m', 'land 004'], other), 'other commit');
    must(_run('git', ['push', '-q', 'origin', 'main'], other), 'other push');
    must(git(['fetch', '-q', 'origin']), 'fetch');
    // Conflicted-merge shape: the merged-in file is STAGED and shows as an add.
    must(git(['merge', '--no-commit', '--no-ff', 'origin/main']), 'merge');
    expect(git(['diff', '--cached', '--name-only']).stdout as String, contains('004_landed_elsewhere.sql'),
        reason: 'fixture: the file must be in the staged set');
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('out of scope: a new chunk-dir file and a new timestamp-scheme file are not judged', () {
    put('supabase/migrations/041_chunks/041_02_more.sql');
    put('supabase/migrations/20261001000001_ts.sql');
    must(git(['add', '-A']), 'add');
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('letter-suffix follow-up: base published => passes; base unknown => FAILS', () {
    put('supabase/migrations/002b_followup.sql');
    must(git(['add', '-A']), 'add');
    expect(gate().exitCode, 0);
    put('supabase/migrations/090b_orphan_followup.sql');
    must(git(['add', '-A']), 'add');
    final r = gate();
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('090'));
  });

  test('--warn-only reports the violation but exits 0', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    final r = gate(['--warn-only']);
    expect(r.exitCode, 0);
    expect('${r.stderr}', contains('FAIL'));
  });

  test('no origin/main ref at all: SKIPS naming what it did not check', () {
    put('supabase/migrations/004_new.sql');
    must(git(['add', '-A']), 'add');
    must(git(['update-ref', '-d', 'refs/remotes/origin/main']), 'drop ref');
    final r = gate();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('SKIP'));
  });
}
