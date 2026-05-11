---
bug_id: 7ad0d4
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 3 deterministic-key helpers (`_nlogKeyForRestore` in sync_service, `exlogKey` in workout_write_service, `_stableItemsHash` in nutrition_write_service) computed their 8-char tag via `String.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0')`. Dart's `String.hashCode` is NOT guaranteed stable across VM versions / isolates / platforms — cross-device round-trip (cloud → Hive on restore, or sync between devices) could produce different tags for the same logical tuple → duplicate Hive rows for what should be one row.
concept: deterministic_uuid_v5_keys
sot_registry_entry: hive_key_deterministic_hash
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _nlogKeyForRestore, line: 127 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: exlogKey, line: 781 }
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: _stableItemsHash, line: 651 }
readers:
  - { file: lib/core/services/exlog_key_migrator.dart, method_or_widget: runIfNeeded (v7 flag bump), line: 22 }
  - { file: lib/core/services/nlog_key_migrator.dart, method_or_widget: runIfNeeded (v7 flag bump), line: 16 }
hive_key_prefix: "nlog_*, exlog_*"
hive_key_formula: "First 8 hex chars of UUID v5 over the canonical join string (namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8')"
sync_methods: []
restore_methods: ["_restoreNutritionLogs (via _nlogKeyForRestore)"]
cloud_table: nutrition_logs
cloud_columns: [id, user_id, date, meal_type]
contract_test_path: "n/a — covered by existing exlog/nlog migrator tests + cross-device round-trip implicit in the migrator suite"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: yes
forbidden_patterns_checked: ["string_hashCode_for_deterministic_key_tag"]
proposed_fix: Replace `String.hashCode.toUnsigned(32).toRadixString(16)` with `Uuid().v5(namespace, joined).replaceAll('-', '').substring(0, 8)` in all 3 sites. Bump exlog + nlog migrator version flags (v6 → v7) so existing devices re-run the migration with the new tag formula and consolidate any rows that had drifted under the unstable hashCode.
regression_test_planned:
  - "existing exlog_key_migrator + nlog_key_migrator tests pass with new formula"
---
# Audit H-15 / H-16 / H-17: deterministic key tags used unstable hashCode

## Bug

3 sites generated an 8-char Hive key tag via `String.hashCode`:

```dart
// _nlogKeyForRestore (sync_service.dart)
final hash = joined.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');

// exlogKey (workout_write_service.dart)
final h = exerciseName.toLowerCase().trim().hashCode;

// _stableItemsHash (nutrition_write_service.dart)
return joined.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
```

**`String.hashCode` is not contractually stable across:**

- Dart VM versions (changes between major releases).
- Isolates (each isolate's hash seed may differ).
- Platforms (Android Dart VM vs iOS Dart VM — different
  implementations).

Result: cross-device round-trip silently produces a DIFFERENT 8-char
tag for the same logical tuple. Two devices restoring the same cloud
row land at different Hive keys → duplicate logical entries.
Receipts, AI snapshot, and per-day aggregations all
double-count.

The bug class is silent — it never produces an error, just gradual
drift over time.

## Cause

The code predates the deterministic UUID v5 pattern that landed
later in `sync_service._deterministicId`. The hashCode shortcut was
fast to write but didn't pin the spec-compliant guarantee.

## Fix

Replace each `hashCode`-based tag with UUID v5 (RFC 4122, stable
across all platforms):

```dart
static const _uuidGen = Uuid();
static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

final hash = _uuidGen
    .v5(_namespace, joined)
    .replaceAll('-', '')
    .substring(0, 8);
```

The first 8 hex chars of a v5 UUID preserve the prior key shape (8
chars) and give the same collision resistance as the prior 32-bit
hashCode-derived tag, but with the cross-platform stability the v5
spec guarantees.

## Migration

Existing devices have rows keyed under the unstable hashCode tags.
Bumped both migrator flags (`exlog_key_migration_v6` → `_v7`;
`nlog_key_migration_v6` → `_v7`) so on next cold start the migrator
re-walks every `exlog_*` / `nlog_*` row, computes the NEW key via
the updated formula, and consolidates rows that landed at different
tags pre-fix.

The migrators were already idempotent and handle the
read-rekey-merge pattern; they just needed the version-flag bump to
re-fire.

## Regression check

Suite: 1569 pass / 0 fail / 2 skip. Existing migrator tests
(`exlog_key_migrator_test`, `nlog_key_migrator_test`) pass with the
new formula.

## Related

- `_deterministicId` / `_uuidGen` in sync_service.dart (the prior
  v5-based stable-ID helper this fix follows)
- exlog_key_migrator.dart, nlog_key_migrator.dart
