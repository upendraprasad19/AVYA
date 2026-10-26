---
bug_id: d1264d
date: 2026-10-25
batch: merge-conflict-treadmill-c1
status: fixed
blast_radius: platform
symptom: >-
  Concluding a conflicted `git merge origin/main` with `git commit` ran the pre-commit catastrophic
  review gate (scripts/check_code_review_pass_exists.dart) over `git diff --cached`, which at a merge is
  the OTHER side's whole content: when main had gained a catastrophic path (payment, a SECURITY DEFINER
  migration, rolling-context) the gate demanded `docs/reviews/<hash>-review.md` for code that had already
  been reviewed and merged on main, and no honest review file can satisfy it (OI-413; five recorded trips,
  and the parent plan measured seven forced merge-only reviews and three hand rebuilds). The only way through was a
  rebuild: save the resolved tree, `git merge --abort`, `git merge -X theirs origin/main` (a clean merge
  concludes without pre-commit), restore the tree and commit normally. A GitHub PR cannot be merged
  server-side with conflicts, so the old workaround (resolve at the merge to main) is not available.
  Measured on this repository's history: of 46 "Merge branch 'main'" syncs the full staged diff reached
  `catastrophic` in 8 and `platform` in 24 (38.0 staged paths on average); graded by what the merge adds
  beyond main it reaches `account` in 1, `platform` in 12 and `catastrophic` in none (5.3 paths); over the
  wider 124 syncs of the same history, 23 reach catastrophic by the full diff and none by the rule.
concept: blast_radius_registry_coverage
sot_registry_entry: blast_radius_registry_coverage
writers:
  - file: scripts/merge_scope_lib.dart
    method: computeMergeScope (decides which staged paths are graded at a branch sync)
    line: 203
  - file: docs/blast_radius.yaml
    method: paths list (the tier of every graded path; the lib is registered platform beside the gate)
    line: 39
readers:
  - file: scripts/check_code_review_pass_exists.dart
    method_or_widget: main (tier loop over the graded set; the hash and the review path still come from the FULL staged diff)
    line: 216
  - file: scripts/check_code_review_pass_exists.dart
    method_or_widget: stagedPaths (-z, --no-renames, --ignore-submodules=none, strict UTF-8)
    line: 116
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/merge_scope_gate_e2e_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'Process\.(run|start)\(.*write-tree', absent: true }   # in scripts/merge_scope_lib.dart: plumbing only (rev-parse, merge-base, diff-index) as git argv; no index.lock, no object writes, no git 2.38 requirement (the file names the newer tree-merge command only in a comment)
  - { pattern: 'Platform\.environment', absent: true }   # the lib and its tests read no environment variable; the gate passes the process environment to git unchanged (so GIT_DIR and GIT_INDEX_FILE reach it as a hook sets them)
  - { pattern: 'parseNulPaths.*allowMalformed: true', absent: true }   # the staged list is decoded strictly; the two tolerant decodes left in the lib (the MERGE_HEAD path and the tip name, `rev-parse` output) never carry a staged path
proposed_fix: >-
  A scoped input for the gate on one narrow merge shape, in a pure lib (scripts/merge_scope_lib.dart,
  platform) the gate imports. While a merge is pending whose single full-hex MERGE_HEAD is an ancestor of
  `refs/remotes/origin/main`'s tip (found through `git rev-parse --git-path MERGE_HEAD`, so it works in a
  linked worktree), only the staged paths whose index entry (mode + object id, or absent) differs from BOTH
  HEAD's and the tip's are graded: `git diff-index --cached --name-only -z --ignore-submodules=none <rev> --`
  for HEAD and for the tip's hex name, intersected, and the HEAD read must equal the gate's own staged list as a set
  (else the scope is refused). Every failed precondition returns a Fallback and the gate grades the full staged list
  as before, saying why in a NOTE; the lib never throws. The hash and the review file name are still derived
  from the FULL staged diff; `-s ours` merges (no staged diff) still SKIP; non-merge commits are unchanged.
  The same commit hardens the gate's own staged-path read for every commit (`git diff --cached --no-renames
  --ignore-submodules=none --name-only -z`, strict UTF-8, a malformed name fails the gate with its own message)
  and gives its glob engine `dotAll: true` (OI-337, the gate half). The B-pass added: the review hash carries
  `--ignore-submodules=none` too (a gitlink hidden by `.gitmodules ignore = all` was graded while the hash was
  that of an empty diff, one review name for every gitlink value), a scoped PASS reads `max blast-radius of the
  graded set`, a FAIL in a branch sync lists every graded path on stderr (the NOTE cuts at 20), and the tip
  reason reads `refs/remotes/origin/main is missing or not a commit`. Rejected, in review: a MERGE_HEAD-only
  stand-down (the human's own edits in the same commit would go ungraded; G15 is its negative control and the
  mutant that grades nothing while a merge is pending reddens 13 tests (10 when it applies to a scoped sync only); the broader stand-down over MERGE_HEAD,
  CHERRY_PICK_HEAD and REVERT_HEAD was rejected earlier in review-gate-tier-gap.md because single-parent commits
  skip the CI keystone), a name-keyed rule (remerge UNION overlap: a rename relocates content
  past it), a spine test (an interior or reverted MERGE_HEAD exempted what main no longer holds), and
  `git write-tree` / `git merge-tree` (index.lock; git 2.38). No runtime flag: rollback is a revert.
regression_test_planned:
  - test/contracts/merge_scope_gate_e2e_test.dart
  - test/scripts/merge_scope_git_test.dart
  - test/scripts/merge_scope_git_fuzz_test.dart
  - test/scripts/merge_scope_lib_test.dart
related_bugs:
  - b7e3d1  # the OI-number collision invariant: a self-numbered catalog without a gate (landing B of this plan); not the same mechanism, same plan
  - eeca32  # A2 of this plan: generated indexes that every branch rewrote
recurrence: |
  YES, recurrence class. The catastrophic review gate has refused a conflicted sync of main five times
  (the memory file `reference_merge_commit_trips_catastrophic_review_gate_2026_10_12` records the instances:
  the OI-321 branch after #108, PRs #126 and #129 and the A2 local-indexes branch, each answered by rebuilding
  the branch commit on origin/main; the rebuild of #159 turned out not to be needed; OI-413 is the fifth
  recorded trip and the one that reached the board). Each time the answer was a workaround; the gate itself was
  never changed. An earlier proposal to stand the gate down over MERGE_HEAD, CHERRY_PICK_HEAD and REVERT_HEAD
  was rejected in review-gate-tier-gap.md (single-parent commits skip the CI keystone); the MERGE_HEAD-only
  version OI-413 proposed is rejected here because it also waves through whatever the human changed in the
  same commit.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ code changed (two Dart scripts, five test files, markdown and two yaml registries)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive key or box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration applied or authored." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service; GitHub Actions runs the new tests through the existing unit-test shards and the gate through the Audit Gates loop. Every test ran only on this VPS's git 2.43.0; the first run on the runner's git 2.55 is the PR's CI, to be read there." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "End to end on real git: the REAL gate was spawned in temp repositories with a REAL pending sync (29 gate tests: scoped, fail-closed, linked worktree with GIT_DIR and an absolute GIT_INDEX_FILE, relative GIT_INDEX_FILE, alternate index, non-merge name shapes, a corrupt index). 79 mutants of the lib and the gate (every row of the plan's table except 6a, plus the B-pass additions), all red on the final tree; an earlier run had one survivor (a hex check that accepts a leading dash), closed by a test. A seeded fuzz of 80 syncs holds three independent oracles." }
impact_analysis: >-
  Platform (the lib is registered platform beside the gate in docs/blast_radius.yaml; the gate was already
  platform). Every commit runs the gate as before. A commit made while a merge of an ancestor of origin/main
  is pending grades FEWER paths (the ones whose entry equals HEAD's or main's are not graded), never more.
  Every commit also gets the stricter staged-path read described at the end of this paragraph. The NOTE is on stdout and the pre-commit loop discards a gate's output, so
  it is read by re-running the gate while the merge is pending (documented in hooks.md and the code-review
  skill). Fail-closed paths are tested for the exact reason string; a flow where scoping is unavailable
  (a sync from another remote or branch, a shallow clone, an octopus merge) keeps today's behavior. CI's
  keystone gate (check_plan_review_record_exists.dart) is untouched and still demands the record and the
  B-pass for the PR. No hook, workflow or token-scope change, so nothing to reinstall on the VPS or the
  Windows clone. The staged-path read is stricter for every commit: a path that is not valid UTF-8 now
  fails the gate with its own message instead of being read leniently, and a rename out of a catastrophic
  path now lists its source (OI-337, gate half; blast_radius_from_diff.dart keeps its lossy reader).
---

# Branch sync: the catastrophic review gate graded main's already-merged content

## What was wrong

The gate classifies `git diff --cached --name-only` and, at `catastrophic`, demands a staged
`docs/reviews/<hash>-review.md` with `verdict: accepted`. For an ordinary commit the staged diff is the
author's work. For a merge commit of origin/main into a branch it is the other side's whole content: every
file main gained since the branch point, the part the author did not write and that main's own gates had
already reviewed. A clean automatic merge concludes inside git and runs only `pre-merge-commit`, so the gate
stayed silent there; a CONFLICTED merge is concluded by `git commit`, which runs pre-commit, and the gate
refused it for any catastrophic path main had gained. The review file it asks for would have to review
code the author did not write and that is already on main.

Writer: `git merge` stages the other side's content and the human stages the resolutions. Reader: the gate.
The drift is gate-input vs. commit shape: the input is right for a commit that adds work and wrong for one
that imports reviewed work.

## What the fix does

See `proposed_fix`. Points worth stating:

- **Entry comparison, not name comparison.** A path is exempt when its index entry equals what HEAD holds
  (nothing new reaches the branch) or what origin/main holds today (already landed through main's gates). The
  comparison is on the entry at the committed path, so it does not matter how git got there: a rename, a
  directory rename, an add/add, a conflict resolved by taking either side, a clean combination of two edits.
  A first design keyed on names (the paths main changed, minus the paths the branch also changed) missed
  content that git relocates by rename; the entry rule cannot be bypassed that way, and an old, interior or
  reverted MERGE_HEAD exempts nothing main does not hold now.
- **Why not stand down while MERGE_HEAD exists.** That is OI-413's own first proposal and it is a free pass: a
  conflict resolution is exactly where a human can add a catastrophic edit. The negative control the OI asked
  for ("the gate still enforces for the same staged paths without a merge") passes, but the stronger one is
  here: the same merge with the human's edit to a catastrophic file is still refused (G3, G4, G14).
- **The staged list and the scope list are cross-checked.** The HEAD read must equal the gate's own staged
  list as a set, otherwise the scope is refused (intent-to-add entries, `diff.relative`, a different
  environment). That turns "the scope list is a subset of the staged list" from a claim into a runtime check
  and removes the fail-open empty-scope shape.
- **Fail closed, and say so.** Every failed precondition (no `refs/remotes/origin/main`, MERGE_HEAD not an
  ancestor of it, an octopus or unreadable MERGE_HEAD, disagreeing reads, any git failure, any exception)
  grades the full staged list as before; the NOTE says "branch-sync scoping not applied (<reason>)". The
  reason strings are asserted exactly, and a helper fails any scenario that returns the catch-all reason
  by accident, so a throwing bug cannot read as a conservative fallback.
- **Byte-exact path handling.** Sets are compared as byte strings (git orders names by UTF-8 bytes; Dart
  strings by UTF-16 code units); the gate's staged list is read with `-z` (no C-quoting), `--no-renames` (a
  rename out of a catastrophic path lists its source) and `--ignore-submodules=none` (a `.gitmodules`
  `ignore = all` must not hide a gitlink), decoded strictly. A name that is not valid UTF-8 fails the gate
  with its own message. `globToRegExp` gets `dotAll: true` so a name with a line terminator still matches a
  `**` glob.
- **The NOTE is on screen, not stored.** It prints the short tip and MERGE_HEAD ids, how many paths are graded
  of how many are staged, and the first 20 graded paths (control characters, backslash, U+2028/2029 and the
  bidi controls escaped so a hostile name cannot forge a line). The pre-commit loop discards gate output, so
  a reviewer reads it by re-running the gate while the merge is pending, and a FAIL in a branch sync lists
  every graded path on stderr (the 124-sync history has one sync with 44 graded paths).

## Tests and mutation proof (rule 21)

Five test files: `test/scripts/merge_scope_lib_test.dart` (the pure lib against a scripted fake: every
condition, the exact call order, null and non-zero runner answers, the catch-all),
`test/scripts/merge_scope_git_test.dart` (23 scenarios against REAL git: hand resolution, renames, directory
renames, a clean combination, `-X ours` and `-X theirs`, a moved tip, a hostile repo-local config, a gitlink,
a linked worktree), `test/scripts/merge_scope_git_fuzz_test.dart` (80 seeded syncs, three oracles computed
without the lib: soundness, "new bytes are never exempt", exact equality with an independent
reimplementation), `test/contracts/merge_scope_gate_e2e_test.dart` (29 tests, the REAL gate in temp repos) and the
updated `review_gate_staged_content_not_working_tree_test.dart` (10 tests; its fixture now copies the gate's import
closure instead of a hand-written two-file list). 79 mutants: one per row of the plan's table (row 6a has no code to
mutate) plus the B-pass additions (a failing git read as "no staged changes", the review hash without the submodule flag,
two stand-down shapes, the FAIL listing, the NOTE cut and the escape boundaries). Each was applied with an
exact-one-match assertion before the write, `dart analyze` required clean (a compile error is not red), the five files
run, the sources restored and their sha256 re-checked (RESTORE-CHECK OK). The whole table was run on the FINAL tree, after the
last edit of code and tests: 79 of 79 red. An earlier run had one survivor, the hex check that accepts a leading dash (`-`
plus 40 digits would reach git as an option); the cases `-` + 40 and `-` + 64 digits were added to the MERGE_HEAD test and
`-` + 40 digits to the tip test. One harness anchor (the FAIL listing) first produced a compile error, which is not red, and was
rewritten until it compiled. The table and counts are in the gate ledger entry. Pre-declared equivalents are stated in the
plan (a verdict-neutral order of the two reads, a display sort).
