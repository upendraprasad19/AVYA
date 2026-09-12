---
bug_id: f3a9c1
date: 2026-09-12
batch: oi-allocator
status: fixed
blast_radius: platform
related_bugs: [d3f1a7]
recurrence: |
  Second gate-level defect in check_oi_numbering_unique.dart's SHAPE SELECTION
  (the first — base == mainline at both merge placements — is recorded in
  docs/audit/gate_test_ledger.yaml under the gate's entry as "its SECOND real
  shipped bug"). Same class as the OI-112 landing half (d3f1a7): the gate
  answered a real question about the wrong pair of trees. The class recurred
  live while this batch was being planned — the branch that filed OI-177/178
  (20302f30, 2026-09-10) collided with main's own 177/178 and was renumbered
  by hand to 186/187 at merge de52f1e8 (2026-09-12) — which is the trigger for
  the allocator this batch ships (scripts/mint_oi.sh).
symptom: |
  On a fresh worktree with ZERO commits, HEAD is the commit the branch was cut
  from — routinely a merge commit on main. The gate's dispatch reads
  `parents.length >= 3`, takes the "merge commit (HEAD^1 vs HEAD^2)" arm and
  compares two ANCESTORS of the branch point. The staged/working board — the
  only place the new number exists — is never read. Output, verbatim from the
  e2e reproduction (test/scripts/oi_numbering_gate_e2e_test.dart test 1, run
  against the pre-fix gate on 2026-09-12): "[check_oi_numbering_unique] PASS
  (vacuous): merge commit (HEAD^1 vs HEAD^2) -- the 3bbb6b0f… side minted no
  OI number that the merge-base lacked, so no cross-branch collision is
  expressible. 3 entries on the cae766a0… side were read and compared; this is
  a checked answer, not a skipped one." followed by "PASS: 4 distinct numbers"
  — while origin/main and the working board each carried `## OI-4` under
  different titles. Filed as OI-176 on 2026-09-08 from a live three-way
  collision (167/168/169) found BY HAND while this gate was green.
concept: oi_number_uniqueness
sot_registry_entry: |
  Not a Hive/cloud writer-reader concept — dev-workflow tooling, same phrasing
  as a4f7c2/f0c2d5. The contract: an OI number new on a branch must not already
  name a different issue on origin/main. Deliberately NOT added to
  docs/sot_registry.yaml (that registry tracks Hive/Postgres contracts).
writers:
  - { file: docs/audit/open_issues.md, method_or_widget: "any session appending `## OI-N — title` (until this batch: by eyeballing the tail; after: scripts/mint_oi.sh reserves refs/heads/oi/N on origin first)", line: 9 }
readers:
  - { file: scripts/check_oi_numbering_unique.dart, method_or_widget: "shape dispatch — the `parents.length >= 3` arm (post-fix position; pre-fix it sat at :292 and fired on a zero-commit worktree, reading HEAD^1/HEAD^2 instead of the working tree). The new `_boardDirty()` arm now precedes it at :311", line: 323 }
  - { file: scripts/check_oi_numbering_unique.dart, method_or_widget: "useWorkingTree = otherSideRev == 'HEAD' — false in the merge arm, so headOpen/headClosed (the working tree) were never compared (post-fix position; pre-fix :331)", line: 362 }
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
  The collision FIX text now prescribes `sh scripts/mint_oi.sh "<title>"`
  instead of "Next free is OI-N" — an eyeballed number is the very thing the
  allocator bans (test/scripts/oi_numbering_lib_test.dart:334 repointed).
regression_test_planned:
  - test/scripts/oi_numbering_gate_e2e_test.dart
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "e2e test 1 reproduces the exact PASS (vacuous) line pre-fix (run red 2026-09-12: 'Expected: not <0> Actual: <0>' with the vacuous line in stdout) and FAILs the gate post-fix; 26/26 green across the e2e (2) and lib (24) files. MUTATIONS (each applied, confirmed absent by grep, run over BOTH files, restored): (1) deleting the `else if (_boardDirty())` arm → 1 red (e2e test 1, the vacuous PASS returns); (2) `baseRev = 'origin/main'` in the new arm (base == mainline) → 1 red (e2e test 1); (3) `baseMerged = <int,String>{}` → 2 red (e2e title-edit test + lib 'PASSES when the branch only edits a pre-existing title'). None was a compile error (25/26, 25/26, 24/26 tallies)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data path." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: "External services", status: verified, evidence: "GitHub ref semantics verified live 2026-09-12 for the allocator this fix pairs with: duplicate ref create => HTTP 422 'Reference already exists'; cloud push to refs/oi/* => 403, to refs/heads/oi/* => created. Both spike refs deleted afterwards." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Developer-tooling contract (branch board vs origin/main board). The e2e fixture cuts the session branch from a merge-commit tip, checked against the real repo where `git log --merges -1 --format=%h main` == `git rev-parse --short main` == 39111d1e on 2026-09-12 — main's tip IS a merge commit, so every fresh worktree starts in the OI-176 shape." }
impact_analysis: |
  EXPOSURE: every number minted in a fresh worktree since the gate shipped
  (fa65f200, 2026-08-17) was checked against the wrong trees at pre-commit.
  Three collision incidents landed in that window — OI-128→130 (fa957dbb, the
  same day), 167/168/169 (found by hand 2026-09-08, filed as OI-176), and
  177/178→186/187 (de52f1e8, 2026-09-12) — each repaired by a manual renumber
  whose predecessor commits still cite the superseded numbers. No user data
  path; the cost is engineering time and identifier ambiguity in cited docs.
---

# OI-collision gate answered PASS about the wrong trees in the zero-commit worktree state

The gate chose which two trees to compare by looking at HEAD's shape. In the
one state where numbers are actually minted — a fresh worktree, zero commits,
the new heading sitting only in the working tree — HEAD is the merge commit the
branch was cut from, so the merge arm fired and compared HEAD^1 against HEAD^2:
two ancestors of the branch point, neither of which contains the edit. It then
printed `PASS (vacuous) … this is a checked answer, not a skipped one`, which is
the gate's own SKIPPED-vs-PASS discipline turned against the reader. The fix
dispatches on the question that matters — *is a board being changed right now?*
(`git diff --quiet HEAD -- <boards>` exits 1) — and only then on HEAD's shape,
with the mid-merge arm keeping precedence because mid-merge the working tree
legitimately holds both sides.

Mutation record (rule 21): three mutations, each applied and confirmed by grep,
run over `oi_numbering_gate_e2e_test.dart` + `oi_numbering_lib_test.dart`
(26 tests), then restored. Deleting the new arm → **1 red**; `baseRev :=
'origin/main'` → **1 red**; `baseMerged := {}` → **2 red** (the e2e title-edit
test and the lib's pre-existing title-edit test — the named reddening mutation
for e2e test 2, which otherwise has none). No compile errors.

This is the detector half. The allocator half — `scripts/mint_oi.sh` reserving
`refs/heads/oi/N` on origin with a compare-and-swap before any stub is written,
and Check C in this same gate requiring every minted number to be reserved — is
specified in `docs/superpowers/specs/2026-09-12-oi-allocator-design.md` §3.
