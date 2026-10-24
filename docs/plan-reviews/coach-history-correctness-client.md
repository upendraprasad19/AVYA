---
branch: coach-history-correctness-client
date: 2026-10-06
blast_radius: platform
review_rounds: 11
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-history-correctness-client-bpass.md
---

# Plan-review record — L1a-2 exercise-log restore, push day and deletes (`coach-history-correctness-client`)

Plan: `docs/plans/coach-history-correctness-client.md` (v9). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L1). Client half of OI-307/OI-312/OI-313 (new-APK fixes for R2, R3, single-device R1, moved-out days) and OI-218's exlog half.

`bpass: accepted` (2026-10-09, `docs/reviews/coach-history-correctness-client-bpass.md`): two fresh context-blind reviewers on commit 5c19161a, 15 findings, all fixed or recorded; fixes in 077e70a8.

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

## Deviations from plan v9 found by the B-pass and by building it (2026-10-09)

- **Cancel on re-log reversed for timed entries (B-F2).** v9 U4 had `logExercise` / `moveExerciseLogs` / `ExlogKeyMigrator` cancel the queued delete. With the time-filtered drain (v7+) the cancel keeps the OLDER cloud version, possibly at a different set count, alive, and the highest-count restore brings the deleted version back over the re-log. Timed entries now stay; only an entry with no delete time (older build) is cancelled. The v9 text of R8C-1 (re-read at the sink) is kept and still tested.
- **Empty UPDATE keeps the entry one more pass (B-F3).** v9 said the in-flight-push race "exists today"; it does not for a creating push in flight (the old upsert created a tombstone first).
- **Old behaviour misdescribed in v9:** the old restore kept the NEWEST-written summary (`_fetchAllRows` reads newest-first), not the oldest. The selector and fix are unaffected.
- **One fix commit for U2, U3, U4 (5c19161a), not three:** the units share `sync_workout.dart` and the stub change; one commit keeps every commit green. Follow-up B-pass commit 077e70a8.
- **Added:** re-key of a row restored under the old rules (A-F1), `created_at` fallback for the push day (A-F2), future-time clamp, malformed-time tolerance, move queues after its Hive work.
