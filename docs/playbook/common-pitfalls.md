---
source: CLAUDE.md §19 (subset — class-C survivors)
migrated: 2026-05-18
status: scaffold
---

# Common Pitfalls — Cross-Domain

> §19 entries that don't fit a specific feature CLAUDE.md or architecture doc.
> Class A entries (test-covered) deleted in Milestone 6.
> Class B entries (need tests) get tests in Milestone 4 then deleted.
> Class C entries (non-testable) relocated here OR to feature CLAUDE.md in Milestone 5.
> Class D entries (historical/stale) deleted in Milestone 6.

<!-- POPULATED IN MILESTONE 5 -->

---

## Batch Retrospectives (durable historical record)

### DRIFT-FIX BATCH 2026-05-24 — first writer-reader-drift-detector validation + 10 findings closed + Gate 23

First execution of the ECC adoption B1 agent (`.claude/agents/writer-reader-drift-detector.md` — see "Adopted ECC Patterns" below) against workout + nutrition domains. 9 findings surfaced by initial scan + 1 orphan caught at T16 verification re-run = 10 closed in one mega-commit `14cda1b` (Approach C; founder-locked, waiving `feedback_gates_before_refactor` for this batch — 10 mostly-mechanical findings; pre-commit hook only runs once).

Headline closures:

- **Nutrition F1 P0** — `NutritionWriteService.computeLogKey` + `logMeal` inline + `logWater` (3 sites; scan caught 2, in-batch sweep caught 3rd per `feedback_ist_sweep_gap`) now route through `istDateStr(date)`; behavioral test `nutrition_write_service_ist_anchored_test.dart` pins.
- **Nutrition F2 P1** — Gate 23 (`scripts/check_nlog_key_canonical.dart`) + contract test pin the 3-file `nlog_*` writer allowlist (mirrors Gate 17 for `exlog_*` from APK Test #16.1).
- **Nutrition F4 P2** + **Workout F4 P2** — migration 068 ships `nutrition_log_items.fiber NUMERIC DEFAULT 0` (additive) + atomic rename `workout_logs.exercise_name` → `workout_name` (column was always a session label e.g. "Push A", never per-exercise; founder choice — sole tester, no dual-write phase). UNIQUE INDEX dropped + renamed + recreated; weekly-report Edge Function (sole `workout_logs.exercise_name` reader) redeployed v21. Source-tree file `068b_drift_fix_batch.sql` (renamed from `068_drift_fix_batch.sql` on 2026-05-27 per `050b` precedent — see `README_RECONCILIATION_2026-05-11.md` §E) lives alongside the existing `068_cron_call_log.sql`; `applied_migrations.json` records `"068b_drift_fix_batch"`.
- **Workout F1 P1** — AI snapshot PR read `reps_completed` (SUM across sets per WriteService contract); new `AiCoachRepository.prSetRepsForExlog` walks `sets[]`, surfaces reps at the PR-weight set, falls through to `reps_completed` for legacy rows without `sets[]`.
- **Workout F2 P1** — 6 sites across 5 train/ files silently read `log['duration_seconds']` at top level; WriteService never emits the field there (`sets[].duration_sec` is canonical) → 0 for every modern row. Routed through `WorkoutReadService.bestPerSetDuration`.
- **Workout F5 P2** — deleted `logSetWithPrRescan` + 3 cascading orphan helpers (`_invalidateExlogDateIndex`, `_recomputePrFlagsForExercise`, `_PrScanEntry`) ~277 lines total. Preflight grep confirmed zero active callers; cascading cleanup verified `_exlogDateIndex`/`_ensureExlogDateIndex` still actively called from `getExerciseLogsForDate` legacy fallback (kept).
- **T16 orphan finding** — `train_provider.dart` 4 sites read legacy `sets_completed` while WriteService emits canonical `set_number`; closed via dual-name read pattern (canonical-first fallthrough) mirroring `ExerciseSet.fromMap` `duration_sec`/`duration_seconds`.

**Class lesson — first B1 validation:** the ECC drift-detector caught a real latent P0 (nutrition F1 IST) on its very first run against an audited domain. ROI of B1 adoption proven. In-batch scope expansion pattern reaffirmed across 4 expansions during execution (F1 2→3 sites, F2 2→6 sites, T11 cascading dead code, T16 orphan) all closed in same commit per `feedback_no_deferrals`.

9 new contract/behavioral tests, 1 new build gate (Gate 23 wired into `.claude/commands/build-apk.md`), 1 migration applied live (version `20260525010726`), 1 Edge Function redeploy (weekly-report v20→v21 `ezbr_sha256 ec4c002321e78fdf4d2348f31f3ce2dec0dcd4c9eeb5f3072736ba952d8114df`). closes-diagnose: 524d12.

Sources: spec `docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md`, plan `docs/superpowers/plans/2026-05-24-drift-fix-batch.md`, closure YAML `docs/audit/2026_05_24_drift_fix_closures.yaml`, diagnose `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md`.

---

## ADOPTED ECC PATTERNS (2026-05-24)

Five tools adopted from [affaan-m/ECC](https://github.com/affaan-m/ECC) on 2026-05-24 to harden the Claude harness workflow against the #1 recurring bug class (writer/reader drift) and the doc drift that hides it. Skipped: PostToolUse hooks (Windows fragility), memory TTL (deferred to separate batch). Adopted ECC's intent + structure; rewrote every prompt for our codebase (SoT registry refs, Hive/Riverpod/Supabase patterns, known drift signatures baked in).

1. **`.claude/settings.json`** (B2) — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55` + `MAX_THINKING_TOKENS=10000`. Compact at 55% not 95%; cap thinking budget. Effect visible from next session.
2. **`.claude/skills/strategic-compact/SKILL.md`** (B5) — surfaces `/compact` suggestions at logical phase boundaries with curated preserve/drop guidance. Founder-approved; never auto-runs.
3. **`.claude/skills/sync-claude-md/SKILL.md`** (B6) — audits CLAUDE.md for drift vs live code/DB state. Extracts paths, line refs, count claims, version claims, memory refs; verifies each. Run at end of every batch before committing CLAUDE.md changes.
4. **`.claude/agents/writer-reader-drift-detector.md`** (B1) — read-only subagent that traces writer→reader paths for a domain or writer file. Targets the writer/reader drift bug class (7+ instances since Test #6). First run surfaced 1 P0 (nutrition IST writer) + 2 P1 (AI PR reps semantic, top-level duration_seconds dead read) + multiple P2 — driving a follow-on drift-fix batch.
5. **`.claude/skills/audit-claude-config/SKILL.md`** (B3) — audits `.claude/settings*.json` for stale Bash allows, orphan permissions, suspected secrets. One-time + quarterly. First run baseline clean (1 P2 stale Bash allow).

Spec: [docs/superpowers/specs/2026-05-24-ecc-adoption-design.md](../superpowers/specs/2026-05-24-ecc-adoption-design.md)
Plan: [docs/superpowers/plans/2026-05-24-ecc-adoption.md](../superpowers/plans/2026-05-24-ecc-adoption.md)
First-run reports: `docs/audit/2026-05-24-{claude-md-drift,drift-scan-workout,drift-scan-nutrition,claude-config-audit}.md`.

Founder gates: T3 first-run surfaced 4 P1 + 2 P2 in CLAUDE.md (count drifts + version-stamp annotation), all closed in same batch (commit `85a47ba`). T4 first-run drift findings escalated to a dedicated drift-fix follow-on batch — shipped 2026-05-24 in commit `14cda1b` (see "DRIFT-FIX BATCH 2026-05-24" entry above); 10/10 findings closed (9 from scan + 1 orphan from T16 verification re-run), migration 068 applied live, Gate 23 added, weekly-report Edge Function v21 deployed.

Explicitly NOT adopted: PostToolUse hooks (Windows fragility), memory TTL (deferred to separate batch), cross-harness adapters (Claude Code only), ECC's 230+ generic skills (only adopted what we'll actually invoke).
