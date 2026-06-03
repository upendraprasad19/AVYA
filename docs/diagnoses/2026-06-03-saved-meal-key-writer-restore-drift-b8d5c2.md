---
bug_id: b8d5c2
date: 2026-06-03
batch: apk-obs-2026-06-02
status: fixed
blast_radius: feature
symptom: >
  Surfaced by the f7e3a1 B-pass (Finding 1) while reviewing the saved-meals sync.
  `NutritionWriteService.saveMealPreset` keyed the local Hive row by
  `saved_meal_<millisecondsSinceEpoch>`, but the cloud restore
  (`SyncService._restoreSavedMeals`) derives `saved_meal_<nameHash>`
  (name.toLowerCase().trim().hashCode). The two key shapes never collide, so on
  every restore / reinstall / device-switch the restored row landed under a
  DIFFERENT Hive key than the locally-written one → each saved meal appeared
  TWICE in the saved-meals list. Single-user, cosmetic (duplicate list entries,
  no data loss, no cross-user effect) — a different, lower-severity class than the
  cross-user collision d4b8e2/f7e3a1 fixed, but the same writer/reader key-drift
  family (debugging skill §2.12, rogue/divergent key formula).
concept: saved_meals
sot_registry_entry: saved_meals
recurrence: "Rogue/divergent Hive-key formula class (debugging §2.12) — same family as the exlog (Gate 17) + nlog (check_nlog_key_canonical) key-canonicalisation fixes, and the Test #9 saved_meal_<cloud-uuid>-vs-<nameHash> restore-dup. The writer drifted to a timestamp key while the restore stayed on the name-hash; aligning the writer + a re-key migrator + a canonical-construction gate closes it the same way exlog/nlog were closed."
related_bugs:
  - f7e3a1
writers: >
  lib/core/services/nutrition_write_service.dart saveMealPreset (the local Hive
  writer — formerly `'saved_meal_${now.millisecondsSinceEpoch}'`, now
  `savedMealKey(name)`); lib/core/services/saved_meal_key_migrator.dart
  SavedMealKeyMigrator.runIfNeeded (one-shot re-key of legacy rows on boot).
readers: >
  lib/core/services/sync/sync_nutrition.dart _restoreSavedMeals (cloud → Hive;
  derives `saved_meal_<nameHash>` — the shape the writer now matches);
  lib/features/nutrition/providers/nutrition_provider.dart SavedMealsNotifier.build
  (savedMealsProvider — lists `saved_meal_*` rows; was showing the duplicates).
hive_key_prefix: saved_meal_
hive_key_formula: >
  Canonical: `saved_meal_<UUID v5 over lowercased,trimmed name>` — the single
  source is NutritionWriteService.savedMealKey(name); the restore derives the same
  key by CALLING that helper (no drift). UUID v5 (NOT String.hashCode) is
  SDK-stable + 122-bit collision-free (f7e3a1 B-pass F3/F6 — hashCode is VM-unstable
  per NlogKeyMigrator's H-17 note + only 32-bit). The LEGACY writer used
  `saved_meal_<millisecondsSinceEpoch>` (the drift this closes); the migrator
  re-keys both legacy <ms> and any older <hashCode> rows to the v5 shape.
sync_methods: _syncSavedMeals
restore_methods: _restoreSavedMeals
cloud_table: user_saved_meals
cloud_columns: >
  user_saved_meals(id pk gen_random_uuid, user_id, name, items, total_calories,
  total_protein, times_used, created_at) — natural key (user_id, name) per
  migration 083 (f7e3a1). No schema change in THIS fix; it is client-only (key
  alignment + migrator). The cloud already deduped by name, so the bug was purely
  the LOCAL writer⇄restore key disagreement.
contract_test_path: test/contracts/saved_meal_key_canonical_test.dart
ist_handling: not_applicable (no date math; Hive-key formula only)
provider_invalidations: >
  saveMealPreset already calls _invalidateNutritionProviders + the sync fan-out;
  the migrator runs at boot (restoring_screen) before /home reads
  savedMealsProvider, so the de-duplicated list renders on first paint.
telemetry_op_types: >
  restoring_screen_migrator_done (message=migrator=saved_meal) — boot timing +
  did_run, mirroring the nlog/exlog migrator telemetry.
cross_account_guard: not_applicable (single-user local key; nutritionBox is user-scoped via wrapUserScopedBox)
forbidden_patterns_checked:
  - "A `saved_meal_*` Hive key constructed outside NutritionWriteService.savedMealKey (or the documented restore mirror) — blocked by scripts/check_saved_meal_key_canonical.dart + test/contracts/saved_meal_key_canonical_test.dart (mirrors Gate 17 exlog / nlog)."
  - "Writer keying by `millisecondsSinceEpoch` while a reader/restorer keys by content-hash (the drift) — eliminated: saveMealPreset now calls savedMealKey(name); the canonical test pins writer == restore formula."
proposed_fix: >
  Three parts (client-only, mirroring the exlog/nlog key-canonicalisation):
  (1) saveMealPreset keys Hive via the new canonical helper
  NutritionWriteService.savedMealKey(name) = `saved_meal_<UUID v5(name)>` (the SAME
  key the restore derives and the cloud (user_id,name) natural key) instead of
  `saved_meal_<ms>`. (2) SavedMealKeyMigrator (one-shot, boot-wired in
  restoring_screen after NlogKeyMigrator, guarded by
  configBox['saved_meal_key_migration_v1']) re-keys existing legacy `saved_meal_<ms>`
  rows to canonical, MERGING the restore-dup collision (legacy <ms> + an already-
  restored <nameHash> row) keeping the latest content + max times_used, then
  deleting the legacy key. (3) scripts/check_saved_meal_key_canonical.dart pins
  single-site construction. The restore mirror is unchanged (already name-hash)
  and pinned equal to the helper. No migration / cloud change needed.
regression_test_planned: >
  test/safety/saved_meal_key_migrator_test.dart (behavioral): re-keys
  `saved_meal_<ms>` → canonical; MERGES the legacy+canonical restore-dup keeping
  max times_used; idempotent (flag gate); leaves nameless rows untouched; and the
  writer now produces NO 13-digit-ms `saved_meal_*` key.
  test/contracts/saved_meal_key_canonical_test.dart (source-grep + drift):
  no non-allowlisted `saved_meal_*` construction; savedMealKey == the restore's
  formula for a sample name; case/whitespace-insensitive.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "saveMealPreset → savedMealKey(name); SavedMealKeyMigrator created + boot-wired; gate check_saved_meal_key_canonical.dart PASS; analyze clean; 8 tests green (3 canonical + 5 migrator)" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "behavioral migrator test proves legacy <ms> rows re-key to canonical + the restore-dup collision merges to ONE row keeping max times_used; nameless rows untouched; idempotent" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live 2026-06-03: user_saved_meals empty (0 rows) — cloud already deduped by (user_id,name) per migration 083; the bug was purely the LOCAL writer/restore key disagreement, so no cloud data fix is needed" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "writer == restore == cloud natural-key, all keyed on (lowercased, trimmed) name → the same saved meal collapses to ONE row on write / sync / restore; pinned by saved_meal_key_canonical_test.dart" }
impact_analysis: >
  Feature-tier (saved-meals convenience list), single-user, cosmetic: a restore
  duplicated every saved meal in the list — no data loss, no cross-user effect.
  Pre-existing and NOT worsened by the f7e3a1 cloud fix (the cloud (user_id,name)
  key dedups server-side regardless). Founder chose to fold it in ("do it right")
  rather than track it. The fix is the codebase's established key-canonicalisation
  pattern (writer helper + restore mirror + one-shot re-key migrator + a
  source-grep gate), mirroring exlog (Gate 17) and nlog
  (check_nlog_key_canonical). The migrator is merge-safe: the restore-dup is
  exactly the (legacy <ms> + canonical <nameHash>) collision, and the migrator
  groups by canonical key + keeps the latest content + max times_used, so a
  re-log count is never lost. Lesson (added to the writer/reader-drift class): a
  Hive-key formula must have ONE constructor; when a restore derives a key, the
  WRITER must use the same derivation — a timestamp key silently duplicates the
  moment a content-hash restorer round-trips it.
---

# Saved-meal key drift — writer kept `saved_meal_<ms>`, restore derived `saved_meal_<nameHash>`

## What happened
`saveMealPreset` keyed the local Hive row by `saved_meal_<millisecondsSinceEpoch>`
while `_restoreSavedMeals` derives `saved_meal_<nameHash>`. The shapes never
collide, so a restore/reinstall wrote a SECOND row for every saved meal → the
saved-meals list showed each preset twice. Surfaced by the f7e3a1 B-pass
(Finding 1); single-user cosmetic, but the same writer/reader key-drift family.

## Fix
The established key-canonicalisation pattern (mirrors exlog Gate 17 / nlog):
- **Writer** → `NutritionWriteService.savedMealKey(name)` (the ONE canonical
  constructor) = `saved_meal_<nameHash>`, matching the restore + the cloud
  `(user_id, name)` natural key.
- **`SavedMealKeyMigrator`** (boot-wired, idempotent) re-keys legacy
  `saved_meal_<ms>` rows to canonical, **merging** the restore-dup collision
  (latest content + max `times_used`), deleting the legacy key.
- **`check_saved_meal_key_canonical.dart`** pins single-site construction; the
  restore mirror is pinned equal to the helper by the contract test.

## Verification
- `saved_meal_key_migrator_test.dart` (behavioral, 5): re-key, restore-dup
  **merge keeping max times_used**, idempotent, nameless-untouched, writer-keys-canonical.
- `saved_meal_key_canonical_test.dart` (3): single-site construction, writer==restore
  formula, case/whitespace-insensitive.
- Gate PASS; analyze clean. Live: `user_saved_meals` empty (cloud already deduped).

## Lesson / class
A Hive-key formula must have ONE constructor. When a restore derives a key, the
WRITER must use the SAME derivation — a `millisecondsSinceEpoch` key silently
duplicates the moment a content-hash restorer round-trips it. Closed the same way
exlog/nlog were: helper + mirror + re-key migrator + source-grep gate.

## B-pass hardenings (f7e3a1 reviewer found 5; 4 fixed in-batch)
- **F3/F6 (P1 / P0-class):** `savedMealKey` uses **UUID v5** (full 122-bit), NOT
  `String.hashCode` — hashCode is VM-unstable (NlogKeyMigrator H-17) and 32-bit
  (collision). v5 is SDK-stable + collision-free; the restore CALLS the helper
  (single source) so writer/restore can't drift.
- **F1 (P2):** the migrator now **puts the merged row BEFORE deleting** legacy
  keys — a throwing put can never lose the group.
- **F4 (P2):** same-name re-save **preserves `times_used`** (no silent reset).
- **F5 (P3):** the gate + contract test strip **block comments** too.
- **Follow-ups surfaced (pre-existing, proven paths — not folded):**
  `NlogKeyMigrator` has the same delete-before-put ordering; the nlog/exlog
  canonical gates lack block-comment stripping.

## See also
- `lib/core/services/nutrition_write_service.dart` (`savedMealKey`, `saveMealPreset`)
- `lib/core/services/saved_meal_key_migrator.dart`, `scripts/check_saved_meal_key_canonical.dart`
- Surfaced by `f7e3a1`; key-canonical siblings: `check_nlog_key_canonical.dart`, `check_exlog_key_canonical.dart`
- `feedback_writer_reader_field_drift_recurring.md`, debugging skill §2.12
