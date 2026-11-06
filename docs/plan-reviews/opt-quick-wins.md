---
branch: opt-quick-wins
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/5a1ac3e1cb4d-review.md
---

# Plan-review record — opt-quick-wins (§4.12)

Covers the first two units shipped on this branch:
- **097** — 5 additive FK covering indexes (advisor `unindexed_foreign_keys`).
- **Unit D + Unit B** — durable `onboarding_completed_at` writer
  (`_syncUserProfile`) + Hive stamp + `.toUtc()` on the timestamptz writes +
  heal migration **098**; diagnose **c4d8a2**.

## Round 1 — plan-time adversarial review (pre-implementation)
The parent plan (`ok-i-have-few-rustling-bear.md`) was built from an 8-lens audit
and carries an explicit new-bug risk register (R1–R7). Unit D's root cause was
named writer→reader by file:line BEFORE proposing: `_syncUserProfile`
([sync_profile.dart:82-135](lib/core/services/sync/sync_profile.dart:82)) omitted
the column → no durable writer → the restoring-screen self-heal (which routes
through `syncProfileNow → _syncUserProfile`) was a silent cloud no-op. The fix
set was derived from that contract, not guessed.

## Round 2 — ground-truth re-baseline against live main + live Supabase
Every item was re-verified against the post-`fe108bd` tree AND live data:
- **test7** confirmed in live `user_profile`: `onboarding_completed = true`, full
  profile + plan, yet `onboarding_completed_at IS NULL` — the exact forced-
  re-onboard class. Heal migration 098 applied live → 1 row healed (test7).
- `users.created_at` confirmed always-populated (auth trigger uses `now()`,
  migration 039) → 098's backfill source is safe.
- 097/098 paired into `backups/applied_migrations.json` in the landing commits.

## B-pass (fresh context-blind Sonnet) — accepted
`docs/reviews/5a1ac3e1cb4d-review.md`. 4 findings, all terminal:
- **F1 (accepted+fixed):** the durable Hive `onboarding_completed_at` activated a
  dormant reader, `WorkoutRepository._earliestUserAnchor`, whose raw mid-day
  instant could exclude the onboarding-day workout from the date-granular streak
  walk. Fixed by `istMidnight(dt)` normalization (only moves the anchor earlier —
  never drops a completed day). Behavioral regression test added
  (`onboarding_streak_anchor_ist_midnight_test.dart`); full streak suite green.
- **F4 (accepted+fixed):** the writer contract test was source-grep only →
  added the behavioral test above (real Hive + `_calculateStreak`).
- **F3 (false_alarm):** 098 `created_at IS NOT NULL` guard — moot (trigger
  guarantees `created_at`; 098 already applied + healed).
- **F2:** reviewer self-reclassified as clean.

## Convergence
No open findings. The one material issue the B-pass surfaced (F1, a streak-anchor
interaction my own Hive-stamp introduced) is fixed with a behavioral test and the
existing streak suite re-verified — converged. Bootstrapper cross-table reconcile
deliberately not taken (cause fixed; 42703 footgun) — rationale in c4d8a2.

> Scope: this record covers 097 + Unit D/B (this merge). Unit A (rank Hybrid,
> platform) and OPT-H (restore) are separate in-scope units of the parent plan,
> each carrying its own §4.12 record + Hermes at its merge.
