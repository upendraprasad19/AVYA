# APK Test #6 Plan C — Nutrition Write Service Verification

**Branch:** `feat/apk-test-6-batch` at HEAD `e08bd5b`

**Coverage:** Tasks C-5 through C-8 (nutrition write-through, meal templates, delete with undo, sync)

---

## C-5: Counter Behavior — Text Log

**Criterion:** Log food via AI text analysis → counter decrements (user quota)

### Steps:
1. Launch APK in dev mode (Supabase free tier user).
2. Navigate to Nutrition > "Search foods" → tap AI icon (text).
3. Type "chicken rice" → tap "Analyze".
4. Verify counter shows remaining calls (e.g., `9/10` after first log).
5. Verify Hive `nutritionBox['nlog_2026-05-01_lunch_<hash>']` contains:
   - `logged_at: '2026-05-01T...'`
   - `meal_type: 'lunch'`
   - `items: [FoodItem{...}]`
   - `total_calories`, `total_protein_g`, etc.
   - `source: 'food_text_analysis'`
   - `updated_at_ms: <current timestamp>`
6. Verify `nutrition_log_index_2026-05-01` includes the new nlog key.

**Expected:** Counter shows 9/10, Hive entry is atomic with all fields, index updated.

---

## C-6: Scan Meal — Cloud Sync

**Criterion:** Scan a meal photo → save → cloud rows synced (both nutrition_logs + nutrition_log_items)

### Steps:
1. On same nutrition screen, tap "📷 Scan" button.
2. Take/pick a meal photo.
3. Verify result shows `[FoodItem{name, quantityG, kcal, P, C, F, fiber}, ...]`.
4. Verify totals display: `1820 kcal | 48g protein`.
5. Tap "SAVE MEAL" button.
6. Verify snackbar "Meal logged" + macros refresh on home screen.
7. Verify Hive `nutritionBox` has new `nlog_2026-05-01_lunch_<new-hash>` entry.
8. Open `supabase/logs/` (if possible) or check in-app coach snapshot:
   - Verify `nutrition_logs` cloud row exists with `user_id`, `logged_at: 2026-05-01`, `total_calories: 1820`, `total_protein_g: 48`.
   - Verify `nutrition_log_items` has 4+ rows (one per food item) with same `nutrition_log_id`.

**Expected:** Both cloud tables populated, macros on home refresh, coach sees the meal in tomorrow's snapshot.

---

## C-7: Long-Press Delete + Undo

**Criterion:** Long-press logged meal → "Delete" → undo snackbar → macros recalc

### Steps:
1. From nutrition screen, long-press any logged meal from C-5 or C-6.
2. Verify contextual menu appears with "Delete" option.
3. Tap "Delete".
4. Verify snackbar "Meal deleted — UNDO" appears for 5 seconds.
5. **Wait 6 seconds** (let undo window close).
6. Verify Hive entry is gone: `nutritionBox.get('nlog_...')` returns null.
7. Verify `nutrition_log_index_2026-05-01` no longer contains that nlog key.
8. Verify home macros recalculate (calories drop by ~1820).
9. **Test undo path:** repeat steps 1-4, then tap "UNDO" within 5 seconds.
10. Verify meal reappears in Nutrition > Food Log (same nlog key, restored from stash).
11. Verify home macros restore (+1820 calories back).

**Expected:** Delete removes entry atomically, index updated, macros refresh both ways. Undo stash survives and restores correctly.

---

## C-8: Save as Template

**Criterion:** Log food → "Save as template" → appears in SAVED MEALS tab

### Steps:
1. From nutrition screen, log any meal (C-5 or C-6 steps).
2. After "Meal logged" snackbar, scroll down and verify meal card shows "Save as template" button.
3. Tap "Save as template".
4. Verify dialog "Template name" with pre-filled name (e.g., "Chicken Rice").
5. Tap "SAVE TEMPLATE".
6. Verify success snackbar "Template saved".
7. Navigate to Nutrition > **SAVED MEALS** tab.
8. Verify template appears as a tappable card with:
   - Template name
   - Food list (e.g., "Chicken 150g, Rice 100g")
   - Macros (e.g., "1820 kcal | 48g P").
9. Tap template → "Log this meal" button appears.
10. Tap "Log this meal".
11. Verify Hive `nutrition_log_index_<today>` includes new nlog entry (different key from template, same items).
12. Verify counter decremented (if from food_text_analysis source).

**Expected:** Template saved to `userBox['saved_meals']['<template-id>']`, appears in SAVED MEALS, logging via template is atomic and sources correctly.

---

## Test Environment

- **Device:** Android (physical or emulator, API 28+)
- **APK Flavor:** `--flavor prod --release`
- **Network:** Online (Supabase free tier)
- **User State:** Fresh sign-up OR returning user on same account
- **Time:** Run all steps within a single calendar day (IST) to keep nutrition_log_index consistent

---

## Success Criteria

| Criterion | C-5 | C-6 | C-7 | C-8 |
|-----------|-----|-----|-----|-----|
| Hive writes atomically (all fields populated) | ✓ | ✓ | ✓ | ✓ |
| Index updated (nutrition_log_index_<date>) | ✓ | ✓ | ✓ | ✓ |
| Counter decrements (if applicable) | ✓ | ✓ | — | ✓ |
| Cloud sync (nutrition_logs + nutrition_log_items) | — | ✓ | ✓ | ✓ |
| Macros refresh on home screen | ✓ | ✓ | ✓ | ✓ |
| Undo stash works (C-7 only) | — | — | ✓ | — |
| Templates saved & relog works (C-8 only) | — | — | — | ✓ |

---

## Notes

- C-5 may show 0/10 counter on fresh account (free trial cap not yet active). Still counts as passing if nlog entry exists.
- C-6 cloud sync assumes the APK is built with Plan C migrations applied to the remote Supabase project.
- C-7 undo window is **5 seconds** — test quickly to ensure undo path is exercised.
- C-8 templates stored per user (`userBox['saved_meals']`), not synced to cloud (deferred to later batch).
- All verification assumes `NlogKeyMigrator.runIfNeeded()` runs on first launch; no manual migration step required.

---

**Sign-off:** When all four criteria pass (C-5, C-6, C-7, C-8), APK Test #6 Plan C is verified complete.
