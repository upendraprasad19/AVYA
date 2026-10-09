---
bug_id: 2026-05-16-referral-restore-completeness
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.10
status: in_progress
symptom: |
  Founder reported during APK Test #2 (2026-04-25) generated a
  referral code via Profile -> Invite Friends. Two weeks later, on a
  fresh reinstall (sumitt@gmail.com cross-device login flow), the
  Invite Friends sheet showed loading then generated a BRAND NEW
  code with a fresh 7-day window. The original code's expiry timer
  effectively reset, and any audit history of who redeemed it (the
  founder's test redemptions during APK #2) was invisible from the
  device.

  Verified live (audit 2026-05-16 findings-agent-4.md F5-S3): the
  `referral_codes` table HAS the user's row (cloud-side persistence
  works — `_generateNewCode` upserts directly) and
  `referral_redemptions` has audit rows for past redemptions, but
  the restore path (`SyncService.restoreFromCloudForUser`) did not
  pull either table back into Hive. Cross-device sign-in left both
  surfaces blank locally.
concept: referral_restore_completeness
sot_registry_entry: referral_codes_hive_cache
writers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: _generateNewCode, line: 121 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method_or_widget: _restoreReferralCodes, line: 303 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method_or_widget: _restoreReferralRedemptions, line: 350 }
readers:
  - { file: lib/features/profile/screens/invite_friends_sheet.dart, method_or_widget: _load, line: 63 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: getOrCreateReferralCode, line: 84 }
hive_key_prefix: referral_
hive_key_formula: "userBox['referral_code'] = {code, expires_at, created_at}; userBox['referral_redemption_history'] = List<Map>"
sync_methods:
  - SupabaseService._generateNewCode (cloud-direct upsert; no Hive sync method — codes are generated server-first)
restore_methods:
  - SyncService._restoreReferralCodes
  - SyncService._restoreReferralRedemptions
cloud_table: referral_codes, referral_redemptions
cloud_columns:
  - referral_codes.code
  - referral_codes.expires_at
  - referral_codes.created_at
  - referral_codes.user_id
  - referral_redemptions.code
  - referral_redemptions.referrer_id
  - referral_redemptions.referee_id
  - referral_redemptions.days_granted_each
  - referral_redemptions.created_at
contract_test_path: test/contracts/restore_completeness_writes_test.dart
ist_handling:
  - { file: lib/core/services/sync/sync_restore_completeness.dart, line: 308, fn: DateTime.now().toUtc().toIso8601String }
provider_invalidations:
  - none (InviteFriendsSheet is a stateful widget that calls SupabaseService directly on _load; no Riverpod provider depends on userBox['referral_code'])
telemetry_op_types:
  success: []
  failure:
    - restore_referral_codes
    - restore_referral_redemptions
cross_account_guard: |
  `restoreFromCloudForUser` runs inside `HiveUserSession.openForUser`
  (verified at sync_service.dart:807). The two new restore methods
  write only to `_hive.userBox` which is namespaced per-owner since
  Test #15.1. No additional guard needed.
forbidden_patterns_checked:
  - { pattern: "Hive.box(", absent: true }
  - { pattern: "await getOrCreateReferralCode", absent: false }
proposed_fix: |
  Two new restore methods added to
  `lib/core/services/sync/sync_restore_completeness.dart`:

  1. `_restoreReferralCodes(String userId)` — SELECTs the most
     recent non-expired row from `referral_codes` and stashes
     `{code, expires_at, created_at}` into `userBox['referral_code']`.
     UI reader `InviteFriendsSheet._load` already calls
     `SupabaseService.getOrCreateReferralCode()` which falls back to
     cloud, but the Hive stash makes the data visible offline and
     unblocks any future widget that wants synchronous access.

  2. `_restoreReferralRedemptions(String userId)` — SELECTs up to 50
     rows from `referral_redemptions` where the user is EITHER
     `referrer_id` OR `referee_id` (PostgREST `.or()` builder) and
     stashes them as a List<Map> into
     `userBox['referral_redemption_history']` for audit display.

  Both methods follow the established `_restoreXxx` shape:
  per-method try/catch, telemetry via `ErrorTelemetry.recordNonFatal`
  + `_reportSyncFailure(opType: 'restore_referral_{codes,redemptions}')`.

  Wired into `SyncService.restoreFromCloudForUser` (Step C —
  restore-completeness surfaces) at sync_service.dart:887 and :890,
  each wrapped in `_safeRestoreOp(...)` with a `_restoreCancelled`
  check before each call so the user can abort restore mid-way
  without leaving Hive in a partial state.

  FK quirk handled by NOT doing any join — both methods filter by
  `user_id` / `referee_id` / `referrer_id` via `.eq()` or `.or()`,
  so the `referral_codes -> auth.users` vs
  `referral_redemptions -> public.users` mismatch (documented in
  CLAUDE.md §7 "FK direction quirk") is irrelevant to the SELECT path.
regression_test_planned:
  - test/contracts/restore_completeness_writes_test.dart (two new test cases — method-presence + _safeRestoreOp wiring)
---

# E.10 — Referral surfaces restore-completeness

`closes-diagnose: 2026-05-16-referral-restore-completeness`

## Symptom

Founder's referral code generated during APK Test #2 (2026-04-25)
and the redemption audit rows for that code were invisible after
cross-device reinstall. Profile -> Invite Friends loaded a brand
new code, effectively resetting the 7-day expiry window the founder
had already shared with friends.

## Root cause

`SyncService.restoreFromCloudForUser` covered 5 restore-completeness
surfaces (freezes, notifications_inbox, saved_diet_plan,
rank_promotions, coach_memory) but the 2 referral surfaces were not
in the contract. The cloud rows survived (writes go through
`SupabaseService._generateNewCode` which upserts directly), but the
local Hive cache was never populated on a fresh device.

This is the same restore-completeness contract gap closed by APK
Test #11 / Theme A for freezes / inbox / diet plan — the contract
covers "every Hive-only surface paying users would lose on
reinstall." The referral surfaces were missed because they DON'T
write to Hive on the local side (cloud-first generation), but the
READ path on a fresh install benefits from a local stash so the UI
can render before the network round-trip completes.

## Fix

Added two new private restore methods to
`lib/core/services/sync/sync_restore_completeness.dart` and wired
both into `restoreFromCloudForUser` in `sync_service.dart`
immediately after `_restoreRankPromotions`, before the subscription
refresh step. Each is wrapped in `_safeRestoreOp` and gated by
`_restoreCancelled` so a mid-restore cancellation is handled
cleanly.

## Verification

- `flutter test test/contracts/restore_completeness_writes_test.dart` — 9/9 passing (2 new tests added).
- `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-16-referral-restore-completeness.md` — passes.

## Follow-ups

- Future work could add `referral_code_provider` (Riverpod) reading
  from `userBox['referral_code']` so widgets get reactive updates,
  but the current `InviteFriendsSheet` stateful widget is the only
  consumer and it already refetches on every open. Out of scope.
- `referral_redemption_history` is not yet wired into any UI — the
  data is now available in Hive for the next batch that adds an
  audit list under Invite Friends.
