---
branch: coach-history-correctness-tools
date: 2026-10-06
blast_radius: platform
review_rounds: 11
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — L1b coach history tools and server readers (`coach-history-correctness-tools`)

Plan: `docs/plans/coach-history-correctness-tools.md` (v12). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L1). Fixes OI-296, OI-308 (recurrence of APK #12.6), OI-269 and the reader half of OI-307, plus T9 (pr-detection reads 20 minutes on an hourly cron).

`bpass: pending` — the B-pass runs on the code before the merge to `main` and this field becomes `accepted` in that commit (CLAUDE.md §4.3, §4.12.3).

## Lineage and rounds

Every round used fresh context-blind reviewers with an exhaustive read-only tool allow-list (no scripts, no database statements); the coordinator re-checked every load-bearing claim against the code or with read-only live SQL before acting on it.

- **R1** (single L1 plan): split into L1a / L1b.
- **R2–R4**: dedupe key gained `user_id`; dedupe before `is_pr`; day from `workout_log_id`; `fetchPagesBounded` in a new module; crypto.subtle v5 with a parity fixture; T9 found live (R4T-1).
- **R5–R8**: `window.ts` + writer-parsing cron test; scoped WARN mode for B8; a 400-day widening (R5) and recency `created_at` bounds (R7) added and then removed after they produced new P1s.
- **R9** (v9): day-window readers select by `.in(workout_log_id, v5 ids)`; missing-date bucket, post-dedupe sort, recency = yesterday/today, weekly-report 7 dates.
- **R10** (v10): one P2 — the 65-minute window overlapped hourly ticks and `shouldSendProactive` does not absorb it ⇒ tick-aligned window.
- **R11** (v11): window confirmed sound; one P2 on the post-deploy check (a manual pr-detection call sends real pushes) ⇒ replaced by cron-tick log + read-only query. **Converged** (`mechanical_only: true` — the round changed a verification step and wording, no mechanism).

## Ground truth verified (coordinator, read-only, 2026-10-06)

0 rows in the missing-date bucket `v5('workout_')` (wle 0 of 226, wls 0); `proactive_pr_detection` cron `0 * * * *` (migration 141 `:162-165`, registry row `CRON_REGISTRY.md:28`) vs the 20-minute window `pr-detection/index.ts:72-78`; `shouldSendProactive` single slot, same-type same-IST-date only (`_shared/proactive_dedup.ts:52-70`); pr-detection has no dry-run or single-user path.

## Founder decisions (2026-10-06)

"Last sync or write wins" (L1a); `future-prediction` disposition is a founder decision row in the plan's ledger; OI-307 flips only after the L1a-1 apply AND every L1b deploy. Each Edge Function deploy needs its own go.

## §4.6

B8 ships a scoped WARN mode first and flips at least 24 h later; reader changes are behaviour fixes with behavioural Deno tests and mutations.
