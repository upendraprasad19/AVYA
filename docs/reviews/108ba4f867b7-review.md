---
reviewed_at: 2026-08-03T21:40:00+05:30
staged_against: 108ba4f867b7
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — `108ba4f867b7`

Branch `oi83-restore-monotonic`, closes OI-83, diagnose `d1f6b3`. Run AFTER two context-blind
Opus rounds (7 + 5 findings, all fixed), so the lenses pointed at an already-twice-hardened diff.

> Reviewed against staging hash `775a80f0bd42`. The hash moved twice after: to `f01e47438d16`
> when the five findings below were fixed and their regression tests added, then to
> `108ba4f867b7` when `docs/plan-reviews/oi83-restore-monotonic.md` was staged — the hash
> excludes `docs/reviews/` but NOT `docs/plan-reviews/`, so the plan-review record must be
> written and staged BEFORE the review file is named. No code change landed in between.

## Finding 1 — P1 — writer_reader_drift — FIXED

- **file:line:** `lib/core/services/auth_session_bootstrapper.dart:373` (was), vs the guarded
  write at `:335`.
- **claim:** The restore writes the monotonically-guarded `current_phase` to Hive, but the
  login-restore plan-regeneration block a few lines below read the **raw cloud row** —
  `progressRows.first['current_phase']` — and fed it straight into
  `generateAndSchedule(phase: …)`. On a restore that had just REFUSED a demotion (local ahead of
  cloud, not yet pushed) the freshly generated plan would be seeded with the **demoted** phase
  while `userBox['progress']` correctly held the higher one. Counter and plan content disagree —
  the same failure shape OI-85 tracks, reached by a third path the guard did not cover.
- **why the guard did not catch it:** the merge is correct; this is a *reader* that bypassed the
  merged result. Classic writer/reader drift, and the reason the SoT registry's reader manifest
  for `phase_progress_current_phase` is explicitly `reader_manifest_complete: false`.
- **verification:** `grep -n "current_phase" lib/core/services/auth_session_bootstrapper.dart`
  → 331 (merge input), 335 (guarded write), 374 (raw cloud read), 398 (`phase:` consumption).
  `progressMerge` is scoped inside the `if (progressRows.isNotEmpty)` block that closes at 338,
  so it is not in scope at 373 — confirmed by reading the block.
- **fix applied:** read the post-merge value from Hive
  (`UserRepository.instance.getProgress()?['current_phase']`), which is the guarded truth and is
  in scope everywhere. Also removes the previous hardcoded `: 1` fallback when the cloud row is
  absent — using the local value there is strictly better.
- **regression test:** `test/contracts/restore_progress_uses_shared_merge_test.dart` — an
  absent-pattern pin on the raw cloud read PLUS a positive pin on the Hive read, so deleting the
  block cannot pass.
- **status:** fixed

## Finding 2 — P1 — doc_accuracy — FIXED

- **file:line:** `docs/audit/open_issues.md`, OI-83 closure block.
- **claim:** The closure asserted the second-order stale-rows problem was "closed... the loser of
  the race repairs its own rows via `reconcileAfterDeclinedAdvance`, which forces
  `PlanIntegrityReconciler` past its `needsHeal` symptom gate" — which is exactly the mechanism
  OI-85 (opened by this same diff) records as REFUTED, and names a function that does not exist
  in the shipped code.
- **verification:** `grep -rn "reconcileAfterDeclinedAdvance" . --include=*.dart` → zero
  definitions; the shipped function is `reportDeclinedAdvanceLeftStaleRows`.
- **fix applied:** closure block rewritten to match the diagnose-doc's accurate account —
  reported via telemetry, repair filed as OI-85 with all three refutations.
- **status:** fixed

## Finding 3 — P2 — doc_accuracy (test counts) — FIXED

- **claim:** the diagnose-doc claimed 22+6=28, the board claimed 26+6=32; neither matched, and
  they disagreed with each other by 4.
- **root cause of the recurrence:** three different counting methods disagree —
  `grep -c '^\s*test('` counts DECLARATIONS (5 in the routing file), the runner's trailing `+N`
  INCLUDES `tearDownAll`, and the routing file's real total is 8 because three of its tests sit
  inside a `for (final path in writers)` loop over 2 writers.
- **fix applied:** both docs corrected to **31 executed** (23 + 8), with the loop and the
  counting trap documented inline so the next reader does not "correct" it back.
- **status:** fixed

## Finding 4 — P2 — observability — FIXED

- **file:line:** `lib/core/services/error_telemetry.dart` `highPriorityOpTypes`.
- **claim:** `phase_advance_declined_rows_stale` — the event OI-85 explicitly designates as the
  frequency measurement that decides whether a repair gets built — was left LOW-priority, so the
  client cooldown can silently drop it. The batch's own added comment argues a cooldown is most
  likely active precisely when the condition is most likely.
- **fix applied:** added to BOTH `highPriorityOpTypes` and the server
  `log-client-error/index.ts` `HIGH_PRIORITY_OP_TYPES`.
- **regression test:** `test/contracts/high_priority_op_types_parity_test.dart` green (the twin
  test would fail on one-sided addition).
- **status:** fixed

## Finding 5 — P3 — doc_accuracy (stale citations) — FIXED

- **claim:** four `writers:`/`readers:` line citations in the diagnose-doc were stale after the
  helper block was relocated (`mergeCloudProgress` cited `:240`, actual `:299`;
  `monotonicProgressFields` `:200` → `:235`; `reportProgressDemotionsDeclined` `:71` → `:79`;
  `reportDeclinedAdvanceLeftStaleRows` `:380` → `:391`). The project names this exact
  phantom-citation class from a prior Unit 6 correction.
- **fix applied:** all four re-derived by grep against the final file state, plus a new reader
  entry for the Finding 1 site.
- **status:** fixed

## Checked clean — with evidence

- **blast_radius_mismatch** — `git diff --cached --name-only | dart run
  scripts/blast_radius_from_diff.dart -` → `platform`, matching the diagnose-doc. All four
  platform requirements present: regression_test + behavioral_test_path (both green),
  `code_review_b_pass` (this record), `feature_flag`
  (`disable_progress_restore_monotonic_merge`).
- **secrets_in_tree** —
  `git diff --cached | grep -nE "sk-[A-Za-z0-9]{10,}|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN"` →
  no matches.
- **unawaited_no_error_sink** — every `unawaited(` added wraps `ErrorTelemetry.logEvent` /
  `recordNonFatal`, both self-swallowing. Note the reviewer's separate observation that the
  *first* draft of `reportDeclinedAdvanceLeftStaleRows` used `unawaited(` INSIDE its own try,
  putting the rejection outside the catch — found by this unit's own test and fixed by awaiting.
- **function_exception_swallow** — both restore writers' merge+put+report sit inside pre-existing
  outer try/catch (`auth_session_bootstrapper.dart:311-411`, `sync_profile.dart:591-631`).
- **malformedFields / declinedFields exclusivity** — traced every branch of
  `mergeCloudProgress`; each `continue`s after touching at most one list, so a field can never
  appear in both.
- **writer_reader_drift (type safety)** — `rank_service.dart:448`, `pro_phase_advance.dart`,
  `sync_profile.dart:100,289,301,320` all use null-safe `as int?` / `(v as num?)?.toInt()` on the
  three guarded fields.

## Founder triage notes

Five findings, all accepted and fixed in-branch, each with a regression pin where one is
possible. Post-fix: `flutter analyze` 0 warnings / 0 errors from this diff; **87 tests green**
across the 7 affected suites; SoT parity green; OI index regenerates at 25 open.

**One residual carried honestly, not silently:** the reviewer flagged that the kill-switch's
key-INSERTION-ORDER equivalence to the pre-fix expression is argued by code reading but not
independently test-verified — the existing test uses a single-key map and `equals()` on Maps is
order-insensitive anyway. Order does not affect any reader (every consumer looks keys up by
name, never by position), so this is recorded as a known limit of the test rather than treated
as a defect.
