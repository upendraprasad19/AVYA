---
bug_id: 2c1c0d
date: 2026-05-16
batch: audit-2026-05-16 reader-side / R7 (post-+27 install observation)
status: fixed
symptom: |
  Profile prediction card showed "Complete onboarding to get your
  personalised fitness prediction" for an already-onboarded user
  (founder, APK +27 fresh install). Goal/weight/phase were all
  populated; only the `prediction_text` Hive value was missing because
  it was never generated or restored on this account.
concept: prediction_card_display
sot_registry_entry: prediction_card_display
writers:
  - { file: lib/core/services/prediction_service.dart, method: buildPrediction, line: 31 }
readers:
  - { file: lib/features/ai_coach/widgets/prediction_card.dart, method: PredictionCard.build, line: 93 }
  - { file: lib/features/profile/screens/profile_screen.dart, method: _buildPredictionCard, line: 1388 }
hive_key_prefix: "(MigratedKey 'prediction_text' + 'prediction_generated_at')"
hive_key_formula: "'prediction_text' / 'prediction_generated_at' (singleton, no per-row suffix)"
sync_methods: []
restore_methods: []
cloud_table: ""
cloud_columns: []
contract_test_path: test/contracts/prediction_card_onboarding_copy_test.dart
ist_handling: []
provider_invalidations: [predictionProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "MigratedKey reads route through userBox once a session is open — user-scoped after Test #11.1 UserConfigMigrator v2"
forbidden_patterns_checked:
  - { pattern: "Complete onboarding to get your personalised fitness prediction", absent_outside_canonical: true }
proposed_fix: |
  Card now accepts an `onboardingCompleted` boolean param. Empty-state
  copy branches:
    - !onboarded -> "Complete onboarding to get your personalised
      fitness prediction." (unchanged for genuinely new users)
    - onboarded  -> "Your forecast is queued. Tap UPDATE to generate
      it now." (new copy for onboarded users with no prediction yet)
  Onboarded-empty state also surfaces an UPDATE CTA so the user can
  trigger first-time generation. Per CLAUDE.md section 14, the first
  prediction is free for all users.
  Caller (profile_screen._buildPredictionCard) reads
  `userProfileProvider['onboarding_completed_at']` and passes it
  through. The CTA is enabled when `!hasPrediction && onboarded`.
regression_test_planned:
  - test/contracts/prediction_card_onboarding_copy_test.dart
---
# Body

## Symptom

Profile screen FORECAST card displayed "Complete onboarding to get
your personalised fitness prediction." for a fully-onboarded user.
All other onboarding-gated affordances on the same screen (goal card,
phase plan, body stats) rendered correctly. Only the prediction card
showed the misleading copy.

## Root cause

`PredictionCard` at `lib/features/ai_coach/widgets/prediction_card.dart`
lines 67 and 92-99 gated empty-state copy on `predictionText.isEmpty`
alone:

```dart
if (hasPrediction) ...[ ... ]
else
  Text('Complete onboarding to get your personalised fitness prediction.', ...)
```

`predictionText` and `onboarded` are independent signals. The card
conflated "no prediction text" with "no onboarding" and showed the
onboarding-prompt copy in both cases. For a fresh install on a
returning account, `prediction_text` is not restored from cloud (it
lives only in Hive `coachBox`), so the field is null even when the
cloud `user_profile` row has `onboarding_completed_at` populated.

This is a 7th instance of the audit's reader-side enumeration gap —
the prediction card was not in the registry's `prediction` concept
reader list (the registry only listed `predictionProvider` writer).

## Fix

Card accepts `onboardingCompleted` param. Branches placeholder copy +
surfaces an UPDATE CTA for the onboarded-empty case. Caller reads
canonical Hive `userProfileProvider['onboarding_completed_at']`.

## Regression test

`test/contracts/prediction_card_onboarding_copy_test.dart` — 4 widget
tests:
- non-onboarded user sees "Complete onboarding" copy (unchanged)
- onboarded + no prediction sees "queued / tap UPDATE" copy
- onboarded + no prediction sees UPDATE CTA + tap fires callback
- onboarded + has prediction sees full action row (no empty-state CTA)
