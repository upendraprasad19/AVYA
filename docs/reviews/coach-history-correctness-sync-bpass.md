---
reviewed_at: 2026-10-06T22:30:00+05:30
staged_against: coach-history-correctness-sync (uncommitted, staged diff hash 0179d37dda5b) vs main ca4c8270; migration body (session scratchpad until applied, Gate 14) sha256 62b945e429130399f28c0705a7c1d572562ca6218eca909aa45fe6cb72d226c1
blast_radius: platform
reviewer: 3 fresh context-blind Sonnet agents in 2 rounds (round 1: B1 read-only, B2 executing on an isolated local Supabase PG 17.6 container; round 2: one executing reviewer on the post-round-1 tree)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 18
verdict: accepted
---

# Code Review (B-pass) — L1a-1 one live exercise-log summary, deletes that land (`coach-history-correctness-sync`)

Plan `docs/plans/coach-history-correctness-sync.md` §3; diagnose-docs `bd79b1` (OI-312) and `4b5c38` (OI-307 writer half). Production was not touched by any reviewer: the executing reviewers ran only against the local container `l1a1-pgtest`, with an exhaustive command allow-list (no MCP, no network, no repo scripts).

**Outcome:** no defect was found in the migration's runtime behaviour on a first apply. Round 1 found one real migration defect (a second apply destroys the kept rows) and that the tests pinned no key predicate of any destructive statement; round 2, on the fixed tree, found no migration defect and seven further test/recipe gaps. Every finding was fixed; 0 false alarms. Final mutation run (author side, local container): **57 mutants, 55 red, 2 equivalent for every reachable input**, 0 not applied.

## Round 1 — reviewer B1 (read-only)

### Finding 1 — P1 — guard_without_its_mirror
- **claim:** no case pins the key predicates (`workout_log_id`, `exercise_id`, `user_id`, `set_number <> new.set_number`) of the runtime-destructive statements; dropping any one leaves DRYRUN_OK.
- **status:** accepted, fixed — N8 (push isolation, owner role, a second user; identical re-push keeps the same id with no new tombstone), N9 (drain isolation). Mutants A3–A8, A11a–c and "drop `set_number <>`" now red.

### Finding 2 — P2 — asserted_fixture_value
- **claim:** `>` → `>=` in the per-set delete survives (N3 re-inserts the sets); the rename-branch lock is unpinned; PRECONDITION_B is unpinned.
- **status:** accepted, fixed — N8 checks per-set rows right after the summary push; N10 (drain-path lock); R7 (shared-xmin siblings → PRECONDITION_B).

### Finding 3 — P2 — blast_radius_mismatch (rollback recipe)
- **claim:** the data rollback fails with 23505 once a push lands after the apply; the per-set re-insert has no `on conflict`; the function comment is not restored; the snapshot is not atomic with the apply.
- **status:** accepted, fixed — commented reverse block at the end of the migration (restore unless a newer live row holds the key; `on conflict do nothing`; 151's comment re-run). The non-atomic snapshot window stays as the plan states it (rows created between the go-#2 re-select and the LOCK are only those the runtime trigger would also touch; a new in-DB backup table was not added, to keep the migration free of new objects).

### Finding 4 — P2 — writer_reader_drift (immutable header)
- **claim:** `<date>`/`<id>` placeholders and non-template tag names (`-- Rollback strategy:`, `-- Linked diagnose-doc:`).
- **status:** accepted, fixed before any hash was pinned.

### Finding 5 — P2 — blast_radius_mismatch (operational)
- **claim:** the harness holds ACCESS EXCLUSIVE on both tables for its whole run; state the expected duration.
- **status:** accepted — measured locally 0.18–0.19 s per run; stated in the go-#1 request with an off-peak recommendation.

### Finding 6 — P2 — guard_without_its_mirror
- **claim:** a count-0 push tombstones the live summary but keeps its per-set rows; undocumented and unasserted.
- **status:** accepted — intended (count 0 = unknown; readers take every per-set row under a count-0 summary, L1a-2 U2(b)); documented in the header and diagnose-doc, asserted in N5.

## Round 1 — reviewer B2 (executing, local container)

### Finding 1 — P1 — other
- **claim:** a SECOND apply tombstones every row the first apply kept (the kept rows are older than the cleanup's tombstones, so 2a pairs them); a retried `apply_migration` would do it silently.
- **status:** accepted, fixed — ALREADY_APPLIED guard after the table locks; R8 applies twice.

### Finding 2 — P1 — guard_without_its_mirror
- **claim:** no bystander rows anywhere (about 20 mutants green, including SECURITY DEFINER on the delete function, which lets any user tombstone another user's row).
- **status:** accepted, fixed — N8, N9, N11 (cross-user drain refused, 42501), R6 (cleanup and 2a isolation).

### Finding 3 — P2 — guard_without_its_mirror
- **claim:** the drain-path advisory lock is load-bearing (a real two-session race loses the delete without it) and unpinned.
- **status:** accepted, fixed — N10.

### Finding 4 — P2 — asserted_fixture_value
- **claim:** C1_4 case 4 passes vacuously on a NULL.
- **status:** accepted, fixed — explicit null check.

### Finding 5 — P2 — other
- **claim:** rollback step 3 fails with 23505 after a re-push; the comment is not restored.
- **status:** accepted, fixed (same fix as B1 Finding 3).

## Round 2 — one executing reviewer on the post-round-1 tree

### Finding 1 — P1 — missing_input
- **claim:** R6's bystanders were older than the kept row, so the cleanup's ranking/count partitions (user_id, workout_log_id) were unpinned.
- **status:** accepted, fixed — R6 reordered (bystanders younger than the kept row) and the bystanders carry legacy per-set rows above their count; P1–P6 red.

### Finding 2 — P2 — guard_without_its_mirror
- **claim:** the harness's own locks hide a missing `LOCK TABLE`/`lock_timeout` in the migration; N7/N10 do not pin lock-before-UPDATE order.
- **status:** accepted, fixed — R12 (behavioural lock_timeout + statement order in the text); N7/N10 position pins on the installed function bodies.

### Finding 3 — P2 — asserted_fixture_value
- **claim:** the author's "equivalent" label for the disabled END_STATE assertion was wrong; both END_STATE checks are reachable.
- **status:** accepted, fixed — R9/R10 swallow the tombstoning with a fixture trigger and expect each END_STATE abort; the equivalent count corrected.

### Finding 4 — P2 — missing_input
- **claim:** the cleanup touching per-set rows of non-duplicate groups (`k.n > 1` → true) survives.
- **status:** accepted, fixed — R6 bystanders carry per-set rows above their count.

### Finding 5 — P2 — writer_reader_drift
- **claim:** after the reverse block, restored siblings share one xmin and a corrected re-apply stops on PRECONDITION_B.
- **status:** accepted, fixed — note in the reverse block (tombstone unwanted siblings by hand before a re-apply).

### Finding 6 — P2 — writer_reader_drift
- **claim:** the new function's suffix bytes and the drain's `deleted_at` value are unpinned.
- **status:** accepted, fixed — C1_4 and C5 assert the exact suffix; C5 asserts the stored `deleted_at` equals the drain's.

### Finding 7 — P3
- **claim:** PRECONDITION_B's group-by columns and the regex `$` anchor unpinned; `search_path` unpinned; per-set delete seq-scans (5.9 ms per push at 40k rows for one user); snapshot filename differs from the plan.
- **status:** accepted — R11 (shared xmin across different keys must not abort), N12 (SECURITY INVOKER + empty search_path); the `$` anchor is equivalent for every reachable input (recorded); the scan cost is not material at the live size (559 per-set rows) and is recorded in the diagnose-doc; plan filename aligned.

## Founder triage notes
Coordinator-triaged under the standing go for the L1a-1 code (2026-10-06); every finding fixed or recorded with its reason. The prod dry-run (go #1) and the apply (go #2) remain separate founder decisions.
