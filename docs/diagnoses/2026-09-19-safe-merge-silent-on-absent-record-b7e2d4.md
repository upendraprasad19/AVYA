---
bug_id: b7e2d4
date: 2026-09-19
batch: gate-integrity (Task 4 / OI-181)
status: fixed
blast_radius: platform
concept: plan_review_record_merge_gate
sot_registry_entry: null
writers:
  - { file: scripts/plan_review_record_lib.dart, method_or_widget: "recordSlug() is the record's FILENAME contract; the record itself (docs/plan-reviews/{slug}.md) is authored by the batch author ON THE FEATURE BRANCH, never on main -- so before the merge it exists only via refs/heads/{branch}", line: 140 }
readers:
  - { file: scripts/safe_merge.sh, method_or_widget: "bpass precheck entry `if [ -n \"$_REC_CONTENT\" ]` -- reads the record's PRESENCE only to decide whether to LOOK at its bpass fields, never to warn about absence (the bug)", line: 208 }
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: "the threshold the new precheck mirrors -- tier < account means no record is required", line: 617 }
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: "_validateRecord `content0 == null` -> FAIL; the keystone gate reads the record AT THE MERGE COMMIT, in CI, after the merge already exists", line: 792 }
  - { file: scripts/safe_merge.sh, method_or_widget: "absent-record precheck (NEW) -- `if [ -z \"$_REC_CONTENT\" ]`, three-dot classify, warn iff >= account", line: 258 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/safe_merge_test.dart
ist_handling:
  - "No date surface touched -- git integration tooling only. The warning text quotes three calendar dates (2026-08-30, 2026-09-10, 2026-09-19 IST) as history; none is computed."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- git integration tooling; no user data path is read or written."
forbidden_patterns_checked:
  - { pattern: "a BLOCKING precheck (non-zero exit on a missing record) that wedges the only path landing work on main", absent: true, evidence: "the block only echoes to stderr; the script's exit code and its `git merge --no-ff` call are untouched, and every advisory-path test asserts exit 0" }
  - { pattern: "two-dot `main..branch` range, which reports main-only changes as the branch's", absent: true, evidence: "three-dot `refs/heads/main...refs/heads/$BRANCH`; mutation 3 flips it to two-dot and the three-dot test reddens" }
  - { pattern: "bare `$BRANCH` ref (a same-named TAG resolves first -- the existing tag-collision test's class)", absent: true, evidence: "refs/heads/ on both sides of the range and in the `git rev-parse --verify` guard" }
  - { pattern: "mirroring the keystone gate's version-bump / dependabot exemptions", absent: true, evidence: "0768a0ce WAS a version bump and the gate failed it (OI-222); the precheck deliberately warns there too" }
  - { pattern: "collapsing 'classifier produced nothing' into 'clean'", absent: true, evidence: "a non-empty changed-path list that yields no tier prints exactly one NOTE line naming the precheck as inconclusive (feedback_bad_news_vs_no_news)" }
  - { pattern: "--no-verify or gate bypass", absent: true }
proposed_fix: |
  Add a second, sibling precheck to scripts/safe_merge.sh directly after the
  bpass-verdict precheck: when the branch has NO plan-review record
  (`_REC_CONTENT` empty), classify the three-dot range
  `refs/heads/main...refs/heads/$BRANCH` with the real classifier
  (`scripts/blast_radius_from_diff.dart -`, same preamble-tolerant extraction
  as pre-push.sh:167-170, dart resolved through scripts/_dart_bin.sh) and, iff
  the tier is >= account, print a WARNING that names the tier, the missing
  record path, and why the repair after the merge is a full unwind. Advisory
  by construction: every failure path (no branch ref, classifier or yaml
  absent, git error) stays silent; only "paths changed but no tier came back"
  prints a NOTE, so bad news and no news cannot collapse.
regression_test_planned:
  - "test/scripts/safe_merge_test.dart :: 'RED PATH: warns when a >= account branch has NO plan-review record' -- fails on the pre-fix script (measured: merged with zero output)"
  - "test/scripts/safe_merge_test.dart :: 'stays silent for a feature-tier branch with no record even with the classifier present' -- the mirror"
  - "test/scripts/safe_merge_test.dart :: 'three-dot: a platform-tier change that landed on MAIN after the branch was cut does not warn' -- pins the range shape"
impact_analysis: |
  Production impact: scripts/safe_merge.sh is the §4.13 integration step, so
  every merge to main passes through this block. It cannot change what the
  merge DOES -- it prints and proceeds -- so the worst case of a defect here
  is a wrong or missing line of stderr, never a blocked or altered merge.
  Blast radius platform via the pinned `scripts/safe_merge.sh`
  (docs/blast_radius.yaml). Cost per merge: one `git diff` plus one
  `dart run` of the classifier (~0.7 s via the SDK exe, measured 2026-09-19
  from a pubspec-less directory), paid only when the branch has no record.
  Risk of the change itself: the block sources scripts/_dart_bin.sh under
  `set -u`; that file guards every parameter expansion it makes, and the
  source is parse-checked (`sh -n`) and `|| true`-wrapped first.
symptom: |
  A branch whose blast-radius is >= account can be merged to main by
  `sh scripts/safe_merge.sh <branch>` with ZERO output about its missing
  docs/plan-reviews/{slug}.md. CI's keystone job
  (check_plan_review_record_exists.dart) then reads the record AT THE MERGE
  COMMIT, finds nothing, and fails -- after the merge exists, when the only
  repair is unwinding it. Three real instances: the 2026-08-30 unwind that
  CLAUDE.md §7 records for the bpass sibling; `dcb94a93` (Merge branch
  'hipri-parity', 2026-09-10 -- `git cat-file -e dcb94a93:docs/plan-reviews/
  hipri-parity.md` exits 1); `0768a0ce` (Merge branch
  'aab-versioncode-bump-44', 2026-09-19 00:34 IST -- record absent at the
  merge, CI red, repaired after the fact by `8ffe28fb`; OI-222 owns the
  version-bump exemption gap that made it look exempt).
root_cause: |
  The 2026-08-30 pre-merge precheck (commit ecc01876) was scoped to the
  bpass verdict, and its whole body sits inside `if [ -n "$_REC_CONTENT" ]`
  (safe_merge.sh:208): presence of the record is read only to decide whether
  to LOOK at its fields. A branch with no record at all therefore skips the
  precheck entirely -- the one shape it structurally could not see -- while
  the keystone gate's first and loudest rejection
  (check_plan_review_record_exists.dart:792, `content0 == null`) is exactly
  that shape. The precheck previewed three of the gate's four rejections and
  was silent on the fourth; a precheck that covers fewer shapes than the gate
  it previews is silent precisely where the merge is about to fail (the same
  parity argument its own header makes for shapes 1-3). No tier computation
  existed anywhere in safe_merge.sh, so "should this branch have a record"
  was not a question the script could ask.
writer_reader:
  writers: [the batch author, writing docs/plan-reviews/{slug}.md on the FEATURE BRANCH (filename per plan_review_record_lib.dart recordSlug, :140)]
  readers: [safe_merge.sh:208 (presence -> whether to look; the gap), check_plan_review_record_exists.dart:617 + :792 (the keystone, AT the merge commit in CI), safe_merge.sh:258 (NEW absent-record precheck)]
fix: |
  scripts/safe_merge.sh gains an ABSENT-RECORD PRECHECK block between the
  bpass precheck's closing `fi` and the "main is caught up" echo. It fires
  iff `_REC_CONTENT` is empty AND `refs/heads/$BRANCH` resolves AND both
  scripts/blast_radius_from_diff.dart and docs/blast_radius.yaml are
  readable; it resolves dart via scripts/_dart_bin.sh (sh -n parse-checked,
  sourced `|| true`, `dart` fallback); computes `git -c core.quotePath=false
  diff --no-renames --name-only refs/heads/main...refs/heads/$BRANCH`
  (three-dot = merge-base, the merge commit does not exist yet; refs/heads/
  on both sides so a same-named tag cannot win; the gate's own diff flags,
  :309-315); pipes the paths to the classifier and extracts the tier with the
  pre-push.sh:167-170 idiom; prints one NOTE when paths were non-empty but no
  tier came back; and on account|platform|catastrophic prints a WARNING that
  names the tier, the record path, the three prior costs and the fix
  (write docs/plan-reviews/{slug}.md on the branch FIRST). The gate's
  exemptions are deliberately not mirrored. Exit code and merge behaviour are
  byte-identical on every path. Tests: three appended to
  test/scripts/safe_merge_test.dart with two helpers -- installClassifier
  (copies the classifier, content lib, _dart_bin.sh and the yaml into the
  fixture, commits + pushes so main stays equal to origin/main; idempotent)
  and makeBranchAdding (a branch off main adding ONE file at a path, no
  record). 12 -> 15 tests, all green; the pre-existing `:426` silence test
  for a no-record feature branch is unchanged.
touched_layers_checked:
  - { layer: client code, status: fixed_in_this_batch, evidence: "scripts/safe_merge.sh block at :234-292; `sh -n` clean; flutter test test/scripts/safe_merge_test.dart 15/15 (12 pre-existing + 3 new); flutter analyze on the test file -> No issues found" }
  - { layer: hive, status: not_applicable, evidence: "git integration tooling; no Hive box is read or written" }
  - { layer: postgres schema, status: not_applicable, evidence: "no cloud surface" }
  - { layer: postgres data, status: not_applicable, evidence: "no cloud surface" }
  - { layer: migrations applied, status: not_applicable, evidence: "no migration" }
  - { layer: edge function code vs deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { layer: cron jobs, status: not_applicable, evidence: "no cron" }
  - { layer: rls policies, status: not_applicable, evidence: "no table" }
  - { layer: storage buckets, status: not_applicable, evidence: "no storage" }
  - { layer: secrets, status: not_applicable, evidence: "no secret read; the classifier and dart resolver read only tracked files" }
  - { layer: external services, status: not_applicable, evidence: "none" }
  - { layer: client to server contract, status: not_applicable, evidence: "the contract here is script-to-CI-gate parity (safe_merge.sh previews check_plan_review_record_exists.dart), verified by the three e2e tests against the real classifier" }
mutation_proven: |
  Three mutations of scripts/safe_merge.sh, each proven applied by grep -c
  before/after, each leaving the script parse-clean (`sh -n`), each run
  against the full 15-test file, each restored byte-identically (cmp):
  (1) delete the whole block (:234-292) -- 'ABSENT-RECORD PRECHECK' count
  1 -> 0 -- reddened 1: the RED PATH test. (2) the case arm
  `account|platform|catastrophic)` -> `*)` (warn on every tier) -- arm count
  1 -> 0, wildcard 0 -> 1 -- reddened 2: the feature-tier silence test and the
  three-dot test; the pre-existing `:426` silence test stayed green because
  its fixture has no classifier, which is why the new mirror test installs
  one. (3) `refs/heads/main...refs/heads` -> `refs/heads/main..refs/heads`
  (two-dot) -- three-dot count 1 -> 0, two-dot 0 -> 1 -- reddened 1: the
  three-dot test (main's own migration was reported as the branch's change).
  Observed 1/2/1 = the plan's expected counts. A control re-run of mutation 3
  after the commit, restored with `git checkout --` and `git diff` empty,
  is recorded in the batch's plan-review record.
related_bugs:
  - "c9f4e1 -- git-safety tooling gaps (2026-08-03): the batch that created safe_merge.sh and its e2e suite; this precheck extends that script"
  - "ecc01876 (2026-08-30, cited by sha because the diagnose id that commit reused, d4e9a2, is the profile-name restore race and NOT this class) -- the bpass-verdict precheck whose `[ -n $_REC_CONTENT ]` entry is the gap fixed here"
  - "OI-181 (the board entry this closes) and OI-222 (the version-bump exemption gap that 0768a0ce exposed; deliberately NOT mirrored here)"
recurrence: "Third instance of merge-without-record reaching CI (2026-08-30 unwind; dcb94a93 2026-09-10; 0768a0ce 2026-09-19). Same class as the bpass sibling's own history: a precheck that previews fewer rejection shapes than the gate it mirrors. Residues stated below, not fixed."
---

## Symptom

`sh scripts/safe_merge.sh <branch>` merged a >= account branch with no
`docs/plan-reviews/{slug}.md` and printed nothing about it. CI's keystone job
then failed at the merge commit -- `dcb94a93` (2026-09-10) and `0768a0ce`
(2026-09-19 00:34 IST) both verified absent-at-merge with
`git cat-file -e <merge>:docs/plan-reviews/<slug>.md` -> exit 1.

## Writer / reader

- Writer: the batch author, on the FEATURE BRANCH (`plan_review_record_lib.dart`
  `recordSlug()`, `:140`, fixes the filename). Never on main before the merge.
- Reader that had the gap: `scripts/safe_merge.sh:208` -- presence decides
  whether to inspect bpass fields; absence falls through silently.
- Mirror it now previews: `check_plan_review_record_exists.dart:617` (tier <
  account -> nothing required) and `:792` (`content0 == null` -> fail).
- New reader: `scripts/safe_merge.sh:258` (block `:234-292`).

## Fix evidence

- Pre-fix: RED PATH test fails ("does not contain 'NO plan-review record'";
  the fixture merged with zero warning). Post-fix: 15/15.
- Mutations 1/2/1 as recorded in the frontmatter.

## Residues (stated, not fixed)

1. Fires only on the `safe_merge.sh` path. `gh pr merge` (used 2026-09-16
   when the sandbox blocked the primary) and a raw `git merge` bypass it; the
   keystone gate in CI remains the authoritative check.
2. An `origin/foo` branch spelling is silent -- `refs/heads/origin/foo` does
   not exist -- the same limitation the bpass precheck already has.
3. Pre-merge, the classifier's SECURITY DEFINER content rule reads the WORKING
   TREE (`blast_radius_content_rules_lib.dart:58-62`), and the script runs on
   main, so a branch's SECURITY DEFINER migration classifies `platform`, not
   `catastrophic`. Still >= account, the warning fires; the tier it prints can
   understate.
4. `test/scripts/safe_merge_test.dart` is not registered in
   `test/contracts/gate_e2e_env_hermetic_test.dart` -- its `_cleanEnv()` strips
   `GIT_*` only. Nothing the new block spawns reads `GITHUB_*` or
   `PUSH_BEFORE`, so registration is not needed for correctness; widening the
   scrub is a separate change.
