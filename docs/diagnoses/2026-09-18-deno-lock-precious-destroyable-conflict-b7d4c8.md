---
bug_id: b7d4c8
date: 2026-09-18
batch: deno-lock-precious-fix
status: fixed
blast_radius: feature
symptom: |
  CI red on `main` (push `8bf79dde`, run 35368296446) — Unit Tests job
  failed with 2 assertion failures in
  test/scripts/gitignore_classification_test.dart:
  "the two classifications are disjoint — nothing is both destroyable and
  precious" and "the precious list agrees with the matcher — every entry
  really does BLOCK". `deno.lock` appeared in BOTH
  `regenerableIgnoredPaths` (scripts/retire_worktree_lib.dart, added by
  the immediately-preceding commit `8bf79dde` "fix(retire): deno.lock is
  regenerable — every Deno-run worktree was unretirable") AND
  `deliberatelyPreciousIgnoredPaths` (test/scripts/gitignore_classification_test.dart:98,
  pre-existing) — a path can only ever hold one classification, and the
  test correctly caught the contradiction.
concept: worktree_retirement_ignored_path_classification
sot_registry_entry: |
  No new entry — this corrects a two-list membership contract
  (regenerableIgnoredPaths vs deliberatelyPreciousIgnoredPaths) that
  already exists; no new writer/reader contract introduced.
writers:
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "regenerableIgnoredPaths — deno.lock entry added by 8bf79dde", line: 251 }
readers:
  - { file: test/scripts/gitignore_classification_test.dart, method_or_widget: "deliberatelyPreciousIgnoredPaths list — stale deno.lock entry, now removed", line: 98 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — tooling-only fix, no Hive involvement."
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/scripts/gitignore_classification_test.dart
ist_handling:
  - "Not applicable — no date keys or clock-derived values involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — tooling/test-classification fix only."
forbidden_patterns_checked:
  - { pattern: "file: test/scripts/gitignore_classification_test.dart, line: 98 (deno.lock in deliberatelyPreciousIgnoredPaths)", absent: true }
proposed_fix: |
  Removed the stale `'deno.lock',` entry from
  `deliberatelyPreciousIgnoredPaths` in
  test/scripts/gitignore_classification_test.dart. This test file's own
  header comment (lines 79-84) already documents the correct move for
  exactly this situation: "If one of these ever blocks a real
  retirement, the fix is to move that ONE entry down to
  `regenerableIgnoredPaths` with evidence — never to loosen the
  matcher." Commit `8bf79dde` did the first half of that move (added to
  `regenerableIgnoredPaths`) but did not do the second half (remove from
  `deliberatelyPreciousIgnoredPaths`), leaving the entry in both lists.
regression_test_planned:
  - "test/scripts/gitignore_classification_test.dart — all 5 tests in the group now pass (previously 2 of 5 failed: the disjointness test and the precious-list-matcher-agreement test)."
impact_analysis: |
  Feature-tier, tooling-only. No app code, no Hive/Postgres/Edge
  Function surface touched. This restores CI-green on `main` — the
  failure blocked no user-facing behavior, only the classification
  contract test that guards `scripts/retire_worktree.dart`'s worktree
  auto-cleanup from silently deleting a file it shouldn't (or refusing
  to delete one it safely could).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter test test/scripts/gitignore_classification_test.dart -> 5/5 passed (was 3/5). flutter test test/scripts/retire_worktree_lib_test.dart -> 37/37 passed (unaffected)." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No client/server contract involved — pure local tooling classification list." }
---

## Summary

The immediately-preceding commit `8bf79dde` fixed "every Deno-run
worktree is unretirable" by adding `deno.lock` to
`regenerableIgnoredPaths`, but left the same literal string in
`deliberatelyPreciousIgnoredPaths` in the disjointness test's own data,
so `main` went CI-red on the very next push.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for `gitignore_classification` /
`deno.lock` / `precious` — no prior instance of this exact two-list
straddle. The test file's own header (lines 55-62, 79-84) already
anticipates and documents the correct one-line fix for this class,
which is why the repair here is a single-line deletion rather than a
new pattern.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `scripts/retire_worktree_lib.dart:251`
(`regenerableIgnoredPaths`) — `8bf79dde` added `'deno.lock',` here.
**Reader:** `test/scripts/gitignore_classification_test.dart:98`
(`deliberatelyPreciousIgnoredPaths`) — still listed `'deno.lock',` from
before that commit, so the same path classified as both destroyable and
precious. `gitignore_classification_test.dart`'s own disjointness
assertion (line ~180) is the reader that caught the contradiction.

## Fix

Deleted line 98 (`'deno.lock',`) from `deliberatelyPreciousIgnoredPaths`
in test/scripts/gitignore_classification_test.dart.

## Verification

`flutter test test/scripts/gitignore_classification_test.dart` — 5/5
passed (was 3/5: "every literal entry classified", "no orphans", "all
four historical instances" passed; "disjoint" and "precious list agrees
with the matcher" failed).
`flutter test test/scripts/retire_worktree_lib_test.dart` — 37/37
passed, unaffected by this change (deno.lock's presence in
`regenerableIgnoredPaths` is untouched).

**Mutated and run** (rule 21): re-added `'deno.lock',` to
`deliberatelyPreciousIgnoredPaths` — reddened exactly 2 of 5 tests in
`gitignore_classification_test.dart` (the same two CI reported).
Reverted; re-ran green.

## Related

Direct continuation of commit `8bf79dde` (same logical change, split
across two commits because the first shipped incomplete and CI caught
it before a second push completed it).
