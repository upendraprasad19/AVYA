// test/scripts/mint_oi_e2e_test.dart
//
// END-TO-END coverage for scripts/mint_oi.sh — the OI-number allocator (spec
// docs/superpowers/specs/2026-09-12-oi-allocator-design.md). A real bare
// "origin" plus real clones in a throwaway dir; the actual script is run with
// `sh`; assertions are on exit codes, remote refs and board bytes — no mocks.
//
// ENV SCRUBBING IS LOAD-BEARING: a surrounding git hook exports GIT_DIR /
// GIT_WORK_TREE, which override BOTH `workingDirectory:` and `-C`, so an
// unscrubbed child git operates on the REAL repo
// (memory/feedback_mistake_git_hook_env_leak).
//
// LINE ENDINGS: the SEED copy of scripts/mint_oi.sh is byte-for-byte (copySync,
// LF), but clone0/clone1 CHECK IT OUT — under this machine's global
// core.autocrlf=true that would be CRLF, which Git Bash's sh tolerates and dash
// rejects (`set: Illegal option -`). So the seed commits a `.gitattributes` with
// `*.sh text eol=lf`, exactly as the real repo does, and the clones get LF.
// Review round 1 found the CR trap; round 2 found the fixture still had it.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  env.remove('MINT_OI_TRANSPORT');
  env.remove('MINT_OI_TEST_HOOK_BEFORE_PUSH');
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String>? extra}) {
  final env = _cleanEnv();
  if (extra != null) env.addAll(extra);
  return Process.runSync(exe, args,
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
}

String _fwd(String p) => p.replaceAll('\\', '/');
String _fileUri(String path) => 'file:///${_fwd(path)}';

const _openBoard = 'docs/audit/open_issues.md';
const _closedBoard = 'docs/audit/closed_issues.md';

/// A seeded board: OI-1..3 with every field build_oi_index.dart:39 requires.
String _seedOpenBoard() {
  final b = StringBuffer('# Open Issues — fixture\n\n## How this file is used\n\n');
  for (var n = 1; n <= 3; n++) {
    b.writeln('## OI-$n — seeded issue number $n\n');
    b.writeln('- **Status**: OPEN');
    b.writeln('- **Blocked on**: none');
    b.writeln('- **Verified**: never\n');
  }
  return b.toString();
}

/// One fixture per test: a bare origin with `main` seeded, plus N clones that
/// each carry a copy of the script under test.
class _Fixture {
  _Fixture(this.tmp, this.remote, this.clones);
  final Directory tmp;
  final String remote;
  final List<String> clones;

  static final _src = Directory.current.path;

  static _Fixture create(String tag, {int clones = 2}) {
    final tmp = Directory.systemTemp.createTempSync('mint_oi_${tag}_');
    final remote = '${tmp.path}/remote.git';
    Directory(remote).createSync(recursive: true);
    _must(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote), 'bare init');

    final seed = '${tmp.path}/seed';
    Directory(seed).createSync();
    _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], seed), 'seed clone');
    _cfg(seed);
    File('$seed/$_openBoard').createSync(recursive: true);
    File('$seed/$_openBoard').writeAsStringSync(_seedOpenBoard());
    File('$seed/$_closedBoard').writeAsStringSync('# Closed issues\n');
    Directory('$seed/scripts').createSync();
    File('$_src/scripts/mint_oi.sh').copySync('$seed/scripts/mint_oi.sh');
    File('$seed/.gitattributes').writeAsStringSync('*.sh text eol=lf\n');
    _must(_run('git', ['add', '-A'], seed), 'seed add');
    _must(_run('git', ['commit', '-q', '-m', 'seed'], seed), 'seed commit');
    _must(_run('git', ['push', '-q', '-u', 'origin', 'main'], seed), 'seed push');

    final list = <String>[];
    for (var i = 0; i < clones; i++) {
      final c = '${tmp.path}/clone$i';
      Directory(c).createSync();
      _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], c), 'clone $i');
      _cfg(c);
      list.add(c);
    }
    return _Fixture(tmp, remote, list);
  }

  static void _cfg(String repo) {
    _run('git', ['config', 'user.email', 't@example.invalid'], repo);
    _run('git', ['config', 'user.name', 'T'], repo);
  }

  static void _must(ProcessResult r, String what) {
    if (r.exitCode != 0) {
      throw StateError('$what failed (${r.exitCode}):\n${r.stdout}\n${r.stderr}');
    }
  }

  ProcessResult mint(String clone, List<String> args,
          {Map<String, String>? env}) =>
      _run('sh', ['scripts/mint_oi.sh', ...args], clone,
          extra: {'MINT_OI_TRANSPORT': 'git', ...?env});

  /// `refs/heads/oi/*` on the bare remote, as numbers.
  Set<int> remoteReservations() {
    final r = _run('git', ['for-each-ref', '--format=%(refname)', 'refs/heads/oi/'],
        remote);
    return {
      for (final l in (r.stdout as String).split('\n'))
        if (RegExp(r'/oi/(\d+)$').firstMatch(l.trim()) != null)
          int.parse(RegExp(r'/oi/(\d+)$').firstMatch(l.trim())!.group(1)!)
    };
  }

  String remoteRefSha(String ref) =>
      (_run('git', ['rev-parse', '--verify', ref], remote).stdout as String).trim();

  String remoteRefMessage(String ref) =>
      (_run('git', ['log', '-1', '--format=%B', ref], remote).stdout as String);

  String board(String clone) => File('$clone/$_openBoard').readAsStringSync();

  void dispose() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // A child may still hold a Windows handle; %TEMP% is reaped by the OS.
    }
  }
}

void main() {
  test('two clones minting in turn get consecutive numbers, both reserved on origin, ledger lines parse',
      () {
    final f = _Fixture.create('seq');
    addTearDown(f.dispose);
    final a = f.mint(f.clones[0], ['alpha issue']);
    expect(a.exitCode, 0, reason: 'A: ${a.stdout}\n${a.stderr}');
    expect((a.stdout as String).trim(), 'OI-4');

    final b = f.mint(f.clones[1], ['beta issue']);
    expect(b.exitCode, 0, reason: 'B: ${b.stdout}\n${b.stderr}');
    expect((b.stdout as String).trim(), 'OI-5');

    expect(f.remoteReservations(), {4, 5});
    final ledger = f.remoteRefMessage('refs/heads/oi/4');
    expect(ledger, contains('OI-4 | branch main | '));
    expect(ledger, contains('| alpha issue'));

    // The stub landed, with the em-dash heading the board parser needs and
    // every field build_oi_index.dart:39 requires.
    final board = f.board(f.clones[0]);
    expect(board, contains('\n## OI-4 — alpha issue\n'));
    final fieldRe = RegExp(r'^-\s+\*\*(Status|Blocked on|Verified)\*\*:\s*\**\s*(.*)$',
        multiLine: true);
    final tail = board.substring(board.indexOf('## OI-4'));
    expect(fieldRe.allMatches(tail).map((m) => m.group(1)).toSet(),
        {'Status', 'Blocked on', 'Verified'});
    expect(tail, contains('- **Status**: OPEN'));

    // Sibling-worktree visibility: the reservation is a LOCAL remote-tracking
    // ref immediately, without a further fetch.
    final local = _run('git', ['rev-parse', '--verify', 'refs/remotes/origin/oi/4'],
        f.clones[0]);
    expect(local.exitCode, 0);
  });

  test('a reservation that already exists on origin is skipped: next free is max(reserved, boards)+1',
      () {
    final f = _Fixture.create('skip');
    addTearDown(f.dispose);
    // Someone reserved oi/6 by hand (pointing at any commit).
    expect(
        _run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/oi/6'], f.clones[0])
            .exitCode,
        0);
    final b = f.mint(f.clones[1], ['after six']);
    expect(b.exitCode, 0, reason: '${b.stdout}\n${b.stderr}');
    expect((b.stdout as String).trim(), 'OI-7');
  });

  test('--reserve N claims exactly N when free, fails 3 when taken, fails 3 when already published; never appends',
      () {
    final f = _Fixture.create('reserve');
    addTearDown(f.dispose);
    final before = f.board(f.clones[0]);

    final free = f.mint(f.clones[0], ['--reserve', '9', 'nine']);
    expect(free.exitCode, 0, reason: '${free.stdout}\n${free.stderr}');
    expect((free.stdout as String).trim(), 'OI-9');
    expect(f.remoteReservations(), {9});
    expect(f.board(f.clones[0]), before, reason: '--reserve must not append a stub');

    final taken = f.mint(f.clones[1], ['--reserve', '9', 'nine again']);
    expect(taken.exitCode, 3, reason: '${taken.stdout}\n${taken.stderr}');
    expect(taken.stderr as String, contains('TAKEN'));
    expect(f.remoteRefMessage('refs/heads/oi/9'), contains('| nine'));
    expect(f.remoteRefMessage('refs/heads/oi/9'), isNot(contains('nine again')));

    final published = f.mint(f.clones[1], ['--reserve', '2', 'two']);
    expect(published.exitCode, 3, reason: '${published.stdout}\n${published.stderr}');
    expect(published.stderr as String, contains('already on'));
  });

  test('offline: exit 2, nothing reserved, board byte-identical', () {
    final f = _Fixture.create('offline');
    addTearDown(f.dispose);
    final before = f.board(f.clones[0]);
    // Make origin unreachable by renaming the bare repo out from under the URL.
    Directory(f.remote).renameSync('${f.remote}.gone');
    addTearDown(() {
      try {
        Directory('${f.remote}.gone').renameSync(f.remote);
      } catch (_) {}
    });
    final r = f.mint(f.clones[0], ['no network']);
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('cannot reach'));
    expect(f.board(f.clones[0]), before);
    expect((r.stdout as String).trim(), isEmpty);
  });

  test('the race, made reachable: a reservation created INSIDE the fetch->push window is respected and the mint retries',
      () {
    final f = _Fixture.create('race');
    addTearDown(f.dispose);
    final a = f.clones[0];
    final aHead = (_run('git', ['rev-parse', 'HEAD'], a).stdout as String).trim();
    // Between B's sync and B's CAS write, A grabs oi/4 (pointing at A's HEAD).
    final hook = 'git -C ${_fwd(a)} push -q origin HEAD:refs/heads/oi/4';
    final b = f.mint(f.clones[1], ['b wants four'],
        env: {'MINT_OI_TEST_HOOK_BEFORE_PUSH': hook});
    expect(b.exitCode, 0, reason: '${b.stdout}\n${b.stderr}');
    expect((b.stdout as String).trim(), 'OI-5',
        reason: 'B must lose the race for 4 and take 5');
    expect(f.remoteRefSha('refs/heads/oi/4'), aHead,
        reason: 'A\'s reservation must not be overwritten (that is the CAS)');
    expect(f.remoteReservations(), {4, 5});
  });

  test('a hand-typed number already on the WORKING board is skipped, not re-issued',
      () {
    final f = _Fixture.create('working');
    addTearDown(f.dispose);
    final c = f.clones[0];
    File('$c/$_openBoard').writeAsStringSync(
        '${f.board(c)}\n## OI-10 — typed by hand, uncommitted\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n');
    final r = f.mint(c, ['after the hand-typed one']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect((r.stdout as String).trim(), 'OI-11');
  });

  test('a number on LOCAL main that origin/main lacks (merged, not yet pushed) is skipped',
      () {
    final f = _Fixture.create('localmain');
    addTearDown(f.dispose);
    final c = f.clones[0];
    // Commit OI-20 on local main WITHOUT pushing -- the §4.13 merged-but-unpushed state.
    File('$c/$_openBoard').writeAsStringSync(
        '${f.board(c)}\n## OI-20 — merged locally, unpushed\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n');
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'local twenty'], c);
    // Then mint from a WORKTREE BRANCH cut from origin/main -- whose board lacks
    // 20, as does origin/main's. Only the local-main term can see 20 here.
    // (Minting from main itself would let the working-board term absorb the
    // case: the first version of this test did exactly that and its mutation
    // reddened nothing -- rule 21, "green for the wrong reason".)
    _run('git', ['checkout', '-q', '-b', 'feature', 'origin/main'], c);
    expect(f.board(c), isNot(contains('OI-20')), reason: 'fixture: the branch board must lack 20');
    final r = f.mint(c, ['after local main']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect((r.stdout as String).trim(), 'OI-21',
        reason: 'local main holds 20 (merged, unpushed); re-issuing it is the collision this term prevents');
  });

  test('--reserve rejects 0 and leading zeros with exit 64 and reserves nothing', () {
    final f = _Fixture.create('badn');
    addTearDown(f.dispose);
    for (final bad in ['0', '007', 'x']) {
      final r = f.mint(f.clones[0], ['--reserve', bad, 'bad']);
      expect(r.exitCode, 64, reason: '$bad: ${r.stdout}\n${r.stderr}');
    }
    expect(f.remoteReservations(), isEmpty);
  });

  test('--release deletes an UNFILED reservation only; a filed one is refused', () {
    final f = _Fixture.create('release');
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--reserve', '12', 'orphan']).exitCode, 0);
    expect(f.mint(c, ['filed thirteen']).exitCode, 0); // 13, stub on the local board
    expect(f.remoteReservations(), {12, 13});

    final refused = f.mint(c, ['--release', '13']);
    expect(refused.exitCode, 3, reason: '${refused.stdout}\n${refused.stderr}');
    expect(refused.stderr as String, contains('FILED'));

    final ok = f.mint(c, ['--release', '12']);
    expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
    expect(f.remoteReservations(), {13});
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/12'], c).exitCode,
        isNot(0));

    final absent = f.mint(c, ['--release', '12']);
    expect(absent.exitCode, 3);
  });

  test('--release refuses a number filed on a SIBLING local branch (a worktree in flight), naming the ledger line',
      () {
    final f = _Fixture.create('sibling');
    addTearDown(f.dispose);
    final c = f.clones[0];
    // Branch `sib` mints N and commits its stub; we return to main, whose
    // board lacks N and whose origin/main lacks N -- the state a SECOND
    // worktree sees when it is told "reserved-but-unfiled".
    _run('git', ['checkout', '-q', '-b', 'sib'], c);
    final minted = f.mint(c, ['sibling issue']);
    expect(minted.exitCode, 0, reason: '${minted.stdout}\n${minted.stderr}');
    // Derive N from the mint itself (the seeded boards hold OI-1..3, so this
    // is 4 today -- but the test must not depend on that).
    final n = int.parse(RegExp(r'OI-(\d+)').firstMatch(minted.stdout as String)!.group(1)!);
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'sib files OI-$n'], c);
    _run('git', ['checkout', '-q', 'main'], c);
    final r = f.mint(c, ['--release', '$n']);
    expect(r.exitCode, 3, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('LOCAL BRANCH'));
    expect(f.remoteReservations(), {n});
    // And --next does not list it as unfiled either.
    final next = f.mint(c, ['--next']);
    expect((next.stdout as String), contains('UNFILED=\n'));
  });
}
