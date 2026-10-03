---
reviewed_at: 2026-06-28T18:10:00+05:30
staged_against: opt-quick-wins (ff1c793 097 FK indexes + 85f0221 Unit D+B durable onboarding_completed_at + 098 heal)
diff_hash: 5a1ac3e1cb4d
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — opt-quick-wins (5a1ac3e1cb4d)

Fresh context-blind Sonnet reviewer over `git diff main...opt-quick-wins` with
the 5 standard lenses + 5 author-stated focus claims. Two real issues, one
theoretical migration nit, the rest clean. All triaged to terminal status.

## Finding 1 — P2 → upgraded P1 on verification — writer_reader_drift
- **file:line:** lib/features/train/repositories/workout_repository.dart:133 (`_earliestUserAnchor.consider`)
- **claim:** Diagnose c4d8a2 makes `onboarding_completed_at` a durable **Hive**
  value. That activates `_earliestUserAnchor`'s `consider(profile['onboarding_completed_at'])`
  read, which was dormant (the Hive profile never carried the column → the anchor
  fell back to the first-workout date). The streak walk-back stop
  `date.isBefore(anchor)` is date-granular, but `date = today.subtract(days)`
  carries the wall-clock time-of-day. A **raw mid-day UTC instant** as the anchor
  excludes the onboarding-day workout whenever onboarding's IST time-of-day
  exceeds the walk's wall-clock time.
- **verification:** Read workout_repository.dart:110-370 — confirmed the loop at
  :313-320 compares the raw anchor against a time-of-day-carrying `date`; wlog
  anchors are date-strings (`DateTime.parse("YYYY-MM-DD")` = 00:00) and so never
  self-exclude, but the onboarding instant is mid-day. Confirmed `formatDateKey`
  = `istDateStr` (date_utils.dart:27), so the walk keys by IST date.
- **triage / fix:** **accepted + fixed in this batch.** `consider()` now anchors
  on `istMidnight(dt)` (ist_date.dart:97). Because `istMidnight(dt) <= dt`, the
  anchor can only move earlier — it includes the onboarding day, never drops a
  completed day. Behavioral regression test added:
  `test/contracts/onboarding_streak_anchor_ist_midnight_test.dart` (streak 2 not
  1 when the onboarding day is completed; anchor still floors the walk before the
  onboarding date). Full streak suite re-run green (no freeze/decay regression).
- **status:** accepted — fixed (commit on opt-quick-wins).

## Finding 2 — verification checkpoint (not a finding)
- restoring_screen self-heal `_stampOnboardingCompletedAt` already wrote UTC and
  is unchanged by this diff; consistent with the new convention. Reviewer
  reclassified it themselves. No action.
- **status:** false_alarm (self-reclassified by reviewer).

## Finding 3 — P1 (low practical) — blast_radius_mismatch (migration 098)
- **file:line:** supabase/migrations/098_heal_onboarding_completed_at.sql:11
- **claim:** `SET onboarding_completed_at = u.created_at` with no
  `AND u.created_at IS NOT NULL` guard; `users.created_at` is `timestamptz
  DEFAULT now()` (nullable in DDL). A null `created_at` would heal to null (no-op).
- **verification:** Reviewer confirmed via migration 039 that the auth trigger
  populates `users.created_at = now()` for every registered user, so it is never
  null in practice; 098 is already applied and healed test7 successfully (its
  `created_at` was set). The guard is belt-and-braces only.
- **triage:** **false_alarm / won't-fix.** The clobber guard
  (`AND up.onboarding_completed_at IS NULL`) is present and correct. The
  `created_at IS NOT NULL` addition would only matter for synthetic rows with an
  explicit-NULL `created_at`, which the trigger makes impossible; 098 is already
  live and a no-op migration 099 to add a guard to already-healed data is not
  warranted.
- **status:** false_alarm (documented).

## Finding 4 — P1 — writer_reader_drift (test coverage gap)
- **file:line:** test/contracts/onboarding_completed_at_durable_writer_test.dart
- **claim:** All three assertions are source-grep (string-presence) only — they
  pass even if the runtime path is broken. Violates §4.4 rule 21 /
  feedback_source_grep_false_confidence.md (every SoT contract needs a behavioral
  test too).
- **triage / fix:** **accepted + addressed.** Added behavioral test
  `test/contracts/onboarding_streak_anchor_ist_midnight_test.dart` (real Hive +
  the real `_calculateStreak` walk) covering the reader side of the durable
  value. The source-grep test is retained for the writer-side presence contract.
- **status:** accepted — fixed.

## Clean lenses
- **function_exception_swallow:** `git diff main...opt-quick-wins | grep "functions\.invoke\|callFunction"` → 0 new. Clean.
- **secrets_in_tree:** grep for `rzp_|sk_|AKIA|BEGIN|key=…20+` over the diff → 0. Clean.
- **unawaited_no_error_sink:** `grep "unawaited("` over the diff → 0 new. Clean.
- **writer_reader_drift (other readers of onboarding_completed_at):** bootstrapper
  (auth_session_bootstrapper.dart:148), prediction_card.dart, ai_snapshot_builder.dart
  are all null-presence checks or raw-string passthrough → invisible to the UTC
  format change. last_active_at Edge-Function readers (re-engagement,
  i-see-you-callout, weekly-recap-ready) parse via `new Date()` or server-side
  `.gte()` → tz-safe. Verified.
- **claim (a) `_hasValue` guard:** confirmed — `_syncUserProfile` gates the field
  on `SyncService._hasValue` → never clobbers cloud with null.
- **blast_radius (097):** five additive `CREATE INDEX IF NOT EXISTS` — idempotent,
  no data/schema change. Clean.

## Founder triage notes
Triaged by the implementing agent under the standing per-action authorization
(founder out; "approve when needed" for deploys only — no deploy here). F1 + F4
fixed in-batch; F3 false_alarm with rationale; F2 self-reclassified. Verdict:
**accepted.** Proceeding to the §4.12 plan-review record + `--no-ff` merge to main.
