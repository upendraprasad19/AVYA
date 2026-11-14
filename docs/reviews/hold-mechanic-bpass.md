---
reviewed_at: 2026-07-21
staged_against: hold-mechanic (worktree, pre-commit staged diff — 15 files)
blast_radius: platform
reviewer: claude-sonnet-via-code-review-skill (fresh, context-blind)
lens_set: [writer_reader_drift, exception_swallow, blast_radius_restore_completeness, secrets_in_tree, unawaited_concurrency]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — hold-mechanic

Fresh context-blind Sonnet over the staged diff. The reviewer independently re-ran the
3 new test files (**16/16 green**), `flutter analyze` on all touched `lib/` files (0
errors/warnings), `validate_diagnose_doc.dart`, and `validate_audit_closure.dart`, and
traced the writer/reader chains itself (not just asserted). Verdict below is
post-remediation: the P0 was a review-ordering artifact (resolved by authoring the two
review files) and all 4 P2s are fixed or documented in-batch (§4.2).

## Finding 1 — P0 (review-ordering, NOT a code defect) — plan-review artifacts absent at review time
- **claim:** `docs/plan-reviews/hold-mechanic.md` + `docs/reviews/hold-mechanic-bpass.md`
  (cited in advance by the diagnose-doc / closure yaml / ship-dark ledger) did not yet
  exist, so the merge-to-main keystone gate `check_plan_review_record_exists.dart` would
  fail at the `--no-ff` merge.
- **status: RESOLVED** — both artifacts authored as the final batch step (this file + the
  plan-review record), in the same commit as the code. The context-blind reviewer could
  not know they were the pending final step. The past-tense "converged/accepted" language
  in the other docs becomes true in this commit.

## Finding 2 — P2 — telemetry-free swallow in holdWeek's durability push
- **file:** lib/core/services/workout_schedule_write_service.dart (durability `catch`)
- **claim:** `catch (_) {}` around `pushWorkoutPlanForSyncDomain()` swallowed a possible
  `_ensureSessionOpen()` throw with NO `ErrorTelemetry` (that await sits outside
  `_syncWorkoutPlan`'s own catch); every other catch in the module pairs one.
- **status: accepted, FIXED** — `catch (e, st)` + `unawaited(ErrorTelemetry.recordNonFatal(
  e, st, reason: 'hold_week_durability_push'))`. Still non-fatal to the user.

## Finding 3 — P2 — diagnose-doc line-citation drift
- **claim:** the writers block cited `holdWeek()` at line 189 (inside `redoWeek4`'s body);
  it declares at 232.
- **status: accepted, FIXED** — corrected to 232 (+ the `normalizeToMonday(nowWall())`
  cite 205→245). The recurring "own-edit drift" class (`feedback_mistake_unverified_done_claims` §8).

## Finding 4 — P2 — crash-mid-loop trailing-days residual (pre-existing)
- **claim:** a crash between the 7 `upsertScheduled` writes and the `plan_end` write leaves
  a truncated hold week; the `PlanIntegrityReconciler` 1..4 symptom scan can't see a
  week-5+ hold row, so it won't heal it.
- **status: accepted, DOCUMENTED** — pre-existing (`redoWeek4` is identical), recoverable
  (the next hold re-materializes a full week; the row-local ordinal advances correctly) and
  cosmetic (a past week shows fewer days). Widening the reconciler scan is deliberately
  REJECTED — it re-introduces the P0-11 "fire-more" concern the #1 re-anchor addresses
  (closure finding D2). Disclosed in the diagnose-doc `impact_analysis`.

## Finding 5 — P2 — "byte-identical for the trigger" overclaim
- **claim:** the `impact_analysis` said flag-OFF is "byte-identical for the trigger" — true
  of the `redoWeek4` FUNCTION but not the tap handler (the H5 guard is a live UX change for
  all users).
- **status: accepted, FIXED** — reworded: the redoWeek4 function is byte-identical when OFF;
  the H5 graduation dead-end guard is a live change regardless of the flag.

## Lenses clean (evidence the reviewer cited)
- **writer_reader_drift:** `'week'` traced writer (`copy['week']=4+n`) → every local reader
  (`['week']` only) → push (`week_number <- entry['week']`) → restore (writes both) — no
  drift. `plan_start` uses the same raw-weekday `_normalizeToMonday` at generation and in
  `holdWeek` (the "NOT mondayOfIst" comment accurate).
- **exception_swallow:** UI catches show a snackbar; the H5 `return`-after-catch correctly
  prevents the blind `/train` nav without skipping the snackbar.
- **blast_radius/restore-completeness:** `PlanWindowReanchor` all 3 branches (fresh /
  advance → cloud verbatim; same-phase → later end) + `paginateAll` termination (incl. the
  exact-multiple edge) verified by code + the passing unit tests.
- **secrets_in_tree:** none.
- **unawaited/concurrency:** `_holdInFlight` check+set has no await between; `finally`
  releases on every path; the durability push is unreachable on early-return/throw — proven
  by the passing "two overlapping holdWeek → one hold" test.

verdict: accepted
