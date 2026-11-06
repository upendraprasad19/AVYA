# E2E Test: Auth & Onboarding

## Setup
- Reset test user data via Supabase MCP (see README.md)
- Start webapp: `python -m http.server 8080 --directory build/web`
- Open preview: `preview_start` on `http://localhost:8080`

---

## E1: Fresh User Sign-In

**Frontend:**
1. `preview_snapshot` → verify sign-in screen is visible (email/password fields)
2. `preview_fill` email field with `<SUPABASE_TEST_EMAIL secret>`
3. `preview_fill` password field with `<SUPABASE_TEST_PASSWORD secret>`
4. `preview_click` "Sign In" button
5. Wait 3 seconds for auth
6. `preview_snapshot` → verify navigation away from sign-in

**Backend:**
```sql
SELECT id, email, full_name, onboarding_completed FROM users
WHERE email = '<SUPABASE_TEST_EMAIL secret>';
```
- **PASS:** Row exists with email = `<SUPABASE_TEST_EMAIL secret>`

---

## E2: Complete Onboarding (12 steps)

**Frontend:**
For each onboarding step, fill in the answer and tap Next:

| Step | Key | Value | Input Type |
|------|-----|-------|------------|
| 1 | full_name | "QA Tester" | text |
| 2 | date_of_birth | 1995-06-15 | datePicker |
| 3 | gender | "male" | chip tap |
| 4 | height_cm | 175 | number |
| 5 | current_weight_kg | 75 | number |
| 6 | target_weight_kg | 70 | number |
| 7 | primary_goal | "build_muscle" | chip tap |
| 8 | fitness_experience | "intermediate" | chip tap |
| 9 | days_per_week | "4" | selector tap |
| 10 | lifestyle_activity | "desk_job" | chip tap |
| 11 | equipment_access | "full_gym" | chip tap |
| 12 | start_date | "this_monday" | chip tap |

After last step, tap "Complete" / "Start" button.
Wait 5 seconds for plan generation + sync.

**Backend:**
```sql
SELECT user_id, gender, height_cm, current_weight_kg, primary_goal,
       fitness_experience, days_per_week, equipment_access, bmr, tdee
FROM user_profile WHERE user_id = '<USER_ID>';
```
- **PASS:** All fields populated (gender=male, height_cm=175, primary_goal=build_muscle)

---

## E3: Onboarding Sync — Progress Table

**Backend (run immediately after E2):**
```sql
SELECT user_id, current_phase, current_week, total_workouts_done
FROM user_progress WHERE user_id = '<USER_ID>';
```
- **PASS:** Row exists with current_phase=1, current_week=1

---

## E4: Sign Out Preserves Supabase Data

**Frontend:**
1. Navigate to Profile tab
2. `preview_click` "Sign Out" / "Logout" button
3. Wait 2 seconds
4. `preview_snapshot` → verify sign-in screen is shown

**Backend:**
```sql
SELECT * FROM user_profile WHERE user_id = '<USER_ID>';
```
- **PASS:** Profile data still exists in Supabase after sign-out

---

## E5: Re-Login Restore

**Frontend:**
1. `preview_fill` email with `<SUPABASE_TEST_EMAIL secret>`
2. `preview_fill` password with `<SUPABASE_TEST_PASSWORD secret>`
3. `preview_click` "Sign In"
4. Wait 5 seconds for auth + restore
5. `preview_snapshot` → verify Home screen shows greeting with user name

- **PASS:** Home screen shows "QA Tester" or "Welcome back" (name restored from Supabase)
- **FAIL:** Shows "User" or redirects to onboarding (restore failed)
