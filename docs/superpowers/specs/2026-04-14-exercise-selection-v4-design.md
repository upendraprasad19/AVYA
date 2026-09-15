# Exercise Selection V4 & Profile Polish — Design Spec

**Date:** 2026-04-14
**Status:** Approved (brainstorm approval #1)
**Scope:** Exercise selection overhaul, profile UX polish, template/schedule fixes

---

## 1. Problem Statement

Testing revealed five interconnected failures in the plan generator:

1. **Curls on Back Day** — The broadening chain in `exercise_selector.dart` drops the `excludeMuscles` constraint on retry 2 (`dropExclude = true`), allowing bicep isolation exercises to fill back-focused slots.
2. **Blunt spec system** — `CSpec('Pull', 6, exclude: ['Biceps'])` treats all Pull exercises as interchangeable. A trainer thinks in muscle slots: "3 lat compounds, 1 rear delt, 2 bicep isolations."
3. **Equipment black holes** — Highly specific muscle slots with limited equipment tiers produce zero candidates. The system needs graceful cascading, not constraint abandonment.
4. **Week reset on days change** — Changing `daysPerWeek` in profile resets the workout schedule to Week 1, losing progress.
5. **Custom templates lack warmup/cooldown** — Templates bypass the plan engine, so Stage 7 (WarmupCooldownSelector) never runs.

Additionally, the profile screen has UX issues: no profile completeness tracking, oversized achievements section, experience level not displayed.

---

## 2. Design: Three Domains

### Domain A — Exercise Selection Overhaul
### Domain B — Profile & UX Polish
### Domain C — Template & Schedule Fixes

---

## 3. Domain A: Exercise Selection Overhaul

### 3.1 Movement Patterns (Safety Net)

Every exercise is tagged with one of 11 irreducible movement patterns. These form the unbreakable fallback — if a workout covers these bases over a week, it is objectively balanced regardless of specific exercises chosen.

**7 Base Patterns:**

| # | Pattern | Description | Fallback chain (Premium > Basic > Bodyweight) |
|---|---------|-------------|-----------------------------------------------|
| 1 | `horizontal_push` | Push away from torso (Chest, Front Delts, Triceps) | Machine Chest Press > DB Bench > Push-ups |
| 2 | `vertical_push` | Push overhead (Shoulders, Upper Chest, Triceps) | Seated DB Press > Barbell OHP > Pike Push-ups |
| 3 | `horizontal_pull` | Pull toward torso (Mid Back, Rhomboids, Biceps) | Seated Cable Row > DB Row > Inverted Row |
| 4 | `vertical_pull` | Pull from overhead (Lats, Biceps) | Lat Pulldown > Pull-ups > DB Pullover (floor) |
| 5 | `knee_dominant` | Max knee flexion (Quads, Glutes) | Hack Squat > DB Goblet Squat > BW Lunges |
| 6 | `hip_dominant` | Max hip flexion (Hams, Glutes, Lower Back) | Barbell RDL > DB RDL > Single-Leg Glute Bridge |
| 7 | `core` | Trunk flexion/stability (Abs, Obliques) | Cable Crunches > Plank > Deadbugs |

**4 Isolation Catch-All Patterns:**

| # | Pattern | Description |
|---|---------|-------------|
| 8 | `elbow_flexion` | Bicep isolation (curls) |
| 9 | `elbow_extension` | Tricep isolation (pushdowns, extensions) |
| 10 | `shoulder_isolation` | Lateral + rear delt isolation (lateral raises, face pulls, reverse flyes) |
| 11 | `hip_isolation` | Glute isolation (kickbacks, abductions) |

### 3.2 Exercise Library Enrichment

Every exercise in the 220+ library gains 6 new fields:

```json
{
  "name": "Lat Pulldown",
  "movement_pattern": "vertical_pull",
  "target_focus": "Lats (Width)",
  "equipment_tier": ["full_gym", "basic_gym"],
  "standard_swap": "Assisted Pull-ups",
  "rep_range": "8-12",
  "priority_tier": 1
}
```

| Field | Type | Values | Purpose |
|-------|------|--------|---------|
| `movement_pattern` | string | One of 11 patterns above | Cascade fallback grouping |
| `target_focus` | string | Granular muscle target (e.g., "Lats (Width)", "Biceps (Short Head)") | Muscle-slot matching |
| `equipment_tier` | string[] | Subset of: `bodyweight`, `home_dumbbells`, `basic_gym`, `full_gym` | Equipment-aware selection |
| `standard_swap` | string | Exercise name | Named alternative for equipment constraints |
| `rep_range` | string | e.g., "5-8", "8-12", "12-15" | Exercise-specific rep prescription |
| `priority_tier` | int | 1 (primary), 2 (secondary), 3 (accessory) | Volume filter cutoff |

### 3.3 Exercise Library Expansion

Add ~30-40 new exercises from the reference spreadsheets that fill gaps in our library:

**Back:** Pendlay Row, Seal Row (already exists), Machine High Row, Machine Low Row
**Chest:** Decline DB Press, Incline DB Flyes, Deficit Push-ups, Floor Press (DB variant)
**Shoulders:** Egyptian Lateral Raise, Poliquin Raises, Bradford Press, Cable Front Raises, Machine Lateral Raises
**Legs (Quads):** Pendulum Squat, Goblet Squat (already exists as BW Squat variant), Walking Lunges (short stride)
**Legs (Hams):** Nordic Hamstring Curls, Stiff-Legged Deadlift, Standing Single Leg Curl
**Legs (Glutes):** Kas Glute Bridge, B-Stance RDL, Deficit Reverse Lunges, Cable Pull-throughs, Frog Pumps, High Box Step-Ups, Hip Abductor Machine
**Triceps:** Bench Dips, Tate Press, Dumbbell Kickbacks
**Biceps:** Spider Curls (already exists), Rope Hammer Curls, High Cable Curls
**Core:** Captain's Chair Leg Raises, Lying Leg Raises, V-Ups, Bird-Dogs (may exist), Hollow Body Hold, Toe Touches, Flutter Kicks, Swiss Ball Crunches, Weighted Sit-ups, Side Plank

Exact count determined during enrichment — some may already exist under different names.

### 3.4 MuscleSlot Spec — Replaces CSpec

The split resolver outputs `MuscleSlot` objects instead of `CSpec`:

```dart
class MuscleSlot {
  final String targetMuscle;      // e.g., 'Lats', 'Biceps', 'Quads'
  final String? subFocus;         // e.g., 'width', 'short_head', 'thickness'
  final String movementPattern;   // e.g., 'vertical_pull'
  final String exerciseType;      // 'compound' | 'isolation'
  final int priority;             // 1, 2, or 3
  final int count;                // exercises to fill (usually 1)
}
```

**Example — 6-Day PPL Pull A (Lat Width Focus):**

```dart
[
  MuscleSlot(target: 'Lats', sub: 'width',     pattern: 'vertical_pull',  type: 'compound',  priority: 1, count: 1),
  MuscleSlot(target: 'Mid Back', sub: 'thickness', pattern: 'horizontal_pull', type: 'compound', priority: 1, count: 1),
  MuscleSlot(target: 'Lats', sub: 'lower',     pattern: 'vertical_pull',  type: 'compound',  priority: 2, count: 1),
  MuscleSlot(target: 'Rear Delts',              pattern: 'shoulder_isolation', type: 'isolation', priority: 2, count: 1),
  MuscleSlot(target: 'Biceps', sub: 'short_head', pattern: 'elbow_flexion', type: 'isolation', priority: 3, count: 1),
  MuscleSlot(target: 'Biceps', sub: 'brachialis', pattern: 'elbow_flexion', type: 'isolation', priority: 3, count: 1),
]
```

Priority is **hardcoded per split definition** — this is trainer wisdom that doesn't change. The CUTOFF (which priorities survive) is dynamic.

### 3.5 Volume Filter (New Stage 1.5)

A new mini-stage between split resolution and exercise selection. Trims `MuscleSlot` lists based on user constraints:

| Condition | Slots Kept |
|-----------|-----------|
| Advanced + 60+ min + hypertrophy | P1 + P2 + P3 (all) |
| Intermediate + 45 min | P1 + P2 |
| Beginner + any duration | P1 + max 1 P2 |
| 30 min (any experience) | P1 only |
| Deload week (any) | P1 only, reduced sets |

Session duration comes from user profile (new Tier 2 field, default 45 min if unset). Experience from `fitness_experience`. Phase archetype from periodization engine.

### 3.6 Cascading Exercise Selector (Rewrite)

For each surviving `MuscleSlot`, the selector cascades through increasingly broad queries:

```
Attempt 1 (Ideal):
  target_focus MATCHES slot.targetMuscle + slot.subFocus
  movement_pattern = slot.movementPattern
  exercise_type = slot.exerciseType
  equipment_tier CONTAINS user.equipment
  suitable_for CONTAINS user.experience (unless advanced)
  NOT IN already_selected
  NOT IN user.injuries (via injury_contraindications)

Attempt 2 (Broader target):
  target_focus CONTAINS slot.targetMuscle (drop subFocus)
  movement_pattern = slot.movementPattern  ← KEPT
  (other filters same)

Attempt 3 (Any in movement pattern):
  movement_pattern = slot.movementPattern  ← KEPT
  DROP target_focus filter
  DROP exercise_type filter (compound OR isolation)
  (equipment + experience filters same)

Attempt 4 (Equipment fallback):
  movement_pattern = slot.movementPattern  ← KEPT
  DROP equipment filter (bodyweight exercises only)
  (experience filter same)

Attempt 5 (Universal bodyweight pool):
  Hardcoded bodyweight exercise for this movement pattern
  (Same as current _universalPool but keyed by movement_pattern)
```

**Critical rule: `movement_pattern` is NEVER dropped.** A vertical_pull slot will never be filled with a horizontal_push exercise. This is the unbreakable safety net.

### 3.7 UI Masking by Experience Level

The exercise engine uses granular `target_focus` internally, but the display adapts to the user's experience level:

| Experience | Display Format | Example |
|-----------|---------------|---------|
| Beginner | Category only | "Back: Lat Pulldown" |
| Intermediate | Muscle group | "Lats: Lat Pulldown" |
| Advanced | Muscle + focus | "Lats (Width): Wide Grip Lat Pulldown" |

Implementation: a display formatter function that reads `target_focus` from the exercise data and the user's `fitness_experience` from profile. Applied in the workout plan UI (train screen, planned day view), NOT in the data layer.

### 3.8 Pipeline Update

The V4 pipeline stages:

```
Stage 0: Progression Resolver   (unchanged — reads Hive logs for weight suggestions)
Stage 1: Split Resolver          (REWRITTEN — outputs MuscleSlot[] instead of CSpec[])
Stage 1.5: Volume Filter         (NEW — trims slots by session_duration + experience + phase)
Stage 2: Exercise Selector       (REWRITTEN — cascading within movement patterns)
Stage 3: Sequencing Engine       (minor update — orders by priority then compound-first)
Stage 4: Periodization Engine    (update — uses exercise-specific rep_range + priority_tier for set/rep assignment)
Stage 5: Superset Pairer         (unchanged)
Stage 6: Cardio Finisher         (unchanged)
Stage 7: Warmup/Cooldown         (unchanged, but now also callable for custom templates — see C1)
```

### 3.9 Validation After Enrichment

After enriching 220+ exercises with new fields:

1. **Automated script:** Every exercise must have all 6 new fields, no nulls. `movement_pattern` must be one of 11 valid values. `equipment_tier` must be non-empty array of valid tiers. `priority_tier` must be 1, 2, or 3.
2. **Coverage matrix:** For each `equipment_tier × movement_pattern` combo, verify minimum 3 candidate exercises. Flag gaps.
3. **Manual spot-check:** For each of the 11 movement patterns, verify top 5 exercises are correctly classified.
4. **Unit tests:** Extend `plan_engine_v3_test.dart` with V4-specific tests for cascading, volume filter, muscle slot selection.

---

## 4. Domain B: Profile & UX Polish

### 4.1 Profile Completeness Card — Home Screen

**Position:** Between Quick Actions (#7) and AI Coach Insight (#8) in the home ListView.

**Behavior:**
- Shows the single highest-impact missing Tier 2 field
- Benefit-focused copy: "Add your session duration for plans that fit your schedule →"
- Dismissible (X button), resurfaces after 3 days with the next missing field
- Never shows if user is mid-workout (active workout state)
- Disappears permanently when all Tier 2 fields are filled

**Tier 2 fields (ordered by plan impact):**
1. Session duration — "Get plans sized for your schedule"
2. Physique focus — "Bias workouts toward your goals"
3. Injuries — "Avoid exercises that could hurt you"
4. Target weight — "Unlock weight projection"
5. Body fat % — "Get more accurate calorie targets"
6. Pace preference — "Control how fast you cut or bulk"

**Design:** Slim card, `AppColors.card` bg, `AppColors.border` border, ~44px height. Left-aligned benefit text, right-aligned "→" chevron. X dismiss button top-right.

### 4.2 Profile Completeness Card — Profile Screen

**Position:** Between name/subtitle row and Daily Goals (Placement 2).

**Behavior:**
- Slim card showing "Profile XX%" + mini progress bar + highest-impact CTA
- Tapping the CTA → navigates to edit profile
- Tapping the card body → opens bottom sheet listing all missing fields with benefit copy
- Each item in sheet is tappable → goes to edit profile scrolled to that section
- Disappears when profile >= 100% or all Tier 2 complete

**Completeness calculation:**
- Tier 1 (onboarding fields): 60% weight (already filled for all users)
- Tier 2 (enhanced plan fields): 40% weight (6 fields × ~6.7% each)
- Formula: `(filledTier1Count / totalTier1 × 60) + (filledTier2Count / totalTier2 × 40)`

### 4.3 Achievements Slim Card

**Remove:** `CompactAchievementsRow` from `ProfileIdentity` banner overlap.

Banner overlap row becomes:
```
[Avatar 80px]                              [PRO pill]
```

**Replace:** Current `_CollapsibleBadgesSection` with a slim single-line card below Daily Goals.

```
┌──────────────────────────────────────────────┐
│ 🏆 Achievements   [🏃] [💪] [🤖] [⭐]  4/15  ▾ │
└──────────────────────────────────────────────┘
```

- Left: "Achievements" label
- Middle: last 3-4 earned badge icons (most recent first)
- Right: earned/total count + chevron
- Tap chevron → opens full badges grid in bottom sheet (reuses existing `BadgesGrid`)
- ~44px height, `AppColors.card` bg

### 4.4 Experience Level Display

- Show `fitness_experience` on profile screen in the subtitle under name: "Phase 1 · Week 1 · Intermediate · Build Muscle"
- Make editable in edit profile screen (currently stored but no UI input)

---

## 5. Domain C: Template & Schedule Fixes

### 5.1 Custom Template Warmup/Cooldown Auto-Inject

When a custom template is scheduled via `WorkoutScheduleService`:

1. Detect the template's muscle focus by analyzing exercise categories/primary_muscles
2. Run `WarmupCooldownSelector` (Stage 7) with the detected focus
3. Append warmup and cooldown exercises to the scheduled workout
4. Mark them as `auto_generated: true` in the schedule entry

**Planned day view:**
```
WARM-UP 4        ▾  (collapsible, "auto" tag)
WORKOUT 5            (user's template exercises)
COOL-DOWN 4      ▾  (collapsible, "auto" tag)
```

User can collapse/expand warmup/cooldown sections. Auto-generated tag distinguishes from manually added exercises. No removal UI needed for MVP — user can simply skip them.

### 5.2 Week Reset Bug Fix

**Root cause:** `generateAndScheduleFromDate()` normalizes to current Monday and recalculates week numbers from that point, treating it as Week 1.

**Fix:** When rescheduling due to `daysPerWeek` change (not a full plan regeneration):
1. Read the existing plan start date from Hive (`plan_start_date` key)
2. Calculate current week number from that original start date
3. Delete only future non-completed schedule entries from today onward
4. Regenerate from today using the new `daysPerWeek` but preserving the original plan start date
5. Week number calculation continues from the original start

Only reset to Week 1 when:
- User explicitly triggers "Generate New Plan"
- Phase transition (Week 4 → new phase)
- First-time plan generation

### 5.3 Broadening Bug Fix

This is inherently solved by the cascading selector (A5). The current `_broadenSelection` method with `dropExclude = true` on retry 2 is entirely replaced. The new cascade NEVER drops the `movement_pattern` constraint, so bicep curls cannot contaminate a back slot.

If Domain A ships before Domain C, a quick interim fix can patch `_broadenSelection` to never set `dropExclude = true` for the `excludeMuscles` parameter. But the full cascade replacement is the proper solution.

---

## 6. New Profile Fields

Two new fields stored in Hive `userBox`:

| Field | Key | Type | Default | UI Location |
|-------|-----|------|---------|-------------|
| Session duration | `session_duration_minutes` | int | 45 | Edit profile (Fitness section) |
| Physique focus | `physique_focus` | string | 'balanced' | Edit profile (Fitness section) |

**Session duration options:** 30, 45, 60, 90 (minutes)
**Physique focus options:** 'balanced', 'glutes_legs', 'chest_shoulders_arms', 'strength'

These are Tier 2 profile fields — not collected at onboarding, nudged via profile completeness cards.

---

## 7. Deferred Items

| Item | Reason | When |
|------|--------|------|
| Swap Engine (real-time exercise swap UI) | Independent system, needs its own spec | Next batch |
| Variable manipulation (tempo/unilateral progression) | Periodization enhancement | Phase 2 |
| Granular equipment checkboxes | Gathered via profile completeness flow | After profile card ships |
| Exercise blacklist | Needs Swap Engine first | After Swap Engine |
| Onboarding flow changes | Keep lean, new fields post-onboarding | Not planned |
| Day swap discoverability | Already implemented (long-press), needs tooltip/onboarding hint | UX polish batch |

---

## 8. Split Definitions (Muscle Slot Specs)

Full muscle slot definitions for all splits (3/4/5/6 day × 4 goals) will be defined during implementation. The pattern for each follows the reference spreadsheets:

**Pull/Back days:** 3 back compounds (P1-P2) → 1 rear delt (P2) → 1-2 bicep isolations (P3)
**Push/Chest days:** 2-3 chest compounds (P1) → 1-2 shoulder (P1-P2) → 1 tricep isolation (P3)
**Leg days:** 2-3 quad/ham compounds (P1) → 1 isolation (P2) → 1 calf (P2-P3) → optional core (P3)
**Upper days:** 1 chest + 1 back compound (P1) → 1 shoulder + 1 lat (P2) → 1 arm superset (P3)
**Full Body (beginner):** 1 push + 1 pull + 1 legs + 1 core (all P1) → 1 extra based on day focus (P2)

The universal ratio is ~60% primary muscle compounds (P1), ~20% secondary muscle (P2), ~20% small muscle isolation (P3).

---

## 9. Files Affected (Estimated)

| File | Change |
|------|--------|
| `assets/data/exercise_library.json` | Enrich 220+ exercises with 6 new fields + add ~30-40 new exercises |
| `lib/shared/repositories/plan_engine/models.dart` | Add `MuscleSlot` class, update `PlannedExercise` |
| `lib/shared/repositories/plan_engine/split_resolver.dart` | Rewrite all splits to output `MuscleSlot[]` |
| `lib/shared/repositories/plan_engine/exercise_selector.dart` | Rewrite with cascading movement-pattern-aware selection |
| `lib/shared/repositories/plan_engine/plan_generator.dart` | Add Volume Filter stage, thread `session_duration` |
| `lib/shared/repositories/plan_engine/sequencing_engine.dart` | Minor — order by priority then compound-first |
| `lib/shared/repositories/plan_engine/periodization_engine.dart` | Use exercise-specific `rep_range` and `priority_tier` |
| `lib/shared/repositories/exercise_repository.dart` | Add query support for `movement_pattern`, `target_focus`, `equipment_tier` |
| `lib/core/services/workout_schedule_service.dart` | Fix week reset, thread session_duration, auto-inject warmup for templates |
| `lib/features/home/screens/home_screen.dart` | Add profile completeness card |
| `lib/features/home/widgets/profile_nudge_card.dart` | NEW — slim nudge card widget |
| `lib/features/profile/screens/profile_screen.dart` | Add profile completeness card, slim achievements, experience display |
| `lib/features/profile/widgets/profile_identity.dart` | Remove CompactAchievementsRow from banner overlap |
| `lib/features/profile/widgets/slim_achievements_card.dart` | NEW — single-line achievements widget |
| `lib/features/profile/screens/edit_profile_screen.dart` | Add session duration + physique focus fields, add experience level |
| `lib/features/profile/providers/profile_provider.dart` | Add completeness calculation provider |
| `lib/features/train/screens/` | UI masking by experience level |
| `test/plan_engine_v4_test.dart` | NEW — V4-specific tests |

---

## 10. Success Criteria

1. A 5-day build_muscle Back day produces: 3 lat/back compounds + 1 rear delt + 1-2 bicep isolations — never 3 curls
2. A `home_dumbbells` user gets a complete 5-exercise workout with zero empty slots
3. Changing daysPerWeek from 6→5 preserves the current week number
4. Custom templates show warmup/cooldown when scheduled
5. Profile completeness card appears on home and profile when Tier 2 fields are missing
6. Achievements section takes ~44px instead of ~180px on profile
7. All 220+ exercises pass automated validation for new fields
8. Coverage matrix shows >= 3 candidates for every equipment_tier × movement_pattern combo
