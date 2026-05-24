---
bug_id: b4a09c
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 0 / unblock)
status: shipped
symptom: |
  Pre-commit hook fails with 4 undefined-method errors blocking all
  commits on main since 2026-05-21:
  - `test/ai_coach/meals_today_snapshot_test.dart:68,108,128` calls
    `AiCoachRepository.mealsTodayForTest()` — method gone.
  - `test/ai_coach/nutrition_trend_7d_snapshot_test.dart:80` calls
    `AiCoachRepository.nutritionTrend7dForTest()` — method gone.
  Root cause: A10 audit-2026-05-20 refactor (commit d6e472c) extracted
  snapshot logic from `AiCoachRepository` (2127 → 302 lines) into
  `AiSnapshotBuilder` (1317 LOC). The refactor forwarded production
  APIs (buildAiContext, enrichContextForQuery) and one back-compat
  dedup shim (findRecentDuplicateMessageKey at line 100) but missed
  these two `@visibleForTesting` seams. Tests have been broken since
  commit landed.
concept: ai_snapshot_building
sot_registry_entry: ai_snapshot_building
writers:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: mealsTodayForTest (existing visibleForTesting seam), line: 303 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: nutritionTrend7dForTest (existing visibleForTesting seam), line: 307 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: new mealsTodayForTest forwarder + new nutritionTrend7dForTest forwarder, line: 138 }
readers:
  - { file: test/ai_coach/meals_today_snapshot_test.dart, method_or_widget: 3 calls to AiCoachRepository.instance.mealsTodayForTest(), line: 68 }
  - { file: test/ai_coach/nutrition_trend_7d_snapshot_test.dart, method_or_widget: 1 call to AiCoachRepository.instance.nutritionTrend7dForTest(), line: 80 }
hive_key_prefix: "n/a — pure forwarder shim addition"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/ai_coach/meals_today_snapshot_test.dart
ist_handling:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 308, source: existing IST date math in _getMealsToday + _getNutritionTrend7d unchanged }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: AiSnapshotBuilder.instance touches Hive via the per-singleton _hive reference (HiveService.instance); the @visibleForTesting methods reach the same boxes the production buildAiContext path uses.
forbidden_patterns_checked:
  - "Dropping back-compat shims silently during refactor — when extracting a class, every public + visibleForTesting member of the original must either move with the call sites OR have a forwarder shim on the old surface."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ai_coach_repository.dart gains 2 forwarder methods at line 138" }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "running test/ai_coach/meals_today_snapshot_test.dart + nutrition_trend_7d_snapshot_test.dart green after the shim lands" }
impact_analysis:
  callers_audited:
    - test/ai_coach/meals_today_snapshot_test.dart (3 callsites)
    - test/ai_coach/nutrition_trend_7d_snapshot_test.dart (1 callsite)
  callers_updated_in_this_batch:
    - lib/features/ai_coach/repositories/ai_coach_repository.dart (added 2 forwarders)
  callers_unchanged:
    - tests are byte-identical; they call the same method names through the shim, which delegates to AiSnapshotBuilder
proposed_fix: |
  Add two @visibleForTesting forwarder methods on AiCoachRepository
  that delegate to AiSnapshotBuilder.instance. Same pattern the A10
  refactor used for buildAiContext + the dedup shim at line 100.
  4-line fix. Tests need zero changes. Pre-commit hook unblocked.
regression_test_planned:
  - test/ai_coach/meals_today_snapshot_test.dart (existing, was failing — passes after shim)
  - test/ai_coach/nutrition_trend_7d_snapshot_test.dart (existing, was failing — passes after shim)
---
# Body

## Why this needed its own commit

The Theme A (Hive-session-init race) commit was blocked by these
pre-existing failures. Per CLAUDE.md rule 20 (no deferred test
failures on main), all 12 planned commits in the obs 5-12 batch would
be blocked too. Fix landed FIRST so the rest can ship.

## Why minimal — 4 lines vs. updating tests

The tests assert on real snapshot behaviour (meal grouping, 7-day
trend math) that still lives in `AiSnapshotBuilder._getMealsToday` /
`_getNutritionTrend7d`. The visible-for-test seams remain on the
new class. The repository is documented as a "shim" that forwards to
the new builder (commit d6e472c). Adding the two missing forwarders
preserves the shim contract without spreading direct
`AiSnapshotBuilder` imports into the test files.

## Self-evolution note

The `writer-reader-drift-detector` skill (added 2026-05-21) catches a
related but distinct class. This bug is **shim-extraction omission**:
when refactoring class X → X + Y, every visible member of X must
either move with its callers or have a forwarder. Add to skill's
red-flag list: "after class-extraction refactor, grep every public +
@visibleForTesting member of the original class against the new
public API + the shim — anything that isn't on either side is broken
callers waiting to surface."
