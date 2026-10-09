---
branch: coach-history-correctness-client
date: 2026-10-06
blast_radius: platform
review_rounds: 11
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — L1a-2 exercise-log restore, push day and deletes (`coach-history-correctness-client`)

Plan: `docs/plans/coach-history-correctness-client.md` (v9). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L1). Client half of OI-307/OI-312/OI-313 (new-APK fixes for R2, R3, single-device R1, moved-out days) and OI-218's exlog half.

`bpass: pending` — the B-pass runs on the code before the merge to `main` and this field becomes `accepted` in that commit (CLAUDE.md §4.3, §4.12.3).

## Lineage and rounds

Fresh context-blind reviewers with an exhaustive read-only allow-list every round; the coordinator re-checked each load-bearing claim against the code or with read-only live SQL.

- **R1–R3** on the combined L1a unit; split after R3 (§4.12.1).
- **R4–R7** (v1–v5): one day drives key/index; sink owner checks; IST midnight via `DateTime.utc`; new SoT concept `pending_exlog_deletes`; U6 and U2(e) moved to L1a-3 after R5–R7 kept finding P1s in the slot/timeout design.
- **R8** (v6): server day clamp U1.5 + backfill WITHDRAWN (future-dated rows were the source of R6–R8 recency findings); D4 measured.
- **R9** (v7): late-delete end state was misdescribed to the founder ⇒ re-asked ⇒ "newest action wins": the drain filters `completed_at <= deleted_at`, fallback upsert removed.
- **R10** (v8): one P1 — restored rows edited after a delete pushed the restore-time `created_at` ⇒ exlog push sends `max(resolved, updated_at_ms)`; non-collision move stamps `updated_at_ms`.
- **R11** (v8): `max` confirmed sound; one P3 text fix; one P2 notification edge (an old PR row moved or edited into today/yesterday can trigger one extra "New PR" push per day) routed to the founder, who accepted it. **Converged** on mechanism.

## Ground truth verified (coordinator, read-only, 2026-10-06)

0 cloud `scheduled_workouts` rows with `status='moved'` (D4 pre-landing half `verified_clean`); `workout_log_exercises.completed_at` NOT NULL and no `updated_at` column; every user exlog write goes through `WorkoutWriteService` and stamps `updated_at_ms` (`:220`, `:984`, `:1136`); restore stamps `created_at` (`sync_workout.dart:940`); shared resolver feeds `workout_logs` too (`:152`).

## Founder decisions (2026-10-06)

1. "Last sync or write wins".
2. CORRECTED: "newest action wins" — a delete removes only versions written before it.
3. Late upload after a newer edit: accepted.
4. The notification edge (R11C-1): ACCEPTED — at most one extra "New PR" push per user per day; no schema marker.

## §4.6

Switches `disable_exlog_restore_dedupe` (restore) and `disable_exlog_allcount_drain` (drain), both dev-panel configBox (no RemoteConfig, OI-95).
