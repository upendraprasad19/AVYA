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

/// A `gh` stand-in that emulates the three GitHub API calls mint_oi.sh makes,
/// ON TOP OF THE BARE REMOTE, so the "server" state is real git state and the
/// post-success fetch in the script works exactly as it does against GitHub.
///   POST   repos/X/git/commits  -> git commit-tree in the bare repo, prints sha
///   POST   repos/X/git/refs     -> `update-ref --stdin create` (fails if exists) => 422 text
///   DELETE repos/X/git/refs/... -> update-ref -d
const _ghShim = r'''#!/bin/sh
set -eu
[ "${1:-}" = api ] || { echo "shim: unsupported: $*" >&2; exit 1; }
shift
method=GET; path=''; tree=''; ref=''; sha=''; msg=''
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method=$2; shift ;;
    -f) kv=$2; shift; k=${kv%%=*}; v=${kv#*=}
        case "$k" in tree) tree=$v ;; ref) ref=$v ;; sha) sha=$v ;; message) msg=$v ;; esac ;;
    --jq) shift ;;
    repos/*) path=$1 ;;
  esac
  shift
done
case "$method:$path" in
  POST:*/git/commits)
    GIT_AUTHOR_NAME=shim GIT_AUTHOR_EMAIL=s@x GIT_COMMITTER_NAME=shim GIT_COMMITTER_EMAIL=s@x \
      git --git-dir="$GH_SHIM_REMOTE" commit-tree "$tree" -m "$msg" ;;
  POST:*/git/refs)
    if printf 'create %s %s\n' "$ref" "$sha" | git --git-dir="$GH_SHIM_REMOTE" update-ref --stdin 2>/dev/null; then
      printf '{"ref":"%s"}\n' "$ref"
    else
      echo 'gh: Reference already exists (HTTP 422)' >&2; exit 1
    fi ;;
  DELETE:*/git/refs/*)
    r=${path#*/git/refs/}; git --git-dir="$GH_SHIM_REMOTE" update-ref -d "refs/$r" ;;
  *) echo "shim: unsupported $method $path" >&2; exit 1 ;;
esac
''';

/// Writes the shim into the fixture and returns the env that routes the
/// script's `gh` calls to it.
Map<String, String> _apiEnv(_Fixture f) {
  final shim = File('${f.tmp.path}/gh');
  shim.writeAsStringSync(_ghShim);
  return {
    'MINT_OI_TRANSPORT': 'api',
    'MINT_OI_GH_BIN': 'sh ${_fwd(shim.path)}',
    'MINT_OI_OWNER_REPO': 'fixture/repo',
    'GH_SHIM_REMOTE': _fwd(f.remote),
  };
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

  test('API transport: create-commit + create-ref via gh; duplicate create is refused (422) and the mint retries',
      () {
    final f = _Fixture.create('api');
    addTearDown(f.dispose);
    final env = _apiEnv(f);
    final a = _run('sh', ['scripts/mint_oi.sh', 'via api'], f.clones[0], extra: env);
    expect(a.exitCode, 0, reason: '${a.stdout}\n${a.stderr}');
    expect((a.stdout as String).trim(), 'OI-4');
    expect(f.remoteReservations(), {4});
    expect(f.remoteRefMessage('refs/heads/oi/4'), contains('| via api'));
    // The API path must ALSO leave the local tracking ref behind (fetched,
    // since the object was created server-side).
    expect(_run('git', ['rev-parse', '--verify', 'refs/remotes/origin/oi/4'], f.clones[0]).exitCode, 0);

    // Race through the API: reserve 5 by hand inside B's window; B must take 6.
    final hook = 'git -C ${_fwd(f.clones[0])} push -q origin HEAD:refs/heads/oi/5';
    final b = _run('sh', ['scripts/mint_oi.sh', 'b via api'], f.clones[1],
        extra: {...env, 'MINT_OI_TEST_HOOK_BEFORE_PUSH': hook});
    expect(b.exitCode, 0, reason: '${b.stdout}\n${b.stderr}');
    expect((b.stdout as String).trim(), 'OI-6');
  });

  test('--prune deletes only reservations whose number is on origin/main, and drops the local tracking ref',
      () {
    final f = _Fixture.create('prune');
    addTearDown(f.dispose);
    final c = f.clones[0];
    // 4: minted AND then published (stub committed + pushed to main).
    expect(f.mint(c, ['published one']).exitCode, 0);
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'file OI-4'], c);
    expect(_run('git', ['push', '-q', 'origin', 'main'], c).exitCode, 0);
    // 5: reserved, not published.
    expect(f.mint(c, ['--reserve', '5', 'in flight']).exitCode, 0);
    expect(f.remoteReservations(), {4, 5});

    final p = f.mint(c, ['--prune']);
    expect(p.exitCode, 0, reason: '${p.stdout}\n${p.stderr}');
    expect(f.remoteReservations(), {5});
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/4'], c).exitCode,
        isNot(0), reason: 'local tracking ref for the pruned reservation must be gone');
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/5'], c).exitCode, 0);
  });

  test('--next reports the next free number and the reserved-but-unfiled list', () {
    final f = _Fixture.create('next');
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--reserve', '7', 'unfiled seven']).exitCode, 0);
    final r = f.mint(c, ['--next']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final lines = (r.stdout as String).trim().split('\n').map((l) => l.trim()).toList();
    expect(lines[0], 'NEXT=8');
    expect(lines[1], 'UNFILED=7');

    // Phase 2: the reserved number is then ADOPTED by hand on the local board
    // (uncommitted). It is filed now, so it must drop out of UNFILED while
    // NEXT stays 8 -- this is the assertion the local-board exclusion exists for.
    File('$c/$_openBoard').writeAsStringSync(
        '${f.board(c)}\n## OI-7 — adopted by hand\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n');
    final r2 = f.mint(c, ['--next']);
    expect(r2.exitCode, 0, reason: '${r2.stdout}\n${r2.stderr}');
    final lines2 = (r2.stdout as String).trim().split('\n').map((l) => l.trim()).toList();
    expect(lines2[0], 'NEXT=8');
    expect(lines2[1], 'UNFILED=');
  });

  test('a title beginning with "-" mints after the "--" end-of-options marker (B-pass F1)', () {
    final f = _Fixture.create('dashtitle', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    // Without `--` the parser reads the title as an unknown flag: exit 64,
    // nothing written. That contract is pinned too, so the two paths cannot
    // silently swap.
    final bare = f.mint(c, ['-leading dash title']);
    expect(bare.exitCode, 64, reason: '${bare.stdout}\n${bare.stderr}');
    expect(bare.stderr as String, contains("goes after '--'"));
    expect(f.remoteReservations(), isEmpty);
    final r = f.mint(c, ['--', '-leading dash title']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect((r.stdout as String).trim(), 'OI-4');
    expect(f.board(c), contains('\n## OI-4 — -leading dash title\n'));
    expect(f.remoteReservations(), {4});
  });

  test('a push REJECTED by the remote for a reason other than a lost race exits 2, is not retried, and names the reason (B-pass F4)',
      () {
    final f = _Fixture.create('policyreject', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    // A pre-receive hook on the bare remote refuses every push, the way a
    // branch-protection rule or a server policy would. git prints
    // `! [remote rejected]` for this exactly as it does for a lost lease, so a
    // stderr-substring classifier alone cannot tell them apart -- the ref's
    // EXISTENCE on the remote can.
    final hook = File('${f.remote}/hooks/pre-receive');
    hook.writeAsStringSync('#!/bin/sh\necho "policy: oi/* pushes are refused here" >&2\nexit 1\n');
    if (!Platform.isWindows) _run('chmod', ['+x', hook.path], f.remote);
    final r = f.mint(c, ['policy rejected']);
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, 2, reason: all);
    expect(r.stderr as String, contains('policy: oi/* pushes are refused here'));
    expect(r.stderr as String, contains('not a lost race'));
    // ONE attempt, not ten: the hook's line appears once.
    expect('policy: oi/* pushes are refused here'.allMatches(r.stderr as String).length, 1,
        reason: 'a policy rejection must not be retried as if N were taken');
    expect(f.remoteReservations(), isEmpty);
    expect(f.board(c), isNot(contains('OI-4')), reason: 'nothing may be written on a refused reservation');
  });
}
