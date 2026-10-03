---
bug_id: 4a37e7
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase B (P1 writer/reader)
status: shipped
symptom: |
  After a rank promotion, the cloud `user_profile.current_rank_code`
  was updated but the local Hive profile served the OLD rank to all
  rank-reading widgets (Profile / Home / Rank chip / Phase Roadmap)
  until the next `restoreFromCloudForUser` cycle — could be minutes
  to hours. Same writer/reader drift class as OI-36, but the writer
  was on the WRONG side (cloud) and reader on the WRONG side (local).
concept: rank_promotion_local_sync
sot_registry_entry: rank_service_rank_evaluation
writers:
  - { file: lib/core/services/rank_service.dart, method: onStateChanged callback declaration, line: 51 }
  - { file: lib/core/services/rank_service.dart, method: local profile update after cloud write, line: 147 }
  - { file: lib/core/services/rank_service.dart, method: onStateChanged invocation, line: 160 }
  - { file: lib/app.dart, method: RankService.onStateChanged wiring, line: 77 }
readers:
  - { file: lib/core/services/rank_service.dart, method: getCurrentRank (local Hive read), line: 169 }
  - { file: lib/features/profile/screens/profile_screen.dart, method_or_widget: rank chip in service record, line: 496 }
  - { file: lib/features/profile/widgets/rank_chip_full_width.dart, method_or_widget: rank chip widget, line: 30 }
  - { file: lib/features/profile/widgets/service_record_section.dart, method_or_widget: service record widget, line: 33 }
  - { file: lib/features/train/screens/phase_roadmap_screen.dart, method_or_widget: phase roadmap rank display, line: 403 }
  - { file: test/contracts/rank_service_local_profile_update_test.dart, method_or_widget: 4-case contract, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: [syncProfileNow]
restore_methods: [restoreFromCloudForUser]
cloud_table: user_profile
cloud_columns:
  - current_rank_code
  - current_rank_achieved_at
contract_test_path: test/contracts/rank_service_local_profile_update_test.dart
ist_handling: []
provider_invalidations: [userProfileProvider]
telemetry_op_types:
  success: []
  failure: [rank_service_evaluate_and_promote, rank_service_local_profile_update]
cross_account_guard: "userBox is user-scoped via HiveUserSession; userProfileProvider watches authUserIdTokenProvider"
forbidden_patterns_checked:
  - { pattern: "RankService cloud write without local Hive update", absent: true }
  - { pattern: "RankService.onStateChanged unset in app.dart", absent: true }
proposed_fix: |
  Three-part fix mirroring NutritionWriteService.onStateChanged pattern:

  1. **RankService.onStateChanged** — new `static void Function()? onStateChanged;`
     callback declared at line 51.
  2. **Local profile update** — after the cloud `user_profile.update`
     at line 129, call `UserRepository.instance.updateProfileFields({
       'current_rank_code': qualified.code,
       'current_rank_achieved_at': achievedAtIso,
     })`. Stamps the same fields the cloud just received.
  3. **app.dart wiring** — assign `RankService.onStateChanged = () =>
     ref.invalidate(userProfileProvider)` so rank widgets that read
     userProfileProvider rebuild immediately.

  `getCurrentRank()` continues to read from local Hive — that's the
  canonical local SoT. The fix is at the WRITE path, not the read
  path.

  Why missed by today's audit: rank domain not in this batch's
  writer/reader sweep. SoT registry has a rank_service entry but the
  round-trip (cloud write → local read) wasn't explicitly pinned.
regression_test_planned:
  - test/contracts/rank_service_local_profile_update_test.dart
---

# Bug 4a37e7 — RankService cloud write didn't update local profile

closes-oi: OI-37

## Root cause

`RankService.evaluateAndPromote` is fire-and-forget from 2 callers
(splash + train_provider completeWorkout). It correctly upserts to
`rank_promotions` (historical events) and updates the denormalized
`user_profile.current_rank_code` in Supabase. But it stops there.

`RankService.getCurrentRank` reads `UserRepository.instance.getProfile()`
— a local Hive read. The local profile only gets refreshed when
`SyncService.restoreFromCloudForUser` runs, which happens on:
- App launch (splash)
- Manual user-triggered "refresh" actions (none currently)
- Day rollover (limited fields)

So a user who promotes from PO3 → SubLt by completing a workout in-app
saw "PO3" on Profile / Home / Rank chip for the rest of their session.
Refreshing fixed it (next launch pulls fresh user_profile). Reproduces
100% post-promotion until the user kills the app.

## Fix

Mirrors NutritionWriteService's `onStateChanged` pattern (Test #12.4 /
Task #3) for the same reasons:

- Service lives in `lib/core/services/` and can't hold a WidgetRef.
- Static `Function()?` callback is the cleanest way to bridge to
  Riverpod without coupling.
- app.dart's `MyAppState` holds the container and assigns the callback
  once at mount.

After the cloud update succeeds at line 129, the function now:

```dart
await UserRepository.instance.updateProfileFields({
  'current_rank_code': qualified.code,
  'current_rank_achieved_at': achievedAtIso,
});
onStateChanged?.call();
```

The local update is wrapped in try/catch so a local-Hive failure
(unlikely — userBox is open + writable here) doesn't drop us into the
outer catch and lose the successful cloud write. Telemetry logged on
failure.

## Why getCurrentRank stayed reading from local Hive

`getCurrentRank()` is called on every Profile / Home rebuild, including
on cold-start before any cloud round-trip is possible. Reading from
local Hive is the right call — it's the canonical READ source. The
fix is to make sure the local Hive value is FRESH after every promotion,
not to change where the reader looks.

## Verification

```
$ flutter test test/contracts/rank_service_local_profile_update_test.dart
All tests passed! (4 cases)
```

The 4 cases pin: (1) onStateChanged declared; (2) UserRepository.updateProfileFields
called with current_rank_code + current_rank_achieved_at; (3)
onStateChanged?.call() fires after local write; (4) app.dart wires the
callback to ref.invalidate(userProfileProvider).

## Related

- Test #12.4 / Task #3 — NutritionWriteService.onStateChanged pattern (the parent of this fix)
- `feedback_writer_reader_field_drift_recurring.md` — same class as the 10 prior instances
- `docs/audit/LENS_REGISTRY.md` — L1 writer/reader drift
- Note: same fix shape applies to any service that writes to user_profile remotely + has readers consuming the local Hive cache. Future similar services should adopt the onStateChanged pattern as the third leg of writer-discipline.
