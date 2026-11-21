---
bug_id: f8c1a5
date: 2026-05-18
batch: APK Test #16.2 observations (2026-05-18)
status: shipped
symptom: |
  On Monday 2026-05-18 IST, the Daily letterhead streak chip rendered
  "4 DAYS / 8/3" where the freeze badge shows 8 available against a
  maximum of 3 (PRO tier cap). User reported the Monday weekly refill
  did not run and asked what the rule is. The "8/3" state is impossible
  via any in-app write path because StreakProgressService.commitRefill
  clamps available at maxFreezes, but the value persisted in Hive
  (streak_freezes_available) is 8. The Monday refill is gated out by
  the idempotency check because streak_freezes_last_refill is already
  set to a Monday at or after this Monday.
concept: streak_freeze_value_clamp_on_read
sot_registry_entry: streaks
writers:
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.commitRefill (clamps on write), line: 58 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.commitConsume (no clamp; trusts caller), line: 91 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.refillIfNewWeek (idempotency gate), line: 115 }
  - { file: lib/core/services/sync/sync_health.dart, method_or_widget: cloud restore path may write unclamped value into Hive, line: 1 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier.build (no clamp on read), line: 267 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: streakFreezeMaxProvider, line: 277 }
  - { file: lib/features/home/widgets/streak_badge.dart, method_or_widget: StreakBadge format string available/max, line: 1 }
hive_key_prefix: "user_progress (Hive map under userBox)"
hive_key_formula: "userBox['progress'] map keys streak_freezes_available, streak_freeze_used_dates, streak_freezes_last_refill"
sync_methods: [syncFreezes]
restore_methods: [restoreFromCloudForUser]
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freeze_used_dates, streak_freezes_last_refill, streak_progress_version]
contract_test_path: test/contracts/streak_freeze_value_clamped_on_read_test.dart
ist_handling:
  - { file: lib/core/services/streak_progress_service.dart, line: 116, source: mondayOfIst correctly used for refill boundary }
  - { file: lib/core/services/streak_progress_service.dart, line: 122, source: thisMondayStr formatted via padded year/month/day from IST date }
provider_invalidations: [streakFreezeProvider, streakFreezeMaxProvider]
telemetry_op_types:
  success: [streak_freeze_one_shot_clamp_applied]
  failure: [streak_freeze_value_above_max]
cross_account_guard: StreakFreezeNotifier.build watches authUserIdTokenProvider at line 265.
forbidden_patterns_checked:
  - "Reading streak_freezes_available without clamping against the tier cap from streakFreezeMaxProvider / SubscriptionService.isPro()"
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "StreakFreezeNotifier.build clamps available against tier cap on read" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "one-shot migrator clamps userBox['progress']['streak_freezes_available'] and clears last_refill" }
  - { tier: 5, name: cloud_sync_outbound, status: verified, evidence: "syncFreezes path writes clamped value going forward" }
  - { tier: 6, name: cloud_sync_restore, status: verified, evidence: "restoreFromCloudForUser surface clamped on read by Tier 1 fix; cloud column unchanged" }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "streakFreezeProvider / streakFreezeMaxProvider invalidation list unchanged" }
  - { tier: 11, name: ist_correctness, status: verified, evidence: "mondayOfIst boundary preserved at streak_progress_service.dart:116" }
impact_analysis:
  callers_audited:
    - lib/features/home/providers/home_provider.dart (StreakFreezeNotifier.build)
    - lib/features/home/providers/home_provider.dart (streakFreezeMaxProvider)
    - lib/core/services/streak_progress_service.dart (commitRefill, commitConsume, refillIfNewWeek)
    - lib/core/services/sync/sync_health.dart (cloud restore writer)
  callers_updated_in_this_batch:
    - lib/features/home/providers/home_provider.dart (StreakFreezeNotifier.build clamps on read)
    - lib/core/services/<streak_freeze_migrator>.dart (new one-shot Hive repair)
  callers_unchanged:
    - lib/core/services/streak_progress_service.dart (commitRefill already clamps on write)
proposed_fix: |
  Four-layer defense (each independently valuable):

  1. Clamp on read in StreakFreezeNotifier.build at
     home_provider.dart:267:
     return ((progress?['streak_freezes_available'] as int?) ?? 1)
       .clamp(0, SubscriptionService.instance.isPro() ? 3 : 1);
     This makes the display correct immediately for the founder's
     existing corrupted state.

  2. One-shot Hive repair in HiveService.init (or a dedicated migrator
     under lib/core/services/<name>_migrator.dart) that runs once per
     install: if userBox['progress']['streak_freezes_available'] >
     maxFreezesForCurrentTier, force-set to max AND clear
     streak_freezes_last_refill so the next Monday refill runs cleanly.
     Gate via a userBox flag so it runs at most once.

  3. Cloud-side clamp in sync_service._restoreFreezes (or wherever the
     restore writer materialises the Hive map): apply the same
     min(value, max) before put.

  4. Server-side: migration adding CHECK constraint
     streak_freezes_available BETWEEN 0 AND 3 on user_progress, plus a
     one-shot UPDATE to cap existing rows. This is the durable fix;
     #1-#3 are the client-side defense in depth.

  Rule for founder's "what is the rule?" question:
  - Freeze cap: 1 for free, 3 for PRO. Tracked by streakFreezeMaxProvider
    at home_provider.dart:277.
  - Refill: +1 per IST Monday, clamped at cap. Triggered from
    DayRolloverObserver._doRolloverWithRef (every rollover, idempotent)
    and splash post-restore (first launch).
  - Consume: 1 per missed day, in WorkoutRepository.calculateCurrentStreak.
  - Display: streakFreezesAvailable/streakFreezesMax, e.g. "1/1" free,
    "3/3" PRO at full bank.
regression_test_planned:
  - test/contracts/streak_freeze_value_clamped_on_read_test.dart — pin StreakFreezeNotifier.build to return min(stored, max) for any pre-existing corrupted value.
  - test/migrations/streak_freeze_one_shot_clamp_test.dart — pin the one-shot migrator: writes 8 to streak_freezes_available, expects 3 after init (PRO) or 1 (free), and streak_freezes_last_refill cleared.
  - test/contracts/streak_freeze_restore_clamps_test.dart — pin sync_service restore path: cloud row with available=8 must land in Hive as available=3.
---
# Body

## What "8/3" means and why it cannot happen in a clean install

"8/3" is the format string `${available}/${max}` rendered by
`StreakBadge`. The display layer reads `streak_freezes_available` from
the Hive `user_progress` map and `streakFreezeMaxProvider` from
`home_provider.dart:277` which returns 3 for PRO, 1 for free.

`StreakProgressService.commitRefill` at line 58-77 clamps on write:
`(currentAvailable + 1).clamp(0, maxFreezes)`. So no in-app refill can
produce a value above the cap. Yet the founder shipped a state of 8.

The only paths that can produce >max:

1. Pre-CQRS (pre-2026-05-11 commit `1fca892` + `88e55af`) where refill
   was inline inside the notifier's `build()`. If a legacy version did
   not clamp, those writes persisted and were synced to cloud. We have
   no evidence the pre-CQRS code skipped the clamp, but it is the only
   in-app suspect.

2. Cloud restore path (`SyncService._restoreFreezes`) that reads
   `user_progress.streak_freezes_available` from cloud and puts it into
   Hive unchecked. If cloud has a corrupt 8 (from any of: legacy code,
   direct SQL admin, or a bad migration backfill), restore lays it down
   on every fresh install.

3. Direct SQL write (impossible for end users, plausible for an admin
   touch we don't remember doing).

## Why Monday refill did not fire

`StreakProgressService.refillIfNewWeek` at line 115-131 short-circuits
at line 124-126 when `lastRefill.compareTo(thisMondayStr) >= 0` — the
idempotency guard. If `streak_freezes_last_refill` is already set to a
date at or after this Monday (e.g. cloud restore brought along a
`last_refill = 2026-05-18` from a different device that already
refilled), no refill happens — by design.

This is a feature, not a bug, except when combined with a corrupted
`streak_freezes_available` value: the refill gate keeps the corrupted
state stuck because refill would have re-clamped it through `commitRefill`.

## Why the read-side clamp is the right primary fix

The founder needs an immediate UX correction. A read-side clamp at
`home_provider.dart:267` makes the display always honest about the
tier cap, regardless of corrupted underlying state. The other three
layers (one-shot Hive repair, restore clamp, server CHECK constraint)
prevent recurrence and decay-prevention but the founder will see "3/3"
on next launch without waiting for any backfill.

We deliberately do NOT silently destroy the founder's stored 8. The
one-shot Hive repair will normalize on next init, with a debugPrint
log so we can trace if needed. No data is lost beyond a flag that was
never legitimately 8.
