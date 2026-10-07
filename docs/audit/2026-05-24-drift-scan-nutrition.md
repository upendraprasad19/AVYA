# Drift Scan — nutrition domain — 2026-05-24

First run of `writer-reader-drift-detector` agent on the nutrition
domain. Scope-capped to ~30 highest-impact verifications across
`nlog_*` Hive shape (parent + items[]) plus the two cloud projections
(`nutrition_logs`, `nutrition_log_items`).

## Summary
- P0 (active bug or contract violation): 1
- P1 (latent risk / partial coverage): 1
- P2 (convention drift): 2

## Writers covered

- `lib/core/services/nutrition_write_service.dart:55-148` —
  `logMeal()` → Hive `nlog_*` map (14 fields: `id`, `log_key`, `date`,
  `meal_type`, `total_calories`, `total_protein`, `total_carbs`,
  `total_fat`, `total_fiber`, `items[]`, `source`, `logged_at`,
  `created_at`).
- `lib/core/services/nutrition_write_service.dart:151-202` —
  `appendItemsToMeal()` recomputes totals on `items[]` union.
- `lib/core/services/nutrition_write_service.dart:205-261` —
  `editLog()` recomputes totals on `items` updates.
- `lib/core/services/nutrition_write_service.dart:734-743` —
  canonical `computeLogKey({istDate, mealType, items})` →
  `nlog_<YYYY-MM-DD>_<mealType>_<v5hash8>`.
- `lib/core/services/nutrition_write_source.dart:62-70` — canonical
  per-item `FoodItem.toMap()` (7 fields: `name`, `quantity_g`,
  `calories`, `protein`, `carbs`, `fat`, `fiber`).
- `lib/core/services/sync/sync_nutrition.dart:72-200` — cloud
  `nutrition_logs` upsert (8 cols projected; `onConflict:
  user_id,date,meal_type`) + per-item `nutrition_log_items` upsert
  (8 cols; `onConflict: id`).
- `lib/core/services/sync/sync_nutrition.dart:203-225` — cloud
  `water_logs` upsert.
- `lib/core/services/sync/sync_nutrition.dart:232-263` — cloud
  `user_saved_meals` upsert.

## Readers covered

- 1 grep-located writer + 12 grep-located readers. Spot-verified:
  - `lib/features/ai_coach/repositories/ai_coach_repository.dart:1086,
    1168, 1411` — `nlog_*` iteration for AI snapshot (`_getMealsToday`,
    `_getNutritionTrend7d`, `_getTodayNutrition`).
  - `lib/features/nutrition/providers/nutrition_provider.dart:884,
    959` — UI mutation callers via `logMeal`.
  - `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart:229,
    304` — search-mode log path.
  - `lib/core/services/sync_service.dart:158-189` — restore mirror
    `_nlogKeyForRestore`.
  - `lib/core/services/nlog_key_migrator.dart:99-125` — migration
    mirror.

## Findings

### F1: `logMeal` callers pass raw `DateTime.now()` (device-local), writer hand-assembles date key NOT through `istDateStr()` → device-local key drift

- **Severity:** **P0** (latent — only fires when device timezone ≠ IST,
  e.g. founder traveling, or any non-India user)
- **Writer:**
  `lib/core/services/nutrition_write_service.dart:87-88` (and mirror
  at `computeLogKey:739-740`) — hand-assembles
  `'${istDate.year}-${month}-${day}'` directly from the input
  DateTime's components.
- **Reader contract violation:**
  `lib/core/services/nutrition_write_service.dart:76` —
  `computeLogKey(istDate: date, ...)` parameter NAME asserts the
  caller pre-shifts to IST, but FIVE callers pass raw
  `DateTime.now()` (device-local, not IST-shifted):
  - `lib/features/nutrition/widgets/scan_meal_section.dart:438`
  - `lib/features/nutrition/widgets/barcode_scan_sheet.dart:186`
  - `lib/features/nutrition/widgets/food_search_sheet.dart:500`
  - `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart:304`
  - `lib/features/ai_coach/services/tool_dispatcher.dart:1348`
  - + `nutrition_provider.dart:884, 959`
- **Drift type:** semantic — IST contract violation, the same class
  flagged in `feedback_use_ist_throughout.md` + Test #11 / B1+B2+M3
  cleanup sweep + Test #12 Theme A `formatDateKey` IST fix.
- **Real-world effect:** A user logging a meal between IST 00:00 and
  IST 00:30 from a device in UTC timezone (or any tz < IST) would
  produce a Hive key with **yesterday's** date. Reader paths
  (`_getMealsToday`, `TodaysMealsCard`) correctly use
  `istDateStr(DateTime.now())` (post-Test #12 fix), so the meal
  vanishes from "Today's Meals" — exact founder-reported symptom
  class from prior batches.
- **Suggested fix:** Inside `computeLogKey` (and the inline build at
  line 87-88), replace the hand-assembly with `istDateStr(date)` from
  `lib/core/utils/ist_date.dart`. The helper already does
  `istDateOf(t) = t.toUtc().add(Duration(hours:5, minutes:30))` so
  passing raw `DateTime.now()` becomes safe.
- **Regression test to add:**
  `test/contracts/nutrition_write_service_ist_anchored_test.dart` —
  given a UTC `DateTime(2026, 5, 24, 22, 0)` (which is IST 2026-05-25
  03:30) as the `date` argument, the Hive key must contain
  `nlog_2026-05-25_*` (IST date) not `nlog_2026-05-24_*` (UTC date).

### F2: `nlog_*` literal assembly outside `NutritionWriteService` (Gate-17-style gap)

- **Severity:** P1 (mirror is documented, but no enforcing gate)
- **Writer:** `lib/core/services/nutrition_write_service.dart:742` —
  canonical `computeLogKey()`.
- **Mirrors:**
  - `lib/core/services/sync_service.dart:188` (`_nlogKeyForRestore`,
    documented mirror because restore takes raw cloud maps, not typed
    `List<FoodItem>`).
  - `lib/core/services/nlog_key_migrator.dart:125`
    (`_computeLogKey`, migration mirror).
- **Drift type:** signature — same risk that produced the 3 rogue
  `exlog_*` writers in Test #16.1 (closes-diagnose: a16c1a). Three
  separate sites computing the same key formula = 3× the chance a
  future change drifts one without the others.
- **Real-world effect:** None today (mirrors are byte-identical per
  docstrings and tests). Latent risk for the next rename / formula
  bump.
- **Suggested fix:** Add a permanent **Gate 18 — nlog key canonical**
  source-grep script mirroring `scripts/check_exlog_key_canonical.dart`
  (Gate 17, shipped in Test #16.1). The new script allowlists
  `nutrition_write_service.dart`, `sync_service.dart` (the
  `_nlogKeyForRestore` mirror), and `nlog_key_migrator.dart`, and
  fails any other literal `'nlog_'` string assembly.
- **Regression test to add:**
  `test/contracts/nlog_key_canonical_test.dart` — assert exactly 3
  allowlisted files contain `'nlog_${...'` / `"nlog_${...` patterns;
  none elsewhere.

### F3: Cloud `nutrition_log_items` projection has dead fallback reads

- **Severity:** P2
- **Writer:** `lib/core/services/nutrition_write_source.dart:62-70`
  (`FoodItem.toMap`) — emits exactly `{name, quantity_g, calories,
  protein, carbs, fat, fiber}`.
- **Reader (cloud projection):**
  `lib/core/services/sync/sync_nutrition.dart:172-174`:
  - `'food_name': item['name'] ?? item['food_name'] ?? ''` — reads
    `food_name` as fallback; writer never emits it.
  - `'quantity_g': item['serving_g'] ?? item['quantity_g']` — reads
    `serving_g` as fallback; writer never emits it.
- **Drift type:** convention / dead defensive read.
- **Suggested fix:** Drop the fallbacks (cleaner code) OR document
  WHY (e.g. compatibility with a known-legacy items[] shape from a
  pre-2026 migration that this scan didn't see). If the latter, add a
  pointer comment to the migration script that produced the legacy
  shape.

### F4: `nutrition_log_items` table has no `fiber` column despite Hive `FoodItem.fiber`

- **Severity:** P2 (documented intent, not drift)
- **Writer (Hive):** `FoodItem.toMap()` emits per-item `fiber`.
- **Reader (cloud):** `sync_nutrition.dart:169-179` deliberately
  omits `fiber` from the per-item projection per inline comment.
  Migration 034 added `total_fiber` to the PARENT (`nutrition_logs`)
  table but not the per-item table.
- **Drift type:** schema partial-coverage. Not a bug — by design per
  current schema state — but the AI coach via `_getTodayNutrition`
  reads `total_fiber` from the parent which is correct.
- **Suggested fix:** Future migration could add `fiber` to
  `nutrition_log_items` for per-item fiber analytics (e.g. weekly
  report could surface fiber-rich foods). Out of scope for a drift
  audit; flag for product roadmap.

## Special signature checks

- ❌ **`nlog_*` keys outside canonical.** Three mirrors exist
  (canonical + restore + migrator) — see F2. Recommend Gate 18 +
  contract test.
- ✅ **`exlog_*` / `wlog_*` keys.** No nutrition-domain emit sites
  (correct).
- ✅ **Duration field-name dual-read.** Not applicable to nutrition.
- ✅ **Hive ↔ cloud `coaching_notes`/`coach_notes` remap.** Not
  applicable to nutrition.
- ❌ **IST date keys** — see F1 (P0).
- ✅ **UUID v5 deterministic IDs.** `_stableItemsHash` uses UUID v5
  via fixed namespace + `(name.lower.trim | quantityG.toFixed(1))`
  pairs per H-17 fix. No `hashCode`-based ID assembly remaining.
- ⚠️ **Auth-scoped Riverpod providers** — out of scope for this
  domain scan (covered by `auth_invalidation_contract_test.dart` from
  Test #15.3 / Bug 5).

## SoT registry coverage

- Writers in scope: 2 services (`NutritionWriteService` +
  `_syncNutritionLogs/_syncWaterLogs/_syncSavedMeals`).
- Of those present in `docs/sot_registry.yaml`: 2 (canonical
  nutrition-domain entries already registered per Test #11 + Test
  #12.5 SoT class registrations).
- Absent from registry (recommend adding entry): 0.

## Overall

**One P0 latent (F1 — non-IST timezone callers).** This is the
recurring IST-drift bug class that has surfaced 3+ times across
Tests #10 → #15.4 in other surfaces (sleep, food log keys,
formatDateKey). Nutrition is the next surface where it could
silently fire.

The fix is one-line inside `computeLogKey` (replace hand-assembly
with `istDateStr(date)` from the canonical helper). Recommend a
diagnose-doc + regression test in the next batch.

Founder direction needed: do you want this fixed in the next batch
(audit-cleanup), or is it acceptable to leave latent given typical
device-tz === IST for the target market?

The remaining 3 findings (F2 nlog-canonical-gate gap, F3 dead
fallback reads, F4 per-item fiber schema partial) are low-risk
hygiene improvements suitable for a routine cleanup batch.

Agent calibrated against known prior drift instances. Ready for
routine use on field renames and per-domain writer changes.
