# PR AI — Stepped Onboarding Field Coverage

**Date:** 2026-04-20
**Branch:** `feat/pr-ai-onboarding-fields` → main
**Merge commit:** `bdbd2f2`
**Main tip before:** `4aaf704`
**Main tip after:** `bdbd2f2`
**Sub-PRs:** 3

---

## 1. Why

The Wardroom stepped onboarding flow shipped with 4 screens (Welcome → Goal → Stats → Plan), covering only 6 of the profile's 13 fields. The remaining 7 were either **inferred via switch expressions** on `activity_level` + `goal` or **hardcoded defaults**. Net effect: two users with identical goal + activity answers produced identical plans regardless of actual equipment, experience, or schedule. PR AI closes this by adding one new screen and wiring two defaults.

## 2. What shipped

| Sub-PR | Commit | Summary |
|---|---|---|
| AI.1 | `284f027` | Stats screen adds a 5th `_StatField` tile labelled `TARGET` (kg, gold-highlighted). Pre-fills with the goal-derived delta plan_screen was previously computing silently. Progress `02 · 03 → 02 · 04`. Routes to `/onboarding/details` instead of `/onboarding/plan`. |
| AI.2 | `65ae007` | New `/onboarding/details` screen (`03 · 04`) — 4 `WardRadioRow` sections stacked vertically in a `SingleChildScrollView`: EXPERIENCE (3) · PACE (3) · DAYS PER WEEK (4) · EQUIPMENT (4). Defaults pre-select old inferred values. Goal meter `01 · 03 → 01 · 04`, Plan meter `03 · 03 → 04 · 04`. Router registers `/onboarding/details` + imports `DetailsScreen`. |
| AI.3 | `b9c7d0c` | `plan_screen._onReportForDuty` reads real values from `widget.data` for `fitness_experience`, `pace_preference`, `days_per_week`, `equipment_access`, `target_weight_kg`. Inference kept as fallback only (legacy chat users / deep-links). `diet_preference` default `'balanced' → 'veg'`. `injuries` default `[] → ['none']`. |

**Files touched:** 5 (1 new). +547 / −63 lines.

---

## 3. Current flow

```
Welcome     (unnumbered)  → CTA only
Goal        01 · 04       → primary_goal
Stats       02 · 04       → sex, weight_kg, target_weight_kg (NEW),
                            height_cm, age, body_fat_pct,
                            activity_level
Details     03 · 04       → fitness_experience, pace_preference,
                            days_per_week, equipment_access
Plan        04 · 04       → REPORT FOR DUTY — consumes real values,
                            falls back to inference only when absent
```

## 4. What stays defaulted

| Field | Default | Source |
|---|---|---|
| `lifestyle_activity` | Inferred from `activity_level` | 1:1 mapping in `plan_screen`. |
| `diet_preference` | `'veg'` (was `'balanced'`) | Indian-first default per user decision. |
| `injuries` | `['none']` (was `[]`) | Matches `edit_profile_screen._injuries` convention. |
| `start_date` | `'this_monday'` | Unchanged from legacy flow. |

Users override diet / injuries via Profile → Edit Profile (already wired at lines 1505–1506).

## 5. Business-logic preservation

Untouched:
- `OnboardingNotifier.completeOnboarding` pipeline + `_syncOnboardingToSupabase` column filter.
- `UserRepository.saveProfile` + `updateProfileFields`.
- `BmrCalculator.calculateTargets` contract.
- `WorkoutScheduleService.generateAndSchedule`.
- `plan_generator` + `plan_engine/*` (CLAUDE rule #14).
- All Edge Function contracts.
- Fire-and-forget sync rules.

Pipeline gets better inputs, not new plumbing.

## 6. Verification

- `flutter analyze` on merged main: 4 issues — all pre-existing baseline warnings (`test/plan_engine_v3_test.dart`, `test/plan_generator/v4_diagnostic/*.dart`). **Zero new issues from PR AI.**
- On-device smoke test: **deferred by user** — merge proceeded without APK validation. Re-run against current main when desired.

## 7. What's deferred (PR AJ)

- `/onboarding/chat` retirement + deletion of `onboarding_chat_screen.dart`. Legacy path stays reachable as rollback until AI is validated end-to-end.

## 8. One-liner for changelogs

> PR AI closes the stepped-onboarding field-coverage gap: Stats gains a target-weight tile; a new Details screen captures fitness_experience, pace_preference, days_per_week, and equipment_access; plan_screen stops inferring when real values are present. Defaults tightened: diet `'balanced' → 'veg'`, injuries `[] → ['none']`. Merge `bdbd2f2`, 3 sub-PRs, zero new `flutter analyze` issues.
