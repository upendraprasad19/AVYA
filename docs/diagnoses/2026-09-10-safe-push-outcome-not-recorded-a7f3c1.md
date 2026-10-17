---
bug_id: a7f3c1
date: 2026-09-10
batch: oi172-push-result-file
status: fixed
blast_radius: platform
symptom: >
  `safe_push.sh` distinguishes THREE outcomes — 0 LANDED, 1 FAILED, 2 UNVERIFIED
  — and nothing recorded WHICH one happened. The only in-flight evidence was the
  lock's `holder` file, and `_git_lock.sh:174-189` `rm -rf`s the lock dir on a
  `trap … EXIT HUP INT TERM`, so on any normal or signalled exit that file is
  GONE. The lock can answer "is a push running right now" and structurally
  cannot answer "what happened". So a push whose stdout was lost — a reaped
  process, a closed terminal, a harness that reported `killed` while the process
  was alive and landing — left NO way to establish whether it landed except
  probing the remote and reasoning about pids. Measured 2026-09-07 (OI-172): the
  harness reported `status: killed`, PID 86281 was still alive holding the lock,
  and it went on to land the push. The failure mode is not corruption, it is a
  FALSE BELIEF about production state — the inverse of
  `feedback_git_landing_verification`'s "git said OK but it didn't land".
  A SECOND, independent defect was found in the same function while fixing this
  and is fixed here: `safe_push.sh:75`'s own resolve guard was INERT. Plain
  `git rev-parse <unresolvable>` prints the NAME to STDOUT and exits 128, so
  `LOCAL_SHA` captured the literal branch string, the `-z` guard never fired, and
  the script pushed a bogus refspec instead of printing "could not resolve local
  ref for branch". The exit on that path was effectively unreachable for the case
  it was written for.
concept: safe_push_terminal_result_record
sot_registry_entry: safe_push_terminal_result_record
writers:
  - { file: scripts/safe_push.sh, method: "_write_push_result — the SOLE writer. One STARTED record before the push, then exactly one terminal record at each of the four verdict exits (LANDED / FAILED / UNVERIFIED / FAILED-ref-did-not-move). Publishes .tmp then `mv -T`" }
  - { file: scripts/safe_push.sh, method: "the four pre-push exits (:58 not-a-repo, :60 cd-failed, :63 lock-refused, :89 unresolvable-ref) deliberately write NOTHING — a FAILED record there would claim a push failed when none was attempted. ⚠ :89 read :78 in the first draft: correct against the pre-fix file, invalidated by THIS commit's own inserted comment block above it (B-pass F1). Re-derived after the last edit" }
readers:
  - { file: scripts/push_result_lib.dart, method: "parsePushResult + classifyPushResult — the ONLY sanctioned reader; the contract lives here as code, not as prose" }
  - { file: scripts/push_result_lib.dart, method: "describePushResult — one-line human summary that names why a verdict is not stronger" }
  - { file: test/scripts/push_result_lib_test.dart, method: "21 assertions pinning the four reader rules" }
  - { file: test/scripts/safe_push_test.dart, method: "12 new subprocess assertions pinning the writer against real repos and a real remote" }
  - { file: test/contracts/safe_push_terminal_result_record_writer_to_reader_test.dart, method: "12 static assertions that the shell writer's key set and the Dart reader's key set match in BOTH directions — the seam neither language can see" }
hive_key_prefix: "n/a — a git-dir file, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a — local git state only, nothing leaves the machine"
cloud_columns: []
contract_test_path: test/scripts/push_result_lib_test.dart
ist_handling: >
  Timestamps are written as UTC ISO-8601 (`date -u +%Y-%m-%dT%H:%M:%SZ`) and are
  DIAGNOSTIC ONLY — nothing in the reader compares them, no day bucket is
  derived, and no quota or reset keys off them. This is deliberate rather than an
  oversight of the IST rule (§4.5): IST day keys exist so a user-facing daily
  reset lands at the right local midnight, and this record has no user-facing
  semantics at all. Staleness is established by comparing `ref` and `local_sha`,
  never by comparing clocks — a time-based staleness rule would have needed a
  timezone decision AND would have been wrong across a clock change.
provider_invalidations: "none — no client state, no Riverpod surface, no Flutter code touched"
telemetry_op_types: >
  None emitted. The record is a passive artifact read on demand; no counter, no
  log line, no cron telemetry. Deliberately NOT wired into
  `arm_ci_reconcile.sh`/`reconcile_ci.dart`, which answer a different question
  (did CI go green, asynchronously afterwards) — `LANDED` never means CI-green
  and the reader says so.
cross_account_guard: "n/a — no user identity involved; the file lives in the local git admin dir and is never transmitted"
forbidden_patterns_checked: >
  No raw `git commit`/`git push` added (the script IS the sanctioned wrapper).
  No `/tmp` path introduced — the record resolves through
  `git rev-parse --absolute-git-dir`, and the pre-existing `mktemp` fallback at
  the LOG line was left untouched as out of scope. No `--no-verify`. No secrets:
  the record carries exactly these thirteen, enumerated from an ACTUAL emitted
  record rather than reasoned from the writer: result, exit, branch, ref, remote,
  local_sha, remote_sha, verified_ref, pid, started, ended, worktree, reason. No
  token, no URL, no credential. ⚠ The first draft of this sentence listed only
  five and omitted remote, ref, verified_ref and worktree (B-pass F5) — and
  `worktree` is an ABSOLUTE local path, so it discloses a username on this
  machine. Not a secret, and it stays, because identifying which worktree a
  record came from is the whole point of the field. ⚠ The sanitizer collapses and
  truncates but does NOT redact, so a credential embedded in an https remote
  could in principle reach `reason`; unreachable here (origin is SSH, which
  cannot carry a password) and from no current call site (every reason passed is
  a script-authored single-line string), and now stated at the function itself
  (B-pass F6). No gitignored file written into a worktree — that is the
  central design decision (see impact_analysis). Not a new `check_*.dart` gate,
  so rule 24's ledger does not apply; `push_result_lib.dart` is a reader lib.
proposed_fix: >
  `safe_push.sh` writes `$(git rev-parse --absolute-git-dir)/.safe_push_result`:
  a `STARTED` record carrying the pid before the push, then one terminal record
  at each of the four verdict exits, published atomically as `.tmp` + `mv -T`
  and `|| true`-guarded so a write failure can never turn a landed push into a
  reported failure. `scripts/push_result_lib.dart` is the reader, holding the
  contract as CODE: absent-or-unparseable ⇒ UNVERIFIED never FAILED; both `ref`
  AND `local_sha` must match; STARTED is not a verdict; an unknown result value
  degrades to UNVERIFIED. Plus the `--verify --quiet` repair to the resolve
  guard. Plus one row in CLAUDE.md §4.9 for the narrow-filter class (the batch's
  second, independent item) and an extension of the §4.3 `safe_push.sh` bullet.
regression_test_planned: >
  Three files, 51 assertions, all green together — and the counts here were
  re-derived from `grep -c` AFTER the last edit, because the first draft of this
  field said "10 new" when the real figure was 12, in four separate places, in
  the batch whose own §4.9 row is about exactly that (B-pass F2).
  test/scripts/push_result_lib_test.dart (NEW, 21, pure — no subprocess, so it
  cannot flake under suite contention);
  test/contracts/safe_push_terminal_result_record_writer_to_reader_test.dart
  (NEW, 12 — the shell-writer/Dart-reader key contract, asserted in BOTH
  directions, which is the seam neither language can see); and 12 new cases in
  test/scripts/safe_push_test.dart (6 pre-existing → 18; real temp repos + a real
  bare remote; file `@Timeout` raised 3 → 14 minutes, and grepped afterwards to
  confirm no per-test `timeout:` overrides it — the 5th recurrence of that class
  was exactly such an override). MUTATION-PROVEN on 15 legs, detail in
  impact_analysis.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "no lib/ file touched; `git diff --stat lib/` empty" }
  - { tier: 2, name: "Hive", status: not_applicable, evidence: "no Hive box, adapter or key involved" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no migration; nothing leaves the machine" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "no query" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no EF touched" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "not cron-dispatched" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "no table" }
  - { tier: 9, name: "Storage", status: not_applicable, evidence: "no bucket or object" }
  - { tier: 10, name: "Secrets", status: verified, evidence: "the record carries branch, shas, pid, UTC timestamps and a sanitized one-line reason — no token, no URL, no user identity. Read the emitted file directly to confirm rather than reasoning from the writer" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none contacted" }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "the writer->reader chain was traced end to end against a real bare remote, not inferred: LANDED (exit 0, local_sha == remote_sha), FAILED (exit 1, non-empty reason), UNVERIFIED (exit 2, EMPTY remote_sha), a mid-flight STARTED carrying a live pid confirmed by `kill -0`, and a tag push recording ref=refs/tags/... against verified_ref=refs/heads/..." }
impact_analysis: >
  WHERE THE FILE LIVES IS THE LOAD-BEARING DECISION, and the obvious answer was
  wrong. OI-172's own text recommended `.claude/.last_push_result` — in the
  WORKTREE. That would have been the FOURTH instance of "a tool wrote a
  gitignored file into a worktree and made it permanently unretirable"
  (`docs/diagnoses/INDEX.md:45`, diagnose `b4d7e9`, OI-128): `retire_worktree_lib.dart`
  treats any unlisted gitignored path as PRECIOUS, and an atomic tmp+rename
  writer owes that list TWO entries, since a process dying mid-write leaves a
  `.tmp` with the identical blocking property. `safe_push.sh`'s own
  `arm_ci_reconcile.sh` call is one of the three prior instances, so the trap was
  one line away from the code being edited. Inside `.git` the file is invisible
  to `git status --ignored` and cannot trip the predicate at all — no
  `.gitignore` entry, no regenerable-list entries, no `.tmp` mirror. Verified by
  reading `retire_worktree.dart`'s dirty check (it runs
  `git status --porcelain --ignored=matching` with `cwd` set to the WORKING
  directory, which never touches the admin path) and by asserting in a test that
  nothing named `safe_push_result` appears in that output.
  `--absolute-git-dir` NOT `--git-dir`: measured, the latter returns a RELATIVE
  `.git` in the primary worktree and an absolute path in a linked one, so a
  reader standing anywhere else would resolve it against its own cwd.
  Per-worktree rather than `--git-common-dir`, matching `_git_lock.sh:203`'s own
  key so the existing lock already serialises writes; a shared path would NOT be
  serialised, because the lock is keyed on `--git-dir` and two linked worktrees
  can push concurrently. An earlier draft chose `--git-common-dir` and justified
  it with "the lock serialises pushes repo-wide" — that claim is false and was
  the load-bearing half of the argument.
  `mv -T` IS MANDATORY, TWICE OVER. Measured on this stack: with a DIRECTORY at
  the destination, plain `mv` exits 0 and moves the file INSIDE it — the record
  lands where no reader looks while the push reports success, a bad-news-vs-no-news
  instance. `mv -T` refuses (exit 1). Onto an existing regular FILE it replaces
  unconditionally, which every push after the first needs — checked separately,
  because a `-T` that refused to overwrite would have broken the common path.
  `_git_lock.sh:96-102` documents the same asymmetry from the other side, where
  it was the WRONG shape for that file's problem; here it is right in both
  directions.
  THE READER IS CODE BECAUSE PROSE MADE ITS OWN TEST CIRCULAR. Through three
  plan drafts the contract was a paragraph and the test invented its own reader,
  so the assertion could only prove a stand-in agreed with prose by the same
  author — and there were no real callers to be wrong. Caught by plan review
  round 3. Same pure-lib / own-test split as `ci_reconcile_state_lib.dart`, the
  reader for the gitignored file `arm_ci_reconcile.sh` writes.
  MUTATION PROOF — 15 legs, 13 red, and BOTH zero-reds were PREDICTED BEFORE
  RUNNING and then explained, per rule 21's third clause.
  ⚠ THESE COUNTS ARE THE SECOND MEASUREMENT, AND THE FIRST ONE WAS WRONG. The
  original run measured each leg against ONE test file; the B-pass re-ran six
  legs against all THREE and found three of them undercounted by exactly one
  (F7). Every leg was then re-run against the full 51-assertion suite, which is
  what is quoted below. The error direction is the instructive part: a narrower
  run can only UNDERCOUNT, so it never looks alarming — it looks like a slightly
  weaker proof, which is exactly the shape nobody re-checks. This is the same
  input-set-width class as the §4.9 row this very batch adds, committed while
  writing it. Fourth instance in two sessions.
  Each mutation was confirmed APPLIED before its run, and `sh -n` was checked
  each time so no red could come from a parse error. ⚠ FIVE applied-checks were
  themselves wrong across the two rounds and every one of them reported "PROVES
  NOTHING" rather than a count — a `grep -cF` on a token that also occurs in
  COMMENTS (so "absent" was unsatisfiable), a `grep` reading `--verify` as its
  own option, a BRE where `\(` meant a capture group, and twice a perl
  replacement where `$REPO_ROOT` interpolated to empty. The check catching its
  own failure is the only reason those did not silently become green "proofs".
  READER: delete the `ref` check → RED 3 (the two-refs-at-one-sha case, and the
  proof the lib was worth shipping); absent → FAILED → RED 3; rule-4 default →
  landed → RED 1; probedTheWrongNamespace → false → RED 1; isInFlight → false →
  RED 2; parse accepts a result-less file → RED 2; delete the isInFlight branch
  inside classify → GREEN, PREDICTED — rule 4's `default` absorbs `STARTED`, so
  that branch is defensive redundancy for CLASSIFICATION only, and the
  isInFlight→false leg (RED 2) proves the getter itself is still load-bearing via
  describePushResult.
  WRITER: revert the resolve guard to plain rev-parse → RED 1; plain `mv` for the
  publish → RED 2; collapse the UNVERIFIED RECORD into FAILED → RED 1 (guards
  `d4f9b2`); record into the WORKTREE → RED 11; drop the STARTED write → RED 3;
  ignore the kill switch → RED 1; sanitizer → passthrough → GREEN, PREDICTED —
  every `reason` this script passes is a constructed single-line string, so the
  sanitizer is defensive for FUTURE callers only and is NOT proven by this batch.
  Said plainly rather than left implied.
  ⚠ One deliberate difference from the B-pass's own numbers: it measured
  "collapse UNVERIFIED into FAILED" at RED 2 by mutating the script's EXIT CODE,
  which also reddens the pre-existing exit-2 test. The leg quoted here mutates
  only the RECORD's result value and leaves the exit code alone, which is the
  narrower and more precise claim — it isolates the record from the script's own
  verdict. Both mutations are valid; they test different things, and the numbers
  are not interchangeable.
  FIXTURE CORRECTIONS, both found by running rather than reading. Pointing
  `origin` at a nonexistent path does NOT reach the UNVERIFIED branch: `git push`
  itself then fails (128) and the FAILED path is taken. UNVERIFIED needs the push
  to SUCCEED and only the probe to fail, so `git` is stubbed on PATH to fail
  `ls-remote` alone — and that PATH entry MUST be POSIX-form, because a Windows
  `C:/...` entry is not searched by this MSYS shell, which would have made the
  test assert LANDED while claiming to test UNVERIFIED. Same class as the
  `safe_merge.sh` precheck whose fixture manufactured a state the workflow never
  produces.
  RESIDUES, NEITHER FIXED, BOTH VISIBLE. A `kill -9` still leaves no record —
  the same limit `_git_lock.sh`'s trap has, and precisely why absent must read
  UNVERIFIED. And a TAG passed where a branch is expected still gets a durably
  WRONG FAILED, because `probe_remote_sha()` hardcodes `refs/heads/$BRANCH`; the
  record now carries `verified_ref` so a reader can SEE the wrong namespace, but
  the verdict is still wrong. Zero call sites pass `--tags`. Fixing it means
  changing the script's verification semantics, which is a separate change with
  its own blast radius; recording the probed ref is contained to the new writer
  and changes no semantics. No gate reads the record, deliberately — a gate on a
  diagnostic artifact would be a ship-stop for a hygiene feature, the reasoning
  §4.13 point 6 already applies to retirement.
recurrence: >
  YES, two classes. (1) The write-into-the-worktree family — OI-128 (test
  outputs) -> `b4d7e9` (the batch-close hook's state file) -> `INDEX.md:45`
  (arm_ci_reconcile's queue, "for the third time"). This fix would have been the
  fourth and dodges the class structurally rather than joining it with two more
  allowlist entries. (2) The bad-news-vs-no-news family
  (`feedback_bad_news_vs_no_news`, 3 prior instances; `d4f9b2` for this exact
  script exiting 0 having verified nothing) — which is why absent reads as
  UNVERIFIED and why UNVERIFIED never collapses into FAILED.
related_bugs: [b4d7e9, d4f9b2, f0c2d5, a4f7c2, c9f4e1]
---

# `safe_push.sh` recorded nothing about which of its three outcomes happened

## The gap, precisely

`safe_push.sh` is the repo's only sanctioned push path and it is careful: it
verifies the remote ref moved rather than trusting git's exit code, and it
reports three distinct outcomes. All of that goes to **stdout**, and stdout is
the one thing a lost session does not keep.

The lock looked like it covered this. It does not, and the difference is the
whole bug:

| question | answered by | when |
|---|---|---|
| is a push running **right now**? | the lock's `holder` file (pid, op, started) | only while it runs |
| **what happened** to that push? | *nothing, before this fix* | — |

`git_lock_release` (`_git_lock.sh:174-189`) `rm -rf`s the lock directory, wired
to `trap … EXIT HUP INT TERM` (`:257-260`). So the moment a push finishes — the
moment you most want to ask what it did — the only artifact is deleted.

## What shipped

A record at `$(git rev-parse --absolute-git-dir)/.safe_push_result`: `STARTED` +
pid before the push, then one terminal record at each of the four verdict exits.
The four exits that precede any push attempt write **nothing** — a `FAILED`
record there would claim a push failed when none was attempted, and `:63` (a
lock refusal) is the sharpest case, since "another push is already running" and
"this push failed" are opposite facts sharing exit code 1.

The reader is `scripts/push_result_lib.dart`, and it is code rather than prose
for a reason worth stating: while it was prose, the test for it had to invent its
own reader, so it could only prove that a stand-in agreed with a paragraph
written by the same author. See `impact_analysis`.

## The second bug, found by the tests

`safe_push.sh:75` read `git rev-parse "$BRANCH"` and guarded on the result being
empty. Plain `rev-parse` prints the **unresolvable name itself to stdout** and
exits 128, so `LOCAL_SHA` became the literal string `no-such-branch-xyz`, the
guard never fired, and the script pushed a bogus refspec — reporting a confusing
`FAILED` instead of the clear "could not resolve local ref" message sitting right
there. `--verify --quiet` prints nothing on failure and resolves real branches
and tags identically.

It surfaced because a new test asserted that a pre-push abort leaves the PRIOR
record untouched, and found a `FAILED` record instead: the abort was not
aborting. Reading the guard would not have shown this; running it did.

## What this does NOT fix

- **`kill -9`** still leaves no record. Same limit the lock's trap has — and the
  reason absent must read as UNVERIFIED rather than FAILED.
- **The memory pressure** that caused the 2026-09-07 reaping. This stops the
  pressure producing false beliefs; it does not reduce it. ⚠ Anyone attacking
  that reads MEMORY.md's do-not-re-derive traps first (CI sharding,
  `PRE_COMMIT_GATE_JOBS`, Defender exclusions are all already-refuted reflexes).
- **A tag passed where a branch is expected** still gets a wrong verdict, now
  self-diagnosing via `verified_ref`.
