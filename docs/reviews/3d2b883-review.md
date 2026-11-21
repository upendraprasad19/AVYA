---
reviewed_at: 2026-06-09
staged_against: 3d2b883 (branch regression-prevention-wi1-2026-06-08, main..HEAD, 4 commits)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, gate_parser_correctness, rank_behavior_preservation, migration_safety, test_validity]
findings_count: 2
verdict: accepted
---

# Code Review — regression-prevention-wi1-2026-06-08 (main..HEAD)

Fresh adversarial B-pass before the `--no-ff` merge to `main`. Two migrations (088, 089) already LIVE on prod (`dedsavbjuwgarrhphgnl`); `evaluate-rank-promotions` v9 already deployed — so the reviewer treated every claim as prod-live and verified independently.

**Result: no P0s, no P1s. Two P2s (test-quality only), both fixed in-batch.**

## Finding 1 — P2 — test_validity — FIXED
- **file:line:** test/contracts/constraint_boundary_clamp_test.dart (old test 3)
- **claim:** "no clamp narrows below the largest CHECK bound" compared each clamp to `max(checkMax)`=10000 — vacuous, since every clamp ≤ 10000. A duration clamp regressed to `clamp(0,100)` would still pass green.
- **verification:** `checkMax.values=[10000,10000,3600,50,50]`; `maxBound=10000`; `3600<=10000` passes even if `3600→100`.
- **fix applied:** replaced with "every clamp literal equals a known live CHECK bound" — `clamp(0,100)` now fails (100 ∉ {10000,3600,50}). Test green.
- **status:** fixed

## Finding 2 — P2 — test_validity — FIXED
- **file:line:** test/contracts/constraint_boundary_clamp_test.dart (test 4)
- **claim:** "set_number is NOT clamped" guarded only the identifier strings `setNum.clamp(` / `clampedSetNum` / `cleanedSets.length.clamp(` — bypassable by a clamp under a different variable name.
- **verification:** `(sm['set_number'] as num?)?.clamp(0,50)` under a new var name passes all three guards.
- **fix applied:** added a defence-in-depth pin on the bare unclamped write expression `'set_number': setNum,` — a clamp under any var name changes the write line and trips it. Test green.
- **status:** fixed

## Lenses returned clean (independently verified)
- **rank_behavior_preservation** — verified the `reason` guard in rank_engine.ts was dead code (cloud `scheduled_workouts` never holds `reason`; pre-onboarding rows are `status='rest'`, already skipped). Reviewer read workout_schedule_read_service.dart:306-312 + sync_workout.dart:1468-1476 + workout_repository.dart:344-350. Removal safe.
- **gate_parser_correctness** — the nested-single-line-map false-positive risk is real in the abstract but has ZERO exposure (`grep` for `.insert/upsert/update({...{...}...})` in supabase/functions → no matches). Gate produces no-output (not a false PASS) on unparseable patterns. Scope honestly documented in the gate header.
- **writer_reader_drift** — duration_secs/status/scheduled_date column names match the writers; the new behavioral test is genuine. No drift.
- **function_exception_swallow** — new catch blocks in sync_workout.dart pair with `recordNonFatal` + `_reportSyncFailure`.
- **blast_radius_mismatch** — platform/account tagging consistent; this B-pass satisfies §4.3.
- **secrets_in_tree** — no credential literals; EF payload references envs via `Deno.env.get`.
- **migration_safety** — 088 metadata-only; 089 re-validated live (max set_number 15 ≤ 50). Minor: 089's inline rollback adds NOT VALID while forward doesn't — acceptable (live state clean).
- **unawaited_no_error_sink** — the two new `unawaited(ErrorTelemetry.logEvent(...))` are the canonical fire-and-forget sink; all Supabase upserts are awaited in try/catch.

## Founder triage notes
Both P2s ACCEPTED and FIXED in-batch (per no-deferrals) — this batch is about test quality, so vacuous/bypassable tests are not acceptable to carry. Re-ran the test: 4/4 green. Verdict: **accepted** — safe to merge to `main`.
