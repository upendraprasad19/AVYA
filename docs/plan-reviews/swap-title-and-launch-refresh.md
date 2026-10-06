---
branch: swap-title-and-launch-refresh
date: 2026-10-04
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — completed-row title follows its log (`swap-title-and-launch-refresh`)

Founder request (chat 2026-10-03/04): plan OI-284 + OI-294 together ("Option A"), "let's plan this and start on
this". Plan: `docs/plans/swap-title-and-launch-refresh.md` (v3). Scope that CONVERGED: OI-284 only. OI-294 was split
out by round 2 (§4.12.1) and re-filed on the board with its design constraints.

## Lineage

Six earlier rounds on `swap-cross-device-reconcile` (v1-v6) shipped only the Home-insight fix (c7e3a9, PR #69); every
sync-side unit was split to the OI board. This branch starts a NEW plan on that board. `review_rounds: 2` counts only
the rounds on this plan's own revisions.

## Rounds

- **R1** (v1, three fresh context-blind reviewers: heal design, launch refresh, process/overlap): NOT converged.
  Verified-in-code findings: (1) bumping `restoreCompletedTick` also opens the streak-decay gate
  (`workout_repository.dart:244-248`); (2) OI-294's premise was half wrong — a cold start already full-restores via
  `/restoring` and refreshes on success; (3) the heal hook was false — `heal_after_restore.dart` runs only on the
  background branch after success; (4) `_restoreWorkoutLogs` keeps the OLDEST cloud row per date (→ OI-302); (5) the
  `source != cloud_restore` guard would have excluded the founder's own kind of wlog (coordinator-caught before
  dispatch: only `cloud_restore_completion` is synthetic); (6) casing and double-completion semantics unstated.
- **R2** (v2, two fresh reviewers): **U2 (the heal and its hooks) converged** — no P0-P2; five round-1 items
  FIXED. **U1 NOT converged**: a wrapper that bumps on a returned `!result.succeeded` is nearly unreachable
  (`_safeRestoreOp` swallows every per-op error/timeout, `sync_service.dart:2681-2714`; the other `failed` returns
  are zero-write; `cancelInflightRestore` only for new users), so U1 was split out and OI-294 rewritten. Mechanical
  P3s applied in v3: telemetry `unawaited`; the `markCompleted` literal guard scans the enclosing function body; cite
  fixes; the hook test goes through a decision seam, not `SyncHarness` (its restore returns `failed('No authenticated
  user')`).

## Ground truth

Every reviewer claim the plan relied on was re-read by the coordinator before use. Live SELECT-only check
(project `dedsavbjuwgarrhphgnl`): `scheduled_workouts` Oct 1/Oct 2 completed, `template_id` NULL on every row Sep
29–Oct 4; cloud `plan_json` Oct 1 = "Pull + Core" completed.

## Execution evidence

Test file written first and watched RED (compile failure — the code did not exist), then the heal + hooks; 23 tests
green; 22 mutations (13 + 5 after the first code review + 4 after a second, ACCEPTED fresh-context review) each applied once and each reddened ≥1 test (files restored and byte-compared); 154 related
existing tests across 18 files pass. Measured blast radius `account` (round 2 predicted the same), so no `bpass`
record is required; a `/code-review` still runs before the merge (§4.3). OI-284 stays OPEN until the founder's
device check (the phone's wlog source is unproven).
