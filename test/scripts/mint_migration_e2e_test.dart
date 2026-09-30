// test/scripts/mint_migration_e2e_test.dart
//
// END-TO-END coverage for scripts/mint_migration.sh — the migration-number allocator (OI-263).
// A real bare "origin" plus real clones in a throwaway dir; the actual script is run with `sh`;
// assertions are on exit codes, remote refs and file bytes — no mocks. Harness copied from
// mint_oi_e2e_test.dart (same trap notes apply):
//
// ENV SCRUBBING IS LOAD-BEARING: a surrounding git hook exports GIT_DIR / GIT_WORK_TREE, which
// override BOTH `workingDirectory:` and `-C`, so an unscrubbed child git operates on the REAL repo.
//
// LINE ENDINGS: the seed commits `.gitattributes` with `*.sh text eol=lf`, so clones get an LF
// script even under a global core.autocrlf=true (dash rejects CRLF: `set: Illegal option -`).
//
// FIXTURE vs HISTORY: the seed tree deliberately contains the shapes that broke naive numbering in
// the REAL repo — a timestamp-scheme file, a `041_chunks/` subdirectory, timestamp ledger ids — so
// `--next` on it discriminates the anchored grammar from `ls | grep -oE '^[0-9]+'`.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  env.remove('MINT_MIG_TRANSPORT');
  env.remove('MINT_MIG_TEST_HOOK_BEFORE_PUSH');
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd, {Map<String, String>? extra}) {
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

const _ledgerPath = 'backups/applied_migrations.json';
const _migDir = 'supabase/migrations';

String _seedLedger() => jsonEncode([
      for (final id in ['001', '002', '003', '20260331000001'])
        {'migration': id, 'applied_at': '2026-09-29T00:00:00+05:30', 'hash': 'sha256:x', 'applier': 't'},
    ]);

class _Fixture {
  _Fixture(this.tmp, this.remote, this.clones);
  final Directory tmp;
  final String remote;
  final List<String> clones;

  static final _src = Directory.current.path;

  static _Fixture create(String tag, {int clones = 2}) {
    final tmp = Directory.systemTemp.createTempSync('mint_mig_${tag}_');
    final remote = '${tmp.path}/remote.git';
    Directory(remote).createSync(recursive: true);
    _must(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote), 'bare init');

    final seed = '${tmp.path}/seed';
    Directory(seed).createSync();
    _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], seed), 'seed clone');
    _cfg(seed);
    Directory('$seed/$_migDir/041_chunks').createSync(recursive: true);
    for (final n in ['001_a.sql', '002_b.sql', '003_c.sql', '20260331000001_early_timestamp.sql']) {
      File('$seed/$_migDir/$n').writeAsStringSync('select 1;\n');
    }
    // A chunk file whose basename is in the allocation grammar: a `.split('/').last` parser reads
    // this as top-level migration 041 and would mint 042.
    File('$seed/$_migDir/041_chunks/041_01_rows.sql').writeAsStringSync('select 1;\n');
    Directory('$seed/backups').createSync(recursive: true);
    File('$seed/$_ledgerPath').writeAsStringSync(_seedLedger());
    Directory('$seed/scripts').createSync();
    File('$_src/scripts/mint_migration.sh').copySync('$seed/scripts/mint_migration.sh');
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
    if (r.exitCode != 0) throw StateError('$what failed (${r.exitCode}):\n${r.stdout}\n${r.stderr}');
  }

  ProcessResult mint(String clone, List<String> args, {Map<String, String>? env}) =>
      _run('sh', ['scripts/mint_migration.sh', ...args], clone,
          extra: {'MINT_MIG_TRANSPORT': 'git', ...?env});

  /// `refs/heads/mig/*` on the bare remote, as numbers.
  Set<int> remoteReservations() {
    final r = _run('git', ['for-each-ref', '--format=%(refname)', 'refs/heads/mig/'], remote);
    return {
      for (final l in (r.stdout as String).split('\n'))
        if (RegExp(r'/mig/(\d+)$').firstMatch(l.trim()) != null)
          int.parse(RegExp(r'/mig/(\d+)$').firstMatch(l.trim())!.group(1)!),
    };
  }

  String remoteRefSha(String ref) =>
      (_run('git', ['rev-parse', '--verify', ref], remote).stdout as String).trim();

  String remoteRefMessage(String ref) => (_run('git', ['log', '-1', '--format=%B', ref], remote).stdout as String);

  void dispose() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // A child may still hold a Windows handle; %TEMP% is reaped by the OS.
    }
  }
}

/// A `gh` stand-in emulating the three GitHub API calls the script makes, ON TOP OF THE BARE
/// REMOTE, so the "server" state is real git state (same shim as mint_oi_e2e_test.dart).
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

Map<String, String> _apiEnv(_Fixture f) {
  final shim = File('${f.tmp.path}/gh');
  shim.writeAsStringSync(_ghShim);
  return {
    'MINT_MIG_TRANSPORT': 'api',
    'MINT_MIG_GH_BIN': 'sh ${_fwd(shim.path)}',
    'MINT_MIG_OWNER_REPO': 'fixture/repo',
    'GH_SHIM_REMOTE': _fwd(f.remote),
  };
}

List<String> _lines(ProcessResult r) => (r.stdout as String).trim().split('\n').map((l) => l.trim()).toList();

void main() {
  test('THE ANCHORED GRAMMAR: next free is 004 — not 42 (041_chunks/ read as 041) and not 20260331000002 (timestamp file)', () {
    final f = _Fixture.create('grammar');
    addTearDown(f.dispose);
    final r = f.mint(f.clones[0], ['--next']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_lines(r)[0], 'NEXT=4', reason: 'only 001-003 are allocated numbers in the seed tree');
  });

  test('two clones minting in turn get consecutive numbers, both reserved on origin, ledger lines parse', () {
    final f = _Fixture.create('seq');
    addTearDown(f.dispose);
    final a = f.mint(f.clones[0], ['alpha_thing']);
    expect(a.exitCode, 0, reason: 'A: ${a.stdout}\n${a.stderr}');
    expect(_lines(a), ['MIG-004', 'supabase/migrations/004_alpha_thing.sql']);
    expect(File('${f.clones[0]}/$_migDir/004_alpha_thing.sql').existsSync(), isFalse,
        reason: 'no file is written unless --stub is passed');

    final b = f.mint(f.clones[1], ['beta_thing']);
    expect(b.exitCode, 0, reason: 'B: ${b.stdout}\n${b.stderr}');
    expect(_lines(b)[0], 'MIG-005');

    expect(f.remoteReservations(), {4, 5});
    final ledger = f.remoteRefMessage('refs/heads/mig/4');
    expect(ledger, contains('MIG-4 | branch main | '));
    expect(ledger, contains('| alpha_thing'));
    // Sibling-worktree visibility: a LOCAL remote-tracking ref immediately, without a fetch.
    expect(_run('git', ['rev-parse', '--verify', 'refs/remotes/origin/mig/4'], f.clones[0]).exitCode, 0);
  });

  test('a reservation already on origin is skipped: next free is max(reserved, tree, ledger)+1', () {
    final f = _Fixture.create('skip');
    addTearDown(f.dispose);
    expect(_run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/mig/6'], f.clones[0]).exitCode, 0);
    final b = f.mint(f.clones[1], ['after_six']);
    expect(b.exitCode, 0, reason: '${b.stdout}\n${b.stderr}');
    expect(_lines(b)[0], 'MIG-007');
  });

  test('--reserve N claims exactly N when free, exits 3 when taken, exits 3 when already published; never writes a file', () {
    final f = _Fixture.create('reserve');
    addTearDown(f.dispose);
    final free = f.mint(f.clones[0], ['--reserve', '9', 'nine']);
    expect(free.exitCode, 0, reason: '${free.stdout}\n${free.stderr}');
    expect(_lines(free)[0], 'MIG-009');
    expect(f.remoteReservations(), {9});
    expect(File('${f.clones[0]}/$_migDir/009_nine.sql').existsSync(), isFalse);

    final taken = f.mint(f.clones[1], ['--reserve', '9', 'nine_again']);
    expect(taken.exitCode, 3, reason: '${taken.stdout}\n${taken.stderr}');
    expect(taken.stderr as String, contains('TAKEN'));
    expect(f.remoteRefMessage('refs/heads/mig/9'), isNot(contains('nine_again')));

    final published = f.mint(f.clones[1], ['--reserve', '2', 'two']);
    expect(published.exitCode, 3, reason: '${published.stdout}\n${published.stderr}');
    expect(published.stderr as String, contains('already on'));
  });

  test('offline: exit 2, nothing reserved, nothing on stdout', () {
    final f = _Fixture.create('offline');
    addTearDown(f.dispose);
    Directory(f.remote).renameSync('${f.remote}.gone');
    addTearDown(() {
      try {
        Directory('${f.remote}.gone').renameSync(f.remote);
      } catch (_) {}
    });
    final r = f.mint(f.clones[0], ['no_network']);
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('cannot reach'));
    expect((r.stdout as String).trim(), isEmpty);
  });

  test('the race, made reachable: a reservation created INSIDE the fetch->push window is respected and the mint retries', () {
    final f = _Fixture.create('race');
    addTearDown(f.dispose);
    final a = f.clones[0];
    final aHead = (_run('git', ['rev-parse', 'HEAD'], a).stdout as String).trim();
    final hook = 'git -C ${_fwd(a)} push -q origin HEAD:refs/heads/mig/4';
    final b = f.mint(f.clones[1], ['b_wants_four'], env: {'MINT_MIG_TEST_HOOK_BEFORE_PUSH': hook});
    expect(b.exitCode, 0, reason: '${b.stdout}\n${b.stderr}');
    expect(_lines(b)[0], 'MIG-005', reason: 'B must lose the race for 4 and take 5');
    expect(f.remoteRefSha('refs/heads/mig/4'), aHead, reason: "A's reservation must not be overwritten (that is the CAS)");
    expect(f.remoteReservations(), {4, 5});
  });

  test('a hand-added file in the WORKING tree is counted: next free skips it', () {
    final f = _Fixture.create('working');
    addTearDown(f.dispose);
    final c = f.clones[0];
    File('$c/$_migDir/010_typed_by_hand.sql').writeAsStringSync('select 1;\n');
    final r = f.mint(c, ['after_ten']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_lines(r)[0], 'MIG-011');
  });

  test('a ledger id on origin/main with NO file (an applied-but-unmerged number recorded there) is counted', () {
    final f = _Fixture.create('ledgerid');
    addTearDown(f.dispose);
    final c = f.clones[0];
    final ledger = jsonDecode(_seedLedger()) as List<dynamic>;
    ledger.add({'migration': '007', 'applied_at': 'x', 'hash': 'sha256:x', 'applier': 't'});
    File('$c/$_ledgerPath').writeAsStringSync(jsonEncode(ledger));
    _run('git', ['add', '-A'], c);
    // Commit through the same safe path the repo uses is not available in a fixture: plain git.
    _run('git', ['commit', '-q', '-m', 'ledger 007'], c);
    _run('git', ['push', '-q', 'origin', 'main'], c);
    final r = f.mint(f.clones[1], ['after_ledger_seven']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_lines(r)[0], 'MIG-008');
  });

  test('a number on LOCAL main that origin/main lacks (merged, not yet pushed) is skipped from a branch cut at origin/main', () {
    final f = _Fixture.create('localmain');
    addTearDown(f.dispose);
    final c = f.clones[0];
    File('$c/$_migDir/020_merged_locally.sql').writeAsStringSync('select 1;\n');
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'local twenty'], c);
    _run('git', ['checkout', '-q', '-b', 'feature', 'origin/main'], c);
    expect(File('$c/$_migDir/020_merged_locally.sql').existsSync(), isFalse, reason: 'fixture: the branch tree must lack 20');
    final r = f.mint(c, ['after_local_main']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_lines(r)[0], 'MIG-021',
        reason: 'local main holds 20 (merged, unpushed); re-issuing it is the collision this term prevents');
  });

  test('--reserve / --release reject 0, leading zeros, junk and 4+ digits with exit 64 and reserve nothing', () {
    final f = _Fixture.create('badn');
    addTearDown(f.dispose);
    for (final bad in ['0', '007', 'x', '1234']) {
      final r = f.mint(f.clones[0], ['--reserve', bad, 'bad']);
      expect(r.exitCode, 64, reason: '$bad: ${r.stdout}\n${r.stderr}');
    }
    expect(f.mint(f.clones[0], ['--release', '0']).exitCode, 64);
    expect(f.remoteReservations(), isEmpty);
  });

  test('slug is validated: missing, empty and unsafe slugs exit 64 and reserve nothing', () {
    final f = _Fixture.create('slug');
    addTearDown(f.dispose);
    expect(f.mint(f.clones[0], []).exitCode, 64);
    expect(f.mint(f.clones[0], ['Has Caps']).exitCode, 64);
    expect(f.mint(f.clones[0], ['a/b']).exitCode, 64);
    expect(f.remoteReservations(), isEmpty);
  });

  test('--stub writes the four-tag header and refuses to overwrite; default writes nothing but prints the header', () {
    final f = _Fixture.create('stub');
    addTearDown(f.dispose);
    final c = f.clones[0];
    final plain = f.mint(c, ['plain_one']);
    expect(plain.exitCode, 0, reason: '${plain.stdout}\n${plain.stderr}');
    expect(plain.stderr as String, contains('-- Intent:'));
    expect(File('$c/$_migDir/004_plain_one.sql').existsSync(), isFalse);

    final stub = f.mint(c, ['--stub', 'stubbed_one']);
    expect(stub.exitCode, 0, reason: '${stub.stdout}\n${stub.stderr}');
    final body = File('$c/$_migDir/005_stubbed_one.sql').readAsStringSync();
    for (final tag in ['-- Intent:', '-- Destructive?:', '-- Rollback strategy:', '-- Linked diagnose-doc:']) {
      expect(body, contains(tag));
    }
    // Re-reserving a TAKEN number exits 3 at the CAS and never reaches write_stub. This tail
    // therefore does NOT test the no-clobber guard (B-pass F3) — the next test does.
    File('$c/$_migDir/005_stubbed_one.sql').writeAsStringSync('-- edited\nselect 1;\n');
    final again = f.mint(c, ['--reserve', '5', '--stub', 'stubbed_one']);
    expect(again.exitCode, 3, reason: 'mig/5 is taken');
    expect(File('$c/$_migDir/005_stubbed_one.sql').readAsStringSync(), startsWith('-- edited'));
  });

  test('ADOPTING a free number whose file already exists: --stub must NOT clobber the hand-written file (write_stub guard, B-pass F3)', () {
    final f = _Fixture.create('adoptstub', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    File('$c/$_migDir/010_x.sql').writeAsStringSync('-- edited by hand\nselect 1;\n');
    final r = f.mint(c, ['--reserve', '10', '--stub', 'x']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(File('$c/$_migDir/010_x.sql').readAsStringSync(), startsWith('-- edited by hand'));
    expect(r.stderr as String, contains('already exists'));
    expect(f.remoteReservations(), {10});
  });

  test('a number that is a SUBSTRING of another is not "the same number": --release 15 with a 150 file present succeeds (contains_line -x, B-pass F4)', () {
    final f = _Fixture.create('exactline', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    File('$c/$_migDir/150_other.sql').writeAsStringSync('select 1;\n');
    expect(f.mint(c, ['--reserve', '15', 'fifteen']).exitCode, 0);
    expect(_lines(f.mint(c, ['--next']))[1], 'UNFILED=15', reason: '15 is reserved and NOT filed (150 is a different number)');
    final r = f.mint(c, ['--release', '15']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(f.remoteReservations(), isEmpty);
  });

  test('the 3-digit number space is exhausted at 999: the next mint exits 3 and reserves nothing (B-pass F5)', () {
    final f = _Fixture.create('exhaust', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--reserve', '999', 'last']).exitCode, 0);
    final r = f.mint(c, ['one_too_many']);
    expect(r.exitCode, 3, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('exhausted'));
    expect(f.remoteReservations(), {999});
  });

  test('a mint that loses EVERY race gives up after 10 attempts (exit 3) instead of looping (B-pass F5)', () {
    final f = _Fixture.create('giveup');
    addTearDown(f.dispose);
    final a = _fwd(f.clones[0]);
    final counter = _fwd('${f.tmp.path}/hook_count');
    // Each attempt, reserve exactly the number the mint is about to try (remote max + 1). The counter
    // BOUNDS the hook: a mutated give-up guard would otherwise loop forever and hang the run instead of
    // failing an assertion.
    final hook = 'c=\$(cat $counter 2>/dev/null || echo 0); [ "\$c" -ge 15 ] && exit 0; echo \$((c+1)) > $counter; '
        'm=\$(git -C $a ls-remote origin "refs/heads/mig/*" | sed "s#.*/mig/##" | sort -n | tail -1); '
        'git -C $a push -q origin HEAD:refs/heads/mig/\$(( \${m:-3} + 1 ))';
    final r = f.mint(f.clones[1], ['always_loses'], env: {'MINT_MIG_TEST_HOOK_BEFORE_PUSH': hook});
    expect(r.exitCode, 3, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('gave up after 10 lost races'));
    expect(f.remoteReservations().length, 10, reason: 'ten attempts, ten reservations taken by the other party, none by the loser');
  });

  test('a FETCH failure mid-retry exits 2 (not "gave up" after 10 stale retries) (B-pass F5)', () {
    final f = _Fixture.create('midretry');
    addTearDown(f.dispose);
    final b = f.clones[1];
    // The hook wins the race for 4 (so the CAS is rejected AND `ls-remote` confirms the ref exists => exit 3
    // inside cas_write), then drops a `.lock` on the tracking ref that sync_refs must update, so the retry's
    // fetch fails while push and ls-remote still work. (Breaking the fetch URL instead makes the existence
    // probe fail too, which the script rightly classifies as "cannot reach origin", a different exit-2 path.)
    // origin/main must also MOVE, or the retry's fetch has nothing to update and never touches the lock.
    final a = _fwd(f.clones[0]);
    final hook = 'git -C $a push -q origin HEAD:refs/heads/mig/4 && '
        'git -C $a commit -q --allow-empty -m advance-main && git -C $a push -q origin main && '
        'touch ${_fwd(b)}/.git/refs/remotes/origin/main.lock';
    final r = f.mint(b, ['loses_fetch'], env: {'MINT_MIG_TEST_HOOK_BEFORE_PUSH': hook});
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('lost the remote mid-retry'));
    expect(f.remoteReservations(), {4}, reason: 'the loser reserved nothing');
  });

  test('the mint updates its OWN local tracking ref even in a narrow-refspec clone (no opportunistic update) (B-pass F5)', () {
    final f = _Fixture.create('narrowrefspec', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    _run('git', ['config', 'remote.origin.fetch', '+refs/heads/main:refs/remotes/origin/main'], c);
    final r = f.mint(c, ['narrow']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/mig/4'], c).exitCode, 0,
        reason: 'a sibling worktree of this clone must see the reservation at once, not at its next fetch');
  });

  test('API transport: the post-mint prune removes a reservation whose number is already published (B-pass F5)', () {
    final f = _Fixture.create('apiprune', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    final env = _apiEnv(f);
    final one = _run('sh', ['scripts/mint_migration.sh', '--stub', 'first'], c, extra: env);
    expect(one.exitCode, 0, reason: '${one.stdout}\n${one.stderr}');
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'publish 004'], c);
    expect(_run('git', ['push', '-q', 'origin', 'main'], c).exitCode, 0);
    expect(f.remoteReservations(), {4});
    final two = _run('sh', ['scripts/mint_migration.sh', 'second'], c, extra: env);
    expect(two.exitCode, 0, reason: '${two.stdout}\n${two.stderr}');
    expect(f.remoteReservations(), {5}, reason: 'mig/4 is on origin/main now; the API-transport mint prunes it');
  });

  test('--next counts a ledger id present ONLY in the working tree ledger (B-pass F5)', () {
    final f = _Fixture.create('wtledger', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    final ledger = File('$c/$_ledgerPath');
    final entries = (jsonDecode(ledger.readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>();
    entries.add({'migration': '009', 'applied_at': 'x', 'hash': 'sha256:x', 'applier': 't'});
    ledger.writeAsStringSync(jsonEncode(entries));
    expect(_lines(f.mint(c, ['--next']))[0], 'NEXT=10');
  });

  test('--next counts a file present ONLY on origin/main (local main behind, no ledger entry, nothing in the working tree) (B-pass F5)', () {
    final f = _Fixture.create('maintree');
    addTearDown(f.dispose);
    final other = f.clones[1];
    File('$other/$_migDir/020_landed.sql').writeAsStringSync('select 1;\n');
    _run('git', ['add', '-A'], other);
    _run('git', ['commit', '-q', '-m', 'land 020'], other);
    expect(_run('git', ['push', '-q', 'origin', 'main'], other).exitCode, 0);
    // clones[0] never pulled: its local main and working tree lack 020; only `--next`'s own fetch sees it.
    expect(_lines(f.mint(f.clones[0], ['--next']))[0], 'NEXT=21');
  });

  test('--live: a list_migrations snapshot is counted, but unprefixed names and 14-digit versions are NOT read as numbers', () {
    final f = _Fixture.create('live');
    addTearDown(f.dispose);
    final c = f.clones[0];
    final snap = File('${f.tmp.path}/live.json')
      ..writeAsStringSync(jsonEncode({
        'migrations': [
          {'version': '20260929003128', 'name': '009_from_live'},
          // Would read as 138 -> next 140 if the parser were unanchored, or as 20260929003128 by a digit grab.
          {'version': '20260906000000', 'name': 'hermes_pass_fixes_138_139'},
          {'version': '20260907000000', 'name': 'usage_counters'},
        ],
      }));
    final r = f.mint(c, ['--live', _fwd(snap.path), 'with_live']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_lines(r)[0], 'MIG-010');
    expect(r.stderr as String, isNot(contains('live prod was NOT consulted')));
    expect(r.stderr as String, contains('--live sees only live names that carry an NNN_ prefix'),
        reason: 'a passing --live must not read as full coverage of prod (69 of 145 live rows are unprefixed)');
    // The same snapshot as a BARE array parses too.
    final bare = File('${f.tmp.path}/live_bare.json')
      ..writeAsStringSync(jsonEncode([
        {'version': '20260929003128', 'name': '030_bare_array'},
      ]));
    final r2 = f.mint(f.clones[1], ['--live', _fwd(bare.path), 'bare']);
    expect(r2.exitCode, 0, reason: '${r2.stdout}\n${r2.stderr}');
    expect(_lines(r2)[0], 'MIG-031');
  });

  test('without --live the mint says plainly that live prod was not consulted', () {
    final f = _Fixture.create('nolive', clones: 1);
    addTearDown(f.dispose);
    final r = f.mint(f.clones[0], ['no_live']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('live prod was NOT consulted'));
  });

  test('--live with an unreadable file exits 64 before reserving anything', () {
    final f = _Fixture.create('livebad', clones: 1);
    addTearDown(f.dispose);
    final r = f.mint(f.clones[0], ['--live', '${f.tmp.path}/nope.json', 'x']);
    expect(r.exitCode, 64);
    expect(f.remoteReservations(), isEmpty);
  });

  test('--release deletes an UNFILED reservation only; a number FILED in the working tree is refused', () {
    final f = _Fixture.create('release');
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--reserve', '12', 'orphan']).exitCode, 0);
    expect(f.mint(c, ['--stub', 'filed_thirteen']).exitCode, 0); // 13, file written
    expect(f.remoteReservations(), {12, 13});

    final refused = f.mint(c, ['--release', '13']);
    expect(refused.exitCode, 3, reason: '${refused.stdout}\n${refused.stderr}');
    expect(refused.stderr as String, contains('FILED'));

    final ok = f.mint(c, ['--release', '12']);
    expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
    expect(f.remoteReservations(), {13});
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/mig/12'], c).exitCode, isNot(0));
    expect(f.mint(c, ['--release', '12']).exitCode, 3, reason: 'already released');
  });

  test('--release refuses a PUBLISHED number', () {
    final f = _Fixture.create('releasepub', clones: 1);
    addTearDown(f.dispose);
    // 002 is on origin/main but has no reservation ref; the published guard fires first.
    final r = f.mint(f.clones[0], ['--release', '2']);
    expect(r.exitCode, 3, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('PUBLISHED'));
  });

  test('--release refuses a number filed on a SIBLING local branch (a worktree in flight), naming the ledger line', () {
    final f = _Fixture.create('sibling');
    addTearDown(f.dispose);
    final c = f.clones[0];
    _run('git', ['checkout', '-q', '-b', 'sib'], c);
    final minted = f.mint(c, ['--stub', 'sibling_thing']);
    expect(minted.exitCode, 0, reason: '${minted.stdout}\n${minted.stderr}');
    final n = int.parse(RegExp(r'MIG-(\d+)').firstMatch(minted.stdout as String)!.group(1)!);
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'sib files $n'], c);
    _run('git', ['checkout', '-q', 'main'], c);
    final r = f.mint(c, ['--release', '$n']);
    expect(r.exitCode, 3, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('BRANCH this clone knows'));
    expect(f.remoteReservations(), {n});
    expect(f.mint(c, ['--next']).stdout as String, contains('UNFILED=\n'),
        reason: 'a number filed on a sibling branch is not "unfiled"');
  });

  test('API transport: create-commit + create-ref via gh; duplicate create is refused (422) and the mint retries', () {
    final f = _Fixture.create('api');
    addTearDown(f.dispose);
    final env = _apiEnv(f);
    final a = _run('sh', ['scripts/mint_migration.sh', 'via_api'], f.clones[0], extra: env);
    expect(a.exitCode, 0, reason: '${a.stdout}\n${a.stderr}');
    expect(_lines(a)[0], 'MIG-004');
    expect(f.remoteReservations(), {4});
    expect(f.remoteRefMessage('refs/heads/mig/4'), contains('| via_api'));
    expect(_run('git', ['rev-parse', '--verify', 'refs/remotes/origin/mig/4'], f.clones[0]).exitCode, 0);

    final hook = 'git -C ${_fwd(f.clones[0])} push -q origin HEAD:refs/heads/mig/5';
    final b = _run('sh', ['scripts/mint_migration.sh', 'b_via_api'], f.clones[1],
        extra: {...env, 'MINT_MIG_TEST_HOOK_BEFORE_PUSH': hook});
    expect(b.exitCode, 0, reason: '${b.stdout}\n${b.stderr}');
    expect(_lines(b)[0], 'MIG-006');
  });

  test('--reserve N also works through the API transport (taken -> 3, free -> reserved)', () {
    final f = _Fixture.create('apireserve');
    addTearDown(f.dispose);
    final env = _apiEnv(f);
    final free = _run('sh', ['scripts/mint_migration.sh', '--reserve', '40', 'adopt_forty'], f.clones[0], extra: env);
    expect(free.exitCode, 0, reason: '${free.stdout}\n${free.stderr}');
    final taken = _run('sh', ['scripts/mint_migration.sh', '--reserve', '40', 'again'], f.clones[1], extra: env);
    expect(taken.exitCode, 3, reason: '${taken.stdout}\n${taken.stderr}');
    expect(taken.stderr as String, contains('TAKEN'));
  });

  test('--release / --next see a number filed on a REMOTE-ONLY branch (a cloud session\'s push this clone never checked out)', () {
    final f = _Fixture.create('remotebranch');
    addTearDown(f.dispose);
    final a = f.clones[0];
    final b = f.clones[1];
    _run('git', ['checkout', '-q', '-b', 'claude/cloud-work'], a);
    final minted = f.mint(a, ['--stub', 'cloud_thing']);
    expect(minted.exitCode, 0, reason: '${minted.stdout}\n${minted.stderr}');
    final n = int.parse(RegExp(r'MIG-(\d+)').firstMatch(minted.stdout as String)!.group(1)!);
    _run('git', ['add', '-A'], a);
    _run('git', ['commit', '-q', '-m', 'cloud file $n'], a);
    expect(_run('git', ['push', '-q', 'origin', 'claude/cloud-work'], a).exitCode, 0);
    // Clone B has never checked that branch out; it only knows it as a remote-tracking ref.
    expect(_run('git', ['fetch', '-q', 'origin'], b).exitCode, 0);
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/heads/claude/cloud-work'], b).exitCode, isNot(0),
        reason: 'fixture: no LOCAL branch may exist in clone B');
    final r = f.mint(b, ['--release', '$n']);
    expect(r.exitCode, 3, reason: 'released a reservation whose file lives on a pushed branch:\n${r.stdout}\n${r.stderr}');
    expect(f.remoteReservations(), {n});
    expect(f.mint(b, ['--next']).stdout as String, contains('UNFILED=\n'));
  });

  test('--prune does NOT prune a base number just because its letter-suffix follow-up is published (003b is not 003)', () {
    final f = _Fixture.create('prunesuffix');
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--reserve', '5', 'base_unmerged']).exitCode, 0);
    File('$c/$_migDir/005b_followup.sql').writeAsStringSync('select 1;\n');
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'publish only the 005b follow-up'], c);
    expect(_run('git', ['push', '-q', 'origin', 'main'], c).exitCode, 0);

    final p = f.mint(c, ['--prune']);
    expect(p.exitCode, 0, reason: '${p.stdout}\n${p.stderr}');
    expect(f.remoteReservations(), {5}, reason: 'the base file 005_*.sql is still unmerged; its reservation must survive');

    // Positive control: once the BASE itself is published, the same prune removes it.
    File('$c/$_migDir/005_base_unmerged.sql').writeAsStringSync('select 1;\n');
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'publish the base'], c);
    expect(_run('git', ['push', '-q', 'origin', 'main'], c).exitCode, 0);
    expect(f.mint(c, ['--prune']).exitCode, 0);
    expect(f.remoteReservations(), isEmpty);
  });

  test('--prune deletes only reservations whose number is on origin/main, and drops the local tracking ref', () {
    final f = _Fixture.create('prune');
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--stub', 'published_one']).exitCode, 0); // 4 + file
    _run('git', ['add', '-A'], c);
    _run('git', ['commit', '-q', '-m', 'file 004'], c);
    expect(_run('git', ['push', '-q', 'origin', 'main'], c).exitCode, 0);
    expect(f.mint(c, ['--reserve', '5', 'in_flight']).exitCode, 0);
    expect(f.remoteReservations(), {4, 5});

    final p = f.mint(c, ['--prune']);
    expect(p.exitCode, 0, reason: '${p.stdout}\n${p.stderr}');
    expect(f.remoteReservations(), {5});
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/mig/4'], c).exitCode, isNot(0),
        reason: 'local tracking ref for the pruned reservation must be gone');
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/mig/5'], c).exitCode, 0);
  });

  test('--next reports the next free number and the reserved-but-unfiled list', () {
    final f = _Fixture.create('next');
    addTearDown(f.dispose);
    final c = f.clones[0];
    expect(f.mint(c, ['--reserve', '7', 'unfiled_seven']).exitCode, 0);
    final r = f.mint(c, ['--next']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(_lines(r), ['NEXT=8', 'UNFILED=7']);
    // Adopted by hand as a working-tree file: filed now, drops out of UNFILED.
    File('$c/$_migDir/007_adopted.sql').writeAsStringSync('select 1;\n');
    final r2 = f.mint(c, ['--next']);
    expect(_lines(r2), ['NEXT=8', 'UNFILED=']);
  });

  test('a push REJECTED for a reason other than a lost race exits 2, is not retried, and names the reason', () {
    final f = _Fixture.create('policyreject', clones: 1);
    addTearDown(f.dispose);
    final c = f.clones[0];
    final hook = File('${f.remote}/hooks/pre-receive');
    hook.writeAsStringSync('#!/bin/sh\necho "policy: mig/* pushes are refused here" >&2\nexit 1\n');
    if (!Platform.isWindows) _run('chmod', ['+x', hook.path], f.remote);
    final r = f.mint(c, ['policy_rejected']);
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('policy: mig/* pushes are refused here'));
    expect(r.stderr as String, contains('not a lost race'));
    expect('policy: mig/* pushes are refused here'.allMatches(r.stderr as String).length, 1,
        reason: 'a policy rejection must not be retried as if N were taken');
    expect(f.remoteReservations(), isEmpty);
  });
}
