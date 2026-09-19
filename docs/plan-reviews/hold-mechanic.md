---
branch: hold-mechanic
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/hold-mechanic-bpass.md
---

# Plan review — hold-mechanic (free-tier "Hold the Line" mechanic + durability, Slice 1)

## What shipped

`holdWeek()` replaces the free-tier `redoWeek4` behind `enable_hold_weeks` (**default OFF**,
ship-dark). It sources the phase's canonical **Peak** week (`plan_start+14`) — or the **deload**
week (`plan_start+21`) every 4th hold — **by date** (never `plan_end`-derived, the old "copied the
deload" bug), **Monday-backdates** to this week via `normalizeToMonday(nowWall())` (keeps
`(rollStart−plan_start) % 7 == 0`), keeps loads **FLAT** (free maintains / PRO progresses), stamps a
gap-proof **row-local `hold_ordinal`** (`max` over rows dated `< rollStart`, `+1` — crash-idempotent),
extends `plan_end`, and **awaits `pushWorkoutPlanForSyncDomain()`** so the extension + exercise-rich
rows + ordinal reach `plan_json` before any reinstall. Flag OFF → the verbatim `redoWeek4`.

Durability guards (NOT flag-gated — live for all users): **#1** a shared monotonic phase-gated
re-anchor (`PlanWindowReanchor`) in BOTH restore writers (same phase → keep the later `plan_end` so
a hold survives a stale snapshot; fresh install / phase advance → cloud verbatim, preserving the
a7d3f1 stale-`plan_start` heal); **#4** a pure `paginateAll` loop replacing `_restoreScheduledWorkouts`'s
`.range(0,999)` truncation. Diagnose `d7f3a9`; closure `docs/audit/hold-mechanic.closure.yaml` (8/8
terminal). No migration, no EF deploy.

## Review rounds (ground-truth verified against source + live DB)

- **Round 1 — ×2 context-blind plan review** (before code). Both rounds verified every claim against
  on-disk source + the live DB (`dedsavbjuwgarrhphgnl`). Round 1 caught a **real durability hole**
  (the coalesced `syncWorkoutData` fan-out does NOT push `plan_json`, so a hold→reinstall would
  collapse) and a **field-name bug** (stamp `'week'`, not `week_number`, since the push maps
  `week_number ← entry['week']`). It also drove: dropping the explicit `phase` stamp (rely on the
  copy — an explicit stamp trips legacy `bucketPastRows` carry-forward), the crash-idempotent ordinal,
  the graduation dead-end guard (H5), and the §4.2 closure YAML. **Ground-truth corrections I made to
  the review itself:** the reviewer's proposed durability fix (`pushSnapshotNow`) was WRONG — that
  pushes the AI daily snapshot, not `plan_json` (verified sync_service.dart:852); corrected to
  `pushWorkoutPlanForSyncDomain` (sync_workout.dart:2032 → `_syncWorkoutPlan`). Live schema verified:
  `scheduled_workouts.week_number` is nullable int, no CHECK, zero EF/cron readers; no
  `hold_ordinal`/`is_hold` column (kept plan_json-only).

- **Round 2 — context-blind review of the HARDENED plan** (the round-1 corrections themselves).
  **CONVERGED — no P0/P1** in the plan or introduced by the corrections. Verified every delta (the
  await-in-mutex durability push, the `'week'` stamp, dropping the phase stamp, the crash-idempotent
  ordinal, the graduation guard) against source + live DB. Surfaced only P2 residuals (all folded in
  during implementation): push-after-mutex-release for UX, wrap the push in its own try/catch,
  `holdWeek` returns `void`, SoT breadth, wording. Convergence (round 2 = P2-only) is the §4.12.1
  signal to proceed.

- **B-pass** (`docs/reviews/hold-mechanic-bpass.md`, verdict: accepted). Fresh context-blind Sonnet
  over the staged diff; re-ran the 16 tests + analyze itself. Found no code P0/P1; 4 P2s — a
  telemetry-free swallow in the durability catch (FIXED: added `recordNonFatal`), a diagnose-doc line
  citation (FIXED: 189→232), a pre-existing crash-mid-loop residual (DOCUMENTED — widening the
  reconciler is the wrong fix, closure D2), and one imprecise `impact_analysis` sentence (FIXED). All
  accepted + resolved in-batch (§4.2). Its "P0" was that these two review files didn't exist yet — the
  expected final-step state, now resolved by this record.

## Ground-truth evidence

- Live DB queried during review: `scheduled_workouts` schema (`week_number` nullable, no CHECK);
  `user_progress.plan_json` size measured (~3.5 KB/day-card, ~25 KB/hold, 2.5 MB total / 11 users →
  #5 verified-acceptable). Grep of `supabase/functions/**` for `week_number` → zero readers.
- Behavioral tests (16/16 green; each fails without its fix): `hold_week_mechanic_behavioral_test.dart`
  (7 — Peak/deload source, Monday + %7, gap-proof ordinal, crash-idempotency, plan_start-untouched,
  concurrent double-call), `plan_window_reanchor_test.dart` (5), `paginate_all_test.dart` (4).
- `flutter analyze` clean on all 8 touched `lib/` files; Gate 40 closure + SoT parity + schema-col
  refs all PASS.

## Platform-tier artifacts

- `feature_flag`: `enable_hold_weeks` (default OFF, ship-dark). OFF → verbatim `redoWeek4`.
- `behavioral_test_path`: test/contracts/hold_week_mechanic_behavioral_test.dart (+ plan_window_reanchor, paginate_all).
- `code_review_b_pass`: accepted (see `bpass_review`).
- No migration, no EF deploy → no live-prod-apply gate. The flag's flip-on (a later batch, after the
  display slices) requires its own full ×2 per §4.12.4; tracked in `docs/ship_dark_pending_review.yaml`.
