---
bug_id: eeca32
date: 2026-10-24
batch: merge-conflict-treadmill-a2
status: fixed
blast_radius: platform
symptom: >-
  docs/audit/OPEN_INDEX.md and docs/diagnoses/INDEX.md were COMMITTED files that a
  pre-commit hook rewrote whole whenever a board or a diagnose doc was staged. Every
  parallel branch that filed an OI or a diagnose doc therefore changed the same generated
  file, and git conflicted in it at the next sync: of 52 replayed main-sync merges,
  OPEN_INDEX.md conflicted in 20 and diagnoses/INDEX.md in 13 (OI-309). Three latent
  defects sat behind the same files. (1) Nothing in CI checked the OI index: the comment
  in test.yml cited a freshness gate named check_oi_index_fresh, which never existed.
  (2) The diagnose-index builder only WARNED about a doc whose frontmatter did not parse
  and left it out of the index that CLAUDE.md 4.1.5 makes the mandatory first lookup; a
  doc with no date crashed its sort with a TypeError; and the only check that bug_id
  matches the file name was Gate 25, a freshness comparison of the committed file.
  (3) Both builders wrote the output in place and called exit(1) in the middle of
  their work, so a reader could see half a file and a caller could not tell a
  validation failure from a failed write.
concept: local_generated_indexes
sot_registry_entry: local_generated_indexes
writers:
  - file: scripts/build_oi_index.dart
    method: runOiIndex (strict and lenient validation, unreadable board and unreadable headers, stat digest taken before the board is read, writeLocalIndex)
    line: 299
  - file: scripts/build_bug_index.dart
    method: runBugIndex (validateDiagnoseDocs strict and lenient, stat digest taken before the docs are read)
    line: 30
  - file: scripts/local_indexes_lib.dart
    method: writeLocalIndex (temp file then rename, exit 3), statDigest, indexState, isStale
    line: 221
  - file: scripts/build_local_indexes.dart
    method: runLocalIndexes (both builders, each guarded, worst exit, self-check), ensureLocalIndexes, ensureBugIndexFresh, resolveLocalIndexesRoot
    line: 74
  - file: scripts/pre-commit.sh
    method: diagnose-index and OI-index regen blocks (exit 3 warns, 1 blocks, a tracked-only add) and the MERGE_HEAD lenient build behind the tracked/builder guard
    line: 187
  - file: scripts/pre-merge-commit.sh
    method: ignored-index branch (validate only: no backup, no restore, no NOTE; exit 3 warns)
    line: 176
readers:
  - file: scripts/discipline_hook.dart
    method_or_widget: localIndexesNudge (stat only, no spawn, own try/catch) and _hooksNotReinstalledWarning
    line: 457
  - file: scripts/local_indexes_lib.dart
    method_or_widget: indexState (the ONE staleness predicate, 256 bytes of each output)
    line: 182
  - file: scripts/check_regression_catalog.dart
    method_or_widget: main (walks docs/diagnoses/INDEX.md on a merge commit; it first makes sure of its own input through ensureBugIndexFresh, and pre-commit.sh also builds it when untracked)
    line: 15
  - file: scripts/check_context_artifact_budget.dart
    method_or_widget: kTrackedArtifacts (budgets OPEN_INDEX.md as built locally; absent is SKIPPED)
    line: 48
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/local_indexes_e2e_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'exit\(1\);', absent: true }   # in scripts/build_oi_index.dart and scripts/build_bug_index.dart: every failure is a return, so the orchestrator can run both builders and report the worst code
  - { pattern: 'git add docs/(diagnoses|audit)/(OPEN_)?INDEX\.md', absent: true }   # scripts/pre-commit.sh stages an index only when it is tracked (A0), and A2 untracks both
  - { pattern: 'git ls-files[^\n]*(OPEN_INDEX|diagnoses/INDEX)', absent: false }   # exactly four sites ask git whether these paths are tracked: scripts/check_local_indexes_untracked.dart and the three guards in scripts/pre-commit.sh (the two regen blocks and the merge-time build)
proposed_fix: >-
  Both indexes become gitignored, untracked LOCAL BUILD PRODUCTS (git rm --cached; two
  exact .gitignore lines; both on retire_worktree_lib.dart's regenerable list).
  scripts/local_indexes_lib.dart is the one home of what the builders, the orchestrator
  and the SessionStart nudge must agree on: each index's input list, the predicate that
  selects diagnose docs (a .md that is not INDEX, README or TEMPLATE, so an editor
  backup never counts), a stamp on line 1 of each output (sha256 over the sorted
  "name size mtime" text of every input, taken from stat BEFORE the inputs are read),
  one staleness predicate, and an atomic write (temp file under .dart_tool/local_indexes,
  rename, one retry after 200 ms; exit 3 when validation passed and the write failed).
  runOiIndex and runBugIndex return exit codes instead of calling exit. STRICT is the
  default (CI and pre-commit): a diagnose doc must have parseable frontmatter, a date, a
  usable symptom and a bug_id equal to its 6-character file-name suffix or its whole stem
  (this replaces Gate 25, which is deleted); its date must be a BARE YYYY-MM-DD, the only
  shape the merge-commit regression walk can read; an unknown OI status, a missing field
  or a `## OI-N` header the section regexp cannot read fails. --lenient skips or FLAGS the
  offender, says so, and writes the rest; a duplicate OI number, an unreadable board and an
  unreadable docs/diagnoses fail in both modes. scripts/build_local_indexes.dart builds
  both, always runs both (a builder that throws counts as 1 and does not stop the other),
  returns the worst code, and self-checks that the result is not stale. Who builds:
  pre-commit (a staged board or diagnose doc, and a lenient diagnose build before the
  catalog walk on a merge commit, only from a tree that has the orchestrator AND where the
  index is untracked), pre-merge-commit (validate only), the catalog walk itself (it makes
  sure of its own input, so an installed hook copy that predates A2 cannot block a merge),
  CI (a plain strict step before the shard run and before the Audit Gates loop), and a
  developer by hand. No Claude Code hook builds anything. The nudge (SessionStart and bug-shaped prompts, stat only, no
  spawn) says "Local indexes stale/missing", and SessionStart warns once when the
  installed pre-commit or pre-merge-commit lacks the A2-only literal. A new gate,
  check_local_indexes_untracked.dart, fails when either path is tracked again.
regression_test_planned:
  - test/scripts/local_indexes_e2e_test.dart
  - test/scripts/bug_index_strict_test.dart
  - test/scripts/check_local_indexes_untracked_test.dart
  - test/scripts/ci_local_indexes_steps_test.dart
  - test/scripts/discipline_hook_local_indexes_e2e_test.dart
  - test/scripts/pre_commit_index_add_e2e_test.dart
  - test/scripts/pre_merge_commit_e2e_test.dart
  - test/scripts/script_closure_fixture_test.dart
  - test/scripts/gitignore_classification_test.dart
  - test/scripts/context_artifact_tracked_list_test.dart
  - test/scripts/gate_index_e2e_test.dart
related_bugs:
  - c5e1a8  # A0: hooks are installed atomically and read-only, and the hook stages an index only when it is tracked; this landing is the one A0 prepared
  - c4e8a2  # 237 of 344 entries of this very index carried no symptom: the strict rules are what now stops that regrowing, with Gate 25 gone
  - b7e3d1  # the OI-collision invariant: a duplicate OI number still fails closed, in lenient mode too
  - f4d1b7  # the diagnose index needs a stable total order (date, then path), kept and now pinned with 80 same-day docs
recurrence: |
  Same class as OI-309 and the sync-merge replays in the plan (docs/plans/merge-conflict-treadmill.md
  section 0): a generated file that is committed gets rewritten by every branch. The earlier
  attempts treated the symptoms: f4d1b7 removed a timestamp that made the committed index
  differ on every run, and Gate 25 checked the committed copy for completeness. This instance
  removes the committed copy. It is not a recurrence of c4e8a2 (a builder that wrote
  placeholders), but with Gate 25 deleted the strict builder is that fix's only guard, so the
  strict rules are pinned by a test over the whole real corpus and by the CI build step.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Tooling only (the one lib/ line is a comment in lib/features/ai_coach/screens/ai_coach/recording_body.dart that pointed at the index; no behaviour change in lib/): local_indexes_lib.dart, both builders, the orchestrator, bug_index_lib.dart validateDiagnoseDocs, the nudge, pre-commit.sh, pre-merge-commit.sh, test.yml, the new gate. 11 test files touched or added (plus one helper and seven frozen fixture files); the touched set is 257 tests, 319 with the three contract files that run the same builders (oi_index_test, bug_index_frontmatter_test, ci_unit_test_matrix_shape_test), all green on the final tree. Mutation proof (rule 21), each applied (re-read after the write, and the file analyzed clean before its run), run, restored (sha256 equal afterwards): 116 mutants on the sources and hooks, 99 reddened a test, 17 SURVIVED. Each survivor was a real hole in a test, not an equivalent mutant (one was equivalent as written and the rule was widened): lib-02 size omitted (the size-only fixture restored the mtime through File.setLastModified, which has SECOND resolution, so the digest changed through the mtime term), lib-14 head bytes (the test compared the constant with itself), lib-21 isStale ignoring a MISSING output (no direct test), lib-24 and lib-25 write failures exiting 1 (only a non-empty directory had been tested), lib-30 pid dropped from the temp name, bug-07 the sort tiebreak (needs more than 32 same-day docs), bug-09 a missing docs/diagnoses reported as success, blib-06 a blank or quoted-empty date (unreachable as written: the parser drops empty values; the rule now unquotes), orch-07 ensureLocalIndexes always rebuilding (the check compared File.lastModified, second resolution, with a rebuild inside the same second), nud-01 the nudge's own catch (chmod 000 makes the output read as missing before anything is listed, so nothing threw; mode 111 does), nud-03 the hooks-warning guard (the fixture installed the real A2 hooks, so no warning could appear either way), pc-01 the tracked-index guard of the merge-time build (case 9b used OLD scripts, which the orchestrator guard already skips), pc-05 a failing merge-time build waved through, pm-03 a backup taken for an ignored index (no scenario had the file on disk), gi-01 and gi-02 the two .gitignore lines (the retire-list tests cannot see them; git is now asked). One more, pc-09, was reported by the harness as a possible compile error only because its fixtures deliberately break the builder; the three tests it reddened are the expected builder-failure-blocks cases, so it counts as killed. Every survivor got a test or a code change and the survivors were re-run on the final tree: 20 re-run mutants (the 17 survivors, with the date rule split into its two variants, plus the original date-check mutant and pc-09 again), all 20 reddened at least one test, and the files were restored byte-identical (sha256 equal) after every run. Separately: the CI steps (10 mutants, 10 killed) and the new gate (13 mutants, 13 killed, ledger evidence). The B-pass round (two fresh seats, see the section below): the reviewers ran 41 mutants of their own, 19 reddened a test and 22 survived (21 real holes and 1 equivalent, parseStamp without trimRight, whose regexp ends in an optional whitespace run). Every survivor and every finding got a test or a code change, and the author then ran 43 mutants against the final tests, one per reviewer survivor or finding and per fix (each applied with an anchor count of 1, analyzed clean, run, restored with sha256 equal): 42 reddened at least one test, and the 43rd (PC-1, the board site of pre-commit.sh blocking only on exit 1) reddened exactly the two tests written for it, the two 3c cases, while the other 37 tests of the file passed; the harness flagged it as a possible compile error only because those fixtures crash a builder on purpose. The four mutants that matter most for the plan: stamp terms dropped (mtime, builder inputs, unsorted list: killed), the id rule reduced to suffix-only (killed by the real-corpus test), a builder calling exit() (killed), a non-atomic write (killed by the inode test)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive key or box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved (GitHub Actions runs the new CI step; verified at PR time)." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "End to end on this VPS with the real tree: the real orchestrator builds both indexes strictly from the real diagnose docs (674) and the real OI board (265 open issues) on the tree rebuilt on origin/main c0565234 (rc 0; the output differs from the indexes committed on that main only in the stamp line, one header sentence, the Re-run lines and, in the diagnose index, the new eeca32 row). The real pre-commit and pre-merge-commit hooks run in fixtures for every index state (tracked, ignored, neither; old and new scripts), and the CI steps' own run: string is executed against a bad board and a dateless doc. Not verifiable from the VPS: the rename-over-an-existing-file step on Windows (the retry exists, behaviour unverified), and the CI runner itself (git 2.55.0 differs from this VPS's 2.43.0; the lesson of PR #159, so the pre-commit fixtures stub git add like 2.55.0)." }
impact_analysis: >-
  Platform. Hooks, CI and the agent read path change. A tree on older scripts is not
  affected until it merges this change (the new hook paths are keyed on the orchestrator
  existing and the index being untracked). A machine whose installed hooks are the A0
  copies (what both machines have) keeps working on an A2 tree, pinned by running those
  hooks frozen in test/scripts/fixtures/pre_a2_hooks: a staged board or diagnose doc builds
  with the strict builder and is not staged; a merge commit works because the regression
  walk now builds its own diagnose index (before the B-pass fix it BLOCKED a merge commit in
  a fresh worktree, with a message about a failing test); pre-merge-commit still blocks a
  duplicate OI and prints the git add advice for an index that is now ignored. Two things the
  old hooks do differently, and the SessionStart warning says so once: pre-commit BLOCKS on a
  failed index write (it knows only 0 and non-0, where A2 warns on 3), and the advice above.
  The one commit-blocking failure mode left is the first-failure symptom: hooks that predate
  A0 run a plain git add on an ignored index, which exits 1 (both the VPS and the Windows
  clone were reinstalled at A0). Agent read path: the indexes are
  absent in a fresh clone, worktree or subagent isolation tree until built; CLAUDE.md 4.1.5
  and section 7 say how, with no-Dart grep fallbacks, and the nudge says so at SessionStart.
---

# Local generated indexes: committed, rewritten by every branch, validated by nobody

## What was wrong

`docs/audit/OPEN_INDEX.md` and `docs/diagnoses/INDEX.md` are pure functions of other files
(`open_issues.md`, `docs/diagnoses/*.md`). They were nonetheless tracked, and `scripts/pre-commit.sh`
regenerated and staged them whenever their sources were staged. So two branches that each filed an OI
or a diagnose doc each changed the same generated lines, and git reported a conflict in a file neither
author wrote. The plan measured it on the last 60 PRs: 47 of 52 main-sync merges conflicted, the OI
index in 20 and the diagnose index in 13 (section 0 of `docs/plans/merge-conflict-treadmill.md`).

Behind the same files sat three smaller defects (symptom, items 1 to 3), each found by reading the
writers and readers:

1. `.github/workflows/test.yml` explained the OI-render step with a gate, `check_oi_index_fresh`,
   that has never existed. The OI index had no freshness check anywhere.
2. `scripts/build_bug_index.dart` skipped an unparseable doc with a warning and exit 0, crashed on a
   doc without `date:` (`e['date'] as String` on null), and nothing compared `bug_id:` with the file
   name except Gate 25.
3. Both builders wrote in place and called `exit(1)` mid-function. A concurrent reader (the nudge, an
   agent's `Read`, a hook) could see half a file, and an orchestrator could not run both builders and
   report the worst result.

## What the fix does

See `proposed_fix`. The design points worth stating here:

- **The stamp is a stat digest, not a content hash.** The nudge runs at SessionStart and on bug-shaped
  prompts, spawns nothing and must cost milliseconds, so it stats each input once and reads 256 bytes of
  each output. The price is that a `touch` or a checkout that rewrites an unchanged input makes an index
  look stale; the answer is one rebuild. The stats are taken before the inputs are read, so a change in
  between leaves the stamp describing the older state and the next check says stale.
- **Strict in CI and pre-commit, lenient on a developer machine.** A work-in-progress diagnose doc must not
  nag every session, so a lenient build skips it, says so, and the stamp (which covers the doc's stat) is
  fresh. A duplicate OI number is the exception: it corrupts every pointer below it, so it fails closed in
  both modes (the b7e3d1 invariant).
- **Exit 3 is not exit 1.** The output is ignored and regenerable, so "validation passed, write failed"
  warns and lets a commit or merge through, while a validation failure blocks.
- **Hooks are shared copies, so the new hook paths are keyed on the tree they run in:** the merge-time
  build needs `scripts/build_local_indexes.dart` to exist AND the index to be untracked; pre-merge-commit
  keys on `git check-ignore`, not on `ls-files`.

## Found while building

- `bug_id:` is sometimes quoted in the real corpus (`bug_id: "132315"`, 2026-10-23). The first strict
  build on the real tree refused it; one pair of surrounding quotes is now tolerated (mismatched quotes
  still fail). `bug_index_strict_test.dart` runs the rule over every doc in the repo.
- `File.lastModified` and `File.setLastModified` have SECOND resolution on the Dart VM, while `FileStat`
  keeps milliseconds. Two of the survivors above (lib-02, orch-07) were that one trap: an mtime
  "restored" or "compared" through the `File` API moved or hid by up to 999 ms. See the memory
  `feedback_dart_lastmodified_is_second_resolution.md`.
- Four survivors (nud-01, nud-03, pc-01, pm-03) were fixtures that could not reach the state the test
  claimed to cover (mode 000 hides the throw; real A2 hooks hide the guard; old scripts hide the second
  guard; a missing file hides the backup). The class is `feedback_test_passes_for_wrong_reason_check_observability.md`.
- A first draft of the gate carried a trailing `sort()` no test could see: `git ls-files` already emits
  index order. It was deleted, and a test for an UNMERGED path (git prints it once per stage) now pins the
  de-duplication that does matter.

## The B-pass (two fresh seats, 2026-10-24): what they found and what changed

Two context-blind reviewers (builders, library, orchestrator and gate; hooks, CI, nudge, docs and the
mixed fleet) found one P1, eight P2 and nine P3 in the staged diff; every one was reproduced before it was
fixed, and every fix has a test that was mutated and shown to redden. The reviewers' own 41 mutants: 19
reddened a test, 22 survived (21 real holes, 1 equivalent). The author's 43 mutants against the final tests:
42 reddened a test, and the 43rd reddened exactly the two tests written for it (tier 1 evidence has the detail).

- **P1, a push that could not happen.** `test/scripts/ci_local_indexes_steps_test.dart:72` carried an
  `unnecessary_non_null_assertion` WARNING. `pre-push` runs `flutter analyze --no-fatal-infos` on every
  push and aborts on a warning, the CI `Analyze` job allows none, and `safe_pr_merge` refuses a PR whose
  `Analyze` check is red. The batch's own gate loop analyzed `lib/` only and so could not see it. Fixed, and
  CLAUDE.md §4.12.8 now says `flutter analyze --no-fatal-infos` (the whole project).
- **A claim in this very document was false.** The impact analysis said a machine whose installed hooks
  predate A2 "prints stale advice but does not block". The frozen A0 hook, run against an A2 tree, BLOCKS a
  merge commit in a fresh worktree: it never builds `docs/diagnoses/INDEX.md`, `check_regression_catalog.dart`
  exited 2 on the missing file, and the hook printed "regression catalog detected a missing or failing test".
  No test had ever run an OLD hook, because the fixtures run the current one. The walk now makes sure of its
  own input (`ensureBugIndexFresh`), the A0 hooks are frozen under `test/scripts/fixtures/pre_a2_hooks/`, and
  cases 9h-9k (and a group in `pre_merge_commit_e2e_test.dart`) run them against an A2 tree. The two things an
  old hook still does differently are pinned and named in the SessionStart warning: it blocks on an index
  write failure (exit 3), and it prints the `git add` advice for an index that is now ignored.
- **A date the regression walk cannot read.** `date: "2026-10-24"`, `soon` and `24/10/2026` were accepted,
  sorted by string order and dropped silently from the merge-commit walk, which keeps only rows whose first
  cell is `YYYY-MM-DD` (and `validate_diagnose_doc_lib.dart` enforces the newer required fields only for a
  date that starts with one). Gate 25 is gone, so the strict rule is the only guard: a date must be a bare
  `YYYY-MM-DD`. Every doc of the repo already is (674 on origin/main c0565234).
- **Two ways a builder could escape its exit-code contract.** A board that is not valid UTF-8 (an em dash
  re-saved as one byte by a Windows editor) threw out of `runOiIndex`, which stopped the orchestrator before
  it built the diagnose index and ended the process with exit 255 and a stack trace; an unreadable
  `docs/diagnoses` did the same from the other side. Both are exit 1 with a message now, and
  `runLocalIndexes` guards each builder, so "both builders always run" is true when one throws.
- **A header that vanishes.** `## OI-409 - title` (a hyphen where the keyboard had no em dash), an en dash,
  a U+2028 in the title, or no title at all is invisible to the status check, the duplicate check and the
  parser: the issue is absent from the index and the generator exits 0 (the OI-68 scar, one step earlier). It
  fails strict now and is listed under "Needs attention" in lenient. The real board has none (259 of 259
  headers parse).
- **Guards no test could see (P2/P3).** The one rename retry; the millisecond term of the stamp; the 256-byte
  head cut inside a multibyte character; the sweep of `*.tmp` only; the `is! File` skip (a directory or a
  dangling link named `*.md`); a lone quote character as `bug_id`; a missing board or docs directory in
  lenient mode; the standalone `main` of each builder (the one pre-commit and CI actually run); the gate's
  no-git arm; the `setUpAll` of the full-suite test; the crash exit codes (2, 254) at the pre-commit board
  site and in pre-merge-commit; a tracked AND ignored index; the merge-time guard asking about the OTHER
  index, and its stderr; the hooks-directory lookup from a LINKED worktree (every session runs in one, where
  `.git` is a file); the warning's own `try/catch`; a third CI job that runs the suite without the build step
  (the list of jobs is derived from the workflow now). Each got a test, and each mutant that had survived was
  re-run red.
- **Claims the code did not satisfy.** The stamp is 87 bytes, not 91; `GATE_INDEX.md` said 48 numbered gates
  where its table shows 47 (the generator counted the number a closure ledger still mints for the deleted
  Gate 25); the SoT sentence on `ensureLocalIndexes` (it only asks whether the file EXISTS); the hint in
  `check_regression_catalog.dart`; "a subagent isolation worktree stays silent because the builder is absent"
  (it holds the tracked builder; it is silent because SessionStart does not fire for subagents); the handbook
  index has no freshness gate; the repo's own `memory/MEMORY.md` listed the diagnose index as visible from a
  cloud session; a dead `OPEN_INDEX.md` link on the board; and 48 `(relocated 2026-05-18 — see
  docs/diagnoses/INDEX.md)` pointers that now say where the index comes from.

## Not covered, said out loud

- **Windows.** The rename over an existing output is retried once after 200 ms for a transient lock; its
  behaviour on the founder's Windows clone is unverified until the first rebuild there. The new tests that
  need POSIX (`chmod`, `touch -d @`, symlinks) skip on Windows; the three separator-sensitive assertions
  were rewritten to compare canonical paths, derived by reading Dart's path semantics, not run there. The
  replacement of the READ-ONLY hook copies by `setup-hooks.sh` on Windows (A0) is likewise still untested.
- **CI.** The first CI run of the new strict step is the proof on the runner (git 2.55.0, not this VPS's
  2.43.0). A0's lesson is why the pre-commit fixtures stub `git add` the way 2.55.0 answers.
- **A stat digest equal despite a changed input** needs the same size AND the same millisecond mtime. Not
  reachable through the normal tools; the cost of the opposite error (a needless rebuild) is one command.

## Roll-out (once per machine, after the merge)

In the primary: `git checkout -- docs/diagnoses/INDEX.md docs/audit/OPEN_INDEX.md` if either is dirty;
`git fetch origin main && git merge --ff-only origin/main`; `dart run scripts/build_local_indexes.dart --lenient`;
then `sh scripts/setup-hooks.sh` (`pre-commit` and `pre-merge-commit` changed). A branch cut before this
change that edited either index meets one modify/delete conflict on its next sync: `git rm --cached` both
paths, then run the builder.
