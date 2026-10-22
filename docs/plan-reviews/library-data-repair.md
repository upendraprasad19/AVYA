---
branch: library-data-repair
date: 2026-10-22
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — Batch A: library data repair (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, EXPECTED.** The diff touches `lib/core/services/seed_service.dart`, `lib/shared/repositories/exercise_repository.dart`, the bundled library and a migration. The tier is recomputed by `scripts/pre-commit.sh` on the first staged diff, and this line is corrected if it differs. `bpass` becomes `accepted` with the review file once Task 6 Step 4 runs.

## Plan
`docs/plans/2026-10-22-library-data-repair.md` implements spec `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` §9 row A.

## Review rounds (context-blind Sonnet reviewers, every claim checked against code and data)

1. **Round 1** (r1): 1 P0, 6 P1, 11 P2. All applied in r2:
   - **P0:** unioning injury tags broke the founder's 13-B carve-out (`k13bKeptSafe`). Injury tags are now never merged.
   - **P1:**
     - The seed-file name missed the cloud test regex.
     - The mirror test was vacuous.
     - `_preferNovel` would hand towel rows to home/gym users, so the six bodyweight relabels moved to Batch B (OI minted).
     - The pick-diff had no tool; `dump_all_picks.dart` was added.
     - The apply was infeasible over MCP and needed a branch for `Destructive: yes`; it is now `is_active=false`, non-destructive, applied via the node API.
     - The E276/E277 relabel was inert.
2. **Round 2** (r2, the post-round-1 plan): **CONVERGED**, 0 P0, 0 P1, 10 P2. All applied in r3:
   - Mutation targets fixed: `is_foundational` and `muscleGroupOf`.
   - Gate 14 window: no commit between generating the .sql and the ledger.
   - `closes-oi` on the board-flip commit.
   - Retired cloud rows now copy the kept twin's repaired text, because three were shifted rows the coach still serves by exact name.
   - The prod rehearsal now sits behind the founder's go.
   - `CURRENT_SEED` moves with the new file; the `naming_conventions` counts are updated.

## Founder gates
- Plan approval: **APPROVED** by the founder in chat, 2026-10-22.
- §4.6 waiver (a seed rewrite has no kill switch; rollback = revert JSON + v13 + re-run 125): **ACCEPTED** by the founder in chat, 2026-10-22.
- Execution mode: **INLINE**, confirmed by the founder, 2026-10-22.
- Go for the Task 6 rehearsal and live apply: pending, asked at Task 6.
