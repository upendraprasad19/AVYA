---
branch: workout-6-readiness
scope: Batch 6 — readiness check-in (W2.3) + session adjustment + PRO trends (W3.7), cloud-durable
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-6-readiness-bpass.md
---

# Plan-review record — Batch 6 (readiness, cloud-durable)

Plan: [`docs/plans/batch6_readiness_plan.md`](../../../../Users/upend/AppData/Local/Temp) (session scratchpad — the
converged plan + both review rounds). §4.12 ×2 context-blind review; every load-bearing claim verified against
code + live state. **Converged → implemented → shipped in 3 sub-units (6-A/6-B/6-C).** PLATFORM tier
(`sync/**` + `plan_engine/**`). Founder: **cloud-durable v1 + migration apply PRE-AUTHORIZED** (2026-07-17).

## Ground-truth verified (subagent a7b8f26e + both review rounds, against code)
`cns_demand` dead (only `sequencing_engine._cnsDemand`); `ActiveWorkoutData` has the ⑦b `sessionDetrainingFactor`
copyWith-thread precedent; `ExerciseData.weight` is dead `'0kg'` (the real load is the `exercise_card` prefill);
`removeLastSet` floors at 1 set; the 2 START callsites are widget-layer (`hero_cards`/`planned_expansion`);
`reports_screen` is not PRO at entry; the C3 single-call restore is fail-closed + fast-path early-returns;
`_fetchAllRows` uses a variable `.from` (schema-gate-exempt); `check_schema_column_refs` is a static literal scan.

## The ×2 review — 4 P0s caught PRE-CODE (the §4.12 value)
- **Round 1:** (P0-1) a `.from('readiness_daily')` LITERAL can't be committed before the migration+regen →
  commit-sequencing (local core gate-clean first). (P0-2) adding readiness to the fail-closed single-call bundle
  collapses the C3 fast-path platform-wide → standalone restore via `_fetchAllRows`. Plus: cut the net-new CNS
  swap (session-time injury/⑥-equipment re-filter risk; the design marked it optional); copyWith-thread any new
  `ActiveWorkoutData` field (⑦b F1); the double-cut vs ⑦b.
- **Round 2 (on the hardened plan) — new P0s the round-1 fixes introduced/missed:** (P0-A) the standalone restore
  is SKIPPED on the default fast path (`_attemptSingleCallRestore` early-returns before the legacy Step C) →
  readiness synced-but-never-restored → a THIRD insertion inside `_attemptSingleCallRestore` before its success
  return. (P0-B) the migration omits RLS. (R2b P0) the LOAD cut was a false model — `ExerciseData.weight` is dead
  `'0kg'`; the real cut is the `exercise_card` prefill (`lastWeight × sessionDetrainingFactor`) → redesign as a
  single-site `effectiveLoadFactor`. Plus migration DDL: `created_at` (P1-C) + `UNIQUE`/PK arbiter (P1-D).

Two rounds surfacing new P0s in two areas = the §4.12 split signal → **split into 6-A (Hive-local core) / 6-B
(load-cut) / 6-C (cloud durability)**, all shipping → cloud-durable v1.

## Implemented (all committed on this branch, tested, analyze-clean)
- **6-A** `21d155f1` — pure engine `readiness.dart` (green/yellow/red flag-count) · flag `enable_readiness`
  (ship-dark) · `HealthWriteService.logReadiness` (healthBox `readiness_<istDate>`) · `HealthReadService`
  reads · `ActiveWorkoutData.readinessLevel` (copyWith-threaded) + `startWorkout(day,{readiness})` Red isolation
  SET-DROP (floor auto) + re-entry read (`nowWall`, stored → never re-prompt) · the 3×3 sheet + both callsites.
- **6-B + W3.7** `cc3f2276` — the LOAD cut redesigned at the single site (`exercise_card` prefill):
  `effectiveLoadFactor(ex)` = LARGER-CUT-WINS(⑦b, readiness compound cut), compound-only, no double-dip,
  byte-identical off. + the PRO readiness-trend section in the Weekly Report (a `subscriptionInfoProvider`
  `.isPro` teaser — B-pass P2-2 removed the dead `featureReadinessTrends` gate-key).
- **6-C** (this commit) — `readiness_daily` cloud sync + standalone `_restoreReadiness` on ALL 3 restore paths
  (incl. the fast-path P0-A insertion) + **migration 105 APPLIED + live-verified** (RLS own-rows / PK arbiter /
  created_at / ON DELETE CASCADE) + live_schema/applied_migrations/SoT-cloud bookkeeping.

Ship-dark: `enable_readiness` OFF → no sheet / no read / no adjust → byte-identical. Behavioral test
`readiness_checkin_behavioral_test.dart` (17: flag-count, copyWith F1, Red set-drop passed + STORED re-entry +
Green no-op + flag-OFF byte-identical + effectiveLoadFactor larger-cut-wins/compound-only + readinessHistory).
restore_completeness pins `_restoreReadiness ≥3` call-sites. SoT `readiness_daily`. Migration pre-authorized.

## Verdict: converged
All 4 P0s + the DDL P1s folded + implemented + tested + the migration applied & live-verified. B-pass on the
implemented Batch-6 diff (§4.3 / platform): **accepted — no P0/P1** (all 4 prior-review P0 fixes verified in code
+ the migration live-verified against `dedsavbjuwgarrhphgnl`). Three ship-dark P2s surfaced and **all fixed
in-branch** (no deferral, §4.2): P2-1 (overload indicator + "TRY:" hint now consume `effectiveLoadFactor`, not the
raw ⑦b factor — else a readiness deload rendered a shaming red↓ + TRY; + a comment-stripped source-grep wiring
lock); P2-2 (trend gates via `ref.watch(subscriptionInfoProvider).isPro` per rule 5; dead `featureReadinessTrends`
gate-key removed per the E.8 precedent); P2-3 (`_syncReadiness` added to `weeklyFullSync` — offline-failed check-in
push now has a periodic backstop). Full record: [`docs/reviews/workout-6-readiness-bpass.md`](../reviews/workout-6-readiness-bpass.md).
