# E2E Test: Training Flow

## Setup
- User must be signed in and onboarded
- Navigate to Train tab

---

## E26: Phase 1 Plan Renders

**Frontend:**
1. Navigate to Train tab
2. `preview_snapshot`

- **PASS:** Phase 1 "Foundation" (or similar) visible with workout days listed
- **FAIL:** Empty screen, "generating plan" stuck, or error

---

## E27: Week Selector Shows 4 Weeks

**Frontend:**
1. On Train tab
2. `preview_snapshot` → look for week selector (Week 1, 2, 3, 4)

- **PASS:** 4 weeks visible and tappable
- **FAIL:** Missing week selector or wrong week count

---

## E28: Exercise Cards Show Details

**Frontend:**
1. `preview_click` on a workout day card
2. `preview_snapshot`

- **PASS:** Exercise cards visible with name, sets, reps (e.g., "Bench Press 3x10")
- **FAIL:** Empty exercise list or missing details

---

## E29: Template Builder Accessible

**Frontend:**
1. Look for "Template Builder" or "Custom Workout" button
2. `preview_click` to open
3. `preview_snapshot`

- **PASS:** Template builder screen renders with exercise search/add UI
- **FAIL:** Button missing or screen crashes

---

## E30: PRO Gate on Start Workout (Free User)

**Frontend:**
1. Find "Start Workout" button on a workout day
2. `preview_click` "Start Workout"
3. `preview_snapshot`

- **PASS:** PaywallSheet appears with PRO pricing (₹349/month, ₹2,999/year)
- **FAIL:** Workout starts without PRO check, or no paywall shown
