# E2E Test: Profile Edit & Sync

## Setup
- User must be signed in and onboarded
- Navigate to Profile tab

---

## E22: Edit Weight

**Frontend:**
1. Navigate to Profile tab
2. `preview_click` "Edit Profile" button
3. Find weight field
4. `preview_fill` weight field with "72"
5. `preview_click` Save button
6. Wait 3 seconds for sync

**Backend:**
```sql
SELECT current_weight_kg FROM user_profile
WHERE user_id = '<USER_ID>';
```
- **PASS:** current_weight_kg = 72 (immediate sync via syncProfileNow)
- **FAIL:** Still shows old weight (sync not triggered)

---

## E23: Edit Goal

**Frontend:**
1. `preview_click` "Edit Profile"
2. Find primary_goal field/chips
3. Change goal to "lose_fat"
4. `preview_click` Save
5. Wait 3 seconds

**Backend:**
```sql
SELECT primary_goal FROM user_profile
WHERE user_id = '<USER_ID>';
```
- **PASS:** primary_goal = "lose_fat"
- **FAIL:** Still shows old goal

---

## E24: BMR/TDEE Recalculation

**Frontend:**
1. After editing weight in E22
2. `preview_snapshot` on Profile screen → look for BMR/TDEE values

- **PASS:** BMR and TDEE values visible and different from onboarding values (weight changed)
- **NOTE:** BMR/TDEE are Hive-only fields, so verify via UI display

---

## E25: Name Update Syncs

**Frontend:**
1. `preview_click` "Edit Profile"
2. Find name field
3. `preview_fill` name with "QA Updated Name"
4. `preview_click` Save
5. Wait 3 seconds

**Backend:**
```sql
SELECT full_name FROM users WHERE id = '<USER_ID>';
```
- **PASS:** full_name = "QA Updated Name"
- **FAIL:** Name unchanged in Supabase

**Frontend verification:**
1. Navigate to Home tab
2. `preview_snapshot` → greeting should show "QA Updated Name"
