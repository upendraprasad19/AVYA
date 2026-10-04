---
bug_id: d3f8a2
date: 2026-07-26
batch: ci-governance
status: shipped
symptom: |
  Three defects in the §4.12 keystone gate's branch-recovery step, all of which
  either redden main for legitimate work or let a merge pass on the wrong
  review:
  (1) a GitHub PR merge subject ("Merge pull request #N from owner/branch")
      does not match the gate's regex at all, so the gate calls die() and turns
      main red on a perfectly valid merge;
  (2) `.split('/').last` truncates any slashed branch name, so
      `dependabot/pub/build_runner-2.15.0` resolves to the record path
      `build_runner-2.15.0.md`, and `feat/foo` and `fix/foo` BOTH resolve to
      `foo.md` — one branch's approved record silently satisfies another's gate;
  (3) a `git pull` on main produces "Merge branch 'main' of <url>", which DOES
      match the regex, yields branch="main", and demands
      docs/plan-reviews/main.md — a self-inflicted red for merely syncing.
concept: keystone_gate_branch_recovery
sot_registry_entry: null
writers:
  - { file: scripts/plan_review_record_lib.dart, method_or_widget: "classifyMergeSubject / recordSlug (new pure helpers)", line: 82 }
readers:
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: "main() — merge-subject recovery + record resolution", line: 152 }
  - { file: .github/workflows/test.yml, method_or_widget: "plan-review-record job (the only place the gate executes)", line: 169 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/plan_review_record_lib_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "unguarded acceptance of a PR-merge subject from any owner", absent: true, after_fix: true, note: "The repo is public. classifyMergeSubject only returns pullRequestMerge when the owner prefix equals GITHUB_REPOSITORY_OWNER (or the origin-derived owner); anything else is foreignPullRequest and dies. Fails closed when the owner cannot be determined at all." }
  - { pattern: "branch-name-only trust for the Dependabot exemption", absent: true, after_fix: true, note: "Anyone with push access can name a branch dependabot/x, so the exemption additionally requires every commit on the merged side to be authored by Dependabot AND the diff to touch only pubspec.yaml/pubspec.lock." }
  - { pattern: ".github/workflows/** exempted for Dependabot", absent: true, after_fix: true, note: "Deliberately excluded from dependabotAllowedPaths. Letting a bot rewrite the CI that enforces every other gate would contradict promoting test.yml to platform tier in this same batch; actions/checkout supplies fetch-depth:0 to the keystone job itself. Action bumps still require a record — documented at the config that generates those PRs (.github/dependabot.yml)." }
  - { pattern: "end-anchored branch regex rejecting this repo's own merge convention", absent: true, after_fix: true, note: "SELF-INFLICTED, caught by review round 2. The first draft used ^Merge branch '([^']+)'(?:\\s+into\\s+\\S+)?\\s*$, which rejects `Merge branch 'X' — <description>` — 49 of the 174 merges on main, including 904e6961, the merge immediately preceding this batch. It would have reddened main on the very next merge, including this batch's own. Now unanchored; pinned by 4 verbatim-history REGRESSION cases plus an end-to-end test that runs the real gate on a real merge commit." }
  - { pattern: "unconditional PASS on any \"' of <x>\" subject", absent: true, after_fix: true, note: "Also caught by round 2. The remote-sync PASS exited 0 before blast-radius was computed, so ANY subject ending in `' of x'` skipped the gate. Now restricted to ms.branch == 'main' (a same-branch sync); `git pull origin <feature>` while on main falls through to the normal record requirement." }
proposed_fix: |
  Extract branch recovery into pure, testable helpers
  (scripts/plan_review_record_lib.dart) and rewire the gate onto them:

  1. classifyMergeSubject() recognises three shapes — local `Merge branch 'X'`,
     GitHub `Merge pull request #N from owner/X` (accepted ONLY when the owner
     matches this repo), and `Merge branch 'X' of <url>` (a git-pull remote
     sync, which PASSES because the incoming commits were already gated when
     they were originally pushed).
  2. recordSlug() strips a leading `origin/` — the original intent of the old
     split-last — then maps remaining `/` to `-`, so slashed branches keep their
     identity and no longer collide.
  3. recordBranchFieldMatches() cross-checks the record's own `branch:` field
     against the recovered branch, closing the residual non-injective case
     (`hold/mechanic` slugs onto the existing, converged `hold-mechanic.md`).
  4. A content-verified Dependabot exemption (author check + manifest-only diff).
regression_test_planned:
  - test/scripts/plan_review_record_lib_test.dart (new — 25 cases driving the pure helpers directly; deliberately NOT spawning a git repo, because a test that does so inherits GIT_DIR/GIT_WORK_TREE inside pre-commit and its results become meaningless — feedback_mistake_git_hook_env_leak)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "scripts/plan_review_record_lib.dart + scripts/check_plan_review_record_exists.dart; `dart analyze` clean on both; 25/25 new tests pass, and the 5 existing ci_workflow_concurrency_test.dart assertions still pass after the contract-tests job deletion (30/30 together)." }
  - { tier: 2, layer: hive, status: not_applicable, evidence: "No Hive read/write — CI enforcement script only." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 6, layer: edge_function, status: not_applicable, evidence: "No Edge Function touched or redeployed." }
  - { tier: 11, layer: external_services, status: verified, evidence: "GitHub is the external system. Verified live that the PR-merge subject shape really occurs here: `git log -1 --format=%s 7c973ee3` = 'Merge pull request #3 from upendraprasad19/feat/exercise-selection-v4', and `git merge-base --is-ancestor 7c973ee3 main` confirms it is an ancestor of main. Repo merge settings changed in the same batch and verified by GET: allow_squash_merge false, allow_rebase_merge false, allow_merge_commit true (before-state recorded: all three true)." }
impact_analysis: |
  Net effect is a gate that fires correctly on shapes it previously mishandled.
  Two directions of change:

  MORE PERMISSIVE — PR-merge subjects and git-pull syncs now resolve instead of
  dying. Both were false reds; neither weakens the record requirement, which
  still applies to every >=account branch landing.

  MORE STRICT — the record must now name its branch in a `branch:` field. Of the
  69 TRACKED records, 68 already carry one; the single exception
  (free-tier-hold-findings.md) is a findings doc that no branch name resolves
  to. So no existing record is invalidated.

  KNOWN-OPEN, explicitly NOT fixed here and not claimed to be — TWO faces of one
  architectural property, both with the same fix:

  (a) The single-parent bypass. The gate exits 0 whenever HEAD^2 is absent, and
      allow_squash_merge/allow_rebase_merge only govern the GitHub merge BUTTON
      — a local `git merge` that fast-forwards, or `git merge --squash`, still
      lands single-parent commits the gate never inspects, and nothing in the
      repo enforces --no-ff. Disabling the buttons (done in this batch) closes
      the GitHub path only.

  (b) Branch identity is derived from the merge-commit SUBJECT, which is
      free text the merging author controls. B-pass proved it live:
      `git merge --no-ff -m "Merge branch 'some-reviewed-branch'" other-branch`
      resolves to that branch's approved record and passes, on a genuine
      two-parent merge. No amount of parsing fixes this — the input itself is
      author-asserted.

  The single real fix for both is the same: stop deriving identity from the
  subject and HEAD^2, and evaluate the actually-pushed range via
  github.event.before..after. That is a materially different design and gets its
  own reviewed unit; it is NOT closed here.

  What this batch DOES close is the ACCIDENTAL half of (b): a subject git itself
  generates can no longer mis-resolve. Slug truncation (`feat/foo` → `foo`) and
  quote truncation (`Merge branch 'a'b'` → `a`) both previously landed on
  another branch's record silently, with no intent required. Both now either
  resolve correctly or fail loud. The remaining exposure needs deliberate
  crafting by someone who already holds push access — the same trust level as
  `--no-verify`, which this gate has never defended against and does not claim
  to.
blast_radius: platform
---

# Keystone-gate branch recovery: three defects in one regex

## Why this matters more than a normal parser bug

`scripts/check_plan_review_record_exists.dart` is the repo's single structural
enforcement point for §4.12 plan quality. Every other discipline gate fires at
commit time and is `--no-verify`-bypassable; this one runs in CI at the
merge-to-main commit. When its branch recovery is wrong, the failure is silent
in both directions — it either blocks legitimate work loudly, or approves work
against somebody else's review quietly.

It also had **zero test coverage** until this batch. Nothing pinned the one
piece of logic the whole gate depends on.

## Root cause

A single line doing two jobs badly:

```dart
final bm = RegExp(r"Merge branch '([^']+)'").firstMatch(subject);   // :145
final branch = bm.group(1)!.split('/').last;  // strip any remote/ prefix  :150
```

- The regex models exactly one of the three merge-subject shapes git and GitHub
  actually produce.
- `.split('/').last` was written to strip an `origin/` prefix, but it cannot
  distinguish a remote prefix from a branch namespace, so it also truncates
  `feat/foo` → `foo`.

## The collision, concretely

`recordSlug` is still not injective — `a/b` maps to `a-b`, which could be a
literal branch. That is not theoretical: a branch named `hold/mechanic` maps
onto `docs/plan-reviews/hold-mechanic.md`, an existing record that is
`verdict: converged` and `bpass: accepted` for entirely unrelated work. Hence
the `branch:` cross-check — the slug finds the file, the field proves it is the
right file.

## The fix introduced a worse bug than any it fixed — and unit tests missed it

Worth recording plainly, because it is the whole argument for §4.12's second
review round.

Tightening the regex for the PR-merge shape, the first draft also end-anchored
the local-merge shape:

```dart
RegExp(r"^Merge branch '([^']+)'(?:\s+into\s+\S+)?\s*$")   // tolerates ONLY " into Y"
```

This repo's dominant convention is `Merge branch 'X' — <description>` — **49 of
the 174 merges on `main`**, including `904e6961`, the merge that landed
immediately before this batch. The anchored form rejects every one of them. The
gate would have called `die()` and reddened `main` on the very next merge,
including this batch's own merge commit.

**All 25 pure-helper tests passed against it**, because they only ever exercised
the ` into Y` suffix. Testing the helper certified the helper, not the gate —
the same false-confidence class as `feedback_source_grep_false_confidence.md`,
one level up. What surfaced it was executing the real gate against a real merge
commit, which is now a permanent test
(`test/scripts/plan_review_record_gate_e2e_test.dart`).

A second round-2 finding was the mirror image: the new remote-sync PASS exited 0
*before* blast-radius was computed, so any crafted subject ending `' of x'`
skipped the gate entirely — a bypass introduced by the fix for a false red. Now
restricted to a same-branch sync of `main`.

## Verification

`dart analyze` clean. 35 tests pass — 30 pure + 5 end-to-end. The end-to-end
suite constructs real merge commits in a throwaway repo and asserts the gate's
actual exit codes:

| scenario | expected |
|---|---|
| em-dash convention + valid record | exit 0 |
| platform change, no record | exit 1 |
| crafted `' of x'` suffix, no record | exit 1 |
| genuine `Merge branch 'main' of <url>` | exit 0 |
| record naming a different branch | exit 1 |

That suite scrubs `GIT_*` from the child environment and **aborts** if the
throwaway repo does not resolve inside the temp dir — run under `pre-commit`, an
inherited `GIT_DIR`/`GIT_WORK_TREE` would otherwise point the child git at the
real repository and make every assertion meaningless
(`feedback_mistake_git_hook_env_leak`).

The Dependabot exemption's two halves are pinned by explicit REGRESSION cases: a
code file in the diff disqualifies it, and a human-authored commit on a
`dependabot/`-named branch disqualifies it.
