---
bug_id: e9d4b7
date: 2026-06-25
batch: fix-streak-stale-cloud
status: fixed
blast_radius: feature
symptom: >
  Full-charter web E2E (2026-06-21, OBS-8b): after idle days the cloud
  `user_progress.current_streak_days` stayed STALE (e.g. 1 when the streak had
  actually decayed to 0). The day-rollover reckon
  (`WorkoutRepository.reckonStreakDecayAndPersist`) persisted the streak-freeze
  fields (via `StreakProgressService.commitConsume`) but never the streak COUNT —
  `current_streak_days` was stamped ONLY by `train_provider` on workout COMPLETION
  (~train_provider.dart:1450). So a streak that decayed via the rollover reckon
  (no workout logged) left the cloud count frozen at its last completion value.
  The predictions reader (`prediction_service.dart:31`) and the server
  `evaluate-rank-promotions` cron read this cloud value, so they saw the old count.
  (The in-chat AI snapshot does NOT read this field — `ai_snapshot_builder.dart:98`
  derives a SEPARATE alias as `current_streak_weeks` x 7, the 7faa3b cron alias;
  flagged below.) Home was UNAFFECTED — it reads
  a LIVE-computed streak (`home_provider.dart:234`, "previously read cached
  current_streak_days"), which is why the screen looked right while the cloud
  diverged. OBS-8a (greedy freeze-consume) is working-as-designed per founder; only
  this stale-cloud drift (OBS-8b) is fixed.
concept: streak_current_days_cloud_persist
sot_registry_entry: not_applicable
contract_test_path: test/contracts/streak_decay_reckon_permanent_ledger_test.dart
writers: >
  `WorkoutRepository.reckonStreakDecayAndPersist` (workout_repository.dart) now,
  in its restore-settled persist branch, calls the new `_persistCurrentStreakDays`
  helper → `unawaited(UserRepository.updateProgress({'current_streak_days': streak}))`
  (updateProgress writes Hive AND fires syncProgressNow itself, user_repository.dart:146
  — so the reckon does NOT double-push). The pre-existing writer
  `train_provider.dart:1450` (workout completion) is unchanged.
readers: >
  `prediction_service.dart:31` (`progress?['current_streak_days'] ?? 0`) reads the
  Hive value directly + the server `evaluate-rank-promotions` cron reads cloud
  `user_progress.current_streak_days` — these saw the stale count and are FIXED.
  `ai_snapshot_builder.dart:98` does NOT read this field (it computes
  `current_streak_weeks` x 7, the 7faa3b alias) → unaffected by the bug AND the fix.
  `home_provider.dart:234` reads a LIVE-computed streak → unaffected.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods:
  - "syncProgressNow → _syncUserProgress (sync_profile.dart:153) upserts user_progress.current_streak_days (line 180) from the Hive progress map"
restore_methods: []
cloud_table: user_progress
cloud_columns: "current_streak_days (the cached streak count; updated_at stamped on every push)"
ist_handling: "streak walk-back uses istDateStr schedule keys (unchanged); the persist itself is date-agnostic"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - "sync_service_sync_user_progress (existing _syncUserProgress catch — unchanged)"
cross_account_guard: false
forbidden_patterns_checked:
  - "OBS-8b: the reckon now persists current_streak_days (not only the freeze fields). Gated by restoreCompletedTick>0 + a schedule row (same gate as freeze consume) so a pre-restore device never persists a spurious decay."
  - "Idempotent: _persistCurrentStreakDays no-ops when the stored value already equals the computed streak (no sync churn)."
  - "NOT monotonic — current_streak_days SHOULD decay (distinct from lifetime/peak fields, which need only-increment guards per feedback_monotonic_field_recompute_demotion). The reckon writes the freshly-walked count, up OR down."
proposed_fix: >
  Add `_persistCurrentStreakDays(int streak)` to WorkoutRepository and call it from
  `reckonStreakDecayAndPersist`'s restore-settled persist branch, right after
  `consumeMissedDayIfFreezeAvailable()` returns the walked count. It stamps Hive
  `current_streak_days` + fires `syncProgressNow()` (fire-and-forget), no-op when
  already correct. Mirrors the field `train_provider` already writes on completion,
  so decay and completion keep the cloud column in sync with the live walk.
regression_test_planned: >
  test/contracts/streak_decay_reckon_permanent_ledger_test.dart — 3 new OBS-8b
  cases in the D2 group (reuse the existing Hive + restoreCompletedTick harness):
  (1) decay with NO freeze persists current_streak_days 1→0 (the founder's symptom;
  RED pre-fix Actual=1); (2) freeze-consume path persists the count (stale 7→1; RED
  pre-fix Actual=7); (3) gated-off (restore not settled) does NOT persist (stays 9 —
  pins the restore-gate safety). All GREEN with the fix; the existing D1/D2/L27
  tests stay green.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "_persistCurrentStreakDays added + wired into reckon; flutter analyze (workout_repository.dart) No issues found" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "reckon test seeds Hive progress + asserts current_streak_days persisted to the Hive map (1→0, 7→1); gated-off leaves it untouched (9)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live OBS-8b symptom = stale current_streak_days in cloud user_progress; _syncUserProgress (sync_profile.dart:180) pushes the field — now stamped on decay too" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "reckon → updateProgress(Hive) → syncProgressNow → user_progress upsert; the decay path now closes the loop train_provider already had for completion" }
impact_analysis: >
  Feature-tier (only workout_repository.dart + its contract test; calls existing
  SyncService/UserRepository, modifies neither). Additive client write + an existing
  sync push — no migration, no schema change, no cross-account-guard impact. Improves
  AI-coach + prediction accuracy (they read the cloud count). Risk surface is small
  and fully covered: gated by restore-settled (no spurious pre-restore decay),
  idempotent (no sync churn), non-monotonic-by-design (current streak decays). OBS-8a
  (greedy consume) intentionally left as working-as-designed.
---

# Streak decay leaves cloud current_streak_days stale (e9d4b7) — OBS-8b

## What happened
The day-rollover reckon persisted streak-FREEZE state but never the streak COUNT.
`current_streak_days` was stamped only by `train_provider` on workout completion, so
a streak that DECAYED via the reckon (idle days, no workout) left the cloud column
frozen at the last completion value. Readers of the cloud value — the AI snapshot +
predictions — saw the stale count. Home reads a LIVE walk, so the screen looked fine
while the cloud diverged (the founder's "streak 1 after idle days" cloud symptom).

## Fix
`_persistCurrentStreakDays(streak)` in `WorkoutRepository`, called from
`reckonStreakDecayAndPersist`'s restore-settled persist branch after the walk. Stamps
Hive `current_streak_days` + `syncProgressNow()` (no-op when already correct). NOT
monotonic — the current streak should decay. OBS-8a (greedy consume) = working-as-designed.

## Flagged follow-up (NOT in this fix — raised to founder)
`ai_snapshot_builder.dart:98` sends the in-chat AI a `current_streak_days` computed as
`current_streak_weeks` x 7 (the 7faa3b "top-level alias for cron readers"), NOT the real
schedule-aware daily count. So even with the cloud value now correct, the AI's chat context
still sees a weeks-times-7 approximation (e.g. 21 for a 3-week streak that has decayed to 1
day). Making the snapshot read the now-reliable `current_streak_days` is a SEPARATE change —
account-tier (`lib/features/ai_coach/**`) and it must not break whatever the 7faa3b alias was
added for — so it is raised to the founder rather than silently altering the AI's input.

## See also
- lib/features/train/repositories/workout_repository.dart (reckonStreakDecayAndPersist + _persistCurrentStreakDays)
- lib/core/services/sync/sync_profile.dart (syncProgressNow / _syncUserProgress:180 — pushes current_streak_days)
- lib/features/train/providers/train_provider.dart (~:1450 — the pre-existing completion writer)
- test/contracts/streak_decay_reckon_permanent_ledger_test.dart (D2 group, OBS-8b cases)
