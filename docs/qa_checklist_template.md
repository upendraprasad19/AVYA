# AVYA per-batch QA Checklist

Copy this file to `docs/qa/<YYYY-MM-DD>-apk-test-N.md` at the start of every
APK test batch. Tester fills in pass/fail per flow, then signs off.

## Pre-flight

- **App version:**           ___ (e.g. 1.0.0)
- **versionCode:**           ___ (e.g. 12)
- **Branch HEAD (sha):**     ___
- **APK MD5:**               ___
- **Build date (IST):**      ___
- **Tester:**                ___
- **Device(s):**             ___ (model + Android version)
- **Account state:**         ___ (fresh install / upgrade / data carried)

---

## Flow 1: Sign in (existing user) → home

**Steps:**
1. Open app on a device that has the previous build's session wiped.
2. Sign in with the existing test account (email or Google).
3. Wait for `RestoringScreen` to complete.

**Expected:**
- Lands on `/home` (NOT `/onboarding/mission-brief`).
- Streak pill, today card, nutrition summary all populated within 5s.
- No "Account not synced" snackbar.

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 2: New user signup → onboarding → home

**Steps:**
1. Sign up with a fresh email never used before.
2. Tap CONTINUE through Mission Brief.
3. Walk through Identity → Goal → Stats → Details → Plan.
4. Tap REPORT FOR DUTY.

**Expected:**
- Mission Brief screen appears (with founder photo).
- Plan preview numbers match what gets saved to the profile.
- Lands on `/home` after REPORT FOR DUTY.
- Today card shows a real workout (not "no workout scheduled").

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 3: Log a meal via search → TodaysMealsCard

**Steps:**
1. Nutrition tab → tap a slot (e.g. Lunch) → search "rice".
2. Pick a result, set quantity, tap LOG.

**Expected:**
- TodaysMealsCard immediately shows the meal under Lunch.
- Calorie count matches the logged item (not 0, not "Unknown").
- Macros bar updates.
- Search dismisses cleanly (no double-tap re-trigger).

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 4: Log a meal via AI breakdown

**Steps:**
1. Nutrition tab → tap a slot → "Describe what you ate" → type
   "two rotis, dal, salad".
2. Wait for AI breakdown card.
3. Tap SAVE.

**Expected:**
- Breakdown card shows itemised list.
- After SAVE: snackbar `Meal saved ✓` + haptic tap.
- TodaysMealsCard shows the meal with correct kcal.
- AI counter increments (visible in profile usage tile if applicable).

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 5: Complete a workout → receipt renders per-set chips

**Steps:**
1. Today card → START WORKOUT.
2. Log 3 sets of bench press (varying weights).
3. Tap COMPLETE WORKOUT.

**Expected:**
- Receipt sheet pops up automatically.
- Receipt shows per-set chips: e.g. `60 kg × 10 reps`, `70 kg × 8 reps`,
  `80 kg × 6 reps` — NOT a single summary line.
- Quote line appears below exercises.
- SHARE button works (system share sheet).

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 6: Edit a completed workout log → sheet shows actual exercises

**Steps:**
1. Home → completed today card → tap "View Card".
2. Tap "Edit log" inside the sheet.

**Expected:**
- Edit sheet opens with all exercises from the workout (NOT empty,
  NOT "0 sets").
- Each exercise row shows the same set count as the receipt.
- Edit a weight, save.
- Receipt and Today card both reflect the change immediately.

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 7: Home today card → DONE + View Card after completion

**Steps:**
1. After Flow 5 (workout completed), return to Home.

**Expected:**
- Today card shows DONE chip (gold/green) + "View Card" button.
- Best lift + total volume displayed in left column.
- Tapping "View Card" reopens the receipt sheet (data identical).

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 8: AI coach progress query → numbers within reason

**Steps:**
1. AI coach tab.
2. Type "show my progress this month" or "what was my hardest workout".

**Expected:**
- Response refers to actual workouts done in the period (count matches
  what user remembers).
- Volume figures NOT 13× off (e.g., user did ~5 t total, response
  doesn't say 65 t).
- No fabricated PRs or weights the user never lifted.
- Response cites at most 1 short quote (<15 words).

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 9: Tap GO PRO when free → Razorpay checkout opens

**Steps:**
1. Profile tab → GO PRO pill (or any locked feature → paywall sheet).
2. Tap UPGRADE / GO PRO button.

**Expected:**
- Razorpay WebView opens within 3s.
- Amount matches plan (₹349 monthly / ₹2,999 yearly).
- Test card flow goes through.
- After success: PRO unlock visible within 10s.
- No "Couldn't start payment" toast on a fresh free account.

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 10: Tap GO PRO when already PRO → "You're already PRO"

**Steps:**
1. With PRO active, tap GO PRO again (e.g. via deep link or accidental tap).

**Expected:**
- Toast/snackbar: "You're already PRO" or "Subscription active".
- NO Razorpay checkout opens (server-side guard via
  `create-razorpay-order` v7 → 409 already_pro).
- NO "Couldn't start payment" generic error.

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 11: AI coach photo upload (PRO feature)

**Steps:**
1. AI coach tab → camera icon.
2. Pick or capture a meal photo.
3. Send.

**Expected (PRO):**
- Photo uploads, AI responds with vision-aware reply.
- No paywall.

**Expected (Free):**
- Paywall sheet pops up before upload.
- After upgrade, upload works.

**Pass/Fail:** [ ]

**Notes:**

---

## Flow 12: Plan regen via Edit Profile → today card + AI insight refresh

**Steps:**
1. Profile → Edit Profile.
2. Change days/week from current to a different value.
3. Tap SAVE.
4. Return to Home.

**Expected:**
- Today card immediately reflects the new plan (different exercise list
  if the day changed).
- AI insight card text changes (no stale "Legs B scheduled" from old plan).
- Calendar week strip rebuilds with new schedule.
- No "loading…" state stuck for >3s.

**Pass/Fail:** [ ]

**Notes:**

---

## Sign-off

- **Install timestamp (IST):**   ___
- **Tester name:**                ___
- **Batch ID:**                   APK Test #___
- **Overall status:**             [ ] PASS    [ ] PASS with notes    [ ] FAIL
- **Critical bugs found:**        ___ (list IDs / file links)
- **Ready to merge to main:**     [ ] yes  [ ] no — see notes
