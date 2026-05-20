---
bug_id: 9c4a17
date: 2026-05-19
batch: APK Test #16.2 observations (2026-05-19 — obs 1+2 batch)
status: shipped
symptom: |
  Founder install of APK Test #16.2 on 2026-05-19 (Tue). Home dashboard
  rendered "0/3" streak freezes and surfaced the "Streak Freeze used! 0
  remaining this week." SnackBar despite the founder NOT missing
  Monday May 18 (calendar shows Mon ✓ + Tue ✓ both logged). Founder
  follow-up confirmed: "Monday count was already 0 too" — ruling out
  the "refill happened then consumed" theory and pointing at the
  Monday +1 silently going missing AND a separate spurious
  commitConsume call lighting up the banner.
concept: streak_freeze_refill_restore_race
sot_registry_entry: streaks
writers:
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.commitRefill (clamps on write + emits streak_freeze_refill_done telemetry), line: 59 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.refillIfNewWeek (idempotency gate + emits streak_freeze_refill_check), line: 143 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.commitConsume (sets streak_freeze_just_used flag + emits streak_freeze_consume_done), line: 100 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method_or_widget: _restoreFreezes (max-merge of available + last_refill replaces blind overwrite), line: 129 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: onRestoreComplete listener re-invokes refillIfNewWeek as defence-in-depth, line: 63 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: cold-start clear of streak_freeze_just_used flag, line: 145 }
readers:
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: _checkStreakFreezeUsed reads streak_freeze_just_used + remaining, line: 99 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier.build returns clamped streak_freezes_available, line: 252 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: _calculateStreak walk-back consumes when missed day found, line: 199 }
hive_key_prefix: "user_progress (Hive map under userBox)"
hive_key_formula: "userBox['progress'] map keys streak_freezes_available, streak_freeze_used_dates, streak_freezes_last_refill, streak_freeze_just_used (session-scoped UI flag), streak_freeze_remaining_after_use (session-scoped UI flag)"
sync_methods: [syncFreezes]
restore_methods: [restoreFromCloudForUser]
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill]
contract_test_path: test/contracts/streak_freeze_refill_race_test.dart
ist_handling:
  - { file: lib/core/services/streak_progress_service.dart, line: 144, source: mondayOfIst correctly used for refill boundary }
  - { file: lib/core/services/streak_progress_service.dart, line: 150, source: thisMondayStr formatted via padded year/month/day from IST date }
provider_invalidations: [streakFreezeProvider, streakProvider]
telemetry_op_types:
  success: [streak_freeze_refill_check, streak_freeze_refill_done, streak_freeze_consume_done]
  failure: [splash_post_restore_refill, splash_just_used_clear]
cross_account_guard: StreakFreezeNotifier.build watches authUserIdTokenProvider; restore path runs after HiveUserSession.openForUser so user-scoped boxes are correct owner.
forbidden_patterns_checked:
  - "Blind unconditional overwrite of streak_freezes_available from cloud value in _restoreFreezes."
  - "Refill orchestrator called only once during boot (refill should run both at splash and post-restore as defence-in-depth)."
  - "streak_freeze_just_used persisted across cold start without being cleared."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "_restoreFreezes max-merge logic + splash post-restore refillIfNewWeek + cold-start just_used clear" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "max-merge preserves local refill when cloud is stale; cold-start clear scrubs stale session flag" }
  - { tier: 6, name: cloud_sync_restore, status: fixed_in_this_batch, evidence: "sync_restore_completeness._restoreFreezes rewritten to compare last_refill timestamps before overwriting available" }
  - { tier: 9, name: provider_invalidation, status: fixed_in_this_batch, evidence: "splash onRestoreComplete listener invalidates streakFreezeProvider + streakProvider so badge refreshes immediately after re-refill" }
  - { tier: 11, name: ist_correctness, status: verified, evidence: "mondayOfIst usage in refillIfNewWeek unchanged at streak_progress_service.dart:144" }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "test/contracts/streak_freeze_refill_race_test.dart + test/contracts/streak_freeze_refill_telemetry_test.dart pin writer/reader/telemetry shape" }
impact_analysis:
  callers_audited:
    - lib/features/auth/screens/splash_screen.dart (runRolloverNow + onRestoreComplete listener)
    - lib/features/auth/screens/restoring_screen.dart (restoreFromCloudForUser kickoff)
    - lib/core/services/day_rollover_service.dart (runRolloverNow + _doRolloverWithRef call refillIfNewWeek)
    - lib/core/services/sync/sync_restore_completeness.dart (_restoreFreezes is the cloud-side reader)
    - lib/features/train/repositories/workout_repository.dart (_calculateStreak commitConsume call site — telemetry plumbing only, no semantic change)
  callers_updated_in_this_batch:
    - lib/core/services/sync/sync_restore_completeness.dart (_restoreFreezes max-merge)
    - lib/features/auth/screens/splash_screen.dart (onRestoreComplete listener + cold-start just_used clear)
    - lib/core/services/streak_progress_service.dart (commitRefill, commitConsume, refillIfNewWeek — added telemetry; commitConsume signature extended with optional newlyConsumedDates + walkStartDate)
    - lib/features/train/repositories/workout_repository.dart (pass newlyConsumedDates + walkStartDate into commitConsume)
  callers_unchanged:
    - lib/features/home/providers/home_provider.dart (StreakFreezeNotifier.build clamping intact from f8c1a5)
    - lib/features/home/screens/home_screen.dart (_checkStreakFreezeUsed reader behaviour preserved)
proposed_fix: |
  Belt-and-braces — two independent layers that each individually close
  the race plus defensive cleanup of a related UI flag leak:

  Layer 1 (B0a). sync_restore_completeness._restoreFreezes max-merge.
  Pre-fix did a blind overwrite of streak_freezes_available from the
  cloud row's value, with a conditional overwrite of last_refill only
  if cloud's value was non-null. New behaviour: lexically compare
  cloud's last_refill against local's. If cloud is newer-or-equal,
  cloud wins on both fields. If local is newer (local already refilled
  this week but the fire-and-forget syncFreezes hasn't reached cloud
  yet), keep local + schedule a syncFreezes so cloud catches up. The
  clamp(0, 3) tier-cap from f8c1a5 layer-3 is preserved.

  Layer 2 (B0b). splash._restoreSub listener re-invokes
  StreakProgressService.instance.refillIfNewWeek() inside the existing
  onRestoreComplete handler. Idempotent — if Layer 1 preserved local
  state, last_refill stamp is already >= thisMondayStr and refill
  no-ops. If for any reason the local stamp got reset, this catches it.
  Also invalidate streakFreezeProvider + streakProvider so badge
  updates without manual reload.

  Layer 3 (B3 — defensive). splash._runDeferredInit clears stale
  streak_freeze_just_used Hive flag on cold start (before runRolloverNow).
  The flag's lifecycle is supposed to be "set by commitConsume, read
  + cleared by home_screen._checkStreakFreezeUsed" — purely a UI
  signal. Persisting it across cold starts is a footgun: any session
  that set it without reaching the home read (auth race, crash,
  signOut before snackbar) leaks it forever. The clear is safe because
  any real consume during the new session re-sets it.

  Plus diagnostic telemetry (B1/B2) so the *next* APK install gives us
  three new client_errors events:
    - streak_freeze_refill_check (every refill check, sees willRefill +
      lastRefill values)
    - streak_freeze_refill_done (every successful refill, sees
      before/after counts)
    - streak_freeze_consume_done (every commitConsume, sees which
      date(s) the walk-back newly flagged + walk start)
  This is critical for the secondary investigation: why did the banner
  fire if Mon was logged? Telemetry will reveal the missed_date the
  walk-back disagreed with.
regression_test_planned:
  - test/contracts/streak_freeze_refill_race_test.dart — pins B0a max-merge logic + B0b splash post-restore hook + B3 cold-start clear via source-grep with comment-stripping.
  - test/contracts/streak_freeze_refill_telemetry_test.dart — pins the three new diagnostic event names in StreakProgressService + plumbing of newlyConsumedDates/walkStartDate from WorkoutRepository._calculateStreak.
---
# Body

## Why the +1 silently disappeared

Splash boot order for a signed-in user runs `DayRolloverObserver.runRolloverNow(ref)` from `_runDeferredInit` BEFORE navigation to RestoringScreen. That call invokes `StreakProgressService.refillIfNewWeek()`, which on a fresh Monday correctly bumps local `streak_freezes_available` 0→1, stamps `streak_freezes_last_refill = thisMondayStr`, and schedules `SyncService.syncFreezes()` as fire-and-forget.

Moments later RestoringScreen calls `SyncService.restoreFromCloudForUser()`. The pre-fix `_restoreFreezes` at `sync_restore_completeness.dart:129` then did this:

```dart
existingMap['streak_freezes_available'] = rawAvailable.clamp(0, 3);  // blind overwrite
// ...
if (lastRefill != null) {
  existingMap['streak_freezes_last_refill'] = lastRefill.toString();
}
```

If the fire-and-forget `syncFreezes()` hadn't reached the server by the time `_restoreFreezes` ran (almost always, on a cold-start network), cloud still returned `available=0`. The blind overwrite clobbered the local 1 back to 0. The local `last_refill='2026-05-18'` survived because cloud's value was either null or older, and the pre-fix only overwrote `last_refill` when cloud's value was non-null.

Tuesday open: `refillIfNewWeek` re-checks idempotency at `streak_progress_service.dart:155` and sees `lastRefill >= thisMondayStr` — refill no-ops. The Monday +1 is permanently lost for this week.

## The max-merge fix

`_restoreFreezes` now compares `last_refill` timestamps lexically (YYYY-MM-DD compares correctly as String). Whichever side has the newer stamp wins on BOTH `available` and `last_refill`. If local is newer than cloud (refill landed but hasn't synced), keep local and schedule another `syncFreezes` so cloud catches up.

This is the canonical pattern for any field whose write is monotonic (refill is always +1) but whose cloud propagation is fire-and-forget. The writer/reader timing-drift class — where the cloud read can observe a not-yet-applied local write — is a variant of the existing writer/reader drift class (skill §2.1).

## The defence-in-depth: post-restore refill

Even with Layer 1 closing the race in the common case, Layer 2 catches the edge where local `last_refill` gets reset between splash and restore (e.g. a HiveUserSession force-clear, a userBox restore order quirk). The `splash._restoreSub` listener already invalidates several providers after `onRestoreComplete`; we add `StreakProgressService.instance.refillIfNewWeek()` to the body and invalidate `streakFreezeProvider` + `streakProvider`.

## The session-flag leak (B3)

Separately from the refill race, the founder's banner fired. The `streak_freeze_just_used` flag is a one-shot UI signal but lives in durable Hive. The lifecycle contract is set-then-immediately-cleared-by-home-snackbar; any session that sets it without reaching the home snackbar read (auth race, crash, signOut, navigation away) leaks it forever, surfacing as a spurious banner on next launch.

The cold-start clear is defensive — it scrubs the flag at boot. Any real consume that fires during this session re-sets it. This does NOT fix the underlying question of why a real consume fired today; that's why we shipped B1/B2 telemetry. The next install will give us the `missed_date` the walk-back flagged, and from there we'll know whether it's a true walk-back bug or a stale leak.

## What we will know after the next install

`client_errors` op_type filter on the founder's user_id:
- `streak_freeze_refill_check` will show whether refill ran on next Monday and what `lastRefill` was at gate time.
- `streak_freeze_refill_done` will confirm before/after counts.
- `streak_freeze_consume_done` will reveal `newly=<dateStr>` — the date the walk-back penalised. If that date is in the calendar's visible logged-✓ range, we have a real walk-back bug to chase next batch.
