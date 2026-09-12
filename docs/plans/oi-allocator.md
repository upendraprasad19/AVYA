# OI-number allocator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make it structurally impossible for two sessions (laptop worktrees *or* cloud clones) to mint the same OI number, by reserving numbers as `oi/N` branches on the GitHub remote and refusing to commit an unreserved number.

**Architecture:** A POSIX-sh allocator (`scripts/mint_oi.sh`) turns GitHub's "a ref cannot be created twice" into a compare-and-swap — `gh api` on the laptop (no `git push`, so no pre-push hook cost), `git push --force-with-lease=<ref>:` in the cloud. The existing detector gate gains a working-tree arm (closes OI-176) and a reservation check. The SessionStart hook prints the next free number and the one command to use. The board stays the single source of truth for content; a reservation is a name plus a provenance line.

**Tech Stack:** POSIX `sh` + `git` (+ `gh` where present); Dart 3 for the gate and hook (`scripts/*.dart`, `dart:io`); `flutter_test` e2e tests spawning real `git` against bare temp remotes; existing pure lib `scripts/oi_numbering_lib.dart` (`parseBoard`, `mergeBoards`, `findCollisions`, `nextFreeNumber`).

**Spec:** `docs/superpowers/specs/2026-09-12-oi-allocator-design.md` (committed `6b6932f6`; §1 / §8 corrected in this plan's commit).

**Branch / worktree:** `oi-allocator` at `.claude/worktrees/oi-allocator`. Every edit and commit happens there (§4.13). Commits go through `sh scripts/safe_commit.sh "<msg>"` — never raw `git commit`.

## Global Constraints

- Blast radius **platform** (`scripts/**` review machinery is individually pinned): plan-review record with `review_rounds: ≥2`, `verdict: converged`, `bpass: accepted` before the merge (§4.12.3); `/code-review` B-pass is self-initiated before `safe_merge.sh` (§4.3).
- Reservation namespace is **exactly** `refs/heads/oi/<digits>` — no slug suffix (spec Q4). Cloud credential writes `refs/heads/**` only; `refs/oi/*` → 403 (spike, 2026-09-12).
- Mint **fails closed** offline (exit 2, nothing written). Every gate/hook path **fails open** to SKIPPED / silence, never to PASS (spec §5).
- Every `Process.runSync` that reads a board passes `stdoutEncoding: utf8` — `systemEncoding` mangles the em-dash and turns a full board into zero headings (`check_oi_numbering_unique.dart:53-60`).
- Every new `test/scripts/*_test.dart` that spawns a process carries `@Timeout(Duration(minutes: 6))` + `library;` at the top, scrubs `GIT_*` from the child env (`feedback_mistake_git_hook_env_leak`), and has a teardown that never throws (§4.9).
- The Dart binary for spawning a gate in tests is resolved as in `test/scripts/cron_registry_snapshot_gate_test.dart:34-58` (`DART_BIN_OVERRIDE` → `<flutter>/cache/dart-sdk/bin/dart` → `dart`), **never** `Platform.resolvedExecutable` (it is `flutter_tester` under `flutter test` and hangs the suite).
- Rule 21: every mutation named below is **applied and confirmed applied** (`grep -c` the mutated token) before its run is believed; the diagnose-doc records what reddened. A mutation that fails to compile is not a proof.
- No `TBD`/`TODO`/`<...>`/`???` anywhere in a diagnose-doc — the validator rejects them.
- Never type an OI number by hand from this batch onward — including in this batch's own docs. The only new board heading this batch writes is OI-176's status flip (existing number).

---

## File map

| Path | Responsibility | Task |
|---|---|---|
| `scripts/mint_oi.sh` (new) | the allocator: sync → next free → ledger commit → CAS write → stub; `--reserve`, `--prune`, `--next`, `--no-append` | 1, 2 |
| `test/scripts/mint_oi_e2e_test.dart` (new) | real bare remote + two clones; race via test seam; `gh` shim for the API transport | 1, 2 |
| `scripts/check_oi_numbering_unique.dart` (modify) | Check B′ working-tree arm (OI-176) + Check C reservation | 3, 4 |
| `test/scripts/oi_numbering_gate_e2e_test.dart` (new) | the OI-176 shape; reservation present / absent / unreachable; title-edit false-positive guard; published-number exemption | 3, 4 |
| `docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-f3a9c1.md` (new) | rule-22 diagnose-doc for the OI-176 fix | 3 |
| `docs/audit/open_issues.md` (modify) | OI-176 → CLOSED; "how to file" rule | 3, 6 |
| `docs/audit/gate_test_ledger.yaml:434-438` (modify) | extend `evidence:` with the new mutations | 4 |
| `scripts/discipline_hook.dart` (modify) | SessionStart OI line (Dart-native, LOCAL refs only, no fetch) | 5 |
| `test/scripts/discipline_hook_oi_line_e2e_test.dart` (new) | hook prints next free + unfiled; does not fetch; silent without origin/main | 5 |
| `docs/blast_radius.yaml` (modify) | pin `scripts/mint_oi.sh` + `scripts/discipline_hook.dart` at `platform` | 6 |
| `CLAUDE.md` §7 OI-uniqueness row; `docs/handbook/process/oi-allocator.md` (new); spec §3.4 wording | docs | 6 |
| `docs/plan-reviews/oi-allocator.md` (new) + `docs/reviews/oi-allocator-bpass.md` (from `/code-review`) | keystone record for the merge gate | 7 |

---

### Task 1: `scripts/mint_oi.sh` — git transport, retry, `--reserve`, offline refusal, stub

**Files:**
- Create: `scripts/mint_oi.sh`
- Create: `test/scripts/mint_oi_e2e_test.dart`

**Interfaces:**
- Produces: `sh scripts/mint_oi.sh [--no-append] [--reserve N] "<title>"` → stdout `OI-N`, exit `0`; exit `2` remote unreachable (nothing written); exit `3` taken / retries exhausted; exit `64` usage. Env knobs: `MINT_OI_TRANSPORT=auto|api|git`, `MINT_OI_REMOTE`, `MINT_OI_GH_BIN`, `MINT_OI_OWNER_REPO`, `MINT_OI_TEST_HOOK_BEFORE_PUSH`. After a successful mint, `refs/remotes/<remote>/oi/N` exists locally.
- Produces (for Task 4's gate): the invariant *"a number new on a branch has `refs/heads/oi/N` on the remote"*.

- [ ] **Step 1: Write the failing e2e tests (git transport)**

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from the worktree root): `flutter test test/scripts/mint_oi_e2e_test.dart`
Expected: every test FAILS in fixture setup — `_Fixture.create` throws `PathNotFoundException` copying `scripts/mint_oi.sh` (the script does not exist yet). That is the intended red: the test cannot pass without the script.

- [ ] **Step 3: Write the script**

```sh
#!/bin/sh
# scripts/mint_oi.sh — the OI-number allocator.
#
# Reserves the next free OI number as the remote branch `oi/N`, using the
# remote's own "a ref cannot be created twice" as a compare-and-swap, then
# appends a board stub. Two sessions on two machines cannot both get N: the
# second create is refused by GitHub (HTTP 422 via the API; `[rejected]`
# with `--force-with-lease=<ref>:` via git) and this script retries with N+1.
#
# Spec: docs/superpowers/specs/2026-09-12-oi-allocator-design.md
#
# Usage:
#   sh scripts/mint_oi.sh "<title>"              reserve next free N, append stub, print OI-N
#   sh scripts/mint_oi.sh --no-append "<title>"  reserve + print only
#   sh scripts/mint_oi.sh --reserve N "<title>"  claim EXACTLY N (for a number filed
#                                                before the allocator existed); never appends
#   sh scripts/mint_oi.sh --prune                delete oi/N whose N is on origin/main's boards
#                                                (laptop/API only — via git it would pay the
#                                                pre-push hook per branch; refused unless
#                                                MINT_OI_TRANSPORT=git was set EXPLICITLY)
#   sh scripts/mint_oi.sh --release N            delete an UNFILED reservation (N on neither
#                                                origin/main's boards nor the local board) —
#                                                the only way an orphan ever goes away
#   sh scripts/mint_oi.sh --next                 read-only: prints NEXT=<n> and UNFILED=<n,n>
#
# An orphan (reserved, never filed — a session died between the CAS and the
# stub) may also be ADOPTED: write `## OI-N — …` by hand; Check C passes
# because oi/N exists. The gate bans UNRESERVED numbers, not hand-typing.
#
# Exit codes:
#   0   done
#   2   cannot reach the remote — NOTHING was written. A number cannot be
#       reserved offline; a local-only mint is exactly how collisions are born.
#   3   taken (--reserve), or 10 consecutive races lost
#   64  usage
#
# Transport (MINT_OI_TRANSPORT=auto|api|git, default auto):
#   api — `gh api`: two POSTs (git/commits, git/refs). Preferred on the laptop
#         because it is NOT a `git push`, so scripts/pre-push.sh (unconditional
#         `flutter analyze` + fail-safe full suite on an empty range) never runs.
#   git — `git push --force-with-lease=refs/heads/oi/N:` (empty expect = "must
#         not exist"; receive-pack enforces old-sha=0 under the ref lock). The
#         cloud has no `gh` and no hooks, so this is its path.
#   auto — api when `gh` is on PATH, else git.
#
# Other env: MINT_OI_REMOTE (origin) · MINT_OI_GH_BIN (gh; word-split on
# purpose so a test can pass "sh /path/shim") · MINT_OI_OWNER_REPO (override the
# owner/repo parsed from the remote URL) · MINT_OI_TEST_HOOK_BEFORE_PUSH (test
# seam: run with `sh -c` between the sync and the CAS write, nowhere else).
set -eu

TAG='[mint_oi]'
BOARD_OPEN=docs/audit/open_issues.md
BOARD_CLOSED=docs/audit/closed_issues.md
REMOTE=${MINT_OI_REMOTE:-origin}
TRANSPORT=${MINT_OI_TRANSPORT:-auto}
# "explicit" means the caller ASKED for the git transport (tests, a cloud user
# who accepts the cost) -- an explicit `auto` is not a request for git.
case "${MINT_OI_TRANSPORT:-}" in git) TRANSPORT_EXPLICIT=1 ;; *) TRANSPORT_EXPLICIT='' ;; esac
GH=${MINT_OI_GH_BIN:-gh}
MAX_ATTEMPTS=10

usage() {
  cat >&2 <<'USAGE'
usage: sh scripts/mint_oi.sh [--no-append] "<title>"
       sh scripts/mint_oi.sh --reserve N "<title>"
       sh scripts/mint_oi.sh --release N
       sh scripts/mint_oi.sh --prune | --next
USAGE
  exit 64
}

MODE=mint
APPEND=1
RESERVE_N=''
RELEASE_N=''
TITLE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --no-append) APPEND=0 ;;
    --reserve)
      [ $# -ge 2 ] && [ -n "$2" ] || usage   # an EMPTY value would vanish from the validator's word list below
      RESERVE_N=$2
      APPEND=0
      shift ;;
    --release)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      RELEASE_N=$2
      MODE=release
      shift ;;
    --prune) MODE=prune ;;
    --next) MODE=next ;;
    -h|--help) usage ;;
    -*) echo "$TAG unknown flag: $1" >&2; usage ;;
    *) TITLE=$1 ;;
  esac
  shift
done
# A positive integer with no leading zero: `oi/007` would parse as 7 on the Dart
# side and as the string "007" here, so it would never prune and never block 7.
for n in $RESERVE_N $RELEASE_N; do
  case "$n" in ''|0*|*[!0-9]*) echo "$TAG --reserve/--release need a positive integer without leading zeros" >&2; usage ;; esac
done
if [ "$MODE" = mint ] && [ -z "$TITLE" ]; then
  echo "$TAG a title is required" >&2
  usage
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "$TAG not inside a git repository" >&2; exit 2; }
cd "$ROOT"

if [ "$TRANSPORT" = auto ]; then
  if command -v gh >/dev/null 2>&1; then TRANSPORT=api; else TRANSPORT=git; fi
fi
case "$TRANSPORT" in api|git) ;; *) echo "$TAG MINT_OI_TRANSPORT must be auto|api|git" >&2; exit 64 ;; esac

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)

# ---- sync: the local copy of the allocator state IS git's ref store ----------
# Fetch every reservation into refs/remotes/<remote>/oi/* (pruning ones deleted
# upstream) and refresh <remote>/main, whose boards are the published numbers.
# On the laptop refs/remotes/ lives in the SHARED .git/, so one worktree's
# fetch is every worktree's fetch.
# Bounded: coreutils `timeout` exists on Git Bash and Linux; without it the
# fetch runs unbounded. A real SSH outage otherwise blocks for the TCP connect
# timeout (tens of seconds) — a renamed fixture fails instantly either way.
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi
}
# Captures stderr into SYNC_ERR so "offline" is never the only diagnosis: a
# shared-.git fetch lock held by a sibling worktree, a hook rejection, or a
# missing SSH key all fail here too, and each says so in git's own words.
SYNC_ERR=''
sync_refs() {
  SYNC_ERR=$(bounded git fetch --quiet --prune "$REMOTE" \
    "+refs/heads/oi/*:refs/remotes/$REMOTE/oi/*" \
    "+refs/heads/main:refs/remotes/$REMOTE/main" 2>&1 >/dev/null)
}

# ---- readers -----------------------------------------------------------------
# Every OI number on both boards at $1 (a rev), or in the working tree when $1
# is empty. ASCII prefix only — immune to the em-dash mis-decoding that once
# blanked the Dart gate (check_oi_numbering_unique.dart:53-60).
board_numbers() {
  if [ -n "${1:-}" ]; then
    { git show "$1:$BOARD_OPEN" 2>/dev/null || true
      git show "$1:$BOARD_CLOSED" 2>/dev/null || true; }
  else
    { cat "$BOARD_OPEN" 2>/dev/null || true
      cat "$BOARD_CLOSED" 2>/dev/null || true; }
  fi | grep -oE '^## OI-[0-9]+' | grep -oE '[0-9]+$' || true
}

reserved_numbers() {
  git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE/oi/" \
    | sed 's#.*/oi/##' | grep -E '^[0-9]+$' | sort -n || true
}

# LOCAL main is included because §4.13's merge-locally-then-push workflow makes
# "merged but not yet pushed" the common state: a number on local main that
# origin/main lacks is still taken. Absent ref (a fresh cloud clone) => empty.
local_main_numbers() {
  if git rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then
    board_numbers refs/heads/main
  fi
}

next_free() {
  n=$( { reserved_numbers; board_numbers "refs/remotes/$REMOTE/main"; local_main_numbers; board_numbers ''; } \
       | sort -n | tail -1 )
  echo $(( ${n:-0} + 1 ))
}

contains_line() { # $1 = newline-separated haystack, $2 = exact line
  printf '%s\n' "$1" | grep -qx -- "$2"
}

# ---- the ledger commit ------------------------------------------------------
# Parentless, on <remote>/main's TREE (already on the server ⇒ zero object
# upload), message = the provenance line. Author is pinned so a clone without
# user.name still mints; who minted is in the MESSAGE, not the author.
ledger_commit() { # $1 = N ; prints the local sha
  tree=$(git rev-parse "refs/remotes/$REMOTE/main^{tree}")
  stamp=$(date +%Y-%m-%dT%H:%M:%S%z)
  GIT_AUTHOR_NAME=mint_oi GIT_AUTHOR_EMAIL=mint_oi@local \
  GIT_COMMITTER_NAME=mint_oi GIT_COMMITTER_EMAIL=mint_oi@local \
    git commit-tree "$tree" -m "OI-$1 | branch $BRANCH | $stamp | $TITLE"
}

owner_repo() {
  if [ -n "${MINT_OI_OWNER_REPO:-}" ]; then echo "$MINT_OI_OWNER_REPO"; return; fi
  git remote get-url "$REMOTE" 2>/dev/null \
    | sed -nE 's#^(git@github\.com:|https://github\.com/)([^/]+)/([^/]+)$#\2/\3#p' \
    | sed 's/\.git$//'
}

# ---- the compare-and-swap write ----------------------------------------------
# $1 = N, $2 = local ledger sha. Returns 0 created (RESULT_SHA set), 3 taken,
# 2 unreachable. The distinction between 3 and 2 is the whole point: taken
# means retry; unreachable means stop and write nothing.
cas_write() {
  case "$TRANSPORT" in
    git)
      if err=$(git push --quiet --force-with-lease="refs/heads/oi/$1:" \
                 "$REMOTE" "$2:refs/heads/oi/$1" 2>&1); then
        RESULT_SHA=$2; return 0
      fi
      case "$err" in
        *"stale info"*|*"already exists"*|*"rejected"*|*"failed to lock"*) return 3 ;;
        *) echo "$TAG push failed: $err" >&2; return 2 ;;
      esac ;;
    api)
      repo=$(owner_repo)
      [ -n "$repo" ] || { echo "$TAG cannot derive owner/repo from the $REMOTE URL (set MINT_OI_OWNER_REPO)" >&2; return 2; }
      tree=$(git rev-parse "refs/remotes/$REMOTE/main^{tree}")
      msg=$(git log -1 --format=%B "$2")
      if ! csha=$($GH api -X POST "repos/$repo/git/commits" \
                    -f message="$msg" -f tree="$tree" --jq .sha 2>/dev/null); then
        echo "$TAG gh api (create commit) failed — offline, or gh is not authenticated" >&2
        return 2
      fi
      if out=$($GH api -X POST "repos/$repo/git/refs" \
                 -f ref="refs/heads/oi/$1" -f sha="$csha" 2>&1); then
        RESULT_SHA=$csha; return 0
      fi
      case "$out" in
        *"already exists"*) return 3 ;;
        *) echo "$TAG gh api (create ref) failed: $out" >&2; return 2 ;;
      esac ;;
  esac
}

append_stub() { # $1 = N
  today=$(date +%Y-%m-%d)
  # The leading newline terminates an unterminated last line AND yields the
  # blank line before the heading when the file already ends in a newline.
  printf '\n## OI-%s — %s\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n- **Identified**: %s · filed via mint_oi.sh from branch `%s`\n' \
    "$1" "$TITLE" "$today" "$BRANCH" >> "$BOARD_OPEN"
}

# The REMOTE delete is the operation; the local tracking-ref delete is
# bookkeeping and must not turn a successful remote delete into "could not
# delete" (the next sync prunes it anyway).
delete_reservation() { # $1 = N ; 0 iff the remote ref is gone
  case "$TRANSPORT" in
    api) repo=$(owner_repo); $GH api -X DELETE "repos/$repo/git/refs/heads/oi/$1" >/dev/null 2>&1 ;;
    git) git push --quiet "$REMOTE" ":refs/heads/oi/$1" >/dev/null 2>&1 ;;
  esac && { git update-ref -d "refs/remotes/$REMOTE/oi/$1" 2>/dev/null || true; }
}

# Every OI number on the boards of EVERY local branch -- a number in flight on
# a sibling worktree's branch is filed, not orphaned, even though this
# worktree's board and origin/main both lack it.
all_local_branch_numbers() {
  for b in $(git for-each-ref --format='%(refname)' refs/heads/); do board_numbers "$b"; done
}

ledger_subject() { git log -1 --format=%s "refs/remotes/$REMOTE/oi/$1" 2>/dev/null || echo '(no ledger line)'; }

do_release() {
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  if contains_line "$published" "$RELEASE_N"; then
    echo "$TAG OI-$RELEASE_N is PUBLISHED on $REMOTE/main — its reservation is pruned, never released." >&2
    exit 3
  fi
  if contains_line "$(board_numbers '')" "$RELEASE_N"; then
    echo "$TAG OI-$RELEASE_N is FILED on THIS board (uncommitted or committed) — remove the entry first if you really mean to release it." >&2
    exit 3
  fi
  if contains_line "$(all_local_branch_numbers)" "$RELEASE_N"; then
    echo "$TAG OI-$RELEASE_N is FILED on a LOCAL BRANCH (a sibling worktree's work in flight) — releasing it would strand that branch at its next commit. Refused." >&2
    exit 3
  fi
  if ! contains_line "$(reserved_numbers)" "$RELEASE_N"; then
    echo "$TAG oi/$RELEASE_N is not reserved on $REMOTE; nothing to release." >&2
    exit 3
  fi
  # A CLOUD branch's in-flight number is invisible here (no local branch for
  # it). The ledger line names who reserved it and when; the operator decides.
  echo "$TAG releasing oi/$RELEASE_N — reserved by: $(ledger_subject "$RELEASE_N")" >&2
  delete_reservation "$RELEASE_N" || { echo "$TAG could not delete oi/$RELEASE_N on $REMOTE" >&2; exit 2; }
  echo "$TAG released oi/$RELEASE_N (it was reserved and never filed)."
}

do_prune() {
  if [ "$TRANSPORT" = git ] && [ -z "$TRANSPORT_EXPLICIT" ]; then
    echo "$TAG --prune deletes branches with git push, which runs scripts/pre-push.sh once PER reservation on the laptop. Install gh (API transport), or set MINT_OI_TRANSPORT=git explicitly to accept that cost." >&2
    exit 64
  fi
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  pruned=0
  for n in $(reserved_numbers); do
    contains_line "$published" "$n" || continue
    delete_reservation "$n" || { echo "$TAG prune: could not delete oi/$n" >&2; continue; }
    pruned=$((pruned + 1))
  done
  echo "$TAG pruned $pruned reservation(s) whose number is already on $REMOTE/main."
}

do_next() {
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  local_nums=$( { board_numbers ''; all_local_branch_numbers; } )
  unfiled=''
  for r in $(reserved_numbers); do
    contains_line "$published" "$r" && continue
    contains_line "$local_nums" "$r" && continue
    unfiled="${unfiled:+$unfiled,}$r"
  done
  echo "NEXT=$(next_free)"
  echo "UNFILED=$unfiled"
}

do_mint() {
  if [ -n "$RESERVE_N" ]; then
    published=$(board_numbers "refs/remotes/$REMOTE/main")
    if contains_line "$published" "$RESERVE_N"; then
      echo "$TAG OI-$RESERVE_N is already on $REMOTE/main's board — a published number needs no reservation." >&2
      exit 3
    fi
  fi
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    if [ -n "$RESERVE_N" ]; then n=$RESERVE_N; else n=$(next_free); fi
    sha=$(ledger_commit "$n")
    if [ -n "${MINT_OI_TEST_HOOK_BEFORE_PUSH:-}" ]; then sh -c "$MINT_OI_TEST_HOOK_BEFORE_PUSH"; fi
    rc=0
    cas_write "$n" "$sha" || rc=$?
    case $rc in
      0) break ;;
      3)
        if [ -n "$RESERVE_N" ]; then
          echo "$TAG TAKEN: oi/$n already exists on $REMOTE — someone else holds OI-$n. Mint a fresh number instead." >&2
          exit 3
        fi
        if [ $attempt -ge $MAX_ATTEMPTS ]; then
          echo "$TAG gave up after $MAX_ATTEMPTS lost races (last tried OI-$n). Nothing reserved." >&2
          exit 3
        fi
        sync_refs || { echo "$TAG lost the remote mid-retry. Nothing reserved." >&2; exit 2; } ;;
      *)
        echo "$TAG cannot reach $REMOTE — an OI number cannot be reserved offline. Nothing was written." >&2
        exit 2 ;;
    esac
  done

  # Make the reservation visible to sibling worktrees NOW, not at their next
  # fetch. git transport: the object is local, point the tracking ref at it.
  # api transport: the commit was created server-side and does NOT exist
  # locally (update-ref would refuse an unknown object) — fetch just that ref.
  # Best-effort on BOTH transports: the reservation already exists on the
  # remote, so a transient ref-lock (a sibling worktree fetching) must not abort
  # before the stub and the OI-N line -- that is exactly how an orphan is made.
  if [ "$TRANSPORT" = git ]; then
    git update-ref "refs/remotes/$REMOTE/oi/$n" "$RESULT_SHA" 2>/dev/null \
      || echo "$TAG note: reserved on $REMOTE, but could not update the local tracking ref; sibling worktrees see it at their next sync." >&2
  else
    git fetch --quiet "$REMOTE" "+refs/heads/oi/$n:refs/remotes/$REMOTE/oi/$n" >/dev/null 2>&1 \
      || echo "$TAG note: reserved on $REMOTE, but could not fetch oi/$n locally; sibling worktrees see it at their next sync." >&2
  fi
  if [ $APPEND -eq 1 ]; then append_stub "$n"; fi
  echo "OI-$n"
  if [ "$TRANSPORT" = api ]; then do_prune >/dev/null 2>&1 || true; fi
}

sync_refs || {
  case "$MODE" in
    mint) echo "$TAG cannot reach $REMOTE — an OI number cannot be reserved offline. Nothing was written." >&2 ;;
    *)    echo "$TAG cannot reach $REMOTE — --$MODE needs the remote's current reservations and board." >&2 ;;
  esac
  [ -z "$SYNC_ERR" ] || printf '%s\n' "$SYNC_ERR" | sed 's/^/    git: /' >&2
  exit 2
}
case "$MODE" in
  next)    do_next ;;
  prune)   do_prune ;;
  release) do_release ;;
  mint)    do_mint ;;
esac
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/scripts/mint_oi_e2e_test.dart`
Expected: 10 tests PASS. If the race test fails with `OI-4`, the CAS did not fire — check the `--force-with-lease=refs/heads/oi/$1:` spelling (the trailing colon is the empty `<expect>`).

- [ ] **Step 5: Mutations — apply, confirm applied, run, revert**

1. `sed -i 's/--force-with-lease="refs\/heads\/oi\/$1:"/--force/' scripts/mint_oi.sh` → confirm with `grep -c 'force-with-lease="refs' scripts/mint_oi.sh` → `0` (the HEADER comments still mention the token, so a bare `grep -c force-with-lease` reads `2` on a correctly applied mutation — review round 1 measured exactly that). Run the file. Expected red: the race test (B prints `OI-4`, `oi/4` now points at B's ledger sha) and the `--reserve` test (the taken reserve succeeds). Record the count. `git checkout -- scripts/mint_oi.sh`.
2. Remove `board_numbers ''` from the `next_free` line only (`do_next`/`do_release` keep theirs) → confirm with `grep -n "board_numbers ''" scripts/mint_oi.sh` showing NO hit inside `next_free`. Run. Expected red: the hand-typed-working-board test — it mints **OI-4** (the max over reserved + main's boards is 3), not `OI-11`. Revert.
3. Remove `reserved_numbers;` from the `next_free` line → the "already exists on origin is skipped" test reddens: the max over the boards alone is 3, so the script mints `OI-4` (4 is genuinely free, the CAS accepts it) where the test asserts `OI-7`. Revert. This is the named reddening mutation for that test.
4. Remove `local_main_numbers;` from `next_free` → the local-main test reddens (`OI-4` instead of `OI-21`). Revert.
5. Change the ledger message to drop `| $TITLE` → the sequential test reddens on `contains('| alpha issue')`. Revert. This is the named reddening mutation for the sequential test; the CAS mutation in (1) does NOT redden it (spec §6), and nobody should cite it as if it did.
6. Drop `0*|` from the `--reserve/--release` validator → the `0`/`007` test reddens. Revert.
7. Drop the `all_local_branch_numbers` clause from `do_release` → the sibling test reddens (`LOCAL BRANCH` refusal gone; the reservation is deleted). Revert.
8. **The `offline` test has NO mutation that only it catches** — every mutation that makes an unreachable remote look reachable also breaks the CAS tests. It is kept as the guard for the fail-closed contract, and this sentence exists so nobody goes looking for a mutation the plan never claimed.
9. Sanity: `sh -n scripts/mint_oi.sh` exits 0, and `dash -n scripts/mint_oi.sh` (dash is at `/usr/bin/dash` on this machine); run the whole file once under dash too (`MINT_OI_SH=dash` is not a knob — just run `dash scripts/mint_oi.sh --next` by hand in a clone).

- [ ] **Step 6: Commit**

```bash
git add scripts/mint_oi.sh test/scripts/mint_oi_e2e_test.dart
sh scripts/safe_commit.sh "feat(board): mint_oi.sh — reserve OI numbers as oi/N branches via a remote CAS (git transport)

Sync = git fetch of refs/heads/oi/* into the shared .git; write =
git push --force-with-lease=<ref>: (empty expect = must not exist).
Offline refuses (exit 2, nothing written). --reserve N for numbers
filed before the allocator. Test seam MINT_OI_TEST_HOOK_BEFORE_PUSH
makes the race reachable in the e2e test.

Tests: test/scripts/mint_oi_e2e_test.dart (10). Mutations: --force in
place of --force-with-lease reddens the race + reserve tests; dropping
each term of next_free reddens its own test; dropping the title from
the ledger reddens the sequential test; dropping the leading-zero
reject reddens the 0/007 test; dropping the sibling-branch clause
reddens the release-sibling test. offline has no exclusive mutation.
Spec: docs/superpowers/specs/2026-09-12-oi-allocator-design.md"
```

---

### Task 2: API transport (`gh` shim), `--prune`, `--next`

**Files:**
- Modify: `scripts/mint_oi.sh` (no code change expected — the api branch, `do_prune` and `do_next` are already in Task 1's script; this task PROVES them)
- Modify: `test/scripts/mint_oi_e2e_test.dart` (add the shim + 3 tests)

**Interfaces:**
- Consumes: `MINT_OI_TRANSPORT=api`, `MINT_OI_GH_BIN`, `MINT_OI_OWNER_REPO` from Task 1.
- Produces (for Task 5): `--next` stdout contract — line 1 `NEXT=<int>`, line 2 `UNFILED=<comma-separated ints or empty>`.

- [ ] **Step 1: Write the failing tests**

Add to `test/scripts/mint_oi_e2e_test.dart`, above `void main()`:

```dart
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
```

And inside `main()`:

```dart
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
  });
```

- [ ] **Step 2: Run to verify the new tests fail or pass honestly**

Run: `flutter test test/scripts/mint_oi_e2e_test.dart`
Expected: the three new tests exercise code Task 1 already shipped, so they may PASS immediately. That is fine ONLY if Step 3's mutations redden them — a green test that no mutation can redden is not evidence (rule 21).

- [ ] **Step 3: Mutations — apply, confirm, run, revert**

1. In the shim (test file), delete the `else` branch that prints `Reference already exists` so a duplicate create silently succeeds → the API race test must redden (B reports `OI-5`, overwriting). This proves the script's `*"already exists"*` match is what drives the retry. Revert.
2. In the script, change `contains_line "$published" "$n" || continue` in `do_prune` to `true || continue` → `--prune` test reddens (5 deleted too). Confirm with `grep -c 'true || continue' scripts/mint_oi.sh` → `1`. Revert.
3. In `do_next`, delete the `contains_line "$local_nums" "$r" && continue` line → the `--next` test still passes (7 is not on the local board) — expected, so ALSO add to that test: append a hand-typed `## OI-7 — typed` stub to the local board before `--next` and assert `UNFILED=` is empty. Then the mutation reddens it. Keep the strengthened test.

- [ ] **Step 4: Commit**

```bash
git add scripts/mint_oi.sh test/scripts/mint_oi_e2e_test.dart
sh scripts/safe_commit.sh "test(board): mint_oi.sh API transport via a gh shim over the bare remote; --prune and --next proven

The shim emulates POST git/commits, POST git/refs (update-ref --stdin
create => 422 text on exists) and DELETE on top of the fixture's bare
repo, so the post-create fetch runs against real git state. Mutations:
dropping the shim's 422 reddens the API race; unconditional prune
reddens --prune; dropping the local-board exclusion reddens --next."
```

---

### Task 3: Gate Check B′ — the working-tree arm (closes OI-176) + diagnose-doc

**Files:**
- Modify: `scripts/check_oi_numbering_unique.dart:120` (signature), `:235-300` (dispatch chain)
- Create: `test/scripts/oi_numbering_gate_e2e_test.dart`
- Create: `docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-f3a9c1.md`
- Modify: `docs/audit/open_issues.md:3313-3314` (OI-176 status → CLOSED)

**Interfaces:**
- Consumes: `findCollisions`, `mergeBoards`, `parseBoard` from `scripts/oi_numbering_lib.dart` (unchanged).
- Produces: the gate compares an UNCOMMITTED board edit against `origin/main` whenever the board differs from `HEAD`, whatever shape `HEAD` has; `main` becomes `Future<void> main(...) async` (Task 4 needs `await`).

- [ ] **Step 1: Write the failing e2e test**

```dart
// test/scripts/oi_numbering_gate_e2e_test.dart
//
// END-TO-END coverage for scripts/check_oi_numbering_unique.dart's two 2026-09-12
// additions: Check B' (the working-tree arm, OI-176) and Check C (reservation
// required). Real bare remote, real clones, the real gate spawned with the SDK
// dart. The pure three-point predicate stays covered by oi_numbering_lib_test.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) => Process.runSync(
      exe, args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

String _fwd(String p) => p.replaceAll('\\', '/');
String _fileUri(String p) => 'file:///${_fwd(p)}';

/// See test/scripts/cron_registry_snapshot_gate_test.dart:26-58 for why this is
/// NOT Platform.resolvedExecutable (flutter_tester => the suite hangs).
String _dartBin() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', ['dart'],
      stdoutEncoding: utf8);
  if (which.exitCode == 0) {
    final first = (which.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = _fwd(File(first).parent.path);
      for (final c in ['$dir/cache/dart-sdk/bin/dart.exe', '$dir/cache/dart-sdk/bin/dart']) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

const _open = 'docs/audit/open_issues.md';
const _closed = 'docs/audit/closed_issues.md';

String _entry(int n, String title) =>
    '\n## OI-$n — $title\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n';

class _Fx {
  _Fx(this.tmp, this.remote, this.integration, this.session);
  final Directory tmp;
  final String remote;
  final String integration; // acts as main's owner
  final String session;     // a fresh session clone, zero commits

  static final _src = Directory.current.path;
  static final _dart = _dartBin();

  static void _must(ProcessResult r, String what) {
    if (r.exitCode != 0) throw StateError('$what (${r.exitCode}):\n${r.stdout}\n${r.stderr}');
  }

  static void _cfg(String repo) {
    _run('git', ['config', 'user.email', 't@example.invalid'], repo);
    _run('git', ['config', 'user.name', 'T'], repo);
  }

  /// main = seed(OI-1..3) -> feature merged with --no-ff, so main's TIP IS A
  /// MERGE COMMIT: the exact HEAD shape a fresh worktree cut from main has
  /// (OI-176). Then a session clone is cut at that tip with zero commits.
  static _Fx create(String tag) {
    final tmp = Directory.systemTemp.createTempSync('oi_gate_${tag}_');
    final remote = '${tmp.path}/remote.git';
    Directory(remote).createSync(recursive: true);
    _must(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote), 'bare');

    final integ = '${tmp.path}/integration';
    Directory(integ).createSync();
    _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], integ), 'clone integ');
    _cfg(integ);
    File('$integ/$_open').createSync(recursive: true);
    File('$integ/$_open').writeAsStringSync(
        '# Open Issues — fixture\n${_entry(1, 'one')}${_entry(2, 'two')}${_entry(3, 'three')}');
    File('$integ/$_closed').writeAsStringSync('# Closed issues\n');
    _must(_run('git', ['add', '-A'], integ), 'add');
    _must(_run('git', ['commit', '-q', '-m', 'seed'], integ), 'seed');
    _must(_run('git', ['checkout', '-q', '-b', 'feature'], integ), 'branch');
    File('$integ/feature.txt').writeAsStringSync('x\n');
    _must(_run('git', ['add', '-A'], integ), 'add2');
    _must(_run('git', ['commit', '-q', '-m', 'feature'], integ), 'feat');
    _must(_run('git', ['checkout', '-q', 'main'], integ), 'co main');
    _must(_run('git', ['merge', '-q', '--no-ff', '-m', 'Merge feature', 'feature'], integ), 'merge');
    _must(_run('git', ['push', '-q', '-u', 'origin', 'main'], integ), 'push');

    final session = '${tmp.path}/session';
    Directory(session).createSync();
    _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], session), 'clone session');
    _cfg(session);
    _must(_run('git', ['checkout', '-q', '-b', 'session'], session), 'session branch');
    return _Fx(tmp, remote, integ, session);
  }

  /// origin/main moves ahead with a new entry; the session fetches so its
  /// origin/main is current while its HEAD is still the merge commit.
  void mainFiles(int n, String title) {
    File('$integration/$_open').writeAsStringSync(
        File('$integration/$_open').readAsStringSync() + _entry(n, title));
    _must(_run('git', ['add', '-A'], integration), 'add main');
    _must(_run('git', ['commit', '-q', '-m', 'file OI-$n'], integration), 'commit main');
    _must(_run('git', ['push', '-q', 'origin', 'main'], integration), 'push main');
    _must(_run('git', ['fetch', '-q', 'origin'], session), 'session fetch');
  }

  void sessionTypes(int n, String title) {
    File('$session/$_open').writeAsStringSync(
        File('$session/$_open').readAsStringSync() + _entry(n, title));
  }

  void reserve(int n) {
    _must(_run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/oi/$n'], session), 'reserve');
    _must(_run('git', ['fetch', '-q', 'origin', '+refs/heads/oi/*:refs/remotes/origin/oi/*'], session),
        'fetch oi');
  }

  ProcessResult gate() =>
      _run(_dart, ['run', '$_src/scripts/check_oi_numbering_unique.dart'], session);

  void dispose() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  test('OI-176 shape: zero-commit worktree whose HEAD is a merge commit, uncommitted board collides with origin/main -> FAIL',
      () {
    final f = _Fx.create('oi176');
    addTearDown(f.dispose);
    f.mainFiles(4, 'main filed four');
    f.sessionTypes(4, 'session filed a different four');
    final r = f.gate();
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: all);
    expect(all, contains('OI-4 names two different issues'));
    expect(all, isNot(contains('PASS (vacuous): merge commit')),
        reason: 'the merge-commit arm must not be the one answering about an uncommitted edit');
  });

  test('a title-only edit of an existing entry on the working board is NOT a collision', () {
    final f = _Fx.create('titleedit');
    addTearDown(f.dispose);
    f.mainFiles(4, 'main filed four');
    final p = '${f.session}/$_open';
    File(p).writeAsStringSync(
        File(p).readAsStringSync().replaceFirst('## OI-2 — two', '## OI-2 — two, reworded'));
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });
}
```

- [ ] **Step 2: Run to verify the OI-176 test fails**

Run: `flutter test test/scripts/oi_numbering_gate_e2e_test.dart`
Expected: test 1 FAILS — the gate exits 0 and prints `PASS (vacuous): merge commit (HEAD^1 vs HEAD^2)`. Test 2 passes already (no minted number). Copy the exact PASS line into the diagnose-doc's `symptom`.

- [ ] **Step 3: Write the diagnose-doc FIRST (rule 22; `feedback_diagnose_doc_first_in_batch`)**

Create `docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-f3a9c1.md` (id `f3a9c1` — `grep -c f3a9c1 docs/diagnoses/INDEX.md` was `0` on 2026-09-12; re-check before writing). Model it on `docs/diagnoses/2026-08-09-core-worktree-shared-config-a4f7c2.md`, which established the phrasing for process-tooling docs. Required keys (`scripts/validate_diagnose_doc_lib.dart:9-16,24`): `bug_id date batch status blast_radius symptom concept sot_registry_entry writers readers hive_key_prefix hive_key_formula sync_methods restore_methods cloud_table cloud_columns contract_test_path ist_handling provider_invalidations telemetry_op_types cross_account_guard forbidden_patterns_checked proposed_fix regression_test_planned touched_layers_checked impact_analysis`.

```yaml
---
bug_id: f3a9c1
date: 2026-09-12
batch: oi-allocator
status: fixed
blast_radius: platform
related_bugs: [d3f1a7]
recurrence: |
  Second gate-level defect in check_oi_numbering_unique.dart's shape selection
  (the first — base == mainline at both merge placements — is recorded in
  docs/audit/gate_test_ledger.yaml:438 as "its SECOND real shipped bug"). Same
  class as the OI-112 landing half (d3f1a7): the gate answered a real question
  about the wrong pair of trees. Founder observed the collision class recurring
  across worktrees on 2026-09-12 (177/178, renumbered by hand in de52f1e8, the
  sixth manual renumber) — the trigger for the allocator this batch ships.
symptom: |
  On a fresh worktree with ZERO commits, HEAD is the commit the branch was cut
  from — routinely a merge commit on main. The gate's dispatch reads
  `parents.length >= 3`, takes the "merge commit (HEAD^1 vs HEAD^2)" arm and
  compares two ANCESTORS of the branch point. The staged/working board — the
  only place the new number exists — is never read. Output, verbatim from the
  e2e reproduction: "PASS (vacuous): merge commit (HEAD^1 vs HEAD^2) -- the
  <sha> side minted no OI number that the merge-base lacked, so no
  cross-branch collision is expressible. N entries ... were read and compared;
  this is a checked answer, not a skipped one." — while origin/main and the
  working board each carried `## OI-4` under different titles. Filed as OI-176
  on 2026-09-08 from a live three-way collision (167/168/169) found BY HAND
  while this gate was green.
concept: oi_number_uniqueness
sot_registry_entry: |
  Not a Hive/cloud writer-reader concept — dev-workflow tooling, same phrasing
  as a4f7c2/f0c2d5. The contract: an OI number new on a branch must not already
  name a different issue on origin/main. Deliberately NOT added to
  docs/sot_registry.yaml (that registry tracks Hive/Postgres contracts).
writers:
  - { file: docs/audit/open_issues.md, method_or_widget: "any session appending `## OI-N — title` (until this batch: by eyeballing the tail; after: scripts/mint_oi.sh)", line: 9 }
readers:
  - { file: scripts/check_oi_numbering_unique.dart, method_or_widget: "shape dispatch — the `parents.length >= 3` arm fired on a zero-commit worktree and read HEAD^1/HEAD^2 instead of the working tree (line as of e9e8f892; RE-DERIVE after the helpers are inserted — the validator only range-checks)", line: 292 }
  - { file: scripts/check_oi_numbering_unique.dart, method_or_widget: "useWorkingTree = otherSideRev == 'HEAD' — false in the merge arm, so headOpen/headClosed (the working tree) were never compared (line as of e9e8f892)", line: 331 }
  - { file: scripts/oi_numbering_lib.dart, method_or_widget: "findCollisions — correct; it was handed the wrong three boards", line: 152 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: test/scripts/oi_numbering_gate_e2e_test.dart
ist_handling:
  - "Not applicable — git refs and Markdown headings; no date key or counter."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Not applicable in the user-account sense. The analogous property — two
  SESSIONS not corrupting each other's identifiers — is what this fixes.
forbidden_patterns_checked:
  - { pattern: "dispatching on HEAD's shape while the board differs from HEAD (git diff --quiet HEAD -- <boards> exits 1)", absent: true }
proposed_fix: |
  Add a working-tree arm to the dispatch chain, AFTER the mid-merge arm and
  BEFORE the merge-commit arm: when `git diff --quiet HEAD -- docs/audit/
  open_issues.md docs/audit/closed_issues.md` exits 1 (staged or unstaged
  board change), compare head := working tree, base := merge-base(HEAD,
  origin/main), mainline := origin/main — regardless of HEAD's parent count.
  Dispatch on "is the board being changed", not on "what does HEAD look
  like". The mid-merge arm keeps precedence because mid-merge the working tree
  holds BOTH sides' entries and would make every number look contested. The
  merge-commit and branch arms are unchanged for a clean tree (CI, pre-merge).
  Fails open exactly as before (no origin/main ref, no merge-base => SKIPPED).
regression_test_planned:
  - test/scripts/oi_numbering_gate_e2e_test.dart
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "e2e test 1 reproduces the exact PASS (vacuous) line pre-fix and FAILs the gate post-fix. MUTATION: reverting the dispatch (deleting the boardDirty arm) reddens test 1; setting baseRev to origin/main (base == mainline) reddens test 1 via the vacuous path. Confirmed applied by grep before each run." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data path." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: "External services", status: verified, evidence: "GitHub ref semantics verified live 2026-09-12: duplicate ref create => 422; cloud push to refs/oi/* => 403, to refs/heads/oi/* => created. Both spike refs deleted." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Developer-tooling contract (branch board vs origin/main board). The e2e fixture cuts the session branch from a merge-commit tip, verified against the real repo where `git log --merges -1 main` is main's tip on 2026-09-12." }
impact_analysis: |
  EXPOSURE: every number minted in a fresh worktree since the gate shipped
  (2026-08-17) was checked against the wrong trees at pre-commit. Three
  collision incidents landed in that window (167-169, 177/178, and OI-128's
  predecessor), each repaired by a manual renumber commit whose predecessors
  still cite the superseded numbers. No user data path; cost is engineering
  time and identifier ambiguity in cited docs.
---

# OI-collision gate answered PASS about the wrong trees in the zero-commit worktree state

(prose body: one paragraph restating the mechanism; the mutation counts from
Task 3 Step 6 pasted in; link to the spec.)
```

Validate: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-f3a9c1.md` → `OK`.

- [ ] **Step 4: Implement the working-tree arm**

In `scripts/check_oi_numbering_unique.dart`:

(a) Change the signature at line 120:
```dart
Future<void> main(List<String> args) async {
```

(b) Add the helper next to `_showAtRev`:
```dart
/// True when either board differs between the WORKING TREE and HEAD — staged
/// or unstaged. That difference IS the mint in progress (OI-176): it is the only
/// place a brand-new number exists before the first commit, and it must be
/// compared against origin/main no matter what shape HEAD has.
bool _boardDirty() {
  try {
    final r = Process.runSync(
        'git', ['diff', '--quiet', 'HEAD', '--', _openBoard, _closedBoard]);
    return r.exitCode == 1; // 0 identical, 1 differs, anything else = could not tell
  } on ProcessException {
    return false;
  }
}
```

(c) In the dispatch chain, insert a new arm between the mid-merge arm and the `parents.length >= 3` arm:
```dart
    } else if (_boardDirty()) {
      // OI-176 (f3a9c1). An UNCOMMITTED board edit is the mint in progress. In
      // a fresh worktree HEAD is routinely a merge commit on main, and the arm
      // below would compare HEAD^1 vs HEAD^2 -- two ancestors of the branch
      // point -- then print PASS about trees that do not contain the edit.
      // Dispatch on "is the board being changed", not on HEAD's shape. The
      // mid-merge arm above keeps precedence: mid-merge the working tree holds
      // BOTH sides' entries and would make every number look contested.
      thisSideRev = 'origin/main';
      otherSideRev = 'HEAD'; // resolves to the WORKING TREE via useWorkingTree below
      baseRev = _run('git', ['merge-base', 'HEAD', 'origin/main'])?.trim();
      shapeNote = 'working tree (uncommitted board vs origin/main)';
    } else if (parents.length >= 3) {
```

`useWorkingTree = otherSideRev == 'HEAD'` is already true for this arm, so `headOpen`/`headClosed` (read from the working tree at the top of `main`) are what get compared.

(d) Repoint the collision FIX text so it no longer prescribes an eyeballed number — the exact thing this batch bans. In the `failures.add(...)` inside the `collisions.isNotEmpty` branch replace
```dart
                  '($thisSideRev is published; its number is fixed). Next free '
                  'is OI-$next.\n'
```
with
```dart
                  '($thisSideRev is published; its number is fixed). Mint the '
                  'replacement with:  sh scripts/mint_oi.sh "<title>"  (never by '
                  'eyeballing; next free was OI-$next at the time of this check).\n'
```
and repoint the source-grep in `test/scripts/oi_numbering_lib_test.dart:334` from `contains('Next free is OI-3')` to `contains('mint_oi.sh')` AND `contains('OI-3')` — the assertion is still true, it moved (§4.9 "extracting or moving code" row: repoint, never loosen).

(e) Add a comment to the existing note at ~`:131` ("Working tree, not the index"): with Check C (Task 4), a hand-typed UNSTAGED number in the worktree blocks EVERY commit from that worktree until it is reserved or removed, by design, at the cost of one bounded `ls-remote` per attempt.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/scripts/oi_numbering_gate_e2e_test.dart test/scripts/oi_numbering_lib_test.dart`
Expected: all PASS (2 new + the lib's existing 23, with `:334` repointed). Also `dart analyze scripts/check_oi_numbering_unique.dart` → no issues.

- [ ] **Step 6: Mutations — apply, confirm, run, revert; paste counts into the diagnose-doc**

1. Delete the whole `else if (_boardDirty()) {...}` arm → confirm with `grep -c 'else if (_boardDirty())' scripts/check_oi_numbering_unique.dart` → `0` (a bare `grep -c '_boardDirty()'` still reads `1` from the definition line — do not read that as "did not apply"). Run. Expected: test 1 reddens with the vacuous PASS line. Revert.
2. In the new arm, replace `baseRev = _run('git', ['merge-base', 'HEAD', 'origin/main'])?.trim();` with `baseRev = 'origin/main';` → base == mainline → degenerate. Run. Expected: test 1 reddens (vacuous PASS). Test 2 stays green. Revert.
3. Replace `final baseMerged = mergeBoards(baseOpen, baseClosed);` with `final baseMerged = <int, String>{};` → every number looks minted-here → TWO tests redden when Step 5's command runs both files: the gate e2e title-edit test (`OI-2 names two different issues`) AND `oi_numbering_lib_test.dart:348` `'PASSES when the branch only edits a pre-existing title'` (verified by review round 2). A "2 red" run is the CORRECT reading, not a broken mutation. Revert. This is the named reddening mutation for test 2; without it that test has none.
4. Confirm every mutation compiled (a `loading … [E]` line means it did not — pick another mutation, per rule 21).

Then flip OI-176 on the board (`docs/audit/open_issues.md:3314`): `- **Status**: OPEN` → `- **Status**: CLOSED · 2026-09-12 · diagnose f3a9c1 · branch oi-allocator — working-tree arm in check_oi_numbering_unique.dart; allocator in scripts/mint_oi.sh`. Leave the entry in place (archiving to `closed_issues.md` is a separate board-hygiene action).

- [ ] **Step 7: Commit**

```bash
git add scripts/check_oi_numbering_unique.dart test/scripts/oi_numbering_gate_e2e_test.dart test/scripts/oi_numbering_lib_test.dart docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-f3a9c1.md docs/audit/open_issues.md
sh scripts/safe_commit.sh "fix(gates): check_oi_numbering_unique compares the UNCOMMITTED board against origin/main whatever shape HEAD has

A zero-commit worktree cut from a merge-commit tip took the merge arm
and compared HEAD^1 vs HEAD^2 -- two ancestors of the branch point --
printing PASS (vacuous) while the staged board collided with main.
New arm dispatches on 'board differs from HEAD', after mid-merge and
before the merge-commit arm.

Regression test: test/scripts/oi_numbering_gate_e2e_test.dart (2).
Mutations: deleting the arm reddens 1; base := origin/main reddens 1;
base := {} reddens the title-edit test. The collision FIX text now
prescribes mint_oi.sh instead of an eyeballed number (lib test :334
repointed).

closes-diagnose: f3a9c1
closes-oi: OI-176"
```

(The `closes-oi:` trailer is REQUIRED — `scripts/check_closes_oi_cited.dart` fires at commit-msg because a `**Status**:` line moves OPEN → CLOSED in this commit.)

---

### Task 4: Gate Check C — every minted number is reserved

**Files:**
- Modify: `scripts/check_oi_numbering_unique.dart` (after the three merged maps are built, ~line 366)
- Modify: `test/scripts/oi_numbering_gate_e2e_test.dart` (+4 tests)
- Modify: `docs/audit/gate_test_ledger.yaml:438` (`evidence:`)

**Interfaces:**
- Consumes: Task 1's invariant (`refs/heads/oi/N` on the remote; `refs/remotes/origin/oi/N` locally after a sync).
- Produces: a board-touching commit with a number that is new vs the merge-base, NOT on origin/main's current board, and NOT reserved, FAILS with the `--reserve N` repair text.
- **Where Check C is MEANINGFUL, stated per shape (review round 1, finding 6):** the working-tree arm and the branch arm (pre-commit — the mint moment), the mid-merge arm (`pre-merge-commit` on the laptop — the backstop for every cloud branch, which has no hooks), and the merge-commit arm at CI on a **PR** (`origin/main` ≠ the PR head). At CI on a push to **main** it is structurally VACUOUS: `origin/main` == `HEAD`, every number is "published", and the exemption skips them all. That is correct, not a gap in the gate — after publication `--prune` may already have deleted the reservation, so checking there would produce false reds. The residue is a hookless environment pushing straight to `main`; the cloud pushes `claude/*` branches and merges happen on the laptop through `safe_merge.sh`, so the residue is a process rule, not a live path. Spec §3.3 / §4 scenario 4 / §5 are corrected in this batch to say exactly this.

- [ ] **Step 1: Write the failing tests** (append inside `main()` of the gate e2e file)

```dart
  test('Check C: a LOCAL-ONLY tracking ref refs/remotes/origin/oi/N satisfies the check with no network', () {
    final f = _Fx.create('localref');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'reserved four');
    // Only the local tracking ref -- nothing on the remote. Pins the
    // no-network short-circuit: step 1 answers, step 2 (ls-remote) never runs.
    expect(_run('git', ['update-ref', 'refs/remotes/origin/oi/4', 'HEAD'], f.session).exitCode, 0);
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO reservation')));
  });

  test('Check C: a reservation that exists ONLY on the remote (another clone made it) is found by ls-remote', () {
    final f = _Fx.create('remoteref');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'reserved elsewhere');
    // Reserved from the OTHER clone; the session has NOT fetched oi/*.
    expect(_run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/oi/4'], f.integration).exitCode, 0);
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/4'], f.session).exitCode,
        isNot(0), reason: 'fixture: the session must not already hold the ref locally');
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('Check C at pre-merge-commit (mid-merge, MERGE_HEAD set): an unreserved number on the branch being merged FAILS', () {
    final f = _Fx.create('midmerge');
    addTearDown(f.dispose);
    // The cloud-branch backstop: the branch commits an unreserved number and is
    // merged on the "laptop" (the integration clone) with --no-commit, which is
    // exactly the state the pre-merge-commit hook sees.
    f.sessionTypes(4, 'cloud typed four');
    _run('git', ['add', '-A'], f.session);
    expect(_run('git', ['commit', '-q', '-m', 'file OI-4 unreserved'], f.session).exitCode, 0);
    expect(_run('git', ['push', '-q', 'origin', 'session'], f.session).exitCode, 0);
    expect(_run('git', ['fetch', '-q', 'origin'], f.integration).exitCode, 0);
    expect(_run('git', ['merge', '--no-ff', '--no-commit', 'origin/session'], f.integration).exitCode, 0);
    expect(File('${f.integration}/.git/MERGE_HEAD').existsSync(), isTrue, reason: 'fixture: must be mid-merge');
    final r = _run(_Fx._dart, ['run', '${_Fx._src}/scripts/check_oi_numbering_unique.dart'], f.integration);
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: all);
    expect(all, contains('OI-4 is on this board but has NO reservation'));
  });

  test('Check C: a number new on the branch with NO reservation fails, naming the --reserve repair', () {
    final f = _Fx.create('unreserved');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'typed by hand');
    final r = f.gate();
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: all);
    expect(all, contains('OI-4 is on this board but has NO reservation'));
    expect(all, contains('mint_oi.sh --reserve 4'));
  });

  test('Check C: no local reservation ref AND remote unreachable -> SKIPPED naming the reservation check (exit 0, UNDETERMINED, no PASS anywhere on stdout)', () {
    final f = _Fx.create('offline');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'cannot be checked');
    Directory(f.remote).renameSync('${f.remote}.gone');
    addTearDown(() {
      try {
        Directory('${f.remote}.gone').renameSync(f.remote);
      } catch (_) {}
    });
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('UNDETERMINED'));
    expect(r.stdout as String, isNot(contains('PASS')),
        reason: 'the vacuous collision PASS must not co-print with a skipped reservation check');
    expect(r.stdout as String, contains('SKIPPED (reservation check)'));
    expect(r.stdout as String, contains('collision check ran'));
    expect('${r.stdout}${r.stderr}', isNot(contains('CI re-runs')),
        reason: 'no later placement re-checks a reservation once the number is published');
  });

  test('Check C: a number already PUBLISHED on origin/main (same title) is exempt — no reservation needed, no collision', () {
    final f = _Fx.create('published');
    addTearDown(f.dispose);
    f.mainFiles(4, 'shared four');
    f.sessionTypes(4, 'shared four'); // same title: the branch carries main's entry
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO reservation')));
  });
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test test/scripts/oi_numbering_gate_e2e_test.dart`
Expected: "localref", "remoteref" and "published" PASS already (nothing fails them yet); "unreserved" and "midmerge" FAIL (gate exits 0); "offline" FAILS (no `UNDETERMINED` on stderr — the collision arm's `origin/main` reads are local and succeed, so today the gate prints PASS).

- [ ] **Step 3: Implement Check C**

Add `import 'dart:async';` (for `unawaited`) beside the existing imports, then helpers next to `_showAtRev`:
```dart
Set<int> _numbersFromRefLines(String lines) {
  final out = <int>{};
  for (final l in lines.split('\n')) {
    final m = RegExp(r'/oi/(\d+)$').firstMatch(l.trim());
    if (m != null) out.add(int.parse(m.group(1)!));
  }
  return out;
}

/// Reservations already fetched into the shared .git (SessionStart sync, or a
/// mint in any sibling worktree). Empty is an answer here: absence of a local
/// ref is what triggers the one network call below.
Set<int> _localReservations() => _numbersFromRefLines(
    _run('git', ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin/oi/']) ?? '');

/// ONE `ls-remote` for the whole namespace (no `--exit-code`: with it an EMPTY
/// namespace is indistinguishable from a failure), bounded to 10 s. null =
/// could not answer (offline, timeout, no remote) -- UNDETERMINED, never
/// "not reserved".
Future<Set<int>?> _remoteReservations() async {
  try {
    final p = await Process.start('git', ['ls-remote', '--refs', 'origin', 'refs/heads/oi/*']);
    final out = p.stdout.transform(utf8.decoder).join();
    unawaited(p.stderr.drain<void>()); // bare drain() is an unawaited_futures WARNING -> fails pre-push analyze
    // 10 s, not 5: a bare ls-remote over this SSH remote measures 2.9-3.2 s
    // (both review rounds); a cold handshake crossing 5 s would SKIP the one
    // check that no later placement repeats once the number is published.
    // The renamed-fixture "offline" path fails in ~1 s either way.
    final code = await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      p.kill();
      return -1;
    });
    if (code != 0) return null;
    return _numbersFromRefLines(await out);
  } catch (_) {
    return null;
  }
}

/// Every number on origin/main's CURRENT boards. A published number is exempt
/// from the reservation check: it is permanent, and `mint_oi.sh --prune` may
/// legitimately have deleted its reservation already.
Set<int>? _publishedOnOriginMain() {
  final open = _parseStrict(_showAtRev('origin/main', _openBoard), 'origin/main open board');
  final closed =
      _parseStrict(_showAtRev('origin/main', _closedBoard) ?? '', 'origin/main closed board');
  if (open == null || closed == null) return null;
  return mergeBoards(open, closed).keys.toSet();
}
```

Then, in `main`, immediately after the three merged maps are built (after `final otherMerged = mergeBoards(otherOpen, otherClosed);`) and BEFORE the `mainlineMintedNothing` vacuous check — Check C must run even when the collision check is vacuous. Declare `var reservationSkipped = false;` next to `var undetermined = false;` at the top of `main` (they are DIFFERENT facts: `undetermined` means the collision check did not run; `reservationSkipped` means the reservation check could not be completed — a gate that folds them together prints a SKIPPED line that is false about one of them):
```dart
        // ---- Check C: every number this side minted is RESERVED ---------------
        // (allocator, 2026-09-12; spec §3.3). Numbers are allocated by
        // scripts/mint_oi.sh as refs/heads/oi/N; a hand-typed UNRESERVED number
        // must not commit (adopting an existing orphan reservation by hand is
        // fine and passes here). Network only when there is something
        // unreserved locally to ask about; offline => UNDETERMINED, never PASS.
        // Numbers already on origin/main's CURRENT board are exempt: they are
        // permanent, and `mint_oi.sh --prune` may already have deleted their
        // reservation -- which is why this check is vacuous at CI-on-main and
        // meaningful at pre-commit, pre-merge-commit and CI-on-a-PR.
        final mintedHere = otherMerged.keys.where((n) => !baseMerged.containsKey(n)).toList()
          ..sort();
        if (mintedHere.isNotEmpty) {
          final published = _publishedOnOriginMain();
          if (published == null) {
            reservationSkipped = true;
            _warnPass('origin/main boards unreadable; reservation check skipped.');
          } else {
            final toCheck = mintedHere.where((n) => !published.contains(n)).toList();
            if (toCheck.isNotEmpty) {
              final local = _localReservations();
              Set<int>? remote;
              if (toCheck.any((n) => !local.contains(n))) {
                remote = await _remoteReservations();
              }
              for (final n in toCheck) {
                if (local.contains(n) || (remote?.contains(n) ?? false)) continue;
                if (remote == null) {
                  reservationSkipped = true;
                  // NOT _warnPass: its tail promises "CI re-runs it", which is
                  // false for THIS check -- once the number is published the
                  // exemption makes every later placement vacuous (spec §3.3).
                  stderr.writeln('[check_oi_numbering_unique] UNDETERMINED (passing): OI-$n has '
                      'no local reservation ref and origin could not be reached to check '
                      'refs/heads/oi/$n. NO LATER PLACEMENT RE-CHECKS THIS once the number is '
                      'published -- reserve it now: sh scripts/mint_oi.sh --reserve $n "<title>"');
                  continue;
                }
                failures.add('OI-$n is on this board but has NO reservation '
                    '(no refs/heads/oi/$n on origin).\n'
                    '    Numbers are allocated, not eyeballed:  '
                    'sh scripts/mint_oi.sh --reserve $n "<title>"\n'
                    '    If that reports TAKEN, someone else holds $n -- renumber with:  '
                    'sh scripts/mint_oi.sh "<title>"');
              }
            }
          }
        }
```

Then TWO edits to the existing output paths, without which the plan's own offline test is red (review round 1, finding 1 — reproduced: `PASS (vacuous)` and `SKIPPED … did NOT run` printed on the same run):

(a) Guard the vacuous PASS print. The line `stdout.writeln('[check_oi_numbering_unique] PASS (vacuous): $shapeNote -- the '` (inside the `else` of `if (untrustworthy)`) becomes conditional:
```dart
          } else if (failures.isEmpty && !reservationSkipped) {
            stdout.writeln('[check_oi_numbering_unique] PASS (vacuous): $shapeNote -- the '
                // ...unchanged text...
          } else {
            // A reservation FAIL or SKIP is the verdict of this run; printing a
            // PASS about the collision half first would be read as the whole.
            stdout.writeln('[check_oi_numbering_unique] collision check ran clean '
                '($shapeNote, vacuous: the $thisSideRev side minted nothing the merge-base lacked).');
          }
```

(b) The final block. `if (failures.isEmpty) { if (undetermined) { ...SKIPPED... } ...PASS... }` becomes:
```dart
  if (failures.isEmpty) {
    if (undetermined) {
      // Deliberately NOT the word PASS. The collision check did not run.
      stdout.writeln('[check_oi_numbering_unique] SKIPPED: '
          '${headOpen.length} entries in open_issues.md + '
          '${headClosed.length} in closed_issues.md; '
          'no cross-board duplicates. Cross-branch collision check did NOT '
          'run (see UNDETERMINED above) -- CI re-runs it against a current '
          'origin/main.');
      exit(0);
    }
    if (reservationSkipped) {
      // The collision check RAN (and found nothing); only the reservation
      // check could not complete. Say exactly that -- "did NOT run" here
      // would be false about the half that did.
      stdout.writeln('[check_oi_numbering_unique] SKIPPED (reservation check): '
          'collision check ran and found nothing; one or more minted numbers '
          'could not be verified against origin (see UNDETERMINED above). '
          'Nothing re-checks this once the number is published -- reserve it '
          'now with: sh scripts/mint_oi.sh --reserve <N> "<title>"');
      exit(0);
    }
    // ...existing PASS line unchanged...
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/scripts/oi_numbering_gate_e2e_test.dart test/scripts/oi_numbering_lib_test.dart`
Expected: 6 + 23 PASS. Then run the gate once in the real worktree — `dart run scripts/check_oi_numbering_unique.dart` — with a clean board: expect `PASS` or `SKIPPED`, never a failure (no `mintedHere`).

- [ ] **Step 5: Mutations — apply, confirm, run, revert**

1. `(remote?.contains(n) ?? false)` → `(remote?.contains(n) ?? true)` → confirm with `grep -c '?? true' scripts/check_oi_numbering_unique.dart` → `1`. Run. Expected: the offline test reddens (no UNDETERMINED). Revert.
2. Delete the `failures.add(...)` statement inside Check C (leave the loop). Run. Expected: the unreserved AND the midmerge tests redden. Revert.
3. Delete `.where((n) => !published.contains(n))` (check published numbers too). Run. Expected: the published test reddens (the reservation lookup finds nothing, remote reachable → FAIL). Revert.
4. Make `_localReservations()` return `<int>{}` → confirm with `grep -c 'return <int>{};' …` → `1`. Run. Expected: the localref test reddens (it falls through to `ls-remote`, which finds nothing → FAIL); the remoteref test stays green. Revert. This is the named mutation for localref.
5. Make `_remoteReservations()` return `<int>{}` (reachable-but-empty) instead of the parsed set. Run. Expected: the remoteref test reddens; localref stays green — which proves the two lookups are independently load-bearing. Revert. This is the named mutation for remoteref.
6. Restore the vacuous PASS print to unconditional (drop `failures.isEmpty && !reservationSkipped`). Run. Expected: the offline test reddens on `isNot(contains('PASS'))`. Revert.

- [ ] **Step 6: The existing lib e2e fixture, and the ledger**

TWO existing fixtures in `test/scripts/oi_numbering_lib_test.dart` mint an unreserved number against a REACHABLE bare origin and assert exit 0 — round 1 named the first, round 2 found the second (the file has **24** tests; every "23" in the ledger's evidence is stale). Check C now (correctly) fails both — §4.9 "repairing a broken ENFORCEMENT breaks every test that was silently relying on it not enforcing", and `feedback_mistake_guard_without_its_mirror` #26: a finding names a SITE, grep the file for the CLASS. `grep -n "branchOpen\|branchClosed" test/scripts/oi_numbering_lib_test.dart` lists every scenario that mints on the branch side; the two that mint a number absent from `mainOpen` are `:336` and `:577`. Strengthen, do not loosen:

(a) `:336` `'PASSES when the branch mints an uncontested number'` — inside that test, after `_scenario(...)` returns `work`, reserve the number the way the allocator does and fetch it:
```dart
      // The number the branch mints must be RESERVED (allocator, 2026-09-12);
      // an unreserved mint is now a FAIL, pinned by
      // oi_numbering_gate_e2e_test.dart 'unreserved'.
      expect(_run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/oi/3'], work).exitCode, 0);
      expect(_run('git', ['fetch', '-q', 'origin', '+refs/heads/oi/*:refs/remotes/origin/oi/*'], work).exitCode, 0);
```
(Use that file's own `_git(work, [...])` helper — `_scenario` (`:227-280`) returns `work` checked out on `feature` with `origin` a bare path added by `git remote add`, so a push also updates the tracking ref; verified by both review rounds.)

(b) `:577` `'e2e — a clean merge with NO collision still passes at the merge commit'` — the branch mints OI-3 on its CLOSED board, then main merges it `--no-ff`; the merge-commit arm finds `mintedHere = {3}`, origin/main lacks 3, nothing reserves it → `FAIL … OI-3 … NO reservation`. That is the CI-on-a-PR shape working as designed. Before the `_git(work, ['checkout', 'main']);` line add:
```dart
      // The branch's number must be RESERVED (allocator, 2026-09-12) -- at the
      // merge commit Check C is meaningful because origin/main lacks 3.
      expect(_git(work, ['push', '-q', 'origin', 'HEAD:refs/heads/oi/3']).exitCode, 0);
```
(`work` is still on `feature` there; the push updates `refs/remotes/origin/oi/3` locally, so no fetch is needed.) Re-run the file: **24 green**.

Then `docs/audit/gate_test_ledger.yaml:436-438`: add `test/scripts/oi_numbering_gate_e2e_test.dart` to `test_path:`, correct the baseline to **24/24**, and append to `evidence:` one sentence per mutation above and per Task 3 mutation, with counts, dated 2026-09-12. Run `dart run scripts/check_gate_test_ledger.dart` → PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/check_oi_numbering_unique.dart test/scripts/oi_numbering_gate_e2e_test.dart test/scripts/oi_numbering_lib_test.dart docs/audit/gate_test_ledger.yaml
sh scripts/safe_commit.sh "feat(gates): check_oi_numbering_unique requires a refs/heads/oi/N reservation for every number minted on the branch

Check C: numbers new vs the merge-base and not yet on origin/main's
board must have a reservation -- local refs/remotes/origin/oi/N first,
then ONE bounded (5 s) ls-remote; unreachable => UNDETERMINED/SKIPPED,
never PASS. Published numbers are exempt (prune may have removed their
reservation). main is now async for the bounded spawn.

Meaningful at pre-commit, pre-merge-commit (the cloud-branch backstop)
and CI-on-a-PR; vacuous by design at CI-on-main. The vacuous collision
PASS no longer co-prints with a reservation FAIL/SKIP, and SKIPPED
names which check was skipped.

Tests: +6 in test/scripts/oi_numbering_gate_e2e_test.dart; TWO lib
e2e fixtures (:336 'uncontested', :577 'clean merge') now reserve their
number (the enforcement they silently relied on not existing; 24/24).
Mutations: null-as-reserved reddens offline; dropping failures.add
reddens unreserved + midmerge; dropping the published exemption
reddens published; empty local refs reddens localref; empty remote
set reddens remoteref; unguarding the vacuous print reddens offline."
```

---

### Task 5: SessionStart — "next free number" line (Dart-native, LOCAL refs only, no network)

**Files:**
- Modify: `scripts/discipline_hook.dart:105-118` (SessionStart case) + new helper; add `import 'oi_numbering_lib.dart';`
- Create: `test/scripts/discipline_hook_oi_line_e2e_test.dart`
- Modify: spec §3.4 (the hook reads LOCAL state only — `refs/remotes/origin/oi/*` and `refs/remotes/origin/main` — and does not fetch. Spec §7.4 pre-decided this: "if it exceeds 2 s median it becomes read-local-only"; review round 1 measured a bare `ls-remote` over the SSH remote at 2.9–3.2 s, on every SessionStart source including `compact`, so the rule fires. The mint syncs before reserving, so the hook line is advisory: "at least N as of the last sync".)

**Interfaces:**
- Consumes: `parseBoard`, `mergeBoards`, `nextFreeNumber` from `scripts/oi_numbering_lib.dart`; the `refs/remotes/origin/oi/*` namespace from Task 1 (kept fresh by every mint, by `sync_refs`, and by any plain `git fetch origin`, whose default refspec `+refs/heads/*:refs/remotes/origin/*` covers `oi/*`).
- Produces: one `additionalContext` paragraph beginning `OI board: next free number is at least <n>`; NOTHING when `refs/remotes/origin/main` cannot be resolved (a repo with no remote, a fresh clone mid-fetch).

- [ ] **Step 1: Write the failing test**

```dart
// test/scripts/discipline_hook_oi_line_e2e_test.dart
//
// The SessionStart hook must tell every session the next free OI number (as
// of the last sync -- it reads LOCAL refs only, no fetch: spec §3.4/§7.4) and
// the one command to mint with, and must stay SILENT (not wrong) when there is
// no origin/main to read.

@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _git(List<String> args, String cwd) => Process.runSync('git', args,
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8);

String _fwd(String p) => p.replaceAll('\\', '/');

String _dartBin() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', ['dart'],
      stdoutEncoding: utf8);
  if (which.exitCode == 0) {
    final first = (which.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = _fwd(File(first).parent.path);
      for (final c in ['$dir/cache/dart-sdk/bin/dart.exe', '$dir/cache/dart-sdk/bin/dart']) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

String _entry(int n, String t) =>
    '\n## OI-$n — $t\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n';

Future<String> _hookOutput(String dart, String src, String cwd, String stdinJson) async {
  final p = await Process.start(dart, ['run', '$src/scripts/discipline_hook.dart'],
      workingDirectory: cwd, environment: _cleanEnv(), includeParentEnvironment: false);
  p.stdin.write(stdinJson);
  await p.stdin.close();
  final out = p.stdout.transform(utf8.decoder).join();
  unawaited(p.stderr.drain<void>());
  await p.exitCode;
  return out;
}

void main() {
  final src = Directory.current.path;
  final dart = _dartBin();
  const startup = '{"hook_event_name":"SessionStart","source":"startup"}';

  late Directory tmp;
  late String remote;
  late String clone;
  late String other;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hook_oi_');
    remote = '${tmp.path}/remote.git';
    clone = '${tmp.path}/clone';
    other = '${tmp.path}/other';
    Directory(remote).createSync();
    expect(_git(['init', '-q', '--bare', '-b', 'main', '.'], remote).exitCode, 0);
    for (final c in [clone, other]) {
      Directory(c).createSync();
      expect(_git(['clone', '-q', 'file:///${_fwd(remote)}', '.'], c).exitCode, 0);
      _git(['config', 'user.email', 't@example.invalid'], c);
      _git(['config', 'user.name', 'T'], c);
    }
    File('$clone/docs/audit/open_issues.md').createSync(recursive: true);
    File('$clone/docs/audit/open_issues.md')
        .writeAsStringSync('# board\n${_entry(1, 'a')}${_entry(2, 'b')}${_entry(3, 'c')}${_entry(4, 'd')}');
    File('$clone/docs/audit/closed_issues.md').writeAsStringSync('# closed\n');
    expect(_git(['add', '-A'], clone).exitCode, 0);
    expect(_git(['commit', '-q', '-m', 'seed'], clone).exitCode, 0);
    expect(_git(['push', '-q', '-u', 'origin', 'main'], clone).exitCode, 0);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('prints next free = max(published board, working board, LOCAL reservation refs)+1 and the unfiled list', () async {
    // A reservation made from THIS clone: git updates refs/remotes/origin/oi/5
    // on a successful push, so it is local without any fetch.
    expect(_git(['push', '-q', 'origin', 'HEAD:refs/heads/oi/5'], clone).exitCode, 0);
    expect(_git(['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/5'], clone).exitCode, 0,
        reason: 'fixture: the push must have updated the local tracking ref');
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('OI board: next free number is at least 6'));
    expect(out, contains('Reserved-but-unfiled: oi/5 ['));
    expect(out, contains('sh scripts/mint_oi.sh'));
  });

  test('a reservation filed on a SIBLING local branch is not listed as unfiled', () async {
    expect(_git(['checkout', '-q', '-b', 'sib'], clone).exitCode, 0);
    expect(_git(['push', '-q', 'origin', 'HEAD:refs/heads/oi/9'], clone).exitCode, 0);
    File('$clone/docs/audit/open_issues.md')
        .writeAsStringSync(File('$clone/docs/audit/open_issues.md').readAsStringSync() + _entry(9, 'sib nine'));
    expect(_git(['add', '-A'], clone).exitCode, 0);
    expect(_git(['commit', '-q', '-m', 'sib files 9'], clone).exitCode, 0);
    expect(_git(['checkout', '-q', 'main'], clone).exitCode, 0);
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('Reserved-but-unfiled: none'));
    expect(out, contains('next free number is at least 10'));
  });

  test('does NOT fetch: a reservation made from ANOTHER clone is invisible until the next sync (and the line says so)', () async {
    // `other` was cloned from the still-EMPTY remote, so its HEAD is unborn;
    // fetch main first and reserve from the fetched ref (review round 2).
    expect(_git(['fetch', '-q', 'origin'], other).exitCode, 0);
    expect(_git(['push', '-q', 'origin', 'refs/remotes/origin/main:refs/heads/oi/7'], other).exitCode, 0);
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('next free number is at least 5'),
        reason: 'local-only read: oi/7 on the remote is not consulted');
    expect(out, contains('as of the last sync'));
  });

  test('stays silent about the board when there is no origin/main to read', () async {
    final lone = '${tmp.path}/lone';
    Directory(lone).createSync();
    expect(_git(['init', '-q', '-b', 'main', '.'], lone).exitCode, 0);
    File('$lone/docs/audit/open_issues.md').createSync(recursive: true);
    File('$lone/docs/audit/open_issues.md').writeAsStringSync('# board\n${_entry(1, 'a')}');
    final out = await _hookOutput(dart, src, lone, startup);
    expect(out, isNot(contains('OI board')));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/scripts/discipline_hook_oi_line_e2e_test.dart`
Expected: tests 1 and 2 FAIL (no `OI board` text in the hook's output). Test 3 passes vacuously — it is the guard for the failure mode, and Step 4's mutation 2 exercises it.

- [ ] **Step 3: Implement**

In `scripts/discipline_hook.dart`: add `import 'oi_numbering_lib.dart';` beside the existing imports; in the `SessionStart` case add, after the `memNudge` lines:
```dart
        final oiLine = _oiBoardLine();
        if (oiLine.isNotEmpty) parts.add(oiLine);
```
Add the helper at file bottom (synchronous — it spawns nothing long-running and touches no network):
```dart
/// OI allocator (spec docs/superpowers/specs/2026-09-12-oi-allocator-design.md
/// §3.4): tell the session the next free number and the ONE way to mint.
///
/// LOCAL READ ONLY -- no fetch. A `git ls-remote` over the SSH remote measured
/// 2.9-3.2 s here (review round 1, 2026-09-12) and this fires on every
/// SessionStart source including `compact`; spec §7.4 set the rule at 2 s.
/// The number is therefore "at least N as of the last sync"; mint_oi.sh syncs
/// before it reserves, so a stale N here can never cause a collision. Every
/// mint, every `sync_refs`, and any plain `git fetch origin` (default refspec
/// covers oi/*) refreshes the refs this reads. Fail-open: any error => ''.
String _oiBoardLine() {
  try {
    final top = Process.runSync('git', ['rev-parse', '--show-toplevel'], stdoutEncoding: utf8);
    if (top.exitCode != 0) return '';
    final root = (top.stdout as String).trim();
    // No origin/main => nothing to say. A wrong number is worse than none.
    final hasMain = Process.runSync(
        'git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main'],
        workingDirectory: root);
    if (hasMain.exitCode != 0) return '';

    String show(String path) {
      final r = Process.runSync('git', ['show', 'refs/remotes/origin/main:$path'],
          workingDirectory: root, stdoutEncoding: utf8); // utf8: the em-dash separator
      return r.exitCode == 0 ? r.stdout as String : '';
    }
    String local(String path) {
      final f = File('$root/$path');
      return f.existsSync() ? f.readAsStringSync() : '';
    }
    const open = 'docs/audit/open_issues.md';
    const closed = 'docs/audit/closed_issues.md';
    final published = mergeBoards(parseBoard(show(open)), parseBoard(show(closed)));
    final working = mergeBoards(parseBoard(local(open)), parseBoard(local(closed)));

    final refs = Process.runSync(
        'git', ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin/oi/'],
        workingDirectory: root, stdoutEncoding: utf8);
    final reserved = <int>{};
    for (final l in (refs.stdout as String).split('\n')) {
      final m = RegExp(r'/oi/(\d+)$').firstMatch(l.trim());
      if (m != null) reserved.add(int.parse(m.group(1)!));
    }
    // A number filed on ANY local branch (a sibling worktree's work in flight)
    // is filed, not orphaned -- otherwise this line would tell worktree B to
    // release worktree A's number (review round 2, finding 3).
    final onLocalBranches = <int>{};
    final heads = Process.runSync('git', ['for-each-ref', '--format=%(refname)', 'refs/heads/'],
        workingDirectory: root, stdoutEncoding: utf8);
    for (final b in (heads.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      for (final path in const [open, closed]) {
        final r = Process.runSync('git', ['show', '$b:$path'],
            workingDirectory: root, stdoutEncoding: utf8);
        if (r.exitCode == 0) onLocalBranches.addAll(parseBoard(r.stdout as String).keys);
      }
    }

    final next = nextFreeNumber([published, working, {for (final r in reserved) r: ''}]);
    final unfiled = reserved
        .where((n) => !published.containsKey(n) && !working.containsKey(n) && !onLocalBranches.contains(n))
        .toList()
      ..sort();
    String subject(int n) {
      final r = Process.runSync('git', ['log', '-1', '--format=%s', 'refs/remotes/origin/oi/$n'],
          workingDirectory: root, stdoutEncoding: utf8);
      return r.exitCode == 0 ? (r.stdout as String).trim() : '(no ledger line)';
    }
    final unfiledText = unfiled.isEmpty
        ? 'none'
        : unfiled.map((n) => 'oi/$n [${subject(n)}]').join('; ') +
            ' — may belong to a CLOUD branch this clone cannot see; adopt by filing `## OI-N` by '
            'hand, or `sh scripts/mint_oi.sh --release N` ONLY if the reserving branch is dead';
    return 'OI board: next free number is at least $next (as of the last sync; '
        'mint_oi.sh re-syncs before reserving). Reserved-but-unfiled: $unfiledText.\n'
        'File new OIs ONLY with:  sh scripts/mint_oi.sh "<title>"  from YOUR worktree — an '
        'UNRESERVED number fails the commit (CLAUDE.md §7, OI allocator row).';
  } catch (_) {
    return '';
  }
}
```

- [ ] **Step 4: Run; mutate; revert**

Run: `flutter test test/scripts/discipline_hook_oi_line_e2e_test.dart test/scripts/batch_close_hook_e2e_test.dart` → PASS.
Mutations: (1) `nextFreeNumber([published, working, {…}])` → `nextFreeNumber([published, working])` (drop reservations) → test 1 reddens (`5` not `6`); (2) `if (hasMain.exitCode != 0) return '';` → `if (false) return '';` → the no-origin/main test reddens (a line prints); (3) add a `git fetch origin` call before the reads → test 2 reddens (`7` becomes visible); (4) drop `&& !onLocalBranches.contains(n)` → the sibling test reddens (`oi/9` listed). Confirm each applied by grep; revert.
Also `dart analyze scripts/discipline_hook.dart` → no issues (no bare `drain()` anywhere).

- [ ] **Step 5: Commit**

```bash
git add scripts/discipline_hook.dart test/scripts/discipline_hook_oi_line_e2e_test.dart docs/superpowers/specs/2026-09-12-oi-allocator-design.md
sh scripts/safe_commit.sh "feat(hooks): SessionStart prints the next free OI number (local refs, no fetch) and the mint command

Reads refs/remotes/origin/oi/* + origin/main's boards + the working
board via oi_numbering_lib; lists reserved-but-unfiled with the adopt /
--release choice. No network: an ls-remote over SSH measured ~3 s and
this fires on every SessionStart source, so spec §7.4's 2 s rule made
it read-local-only. Silent when origin/main is absent.

Tests: test/scripts/discipline_hook_oi_line_e2e_test.dart (4).
Mutations: dropping reservations from the max reddens 1; ignoring the
missing-origin/main guard reddens 1; adding a fetch reddens 1;
dropping the sibling-branch exclusion reddens 1."
```

---

### Task 6: Docs — board filing rule, CLAUDE.md §7 row, handbook page

**Files:**
- Modify: `docs/audit/open_issues.md:9-11`
- Modify: `CLAUDE.md` §7 row beginning `| **OI number uniqueness across branches**`
- Modify: `docs/blast_radius.yaml` (next to the existing `scripts/check_oi_numbering_unique.dart` pin at `:199`): add `- { glob: "scripts/mint_oi.sh", tier: platform }` and `- { glob: "scripts/discipline_hook.dart", tier: platform }` with a one-line comment each — today both fall through `scripts/**` to `feature` (`:315`), so a later edit to the allocator alone would get no B-pass and no full suite (review round 1, finding 10; verified with `blast_radius_from_diff.dart`). `scripts/check_blast_radius_coverage.dart` runs at pre-commit.
- Create: `docs/handbook/process/oi-allocator.md`
- Modify: `CLAUDE.md` §4.3, the bullet beginning `**Commits and pushes go through \`scripts/safe_commit.sh\` / \`scripts/safe_push.sh\`, never raw`: append one clause — *"One documented exemption: the ref-CREATE push inside \`scripts/mint_oi.sh\` (§7, OI allocator row) — it creates a ref that must not exist, so its exit code is the verification and there is no range to gate."* A §4.3 reader never sees the §7 row otherwise (review round 2).
- Modify: `scripts/build_oi_index.dart:110-111` and `scripts/oi_numbering_lib.dart:7-8` — both still say *"There is no allocator"*. Change to *"Until 2026-09-12 there was no allocator; \`scripts/mint_oi.sh\` now reserves numbers as \`oi/N\` branches. This check remains the LANDING backstop."* Comment-only edits; `dart analyze` both.
- Modify: `vercel.json` — add `"ignoreCommand": "case \"$VERCEL_GIT_COMMIT_REF\" in oi/*) exit 0;; esac; exit 1"`. Vercel builds every pushed branch of this repo (a preview deployment exists for `regen-wave-unit2`, verified read-only in review round 2), and a reservation is a NEW commit carrying main's full tree, so without this every mint — and every retry-loser — would trigger a full Flutter-web build. Vercel semantics: `ignoreCommand` exit **0 = skip the build**, 1 = build. Confirm after the first real mint (Task 7 Step 7).
- Modify: `scripts/new-worktree.sh:69,73` — the two `git fetch origin main --quiet` calls become `git fetch origin main '+refs/heads/oi/*:refs/remotes/origin/oi/*' --quiet`: same round trip, and every new worktree starts with current reservations so the SessionStart line is fresh at the moment a session most often mints. `test/scripts/new_worktree_base_test.dart` pins the base-choice BEHAVIOUR, not the fetch string (checked); run it.
- (Considered, no change: `.claude/skills/debugging/SKILL.md` — no new bug class; the eyeball-minted-sequence class is OI-167's and this batch resolves the OI-board instance of it, not the skill-numbering instance. Spec §3.5 is amended to say the same.)

- [ ] **Step 1: Board header** — after the `Append-only at the bottom.` bullet add:

```markdown
- **Numbers are ALLOCATED, never eyeballed (2026-09-12).** File a new issue with
  `sh scripts/mint_oi.sh "<title>"` — it reserves the next free number as the
  remote branch `oi/N` (an atomic create on GitHub, so two sessions cannot both
  get N, laptop or cloud) and appends the stub. An UNRESERVED number FAILS the
  commit (`check_oi_numbering_unique.dart`, Check C) at pre-commit and at
  pre-merge-commit — adopting an orphan reservation by hand is fine. Run it in
  YOUR worktree (§4.13) — it edits this file. A number filed before the
  allocator existed: `sh scripts/mint_oi.sh --reserve N "<title>"`. Never mint
  offline — the script refuses, by design. The cloud never prunes (no `gh`);
  the next laptop mint prunes for it. Spec:
  `docs/superpowers/specs/2026-09-12-oi-allocator-design.md`.
```

- [ ] **Step 2: CLAUDE.md §7 row** — replace the two cells of the OI-uniqueness row with:

Left: `**OI number uniqueness across branches** — numbers are ALLOCATED by \`scripts/mint_oi.sh\` (2026-09-12), never eyeballed. Before it: no allocator, the ceiling split across two files, six manual renumbers by 2026-09-12 (the last, 177/178→186/187, landed while the allocator was being specified). The detector alone was structurally late — two of its three placements run after the number is committed, and the early one was vacuous in the zero-commit worktree state (OI-176).`

Right: `\`scripts/mint_oi.sh\` reserves \`refs/heads/oi/N\` as a server-side compare-and-swap: \`gh api\` on the laptop (NOT a \`git push\`, so pre-push never runs), \`git push --force-with-lease=<ref>:\` in the cloud (no \`gh\`, no hooks, and its credential writes \`refs/heads/**\` only — \`refs/oi/*\` is a 403). **That push is a documented exemption from §4.3's \`safe_push.sh\` rule:** it creates a ref that must not exist, so the exit code IS the landing verification, there is no range to gate, and \`git_safety_hook.dart\` cannot see it (it runs inside a script). Sync is \`git fetch\` into the SHARED \`.git/\`, so every laptop worktree sees a reservation instantly. Offline ⇒ the mint REFUSES (exit 2, nothing written) — the one deliberately fail-closed step; gates stay fail-open. Gate \`scripts/check_oi_numbering_unique.dart\`: Check B′ compares the UNCOMMITTED board against origin/main whatever shape HEAD has (closes OI-176, diagnose \`f3a9c1\`); Check C fails a commit whose new number has no \`oi/N\` — meaningful at pre-commit, pre-merge-commit (the backstop for hookless cloud branches) and CI-on-a-PR; VACUOUS by design at CI-on-main (published numbers are exempt because prune may already have removed their reservation); offline ⇒ SKIPPED naming which check. SessionStart prints \`next free number is at least N\` from LOCAL refs (no fetch — ~3 s over SSH, on every source incl. compact). Orphan reservations: adopt by hand or \`--release N\` — which refuses any number filed on ANY local branch and prints the ledger line (branch + time) before deleting, because from worktree B a sibling A's in-flight number looks unfiled. The cloud never prunes (no \`gh\`); the next laptop mint prunes for it. \`vercel.json\` skips \`oi/*\` builds (\`ignoreCommand\`). GitHub Issues as the allocator was REJECTED: issues+PRs share one sequence, max #23 < OI-185. Residue: a hookless environment pushing straight to \`main\` is checked for collisions but not reservations. Tests: \`test/scripts/mint_oi_e2e_test.dart\`, \`oi_numbering_gate_e2e_test.dart\`, \`discipline_hook_oi_line_e2e_test.dart\` — counts deliberately omitted; run them. Spec: \`docs/superpowers/specs/2026-09-12-oi-allocator-design.md\`.`

- [ ] **Step 3: Handbook page** `docs/handbook/process/oi-allocator.md`:

```markdown
---
title: OI numbers are allocated, never eyeballed
category: process
source_memory: project_oi_allocator_brainstorm_inflight.md
last_reviewed: 2026-09-12
---

# OI numbers are allocated, never eyeballed

## The rule

File a new open issue with `sh scripts/mint_oi.sh "<title>"`. Never type `## OI-N` with a number you
chose by reading the board's tail. A commit that adds an unreserved number fails
(`check_oi_numbering_unique.dart`, Check C) with the exact repair command.

## Why

Sequential integers need a single allocator. This repo has many concurrent allocators — laptop
worktrees and cloud sessions — each reading its own copy of the board. Six manual renumbers
(100–105, 106–108, 128, 167–169, 177/178) proved that detection after the fact is the wrong shape:
by then the number is in pushed commit messages that are never rewritten.

## How it works

The remote branch `oi/N` is the reservation. Creating a ref that already exists is refused by
GitHub, so the second session to ask for N is told no and takes N+1. The laptop creates it through
`gh api` (no `git push`, so no pre-push hook cost); the cloud through
`git push --force-with-lease=refs/heads/oi/N:`. `git fetch` is the sync. The board remains the only
source of truth for content; `git log -1 origin/oi/N` shows who reserved it and when.

## Orphans and siblings

A reservation nobody filed (a session died between the reservation and the stub) is listed at every
SessionStart as reserved-but-unfiled, with its ledger line. Adopt it by filing `## OI-N` by hand, or
`sh scripts/mint_oi.sh --release N`. `--release` refuses a number filed on any local branch — from
your worktree a sibling worktree's in-flight number looks exactly like an orphan. A cloud branch's
in-flight number is invisible to your clone; read the ledger line before releasing. The cloud never
prunes; the next laptop mint prunes for it.

## Offline

`mint_oi.sh` refuses to mint offline. That is the point: a local-only number is a promise the
remote has not seen, and it is exactly how collisions are born. Everything else — gates, the
SessionStart line — fails open to SKIPPED or silence.

## Spec

`docs/superpowers/specs/2026-09-12-oi-allocator-design.md`
```

`build_handbook_index.dart` regenerates `docs/handbook/INDEX.md` at pre-commit (`pre-commit.sh:257`).

- [ ] **Step 4: Commit**

```bash
git add docs/audit/open_issues.md CLAUDE.md docs/blast_radius.yaml docs/handbook/process/oi-allocator.md docs/handbook/INDEX.md scripts/build_oi_index.dart scripts/oi_numbering_lib.dart vercel.json scripts/new-worktree.sh
sh scripts/safe_commit.sh "docs(board): filing rule, CLAUDE.md §4.3 exemption + §7 allocator row, blast-radius pins, handbook page, Vercel skip for oi/*, new-worktree fetches reservations — OI numbers are allocated, never eyeballed"
```

(If the pre-commit regen leaves `docs/handbook/INDEX.md` modified, add it and re-run the commit.)

---

### Task 7: Verify, review, land

- [ ] **Step 1: Analyze what was written** — `flutter analyze scripts/ test/scripts/` → zero warnings (`--no-fatal-infos` hides infos only; ONE warning fails the push with git's opaque `failed to push some refs`).
- [ ] **Step 2: Full suite ONCE** (§4.9: a targeted run cannot create the contention a subprocess test breaks under): `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`. Green or fix — never "pre-existing".
- [ ] **Step 3: Gate loop** — `sh scripts/pre-commit.sh` (or attempt a no-op commit) before dispatching the B-pass (§4.12.5).
- [ ] **Step 4: B-pass** — `/code-review` on the branch diff (platform ⇒ mandatory, self-initiated). Fix every finding in this batch. The skill writes `docs/reviews/oi-allocator-bpass.md` and appends its tuning-history entry (gated by `check_skill_tuning_history.dart`).
- [ ] **Step 5: Plan-review record** `docs/plan-reviews/oi-allocator.md`:

```markdown
---
branch: oi-allocator
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi-allocator-bpass.md
---

# Plan review — oi-allocator

(Round 1 / Round 2 summaries: reviewer, verdict, findings folded, with the two spike results as
the ground truth checked. `verdict: accepted` in the cited B-pass file must be a BARE line — no
trailing comment — or the merge gate hard-fails in CI.)
```

Commit it: `sh scripts/safe_commit.sh "docs(plan-review): keystone record for oi-allocator (platform)"`.

- [ ] **Step 6: Land** — from the PRIMARY worktree: `sh scripts/safe_merge.sh oi-allocator` then `sh scripts/safe_push.sh origin main`. Read `safe_push.sh`'s THREE outcomes (0 landed / 1 failed / 2 unverified) — not two.
- [ ] **Step 7: First real mint** — from the primary worktree after the push: `sh scripts/mint_oi.sh --next` → expect `NEXT=` = 1 + main's board max (re-derive; do not trust any number in this plan). Do NOT mint a real number without an issue to file. ⚠ The API transport's `POST /git/commits` WITHOUT `parents` creating a ROOT commit is documented by GitHub but was NOT proven live (the spike proved the refs 422 and the cloud 403; the shim's `commit-tree` cannot prove GitHub's behaviour). The first real laptop mint proves it; if it 422s on the commit call, the fallback is `--input` with an explicit `"parents": []` JSON body — one line in `cas_write`. After that first mint ALSO confirm on the Vercel dashboard (or `vercel ls`) that NO deployment was created for `oi/N` — the `ignoreCommand` from Task 6 is what prevents a full Flutter-web build per mint.
- [ ] **Step 8: §5 batch-close rows** — retrospective `memory/project_oi_allocator_shipped_<date>.md`; retire the `IN-FLIGHT` index line to `MEMORY_ARCHIVED.md`; correct `project_regen_alignment_brainstorm_inflight.md`'s "177/178" to "186/187"; `dart run scripts/retire_worktree.dart` (dry-run) then `--execute oi-allocator`; `dart run scripts/check_context_artifact_budget.dart`.

---

## Self-review against the spec

- §3.1 reservation = branch + orphan commit on main's tree + ledger message → Task 1 `ledger_commit` / `cas_write`. ✓
- §3.2 all five invocations, exit codes, transports, retry, test seam, stub fields, prune rule → Tasks 1–2. ✓
- §3.3 Check B′ + Check C, published exemption, 5 s bound, SKIPPED-never-PASS → Tasks 3–4. ✓
- §3.4 SessionStart line → Task 5 (Dart-native, local-only per §7.4's own rule; spec amended in the same commit). ✓
- §3.5 docs → Tasks 3 (diagnose-doc, OI-176 CLOSED), 6 (board, CLAUDE.md, handbook). ✓
- §6 tests and mutations → each task's mutation step; the "tests 1–2 do NOT redden under `--force`" caveat is carried into Task 1 Step 5. ✓
- §7 residues: +orphan reservations (adopt or `--release`), +CI-on-main vacuity / hookless direct-to-main, +API root-commit unproven until the first live mint — spec amended in the plan-hardening commit. §8 rollout → Task 7 Steps 6–8. ✓
- Review round 2 (2026-09-12, on the hardened plan `57643ee8`): 1 P1 + 4 P2 + 5 P3, verdict harden, no split — folded: F1 the SECOND lib fixture (`:577`, the class had two members — `feedback_mistake_guard_without_its_mirror` #26), F2 hook test-2 unborn HEAD, F3 `--release`/unfiled blind to live siblings (refuse any local branch's numbers; print the ledger line), F4 ls-remote bound 10 s + the false "CI re-runs" sentence, F5 named mutations for remoteref / 0-007 / release + "offline has none" stated, F6 Vercel `ignoreCommand` for `oi/*`, F7 mutation 3 reddens two, F8 fixture `.gitattributes`, F9 spec/plan drift (a–e), F10 script edges (`TRANSPORT_EXPLICIT` only for `git`, empty `--reserve`, sync stderr, local-delete best-effort, "your worktree", `new-worktree.sh` refspec), Q10 §4.3 cross-reference. Convergence declared after the fold per this repo's record convention (see `docs/plan-reviews/workout-progression-resolver.md`: round 2 "harden (2 P2, surgical), both folded in-place" → `verdict: converged`).
- Review round 1 (2026-09-12): 4 P1 + 13 P2, verdict harden — every finding folded above (F1 output guards, F2 `unawaited`, F3 lib-fixture reservation, F4 local-only hook, F5 mutation greps, F6 placements, F7 local-main term, F8 `0`/leading-zero, F9 best-effort bookkeeping + `--release`, F10 pins, F11 FIX text, F12 citations, F13 fixtures, F14 prune guard, F15 §4.3 exemption sentence, F16 mode-keyed message, F17 numeric sort).
- Type consistency: `_boardDirty`, `_localReservations`, `_remoteReservations`, `_publishedOnOriginMain`, `_numbersFromRefLines` are defined in Task 3/4 and used only there; `_oiBoardLine`/`_runBounded` only in Task 5; `MINT_OI_*` env names identical across Tasks 1, 2, 5. ✓
- Placeholders: none (`<title>` and `<sha>` are literal usage text, not plan gaps).
