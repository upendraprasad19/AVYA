# E2E Test: Home Screen

## Setup
- User must be signed in and onboarded
- Start preview on `http://localhost:8080`
- Navigate to Home tab if not already there

---

## E6: Greeting Shows Correct Name

**Frontend:**
1. `preview_snapshot` on Home screen

- **PASS:** Snapshot contains the user's name (e.g., "QA Tester" or "Hey, QA")
- **FAIL:** Shows "User" or generic greeting

---

## E7: Weekly Calendar Renders 7 Days

**Frontend:**
1. `preview_snapshot` → look for calendar strip

- **PASS:** 7 day indicators visible (M, T, W, T, F, S, S or date numbers)
- **FAIL:** Calendar strip missing or fewer than 7 days

---

## E8: Nutrition Snapshot Shows Calories/Protein

**Frontend:**
1. Scroll to nutrition section
2. `preview_snapshot`

- **PASS:** Shows calorie target and/or protein target (numbers visible)
- **FAIL:** Nutrition section missing or shows 0/0

---

## E9: Weight Sparkline Renders

**Frontend:**
1. Scroll to weight section
2. `preview_snapshot`

- **PASS:** Weight sparkline or weight display visible
- **PASS (empty state):** Shows "Log your first weight" or similar prompt
- **FAIL:** Section crashes or is completely absent

---

## E10: PR Snapshot Shows Exercise Data

**Frontend:**
1. Scroll to PR section
2. `preview_snapshot`

- **PASS:** PR snapshot visible (may show "No PRs yet" for new user — that's OK)
- **FAIL:** Section crashes or is completely absent
