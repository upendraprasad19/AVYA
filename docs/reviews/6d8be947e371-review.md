---
reviewed_at: 2026-07-21T00:00:00+05:30
staged_against: 6d8be947e371
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, kill_switch_correctness, unconditional_write_correctness, scope_and_phase_source, test_integrity]
findings_count: 5
verdict: accepted
---

# Code Review — 6d8be947e371 (current-week program-week projection)

Fresh context-blind Sonnet B-pass over the staged diff (6 files at review time; 7 after fixes).
All five findings triaged **accepted** and **fixed in-batch** (§4.2). Author re-verified each
against source before fixing.

## Finding 1 — P1 — writer_reader_drift — ACCEPTED, FIXED
- **file:line:** lib/core/services/sync_service.dart:1085 (`_replayPendingOnboardingSync`)
- **claim:** A second, unlisted writer of `user_progress.current_week` — the boot replay passed the
  frozen Hive `pr['current_week'] ?? 1` into a `user_progress` upsert on every launch while
  `pending_onboarding_sync` was set, stomping the projected program week and partially recreating
  the "Week 1 forever" bug.
- **verification:** `grep -n "'current_week': pr\['current_week'\]" lib/core/services/sync_service.dart`
  → line 1085 (confirmed); call chain `:745 → :1023-1094 → user_repository.dart:424` upserts it.
- **fix:** dropped `current_week` from the replay's `progressData` (the column is preserved on
  update / schema-defaults to 1 on a fresh insert). Added the removed writer + the correct-by-
  construction onboarding writers (`onboarding_provider:473/786`) to the SoT writer inventory. Pinned
  by a new source-wiring assertion `the boot replay does NOT write current_week`.
- **status:** fixed

## Finding 2 — P1 — test_integrity — ACCEPTED, FIXED
- **file:** docs/sot_registry.yaml (program_week_projection.behavioral_test_path) + the sync writer
- **claim:** The sync-write path had only presence-level (source-grep) coverage; a mis-wire (wrong
  variable / wrong flag polarity) would pass every test — rule 21 violation.
- **fix:** extracted `WorkoutScheduleReadService.currentWeekColumnProjection(frozenWeek, phase,
  disabled)` and wired `sync_profile` through it; added a **behavioral** test asserting the decision
  logic — OFF → frozen passthrough (incl. null), ON → program week (non-null, frozen ignored).
- **verification:** `grep -n "currentWeekColumnProjection" test/contracts/program_week_projection_behavioral_test.dart lib/core/services/sync/sync_profile.dart`
- **status:** fixed

## Finding 3 — P2 — writer_reader_drift (stale citation) — ACCEPTED, FIXED
- **claim:** diagnose-doc + SoT cited `train_provider.dart:596/825`; real lines are `:531/:760`.
- **verification:** `grep -n "current_week.*as int?.*?? 1" lib/features/train/providers/train_provider.dart`
  → 531, 760. (Underlying dead-fallback claim itself re-verified true.)
- **fix:** corrected both citations.
- **status:** fixed

## Finding 4 — P2 — kill_switch_correctness (OFF-path cast) — ACCEPTED, FIXED
- **file:line:** lib/core/services/sync/sync_profile.dart (OFF branch cast)
- **claim:** `(p['current_week'] as int?)` would throw on a non-int numeric where the original
  untyped passthrough wouldn't — not strictly byte-identical.
- **fix:** the helper now receives `(p['current_week'] as num?)?.toInt()` (non-throwing).
- **status:** fixed

## Finding 5 — P3 — quality nit (deprecated shim) — ACCEPTED, PARTIAL
- **claim:** new call sites route through the `@Deprecated` `WorkoutScheduleService` shim.
- **fix:** the new sync path now calls `WorkoutScheduleReadService` directly (via the helper);
  import switched. The two pre-existing snapshot sites keep the file's existing shim convention
  (INFO-severity, non-fatal) — out of scope for this fix.
- **status:** fixed (sync path) / accepted-as-is (snapshot sites)

## Clean lenses (verified, not assumed)
Bounded [1,12] program week (hand-checked); identical flag literal at all sites; OFF-path
byte-identity for both snapshot sites; correct phase source + import scope; no secrets; no new
`unawaited(`. See the B-pass transcript.

## Founder triage notes
All P1/P2 fixed in-batch. Re-verified: `flutter analyze` clean (1 INFO null-aware nit, non-fatal);
8/8 behavioral tests green incl. the new helper + F1 assertions; diagnose-doc re-validates.
