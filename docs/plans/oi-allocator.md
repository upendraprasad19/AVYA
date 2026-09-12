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
| `scripts/discipline_hook.dart` (modify) | SessionStart OI line (Dart-native, imports the lib) | 5 |
| `test/scripts/discipline_hook_oi_line_e2e_test.dart` (new) | hook prints next free + unfiled; silent offline | 5 |
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
#   sh scripts/mint_oi.sh --next                 read-only: prints NEXT=<n> and UNFILED=<n,n>
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
GH=${MINT_OI_GH_BIN:-gh}
MAX_ATTEMPTS=10

usage() {
  cat >&2 <<'USAGE'
usage: sh scripts/mint_oi.sh [--no-append] "<title>"
       sh scripts/mint_oi.sh --reserve N "<title>"
       sh scripts/mint_oi.sh --prune | --next
USAGE
  exit 64
}

MODE=mint
APPEND=1
RESERVE_N=''
TITLE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --no-append) APPEND=0 ;;
    --reserve)
      [ $# -ge 2 ] || usage
      RESERVE_N=$2
      APPEND=0
      shift ;;
    --prune) MODE=prune ;;
    --next) MODE=next ;;
    -h|--help) usage ;;
    -*) echo "$TAG unknown flag: $1" >&2; usage ;;
    *) TITLE=$1 ;;
  esac
  shift
done
if [ -n "$RESERVE_N" ]; then
  case "$RESERVE_N" in ''|*[!0-9]*) echo "$TAG --reserve needs a positive integer" >&2; usage ;; esac
fi
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
sync_refs() {
  git fetch --quiet --prune "$REMOTE" \
    "+refs/heads/oi/*:refs/remotes/$REMOTE/oi/*" \
    "+refs/heads/main:refs/remotes/$REMOTE/main" >/dev/null 2>&1
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
    | sed 's#.*/oi/##' | grep -E '^[0-9]+$' || true
}

next_free() {
  n=$( { reserved_numbers; board_numbers "refs/remotes/$REMOTE/main"; board_numbers ''; } \
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

do_prune() {
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  pruned=0
  for n in $(reserved_numbers); do
    contains_line "$published" "$n" || continue
    case "$TRANSPORT" in
      api)
        repo=$(owner_repo)
        $GH api -X DELETE "repos/$repo/git/refs/heads/oi/$n" >/dev/null 2>&1 \
          || { echo "$TAG prune: could not delete oi/$n" >&2; continue; } ;;
      git)
        git push --quiet "$REMOTE" ":refs/heads/oi/$n" >/dev/null 2>&1 \
          || { echo "$TAG prune: could not delete oi/$n" >&2; continue; } ;;
    esac
    git update-ref -d "refs/remotes/$REMOTE/oi/$n" 2>/dev/null || true
    pruned=$((pruned + 1))
  done
  echo "$TAG pruned $pruned reservation(s) whose number is already on $REMOTE/main."
}

do_next() {
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  local_nums=$(board_numbers '')
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
  if [ "$TRANSPORT" = git ]; then
    git update-ref "refs/remotes/$REMOTE/oi/$n" "$RESULT_SHA"
  else
    git fetch --quiet "$REMOTE" "+refs/heads/oi/$n:refs/remotes/$REMOTE/oi/$n" >/dev/null 2>&1 \
      || echo "$TAG note: reserved on $REMOTE, but could not fetch oi/$n locally; sibling worktrees see it at their next sync." >&2
  fi
  if [ $APPEND -eq 1 ]; then append_stub "$n"; fi
  echo "OI-$n"
  if [ "$TRANSPORT" = api ]; then do_prune >/dev/null 2>&1 || true; fi
}

sync_refs || {
  echo "$TAG cannot reach $REMOTE — an OI number cannot be reserved offline. Nothing was written." >&2
  exit 2
}
case "$MODE" in
  next)  do_next ;;
  prune) do_prune ;;
  mint)  do_mint ;;
esac
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/scripts/mint_oi_e2e_test.dart`
Expected: 6 tests PASS. If the race test fails with `OI-4`, the CAS did not fire — check the `--force-with-lease=refs/heads/oi/$1:` spelling (the trailing colon is the empty `<expect>`).

- [ ] **Step 5: Mutations — apply, confirm applied, run, revert**

1. `sed -i 's/--force-with-lease="refs\/heads\/oi\/$1:"/--force/' scripts/mint_oi.sh` → `grep -c -- '--force-with-lease' scripts/mint_oi.sh` must print `0`. Run the file. Expected red: the race test (B prints `OI-4`, `oi/4` now points at B's ledger sha) and the `--reserve` test (the taken reserve succeeds). Record the count. `git checkout -- scripts/mint_oi.sh`.
2. Remove `board_numbers ''` from `next_free` → confirm with `grep -c "board_numbers ''" scripts/mint_oi.sh` → `0`… note `do_next` also calls it, so expect `1`, and verify the `next_free` line specifically. Run. Expected red: the hand-typed-working-board test (`OI-10` re-issued instead of `OI-11`). Revert.
3. Sanity: `sh -n scripts/mint_oi.sh` exits 0 (parse check every hook does before sourcing).

- [ ] **Step 6: Commit**

```bash
git add scripts/mint_oi.sh test/scripts/mint_oi_e2e_test.dart
sh scripts/safe_commit.sh "feat(board): mint_oi.sh — reserve OI numbers as oi/N branches via a remote CAS (git transport)

Sync = git fetch of refs/heads/oi/* into the shared .git; write =
git push --force-with-lease=<ref>: (empty expect = must not exist).
Offline refuses (exit 2, nothing written). --reserve N for numbers
filed before the allocator. Test seam MINT_OI_TEST_HOOK_BEFORE_PUSH
makes the race reachable in the e2e test.

Tests: test/scripts/mint_oi_e2e_test.dart (6). Mutation: --force in
place of --force-with-lease reddens the race + reserve tests; dropping
the working-board term from next_free reddens the hand-typed test.
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
  - { file: scripts/check_oi_numbering_unique.dart, method_or_widget: "shape dispatch — the `parents.length >= 3` arm fired on a zero-commit worktree and read HEAD^1/HEAD^2 instead of the working tree", line: 279 }
  - { file: scripts/check_oi_numbering_unique.dart, method_or_widget: "useWorkingTree = otherSideRev == 'HEAD' — false in the merge arm, so headOpen/headClosed (the working tree) were never compared", line: 322 }
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

Nothing else changes: `useWorkingTree = otherSideRev == 'HEAD'` is already true for this arm, so `headOpen`/`headClosed` (read from the working tree at the top of `main`) are what get compared.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/scripts/oi_numbering_gate_e2e_test.dart test/scripts/oi_numbering_lib_test.dart`
Expected: all PASS (2 new + the lib's existing 23). Also `dart analyze scripts/check_oi_numbering_unique.dart` → no issues.

- [ ] **Step 6: Mutations — apply, confirm, run, revert; paste counts into the diagnose-doc**

1. Delete the whole `else if (_boardDirty()) {...}` arm → `grep -c '_boardDirty()' scripts/check_oi_numbering_unique.dart` → `0` (the helper definition remains; the CALL is gone). Run. Expected: test 1 reddens with the vacuous PASS line. Revert.
2. In the new arm, replace `baseRev = _run('git', ['merge-base', 'HEAD', 'origin/main'])?.trim();` with `baseRev = 'origin/main';` → base == mainline → degenerate. Run. Expected: test 1 reddens (vacuous PASS). Test 2 stays green. Revert.
3. Confirm every mutation compiled (a `loading … [E]` line means it did not — pick another mutation, per rule 21).

Then flip OI-176 on the board (`docs/audit/open_issues.md:3314`): `- **Status**: OPEN` → `- **Status**: CLOSED · 2026-09-12 · diagnose f3a9c1 · branch oi-allocator — working-tree arm in check_oi_numbering_unique.dart; allocator in scripts/mint_oi.sh`. Leave the entry in place (archiving to `closed_issues.md` is a separate board-hygiene action).

- [ ] **Step 7: Commit**

```bash
git add scripts/check_oi_numbering_unique.dart test/scripts/oi_numbering_gate_e2e_test.dart docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-f3a9c1.md docs/audit/open_issues.md
sh scripts/safe_commit.sh "fix(gates): check_oi_numbering_unique compares the UNCOMMITTED board against origin/main whatever shape HEAD has

A zero-commit worktree cut from a merge-commit tip took the merge arm
and compared HEAD^1 vs HEAD^2 -- two ancestors of the branch point --
printing PASS (vacuous) while the staged board collided with main.
New arm dispatches on 'board differs from HEAD', after mid-merge and
before the merge-commit arm.

Regression test: test/scripts/oi_numbering_gate_e2e_test.dart (2).
Mutations: deleting the arm reddens 1; base := origin/main reddens 1.

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

- [ ] **Step 1: Write the failing tests** (append inside `main()` of the gate e2e file)

```dart
  test('Check C: a number new on the branch with a matching origin/oi/N reservation passes', () {
    final f = _Fx.create('reserved');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'reserved four');
    f.reserve(4);
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
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

  test('Check C: no local reservation ref AND remote unreachable -> SKIPPED (exit 0, UNDETERMINED, no PASS)', () {
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
    expect(r.stdout as String, isNot(contains('PASS')));
    expect(r.stdout as String, contains('SKIPPED'));
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
Expected: "reserved" and "published" PASS already (nothing fails them yet); "unreserved" FAILS (gate exits 0); "offline" FAILS (no `UNDETERMINED` on stderr — the collision arm's `origin/main` reads are local and succeed, so today the gate prints PASS).

- [ ] **Step 3: Implement Check C**

Add helpers next to `_showAtRev`:
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

/// ONE `ls-remote` for the whole namespace, bounded to 5 s. null = could not
/// answer (offline, timeout, no remote) -- UNDETERMINED, never "not reserved".
Future<Set<int>?> _remoteReservations() async {
  try {
    final p = await Process.start('git', ['ls-remote', '--refs', 'origin', 'refs/heads/oi/*']);
    final out = p.stdout.transform(utf8.decoder).join();
    p.stderr.drain<void>();
    final code = await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
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

Then, in `main`, immediately after the three merged maps are built (after `final otherMerged = mergeBoards(otherOpen, otherClosed);`) and BEFORE the `mainlineMintedNothing` vacuous check — Check C must run even when the collision check is vacuous:
```dart
        // ---- Check C: every number this side minted is RESERVED ---------------
        // (allocator, 2026-09-12; spec §3.3). Numbers are allocated by
        // scripts/mint_oi.sh as refs/heads/oi/N; a hand-typed number has no
        // reservation and must not commit. Network only when there is something
        // unreserved locally to ask about; offline => UNDETERMINED, never PASS.
        final mintedHere = otherMerged.keys.where((n) => !baseMerged.containsKey(n)).toList()
          ..sort();
        if (mintedHere.isNotEmpty) {
          final published = _publishedOnOriginMain();
          if (published == null) {
            undetermined = true;
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
                  undetermined = true;
                  _warnPass('OI-$n has no local reservation ref and origin could not be '
                      'reached to check refs/heads/oi/$n. Reservation check skipped for it.');
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

- [ ] **Step 4: Run the tests**

Run: `flutter test test/scripts/oi_numbering_gate_e2e_test.dart test/scripts/oi_numbering_lib_test.dart`
Expected: 6 + 23 PASS. Then run the gate once in the real worktree — `dart run scripts/check_oi_numbering_unique.dart` — with a clean board: expect `PASS` or `SKIPPED`, never a failure (no `mintedHere`).

- [ ] **Step 5: Mutations — apply, confirm, run, revert**

1. `(remote?.contains(n) ?? false)` → `(remote?.contains(n) ?? true)` → confirm with `grep -c '?? true' scripts/check_oi_numbering_unique.dart` → `1`. Run. Expected: the offline test reddens (no UNDETERMINED). Revert.
2. Delete the `failures.add(...)` statement inside Check C (leave the loop). Run. Expected: the unreserved test reddens. Revert.
3. Delete `.where((n) => !published.contains(n))` (check published numbers too). Run. Expected: the published test still passes locally (the reservation lookup finds nothing, remote reachable → FAIL → reddens). Good — it reddens. Revert.

- [ ] **Step 6: Ledger evidence**

In `docs/audit/gate_test_ledger.yaml:436-438`, add `test/scripts/oi_numbering_gate_e2e_test.dart` to `test_path:` and append to `evidence:` one sentence per mutation above and per Task 3 mutation, with counts, dated 2026-09-12. Run `dart run scripts/check_gate_test_ledger.dart` → PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/check_oi_numbering_unique.dart test/scripts/oi_numbering_gate_e2e_test.dart docs/audit/gate_test_ledger.yaml
sh scripts/safe_commit.sh "feat(gates): check_oi_numbering_unique requires a refs/heads/oi/N reservation for every number minted on the branch

Check C: numbers new vs the merge-base and not yet on origin/main's
board must have a reservation -- local refs/remotes/origin/oi/N first,
then ONE bounded (5 s) ls-remote; unreachable => UNDETERMINED/SKIPPED,
never PASS. Published numbers are exempt (prune may have removed their
reservation). main is now async for the bounded spawn.

Tests: +4 in test/scripts/oi_numbering_gate_e2e_test.dart. Mutations:
null-as-reserved reddens offline; dropping failures.add reddens
unreserved; dropping the published exemption reddens published."
```

---

### Task 5: SessionStart — "next free number" line (Dart-native, no `sh` dependency)

**Files:**
- Modify: `scripts/discipline_hook.dart:105-118` (SessionStart case) + new helpers; add `import 'oi_numbering_lib.dart';`
- Create: `test/scripts/discipline_hook_oi_line_e2e_test.dart`
- Modify: spec §3.4 (one sentence: the hook computes `--next` in Dart via the shared lib instead of shelling to `sh`, because `sh` is not guaranteed on the PATH of a Dart process the harness starts on Windows; `--next` stays in the script for humans and the cloud).

**Interfaces:**
- Consumes: `parseBoard`, `mergeBoards`, `nextFreeNumber` from `scripts/oi_numbering_lib.dart`; the `refs/remotes/origin/oi/*` namespace from Task 1.
- Produces: one `additionalContext` paragraph beginning `OI board: next free number is <n>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/scripts/discipline_hook_oi_line_e2e_test.dart
//
// The SessionStart hook must tell every session the next free OI number and
// the one command to mint with -- and must stay SILENT (not wrong) offline.

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

void main() {
  final src = Directory.current.path;
  final dart = _dartBin();

  late Directory tmp;
  late String remote;
  late String clone;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hook_oi_');
    remote = '${tmp.path}/remote.git';
    clone = '${tmp.path}/clone';
    Directory(remote).createSync();
    expect(_git(['init', '-q', '--bare', '-b', 'main', '.'], remote).exitCode, 0);
    Directory(clone).createSync();
    expect(_git(['clone', '-q', 'file:///${_fwd(remote)}', '.'], clone).exitCode, 0);
    _git(['config', 'user.email', 't@example.invalid'], clone);
    _git(['config', 'user.name', 'T'], clone);
    File('$clone/docs/audit/open_issues.md').createSync(recursive: true);
    File('$clone/docs/audit/open_issues.md')
        .writeAsStringSync('# board\n${_entry(1, 'a')}${_entry(2, 'b')}${_entry(3, 'c')}${_entry(4, 'd')}');
    File('$clone/docs/audit/closed_issues.md').writeAsStringSync('# closed\n');
    expect(_git(['add', '-A'], clone).exitCode, 0);
    expect(_git(['commit', '-q', '-m', 'seed'], clone).exitCode, 0);
    expect(_git(['push', '-q', '-u', 'origin', 'main'], clone).exitCode, 0);
    // A reservation nobody has filed yet.
    expect(_git(['push', '-q', 'origin', 'HEAD:refs/heads/oi/5'], clone).exitCode, 0);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('SessionStart prints next free = max(board, reservations)+1 and the unfiled reservation', () async {
    final out = await _hookOutput(dart, src, clone, '{"hook_event_name":"SessionStart","source":"startup"}');
    expect(out, contains('OI board: next free number is 6'));
    expect(out, contains('Reserved-but-unfiled: oi/5'));
    expect(out, contains('sh scripts/mint_oi.sh'));
  });

  test('SessionStart stays silent about the board when origin is unreachable', () async {
    Directory(remote).renameSync('$remote.gone');
    final out = await _hookOutput(dart, src, clone, '{"hook_event_name":"SessionStart","source":"startup"}');
    expect(out, isNot(contains('OI board')));
  });
}

Future<String> _hookOutput(String dart, String src, String cwd, String stdinJson) async {
  final p = await Process.start(dart, ['run', '$src/scripts/discipline_hook.dart'],
      workingDirectory: cwd, environment: _cleanEnv(), includeParentEnvironment: false);
  p.stdin.write(stdinJson);
  await p.stdin.close();
  final out = p.stdout.transform(utf8.decoder).join();
  p.stderr.drain<void>();
  await p.exitCode;
  return out;
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/scripts/discipline_hook_oi_line_e2e_test.dart`
Expected: test 1 FAILS (no `OI board` text in the hook's output). Test 2 passes vacuously — fine; it is the guard for the failure mode, and Step 4's mutation 2 exercises it.

- [ ] **Step 3: Implement**

In `scripts/discipline_hook.dart`: add `import 'oi_numbering_lib.dart';` beside the existing imports; in the `SessionStart` case add, after the `memNudge` lines:
```dart
        final oiLine = await _oiBoardLine();
        if (oiLine.isNotEmpty) parts.add(oiLine);
```
(`main` is already `async`.) Add the helpers at file bottom:
```dart
/// OI allocator (spec docs/superpowers/specs/2026-09-12-oi-allocator-design.md
/// §3.4): tell the session the next free number and the ONE way to mint.
/// Best-effort and fail-open: bounded fetch, any error => empty string. No
/// remote writes here; pruning lives in mint_oi.sh.
Future<String> _oiBoardLine() async {
  try {
    final top = Process.runSync('git', ['rev-parse', '--show-toplevel'], stdoutEncoding: utf8);
    if (top.exitCode != 0) return '';
    final root = (top.stdout as String).trim();
    final code = await _runBounded(
        'git',
        ['fetch', '--quiet', '--prune', 'origin',
          '+refs/heads/oi/*:refs/remotes/origin/oi/*',
          '+refs/heads/main:refs/remotes/origin/main'],
        root,
        const Duration(seconds: 6));
    if (code != 0) return '';

    String show(String path) {
      final r = Process.runSync('git', ['show', 'origin/main:$path'],
          workingDirectory: root, stdoutEncoding: utf8);
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

    final next = nextFreeNumber([published, working, {for (final r in reserved) r: ''}]);
    final unfiled = reserved
        .where((n) => !published.containsKey(n) && !working.containsKey(n))
        .toList()
      ..sort();
    final now = DateTime.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return 'OI board: next free number is $next (synced with origin at $hhmm). '
        'Reserved-but-unfiled: ${unfiled.isEmpty ? 'none' : unfiled.map((n) => 'oi/$n').join(', ')}.\n'
        'File new OIs ONLY with:  sh scripts/mint_oi.sh "<title>"  — never type a number by '
        'hand; a hand-typed number fails the commit (CLAUDE.md §7, OI allocator row).';
  } catch (_) {
    return '';
  }
}

Future<int> _runBounded(String exe, List<String> args, String cwd, Duration limit) async {
  final p = await Process.start(exe, args, workingDirectory: cwd);
  p.stdout.drain<void>();
  p.stderr.drain<void>();
  return p.exitCode.timeout(limit, onTimeout: () {
    p.kill();
    return -1;
  });
}
```

- [ ] **Step 4: Run; mutate; revert**

Run: `flutter test test/scripts/discipline_hook_oi_line_e2e_test.dart test/scripts/batch_close_hook_e2e_test.dart` → PASS.
Mutations: (1) `nextFreeNumber([...])` → `nextFreeNumber([published, working])` (drop reservations) → test 1 reddens (`5` not `6`); (2) `if (code != 0) return '';` → `if (false) return '';` → test 2 reddens (a stale line prints offline). Confirm each applied by grep; revert.
Also `dart analyze scripts/discipline_hook.dart` → no issues.

- [ ] **Step 5: Commit**

```bash
git add scripts/discipline_hook.dart test/scripts/discipline_hook_oi_line_e2e_test.dart docs/superpowers/specs/2026-09-12-oi-allocator-design.md
sh scripts/safe_commit.sh "feat(hooks): SessionStart prints the next free OI number and the mint command

Bounded (6 s) fetch of refs/heads/oi/* + main, then max over published,
working and reserved via oi_numbering_lib; lists reserved-but-unfiled.
Silent on any failure. Dart-native rather than shelling to mint_oi.sh
--next: sh is not guaranteed on a harness-started Dart process's PATH on
Windows (spec §3.4 amended).

Tests: test/scripts/discipline_hook_oi_line_e2e_test.dart (2).
Mutations: dropping reservations from the max reddens 1; ignoring the
fetch failure reddens 1."
```

---

### Task 6: Docs — board filing rule, CLAUDE.md §7 row, handbook page

**Files:**
- Modify: `docs/audit/open_issues.md:9-11`
- Modify: `CLAUDE.md` §7 row beginning `| **OI number uniqueness across branches**`
- Create: `docs/handbook/process/oi-allocator.md`
- (Considered, no change: `.claude/skills/debugging/SKILL.md` — no new bug class; the eyeball-minted-sequence class is OI-167's and this batch resolves the OI-board instance of it, not the skill-numbering instance.)

- [ ] **Step 1: Board header** — after the `Append-only at the bottom.` bullet add:

```markdown
- **Numbers are ALLOCATED, never eyeballed (2026-09-12).** File a new issue with
  `sh scripts/mint_oi.sh "<title>"` — it reserves the next free number as the
  remote branch `oi/N` (an atomic create on GitHub, so two sessions cannot both
  get N, laptop or cloud) and appends the stub. A hand-typed number FAILS the
  commit (`check_oi_numbering_unique.dart`, Check C). A number filed before the
  allocator existed: `sh scripts/mint_oi.sh --reserve N "<title>"`. Never mint
  offline — the script refuses, by design. Spec:
  `docs/superpowers/specs/2026-09-12-oi-allocator-design.md`.
```

- [ ] **Step 2: CLAUDE.md §7 row** — replace the two cells of the OI-uniqueness row with:

Left: `**OI number uniqueness across branches** — numbers are ALLOCATED by \`scripts/mint_oi.sh\` (2026-09-12), never eyeballed. Before it: no allocator, the ceiling split across two files, six manual renumbers by 2026-09-12 (the last, 177/178→186/187, landed while the allocator was being specified). The detector alone was structurally late — two of its three placements run after the number is committed, and the early one was vacuous in the zero-commit worktree state (OI-176).`

Right: `\`scripts/mint_oi.sh\` reserves \`refs/heads/oi/N\` as a server-side compare-and-swap: \`gh api\` on the laptop (NOT a \`git push\`, so pre-push never runs), \`git push --force-with-lease=<ref>:\` in the cloud (no \`gh\`, no hooks, and its credential writes \`refs/heads/**\` only — \`refs/oi/*\` is a 403). Sync is \`git fetch\` into the SHARED \`.git/\`, so every laptop worktree sees a reservation instantly. Offline ⇒ the mint REFUSES (exit 2, nothing written) — the one deliberately fail-closed step; gates stay fail-open. Gate \`scripts/check_oi_numbering_unique.dart\`: Check B′ compares the UNCOMMITTED board against origin/main whatever shape HEAD has (closes OI-176, diagnose \`f3a9c1\`); Check C fails a commit whose new number has no \`oi/N\` (published numbers exempt; offline ⇒ SKIPPED). SessionStart prints \`next free number is N\`. GitHub Issues as the allocator was REJECTED: issues+PRs share one sequence, max #23 < OI-185. Tests: \`test/scripts/mint_oi_e2e_test.dart\` (9), \`oi_numbering_gate_e2e_test.dart\` (6), \`discipline_hook_oi_line_e2e_test.dart\` (2) — counts are PROSE; re-run rather than trust. Spec: \`docs/superpowers/specs/2026-09-12-oi-allocator-design.md\`.`

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
git add docs/audit/open_issues.md CLAUDE.md docs/handbook/process/oi-allocator.md docs/handbook/INDEX.md
sh scripts/safe_commit.sh "docs(board): filing rule, CLAUDE.md §7 allocator row, handbook page — OI numbers are allocated, never eyeballed"
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
- [ ] **Step 7: First real mint** — from the primary worktree after the push: `sh scripts/mint_oi.sh --next` → expect `NEXT=` = 1 + main's board max (re-derive; do not trust any number in this plan). Do NOT mint a real number without an issue to file.
- [ ] **Step 8: §5 batch-close rows** — retrospective `memory/project_oi_allocator_shipped_<date>.md`; retire the `IN-FLIGHT` index line to `MEMORY_ARCHIVED.md`; correct `project_regen_alignment_brainstorm_inflight.md`'s "177/178" to "186/187"; `dart run scripts/retire_worktree.dart` (dry-run) then `--execute oi-allocator`; `dart run scripts/check_context_artifact_budget.dart`.

---

## Self-review against the spec

- §3.1 reservation = branch + orphan commit on main's tree + ledger message → Task 1 `ledger_commit` / `cas_write`. ✓
- §3.2 all five invocations, exit codes, transports, retry, test seam, stub fields, prune rule → Tasks 1–2. ✓
- §3.3 Check B′ + Check C, published exemption, 5 s bound, SKIPPED-never-PASS → Tasks 3–4. ✓
- §3.4 SessionStart line → Task 5 (Dart-native; spec amended in the same commit). ✓
- §3.5 docs → Tasks 3 (diagnose-doc, OI-176 CLOSED), 6 (board, CLAUDE.md, handbook). ✓
- §6 tests and mutations → each task's mutation step; the "tests 1–2 do NOT redden under `--force`" caveat is carried into Task 1 Step 5. ✓
- §7 residues unchanged; §8 rollout → Task 7 Steps 6–8. ✓
- Type consistency: `_boardDirty`, `_localReservations`, `_remoteReservations`, `_publishedOnOriginMain`, `_numbersFromRefLines` are defined in Task 3/4 and used only there; `_oiBoardLine`/`_runBounded` only in Task 5; `MINT_OI_*` env names identical across Tasks 1, 2, 5. ✓
- Placeholders: none (`<title>` and `<sha>` are literal usage text, not plan gaps).
