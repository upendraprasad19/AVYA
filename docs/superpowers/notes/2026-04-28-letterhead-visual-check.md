# Tab Letterhead — Manual Visual Check (Plan D D-11)

**Run after installing the APK Test #5 build for verification of OBS-6 fix.**

## What this verifies

OBS-6 reported: U7 unified `WardTabHeader` flattened tab personalities — lost personalised greeting on Home, Fraunces serif titles on Nutrition / Coach / Profile, plan header on Train.

Plan D's solution: Each tab keeps its own letterhead style, with a shared structural rule (eyebrow → Fraunces 28sp title → gold rule → status strip).

## Per-tab visual check

### 🏠 Home tab (Daily Brief)

1. Open Home tab.
2. **Verify** letterhead structure (top-down):
   - 44dp avatar on the LEFT (initial letter, gold-ringed)
   - Eyebrow: `DAILY · TUE 28 APR` (or current date — TUE/WED/etc + day + 3-letter month)
   - Title (Fraunces 28sp): `Good morning, <FirstName>.` / `Good afternoon, <FirstName>.` / `Good evening, <FirstName>.` based on time of day
   - Gold rule (60dp)
   - Status strip below: 🔥 streak chip + ❄ freeze chip
3. **Verify** time-of-day greeting matches device clock (morning before 12:00, afternoon 12:00–17:00, evening after 17:00).
4. **Verify** first name is correct (matches profile name; not generic "User" placeholder).

### 🏋️ Train tab

1. Open Train tab.
2. **Verify** letterhead structure:
   - Eyebrow: `TRAIN · WK 2 OF 4` (current week + plan total weeks)
   - Title (Fraunces 28sp): phase name (e.g. `Foundation`, `Strength`, `Hypertrophy`)
   - Subtitle line: `<N> of <M> sessions complete`
   - Progress bar with gold trailing percent
   - Status strip: 🔥 streak + ❄ freeze (NO rank chip — confirmed roadmap is source of truth)
3. **Verify** rank chip is NOT shown anywhere on Train tab top section.

### 🥗 Nutrition tab (Galley)

1. Open Nutrition tab.
2. **Verify** letterhead structure:
   - Eyebrow: `GALLEY · TUE 28 APR` (current date)
   - Title (Fraunces 28sp): `Fueling the plan`
   - Trailing pill: `🍽 DIET PLAN` (gold-soft, opens diet plan screen)
   - Gold rule
   - Status strip: 🔥 streak + ❄ freeze (no rank chip)

### 💬 AI Coach tab (The Bridge)

1. Open AI Coach tab.
2. **Verify** letterhead structure:
   - Eyebrow: `THE BRIDGE · 24/7` (NOT `YOUR AI COACH · 24/7` — verify the change shipped)
   - Title (Fraunces, italic): `Aye Captain` (NOT `Good <morning|afternoon|evening>, <Name>.` — verify the change shipped, eliminates "Captain" duplicate with eyebrow)
   - Status pill / overflow menu on the right
   - Status strip: 🔥 streak + ❄ freeze

### 👤 Profile tab (Dossier)

1. Open Profile tab.
2. **Verify** letterhead structure:
   - Banner (110dp gradient or uploaded image)
   - **Floating eyebrow on banner top-left at ~65% alpha:** `DOSSIER · OFFICER`
   - Edit icon (top-right)
   - 80dp avatar overlapping banner bottom
   - Name (Fraunces) + subtitle below banner, with EDIT PROFILE button on the right
   - **Gold rule** (60dp) below the name row
   - Status strip with rank chip rendered by ServiceRecordSection / RankChip (existing surfaces)

## Pass criteria

All 5 tabs show distinct personalities (welcome row vs plan header vs Galley letterhead vs Bridge greeting vs banner+floating-eyebrow), but follow the same structural rhythm (eyebrow → title → rule → status strip). Streak + freeze chips visible at the same logical position on every tab.

## Fail criteria

Any tab where:
- Eyebrow is missing or wrong format
- Title font is not Fraunces serif (Home / Train / Nutrition / Coach) or wrong text
- Gold rule missing
- Status strip missing or in wrong position
- Train shows rank chip at top (should be removed)
- AI Coach eyebrow says `YOUR AI COACH` or title says `Good morning/afternoon/evening`
- Profile banner missing the floating `DOSSIER · OFFICER` overlay

## Reference

- Spec: `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §6
- Plan: `docs/superpowers/plans/2026-04-28-apk-test-5-plan-D-letterhead.md`
