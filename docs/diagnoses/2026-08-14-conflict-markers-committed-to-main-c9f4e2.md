---
bug_id: c9f4e2
date: 2026-08-14
batch: conflict-marker-gate
status: fixed
blast_radius: feature
symptom: >-
  `docs/audit/open_issues.md` on `main` at `5d1c6f12` carried three unresolved
  git conflict markers — an open marker at :2821, a bare separator at :2892 and
  a close marker naming `supabase-test-http` at :3107. A merge commit had been
  made without resolving the conflict. Nothing detected it: every gate passed
  green, `docs/audit/OPEN_INDEX.md` regenerated with no marker rows, the board's
  70 `## OI-` headers were all intact and carried zero duplicate ids. It was
  found only because a human read the file for an unrelated reason, roughly a
  day after it landed.
concept: unresolved_conflict_markers_committed
sot_registry_entry: not_applicable
writers:
  - "The merge commit `5d1c6f12` (`Merge branch 'supabase-test-http'`) — there is
     no program writer. Git itself writes conflict markers into the working tree
     on a conflicted merge, and the human/agent commit step is what promoted them
     into history. `scripts/pre-commit.sh` ran and passed: none of its ~72 gates
     inspects file content for markers."
readers:
  - "scripts/build_oi_index.dart — parses the board into OPEN_INDEX.md. It keys on
     `## OI-<n>` section headers, so the three marker lines are not headers and
     were skipped as ordinary prose. It fails closed on four conditions (unknown
     Status, missing `Blocked on`/`Verified`, zero parsed issues, board absent);
     'the file contains conflict markers' was not among them, so it emitted a
     clean-looking index over a corrupt source."
  - "Every human or agent reading `docs/audit/open_issues.md` — the board is the
     stated source of truth for 'what is owed' (root CLAUDE.md §7), and both sides
     of the conflict were present, so the file read as though two unrelated OI
     blocks had been concatenated."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/no_conflict_markers_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Checked for an existing conflict-marker gate before writing one: `ls scripts/ |
  grep -i 'conflict\|marker'` returns only `check_onconflict_live_arbiter.dart`,
  which concerns SQL `ON CONFLICT` arbiters and is unrelated. No gate in the repo
  inspected file content for merge markers.
proposed_fix: >-
  Two parts. (1) Delete the three marker lines from the board, highest line number
  first so earlier deletions do not shift later targets; each line's exact content
  was printed and confirmed before removal. (2) Add `scripts/check_no_conflict_markers.dart`
  plus its pure lib, auto-wired into pre-commit and CI by the existing
  `for GATE in scripts/check_*.dart` loops in `scripts/pre-commit.sh` and
  `.github/workflows/test.yml:209` — no workflow edit required.
regression_test_planned: >-
  `test/scripts/no_conflict_markers_test.dart` — 12 tests in three groups: the
  pure detector's decisions, the unreadable-vs-clean distinction, and an e2e group
  that runs the real gate binary against a throwaway git repo carrying a
  conflicted tracked file. Mutation-proven three ways; see
  `docs/audit/gate_test_ledger.yaml`.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ code touched; this is repo tooling and a docs artifact." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "No Hive box, adapter or key involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration, no schema change." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No table read or written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration applied." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy involved." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written by the gate." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The gate was run against the real repository after the fix - PASS, 3102 tracked files scanned, 80 binary/unreadable skipped, exit 0. Before the fix the same binary exits 1 naming the three board lines. Board integrity re-verified after the deletions - 70 OI headers preserved, zero duplicate ids, zero residual markers." }
impact_analysis: >-
  Bounded and non-user-facing. No shipped code path reads the OI board, so no APK
  or Edge Function behaviour was affected and no user data was at risk. The damage
  was to the repo's own coordination surface: the board is the stated source of
  truth for outstanding work, and it silently contained a merge artifact for about
  a day. The compounding risk was the next merge — markers left in a file become
  part of the base for every subsequent three-way merge, so the corruption tends to
  spread and to produce increasingly confusing conflicts rather than to heal. The
  new gate is `feature` tier (confirmed by `scripts/blast_radius_from_diff.dart`
  over the changed file set), runs on every commit and every CI push, and covers
  all 3102 tracked files rather than only the board.
related_bugs: []
recurrence: >-
  First recorded instance of this specific class in the repo. It is, however,
  another case of the recurring "a green check is only as wide as its input set"
  family that `docs/diagnoses/INDEX.md` carries several members of: every gate
  passed, and the passing was truthful about what each one examined. None of them
  examined file content for merge artifacts, so the aggregate green said nothing
  about the property that was actually violated.
---

# Unresolved conflict markers committed to `main` in the OI board

## What happened

The merge `5d1c6f12` (`Merge branch 'supabase-test-http'`) conflicted in
`docs/audit/open_issues.md`. The conflict was not resolved, and the file was
committed with all three marker lines intact — the open marker at line 2821, the
bare separator at 2892, and the close marker naming the branch at 3107.

Both sides' content survived. The HEAD side carried OI-115 and OI-116; the
incoming side carried OI-121, OI-122, OI-117, OI-118, OI-120 and OI-119. Nothing
was lost, and no OI id was duplicated. That is precisely why it was invisible:
the failure mode of an unresolved merge is usually *missing* content, and this
one had none.

## Why nothing caught it

`scripts/build_oi_index.dart` regenerates `OPEN_INDEX.md` on any commit touching
the board, and it fails closed four separate ways. All four concern the *shape of
an OI entry* — an unknown `Status`, a missing `Blocked on` or `Verified`, zero
parsed issues, an absent board. A marker line is none of those things. It is not
a `## OI-` header, so the parser stepped over it as prose, produced a correct
index of 70 correct entries, and exited 0 truthfully.

The duplicate-id detector added days earlier (`b7e3d1`) also passed, correctly:
the two sides had minted *different* ids, so there was genuinely no collision.

Every gate that ran was honest. None of them was looking at file content for
merge artifacts, because no gate in the repo did.

## The fix

**The instance:** the three lines are deleted. Each line's exact bytes were
printed and confirmed before removal, and the deletions were applied
highest-line-first so that earlier removals could not shift later targets. After:
70 `## OI-` headers (unchanged), zero duplicate ids, zero residual markers.

**The class:** `scripts/check_no_conflict_markers.dart` scans every path
`git ls-files` reports, reading the working tree.

Three design choices are load-bearing, and each closes a hole the obvious
implementation would have opened:

1. **The patterns are synthesised, not spelled.** Each marker is built as a
   repeated character (`'<' * 7`), so no literal marker exists in the gate, its
   lib, or its tests. The obvious alternative — writing the literals and then
   excluding `scripts/` and `test/` by path — is a bypass rather than a fix, and
   it blinds the gate to `test/`, which is exactly where real merges conflict.
   The fixtures write their markers to a temp directory at runtime for the same
   reason. This document keeps every marker token mid-line, never at column 0, so
   that it too passes the gate it describes.

2. **A lone separator is not a conflict.** A run of `=` on its own line is an
   ordinary prose divider and this repo's docs contain them. The separator counts
   only when the same file also carries an open or close marker — a conflict
   cannot exist without one, so the condition costs no detection and removes a
   whole class of false positives.

3. **"Could not read" is reported separately from "clean."** Binary and
   unreadable files land in a `skipped` list whose count is printed on every run,
   including passing ones. Collapsing them into the clean pile would make a zero
   mean both "no markers" and "never looked" — a failure this repo has shipped
   twice before.

The gate also fails when `git ls-files` returns nothing, rather than passing over
an empty input set.

## Wiring

No workflow edit was needed. Both `scripts/pre-commit.sh` and
`.github/workflows/test.yml:209` iterate `for GATE in scripts/check_*.dart`, so a
new gate is picked up by filename in both places. Per rule 24 the gate takes **no
number** — the filename is its identity.

## Mutation proof

Run, not asserted. Baseline 12/12 green before and after each restore.

| mutation | effect | tests reddened |
|---|---|---|
| open-marker branch condition replaced with `false` | detection dead | **7** |
| separator counted unconditionally | false-positive regression | **1** |
| final `exit(1)` changed to `exit(0)` | detects and prints, never fails | **1** |

The third is the Gate-44 class itself — a gate that sees the problem and reports
success — and it is caught by the e2e group, which is why that group exists
alongside the pure tests.
