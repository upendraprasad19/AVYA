# Agent 1 Findings — Clusters 1, 2, 14 (Naming · SoT parity · Dead schema)

**Date:** 2026-05-16 · **Word count:** 1480

## Cluster 1 — Naming & directory hygiene

### F1-N1: Feature-name collision — dual submissions surfaces — NEEDS_DECISION
- **Evidence:** `lib/features/profile/screens/submissions_screen.dart` (unified) vs `lib/features/profile/screens/my_submissions_screen.dart` (legacy). Both use "submissions" domain.
- **Why:** Two files, one concept, unclear which is canonical. Tabbed unified screen makes the standalone legacy obsolete.
- **Remediation:** Confirm `MySubmissionsScreen` is dead → delete it. CLAUDE.md §5 already documents intent to retire after one release cycle.

### F1-N2: Deprecated legacy widgets still in active use — NEEDS_DECISION
- **Evidence:** `lib/shared/widgets/wardroom/rank_chip.dart:21` and `rank_insignia.dart` marked "scheduled for rename"; 5+ live callsites: `profile_screen.dart`, `profile_identity.dart`, `rank_chip_full_width.dart`, `train_screen.dart`, `phase_roadmap_screen.dart`.
- **Why:** Audit expects them unused per CLAUDE.md §9 "Legacy (slated for removal)" section. They're not.
- **Remediation:** (a) Migrate callsites to `WardRankPill` / `WardRankInsignia` + delete legacy, OR (b) drop "slated for removal" claim from CLAUDE.md §9.

### F1-N3: Directory structure baseline — PASS
- All directories present; 81 migrations verified. No drift.

## Cluster 2 — SoT registry parity

### F2-R1: SoT registry completeness — PASS
- 36 concepts in registry; 36 `regression_test` entries. Full parity (Phase C will re-verify CLAUDE.md §15 cross-reference).

### F2-R2: 🚨 CRITICAL — Unregistered writer: sleep_logs direct Hive write bypasses any WriteService — CONFIRMED_BUG
- **Evidence:** `lib/features/profile/providers/profile_provider.dart:498` — `BiometricNotifier.logSleep()` writes `healthBox.put('sleep_log_$todayStr', {...})` directly. No `HealthWriteService` exists. Registry has zero entry for this writer (only `_syncSleepLogs` + `_restoreSleepLogs` sync paths).
- **Why:** Same drift class as Tests #8/#12/#16 — unregistered writer with no contract test pinning fields. Linked to F14-D2: `sleep_logs` cloud table has 0 rows.
- **Remediation:** (a) Create `HealthWriteService` singleton, route `logSleep` + `logWeight` + `logMeasurement` through it, OR (b) explicitly document this as exempt in CLAUDE.md §15 + add the manual write to SoT registry + add field-contract test.

### F2-R3: Framework asymmetry — only Workout & Nutrition have WriteServices — FRAMEWORK_GAP
- **Evidence:** 2 WriteServices total. Health domain writes (weight, water, sleep, measurements, steps) happen in notifiers/providers directly.
- **Why:** Architectural asymmetry. Same drift surface as Workout/Nutrition pre-#6, undocumented.
- **Remediation:** Document the decision in CLAUDE.md §15 — either intentional or future refactor. Prevents re-flagging.

## Cluster 14 — Dead schema / dead code

### F14-D1: `featureActiveWorkoutMode` constant — DEAD_SCHEMA_CANDIDATE
- **Evidence:** `lib/core/constants/app_constants.dart:8`, marked `@Deprecated` (Q6 retirement); 0 `.gate('feature_active_workout_mode', ...)` callsites.
- **Remediation:** Delete the constant; update FeatureGates enum comment.

### F14-D2: 🚨 CRITICAL — 8 zero-row cloud tables = sync broken — CONFIRMED_BUG
- **Evidence:** Phase A snapshot RED FLAGS:
  1. `body_measurements` — Hive writes, sync method likely broken
  2. `promo_code_uses` — 3 codes exist; no redemption ever synced
  3. `referral_codes` — founder seeded; sync broken
  4. `saved_diet_plans` — `_syncSavedDietPlan` exists per SoT registry; 0 cloud rows
  5. `sleep_logs` — `_syncSleepLogs` exists; 0 cloud rows (linked to F2-R2)
  6. `user_custom_foods` — `_syncCustomFoods` exists; 0 cloud rows
  7. `user_saved_meals` — `_syncSavedMeals` exists; 0 cloud rows
  8. `referral_redemptions` — paired with referral_codes
- **Why:** Same writer/reader drift class as Tests #11/#12/#16. Sync methods exist but evidently not firing OR failing silently OR RLS/FK rejecting.
- **Remediation:** Agent 4 owns root-cause investigation per cluster 5 atomic checks.

### F14-D3: `UserRepository.softDeleteAccount` — DEAD_SCHEMA_CANDIDATE
- **Evidence:** Method exists; 0 callsites (hard-delete via `delete-account` Edge Function is canonical per Test #11 H1).
- **Remediation:** Delete method.

### F14-D4: Legacy widgets verdict — NOT DEAD — NEEDS_DECISION
- See F1-N2 — actively used despite "scheduled for removal" status.

## Linked-findings summary

| Finding | ID | Severity | Linked |
|---|---|---|---|
| Submissions collision | F1-N1 | NEEDS_DECISION | — |
| Legacy widget naming | F1-N2 | NEEDS_DECISION | F14-D4 |
| **sleep_logs unregistered writer** | **F2-R2** | **CONFIRMED_BUG** | **F14-D2** |
| Health WriteService asymmetry | F2-R3 | FRAMEWORK_GAP | F2-R2 |
| Active-workout feature constant | F14-D1 | DEAD_SCHEMA_CANDIDATE | — |
| **8-table sync broken** | **F14-D2** | **CONFIRMED_BUG** | **F2-R2** |
| Dead `softDeleteAccount` | F14-D3 | DEAD_SCHEMA_CANDIDATE | — |
| Legacy rank widgets in use | F14-D4 | NEEDS_DECISION | F1-N2 |

**Highest-value:** F2-R2 + F14-D2 are linked. Same recurring bug class as Tests #8–#16.
