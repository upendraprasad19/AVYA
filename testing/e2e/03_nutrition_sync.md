# E2E Test: Nutrition & Sync

## Setup
- User must be signed in and onboarded
- Navigate to Nutrition tab

---

## E11: Log a Meal

**Frontend:**
1. Navigate to Nutrition tab
2. `preview_snapshot` → verify Nutrition screen loaded
3. Find food search / "Log Meal" / "Add Food" button
4. `preview_click` to open food logger
5. `preview_fill` search field with "rice"
6. Wait 2 seconds for search results
7. `preview_snapshot` → verify search results appear
8. `preview_click` first result to add it
9. Confirm / save the food entry

**Backend (after sync):**
```sql
SELECT * FROM nutrition_logs
WHERE user_id = '<USER_ID>'
AND date = CURRENT_DATE;
```
- **PASS:** Nutrition log entry exists (may need weekly sync trigger)
- **NOTE:** Immediate Supabase entry not expected (Hive-first). Verify via `preview_snapshot` that UI shows the logged meal.

---

## E12: Macro Totals Update

**Frontend:**
1. After logging a meal in E11
2. `preview_snapshot` on Nutrition tab

- **PASS:** Calorie count increased from before logging
- **FAIL:** Calories unchanged or show 0

---

## E13: Weight Log

**Frontend:**
1. Navigate to Home tab or Profile
2. Find weight log input / "Log Weight" button
3. `preview_click` to open weight logger
4. `preview_fill` weight field with "74.5"
5. `preview_click` Save/Confirm

**Backend (after sync):**
```sql
SELECT * FROM weight_logs
WHERE user_id = '<USER_ID>'
ORDER BY created_at DESC
LIMIT 1;
```
- **PASS:** Weight log entry with weight_kg = 74.5 (after weekly sync)
- **NOTE:** Verify via `preview_snapshot` that weight sparkline updated

---

## E14: Water Tracking

**Frontend:**
1. Navigate to Nutrition or Home tab
2. Find hydration / water tracking section
3. `preview_click` water add button (e.g., +250ml)
4. `preview_snapshot`

- **PASS:** Water count increased
- **FAIL:** Water display unchanged

---

## E15: Food Search Works

**Frontend:**
1. Navigate to Nutrition tab
2. Open food search
3. `preview_fill` search with "paneer"
4. Wait 2 seconds
5. `preview_snapshot`

- **PASS:** Search results include paneer items (from seeded food_database)
- **FAIL:** No results or search crashes
