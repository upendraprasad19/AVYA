# V4 Diagnostic — 2026-05-01

Run from: `flutter test test/plan_generator/v4_diagnostic_test.dart`

## Library integrity pre-check

**Triplet counts** (movement_pattern × equipment_tier × suitable_for × foundational-only)

| movement_pattern | equipment_tier | suitable_for | foundational | count |
|---|---|---|---|---|
| horizontal_push | bodyweight | beginner | true | 2 |
| horizontal_push | bodyweight | beginner | false | 4 |
| horizontal_push | bodyweight | intermediate | true | 2 |
| horizontal_push | bodyweight | intermediate | false | 5 |
| horizontal_push | bodyweight | advanced | true | 1 |
| horizontal_push | bodyweight | advanced | false | 4 |
| horizontal_push | home_dumbbells | beginner | true | 4 |
| horizontal_push | home_dumbbells | beginner | false | 6 |
| horizontal_push | home_dumbbells | intermediate | true | 5 |
| horizontal_push | home_dumbbells | intermediate | false | 11 |
| horizontal_push | home_dumbbells | advanced | true | 4 |
| horizontal_push | home_dumbbells | advanced | false | 10 |
| horizontal_push | basic_gym | beginner | true | 6 |
| horizontal_push | basic_gym | beginner | false | 8 |
| horizontal_push | basic_gym | intermediate | true | 8 |
| horizontal_push | basic_gym | intermediate | false | 17 |
| horizontal_push | basic_gym | advanced | true | 7 |
| horizontal_push | basic_gym | advanced | false | 17 |
| horizontal_push | full_gym | beginner | true | 7 |
| horizontal_push | full_gym | beginner | false | 11 |
| horizontal_push | full_gym | intermediate | true | 9 |
| horizontal_push | full_gym | intermediate | false | 23 |
| horizontal_push | full_gym | advanced | true | 8 |
| horizontal_push | full_gym | advanced | false | 23 |
| vertical_push | bodyweight | beginner | true | 1 |
| vertical_push | bodyweight | beginner | false | 1 |
| vertical_push | bodyweight | intermediate | true | 1 |
| vertical_push | bodyweight | intermediate | false | 1 |
| vertical_push | bodyweight | advanced | true | 0 ⚠️ |
| vertical_push | bodyweight | advanced | false | 0 ⚠️ |
| vertical_push | home_dumbbells | beginner | true | 3 |
| vertical_push | home_dumbbells | beginner | false | 4 |
| vertical_push | home_dumbbells | intermediate | true | 4 |
| vertical_push | home_dumbbells | intermediate | false | 6 |
| vertical_push | home_dumbbells | advanced | true | 3 |
| vertical_push | home_dumbbells | advanced | false | 4 |
| vertical_push | basic_gym | beginner | true | 4 |
| vertical_push | basic_gym | beginner | false | 5 |
| vertical_push | basic_gym | intermediate | true | 5 |
| vertical_push | basic_gym | intermediate | false | 7 |
| vertical_push | basic_gym | advanced | true | 4 |
| vertical_push | basic_gym | advanced | false | 5 |
| vertical_push | full_gym | beginner | true | 4 |
| vertical_push | full_gym | beginner | false | 5 |
| vertical_push | full_gym | intermediate | true | 6 |
| vertical_push | full_gym | intermediate | false | 10 |
| vertical_push | full_gym | advanced | true | 5 |
| vertical_push | full_gym | advanced | false | 10 |
| horizontal_pull | bodyweight | beginner | true | 1 |
| horizontal_pull | bodyweight | beginner | false | 1 |
| horizontal_pull | bodyweight | intermediate | true | 1 |
| horizontal_pull | bodyweight | intermediate | false | 1 |
| horizontal_pull | bodyweight | advanced | true | 0 ⚠️ |
| horizontal_pull | bodyweight | advanced | false | 0 ⚠️ |
| horizontal_pull | home_dumbbells | beginner | true | 1 |
| horizontal_pull | home_dumbbells | beginner | false | 2 |
| horizontal_pull | home_dumbbells | intermediate | true | 1 |
| horizontal_pull | home_dumbbells | intermediate | false | 3 |
| horizontal_pull | home_dumbbells | advanced | true | 1 |
| horizontal_pull | home_dumbbells | advanced | false | 3 |
| horizontal_pull | basic_gym | beginner | true | 3 |
| horizontal_pull | basic_gym | beginner | false | 5 |
| horizontal_pull | basic_gym | intermediate | true | 4 |
| horizontal_pull | basic_gym | intermediate | false | 8 |
| horizontal_pull | basic_gym | advanced | true | 4 |
| horizontal_pull | basic_gym | advanced | false | 8 |
| horizontal_pull | full_gym | beginner | true | 5 |
| horizontal_pull | full_gym | beginner | false | 8 |
| horizontal_pull | full_gym | intermediate | true | 6 |
| horizontal_pull | full_gym | intermediate | false | 14 |
| horizontal_pull | full_gym | advanced | true | 5 |
| horizontal_pull | full_gym | advanced | false | 13 |
| vertical_pull | bodyweight | beginner | true | 0 ⚠️ |
| vertical_pull | bodyweight | beginner | false | 0 ⚠️ |
| vertical_pull | bodyweight | intermediate | true | 0 ⚠️ |
| vertical_pull | bodyweight | intermediate | false | 0 ⚠️ |
| vertical_pull | bodyweight | advanced | true | 0 ⚠️ |
| vertical_pull | bodyweight | advanced | false | 0 ⚠️ |
| vertical_pull | home_dumbbells | beginner | true | 1 |
| vertical_pull | home_dumbbells | beginner | false | 1 |
| vertical_pull | home_dumbbells | intermediate | true | 2 |
| vertical_pull | home_dumbbells | intermediate | false | 3 |
| vertical_pull | home_dumbbells | advanced | true | 2 |
| vertical_pull | home_dumbbells | advanced | false | 5 |
| vertical_pull | basic_gym | beginner | true | 2 |
| vertical_pull | basic_gym | beginner | false | 4 |
| vertical_pull | basic_gym | intermediate | true | 3 |
| vertical_pull | basic_gym | intermediate | false | 6 |
| vertical_pull | basic_gym | advanced | true | 3 |
| vertical_pull | basic_gym | advanced | false | 8 |
| vertical_pull | full_gym | beginner | true | 2 |
| vertical_pull | full_gym | beginner | false | 4 |
| vertical_pull | full_gym | intermediate | true | 3 |
| vertical_pull | full_gym | intermediate | false | 7 |
| vertical_pull | full_gym | advanced | true | 3 |
| vertical_pull | full_gym | advanced | false | 9 |
| knee_dominant | bodyweight | beginner | true | 2 |
| knee_dominant | bodyweight | beginner | false | 5 |
| knee_dominant | bodyweight | intermediate | true | 3 |
| knee_dominant | bodyweight | intermediate | false | 11 |
| knee_dominant | bodyweight | advanced | true | 3 |
| knee_dominant | bodyweight | advanced | false | 15 |
| knee_dominant | home_dumbbells | beginner | true | 0 ⚠️ |
| knee_dominant | home_dumbbells | beginner | false | 2 |
| knee_dominant | home_dumbbells | intermediate | true | 0 ⚠️ |
| knee_dominant | home_dumbbells | intermediate | false | 7 |
| knee_dominant | home_dumbbells | advanced | true | 0 ⚠️ |
| knee_dominant | home_dumbbells | advanced | false | 9 |
| knee_dominant | basic_gym | beginner | true | 0 ⚠️ |
| knee_dominant | basic_gym | beginner | false | 3 |
| knee_dominant | basic_gym | intermediate | true | 1 |
| knee_dominant | basic_gym | intermediate | false | 9 |
| knee_dominant | basic_gym | advanced | true | 1 |
| knee_dominant | basic_gym | advanced | false | 13 |
| knee_dominant | full_gym | beginner | true | 9 |
| knee_dominant | full_gym | beginner | false | 14 |
| knee_dominant | full_gym | intermediate | true | 16 |
| knee_dominant | full_gym | intermediate | false | 27 |
| knee_dominant | full_gym | advanced | true | 16 |
| knee_dominant | full_gym | advanced | false | 34 |
| hip_dominant | bodyweight | beginner | true | 0 ⚠️ |
| hip_dominant | bodyweight | beginner | false | 0 ⚠️ |
| hip_dominant | bodyweight | intermediate | true | 0 ⚠️ |
| hip_dominant | bodyweight | intermediate | false | 0 ⚠️ |
| hip_dominant | bodyweight | advanced | true | 0 ⚠️ |
| hip_dominant | bodyweight | advanced | false | 2 |
| hip_dominant | home_dumbbells | beginner | true | 0 ⚠️ |
| hip_dominant | home_dumbbells | beginner | false | 1 |
| hip_dominant | home_dumbbells | intermediate | true | 0 ⚠️ |
| hip_dominant | home_dumbbells | intermediate | false | 4 |
| hip_dominant | home_dumbbells | advanced | true | 0 ⚠️ |
| hip_dominant | home_dumbbells | advanced | false | 4 |
| hip_dominant | basic_gym | beginner | true | 0 ⚠️ |
| hip_dominant | basic_gym | beginner | false | 2 |
| hip_dominant | basic_gym | intermediate | true | 2 |
| hip_dominant | basic_gym | intermediate | false | 9 |
| hip_dominant | basic_gym | advanced | true | 2 |
| hip_dominant | basic_gym | advanced | false | 11 |
| hip_dominant | full_gym | beginner | true | 0 ⚠️ |
| hip_dominant | full_gym | beginner | false | 5 |
| hip_dominant | full_gym | intermediate | true | 3 |
| hip_dominant | full_gym | intermediate | false | 15 |
| hip_dominant | full_gym | advanced | true | 3 |
| hip_dominant | full_gym | advanced | false | 20 |
| core | bodyweight | beginner | true | 6 |
| core | bodyweight | beginner | false | 10 |
| core | bodyweight | intermediate | true | 7 |
| core | bodyweight | intermediate | false | 15 |
| core | bodyweight | advanced | true | 7 |
| core | bodyweight | advanced | false | 15 |
| core | home_dumbbells | beginner | true | 2 |
| core | home_dumbbells | beginner | false | 7 |
| core | home_dumbbells | intermediate | true | 4 |
| core | home_dumbbells | intermediate | false | 12 |
| core | home_dumbbells | advanced | true | 4 |
| core | home_dumbbells | advanced | false | 15 |
| core | basic_gym | beginner | true | 4 |
| core | basic_gym | beginner | false | 9 |
| core | basic_gym | intermediate | true | 6 |
| core | basic_gym | intermediate | false | 15 |
| core | basic_gym | advanced | true | 6 |
| core | basic_gym | advanced | false | 18 |
| core | full_gym | beginner | true | 8 |
| core | full_gym | beginner | false | 17 |
| core | full_gym | intermediate | true | 11 |
| core | full_gym | intermediate | false | 29 |
| core | full_gym | advanced | true | 11 |
| core | full_gym | advanced | false | 38 |
| elbow_flexion | bodyweight | beginner | true | 0 ⚠️ |
| elbow_flexion | bodyweight | beginner | false | 0 ⚠️ |
| elbow_flexion | bodyweight | intermediate | true | 0 ⚠️ |
| elbow_flexion | bodyweight | intermediate | false | 0 ⚠️ |
| elbow_flexion | bodyweight | advanced | true | 0 ⚠️ |
| elbow_flexion | bodyweight | advanced | false | 0 ⚠️ |
| elbow_flexion | home_dumbbells | beginner | true | 3 |
| elbow_flexion | home_dumbbells | beginner | false | 3 |
| elbow_flexion | home_dumbbells | intermediate | true | 3 |
| elbow_flexion | home_dumbbells | intermediate | false | 3 |
| elbow_flexion | home_dumbbells | advanced | true | 3 |
| elbow_flexion | home_dumbbells | advanced | false | 3 |
| elbow_flexion | basic_gym | beginner | true | 5 |
| elbow_flexion | basic_gym | beginner | false | 6 |
| elbow_flexion | basic_gym | intermediate | true | 5 |
| elbow_flexion | basic_gym | intermediate | false | 9 |
| elbow_flexion | basic_gym | advanced | true | 5 |
| elbow_flexion | basic_gym | advanced | false | 9 |
| elbow_flexion | full_gym | beginner | true | 5 |
| elbow_flexion | full_gym | beginner | false | 8 |
| elbow_flexion | full_gym | intermediate | true | 6 |
| elbow_flexion | full_gym | intermediate | false | 12 |
| elbow_flexion | full_gym | advanced | true | 6 |
| elbow_flexion | full_gym | advanced | false | 12 |
| elbow_extension | bodyweight | beginner | true | 0 ⚠️ |
| elbow_extension | bodyweight | beginner | false | 1 |
| elbow_extension | bodyweight | intermediate | true | 0 ⚠️ |
| elbow_extension | bodyweight | intermediate | false | 1 |
| elbow_extension | bodyweight | advanced | true | 0 ⚠️ |
| elbow_extension | bodyweight | advanced | false | 0 ⚠️ |
| elbow_extension | home_dumbbells | beginner | true | 1 |
| elbow_extension | home_dumbbells | beginner | false | 3 |
| elbow_extension | home_dumbbells | intermediate | true | 1 |
| elbow_extension | home_dumbbells | intermediate | false | 3 |
| elbow_extension | home_dumbbells | advanced | true | 1 |
| elbow_extension | home_dumbbells | advanced | false | 2 |
| elbow_extension | basic_gym | beginner | true | 2 |
| elbow_extension | basic_gym | beginner | false | 7 |
| elbow_extension | basic_gym | intermediate | true | 3 |
| elbow_extension | basic_gym | intermediate | false | 9 |
| elbow_extension | basic_gym | advanced | true | 3 |
| elbow_extension | basic_gym | advanced | false | 8 |
| elbow_extension | full_gym | beginner | true | 2 |
| elbow_extension | full_gym | beginner | false | 7 |
| elbow_extension | full_gym | intermediate | true | 3 |
| elbow_extension | full_gym | intermediate | false | 9 |
| elbow_extension | full_gym | advanced | true | 3 |
| elbow_extension | full_gym | advanced | false | 8 |
| shoulder_isolation | bodyweight | beginner | true | 0 ⚠️ |
| shoulder_isolation | bodyweight | beginner | false | 0 ⚠️ |
| shoulder_isolation | bodyweight | intermediate | true | 0 ⚠️ |
| shoulder_isolation | bodyweight | intermediate | false | 0 ⚠️ |
| shoulder_isolation | bodyweight | advanced | true | 0 ⚠️ |
| shoulder_isolation | bodyweight | advanced | false | 0 ⚠️ |
| shoulder_isolation | home_dumbbells | beginner | true | 2 |
| shoulder_isolation | home_dumbbells | beginner | false | 2 |
| shoulder_isolation | home_dumbbells | intermediate | true | 2 |
| shoulder_isolation | home_dumbbells | intermediate | false | 2 |
| shoulder_isolation | home_dumbbells | advanced | true | 2 |
| shoulder_isolation | home_dumbbells | advanced | false | 2 |
| shoulder_isolation | basic_gym | beginner | true | 3 |
| shoulder_isolation | basic_gym | beginner | false | 5 |
| shoulder_isolation | basic_gym | intermediate | true | 3 |
| shoulder_isolation | basic_gym | intermediate | false | 6 |
| shoulder_isolation | basic_gym | advanced | true | 3 |
| shoulder_isolation | basic_gym | advanced | false | 6 |
| shoulder_isolation | full_gym | beginner | true | 4 |
| shoulder_isolation | full_gym | beginner | false | 7 |
| shoulder_isolation | full_gym | intermediate | true | 4 |
| shoulder_isolation | full_gym | intermediate | false | 8 |
| shoulder_isolation | full_gym | advanced | true | 4 |
| shoulder_isolation | full_gym | advanced | false | 8 |
| hip_isolation | bodyweight | beginner | true | 1 |
| hip_isolation | bodyweight | beginner | false | 4 |
| hip_isolation | bodyweight | intermediate | true | 1 |
| hip_isolation | bodyweight | intermediate | false | 4 |
| hip_isolation | bodyweight | advanced | true | 1 |
| hip_isolation | bodyweight | advanced | false | 4 |
| hip_isolation | home_dumbbells | beginner | true | 0 ⚠️ |
| hip_isolation | home_dumbbells | beginner | false | 3 |
| hip_isolation | home_dumbbells | intermediate | true | 0 ⚠️ |
| hip_isolation | home_dumbbells | intermediate | false | 3 |
| hip_isolation | home_dumbbells | advanced | true | 0 ⚠️ |
| hip_isolation | home_dumbbells | advanced | false | 3 |
| hip_isolation | basic_gym | beginner | true | 0 ⚠️ |
| hip_isolation | basic_gym | beginner | false | 4 |
| hip_isolation | basic_gym | intermediate | true | 0 ⚠️ |
| hip_isolation | basic_gym | intermediate | false | 4 |
| hip_isolation | basic_gym | advanced | true | 0 ⚠️ |
| hip_isolation | basic_gym | advanced | false | 4 |
| hip_isolation | full_gym | beginner | true | 1 |
| hip_isolation | full_gym | beginner | false | 9 |
| hip_isolation | full_gym | intermediate | true | 1 |
| hip_isolation | full_gym | intermediate | false | 10 |
| hip_isolation | full_gym | advanced | true | 1 |
| hip_isolation | full_gym | advanced | false | 10 |

**Equipment tier unique values:** `basic_gym`, `bodyweight`, `full_gym`, `home_dumbbells`

## Combo: bug-repro baseline (advanced/full_gym/build_muscle/5d/P1/sd=null)

**INPUT:**
- goal=build_muscle
- equipment=full_gym
- daysPerWeek=5
- experience=advanced
- phase=1
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=full_gym

### Week baseline

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

---

## Combo: beginner/bodyweight/general_fitness/3d/P1

**INPUT:**
- goal=general_fitness
- equipment=bodyweight
- daysPerWeek=3
- experience=beginner
- phase=1
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=beginner
- equipmentTier=bodyweight

### Week baseline

#### Day "Full Body A" (full_body, strength)

**Variant A**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_push, eq=bodyweight, suit=beginner, excluded=1): 1 → [Pike Push Up]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Pike Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Pike Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Pike Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Pike Push Up, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (5): Push Up, Pike Push Up, Inverted Row, Walking Lunge, Russian Twist
  - A1 (mp=elbow_extension, tm="Triceps", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=bodyweight, type=isolation, suit=beginner, excluded=5): 0
  - A3 (mp=elbow_extension, eq=bodyweight, suit=beginner, excluded=5): 1 → [Bench Dips]
  - A4 (mp=elbow_extension, suit=beginner, excluded=5): 7 → [Bench Dips, Tricep Pushdown (Cable), Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Bench Dips (attempt3DropTypeAndTarget)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_push, eq=bodyweight, suit=beginner, excluded=1): 1 → [Pike Push Up]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Pike Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Pike Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Pike Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Pike Push Up, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (5): Push Up, Pike Push Up, Inverted Row, Walking Lunge, Russian Twist
  - A1 (mp=elbow_extension, tm="Triceps", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=bodyweight, type=isolation, suit=beginner, excluded=5): 0
  - A3 (mp=elbow_extension, eq=bodyweight, suit=beginner, excluded=5): 1 → [Bench Dips]
  - A4 (mp=elbow_extension, suit=beginner, excluded=5): 7 → [Bench Dips, Tricep Pushdown (Cable), Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Bench Dips (attempt3DropTypeAndTarget)

#### Day "Full Body B" (full_body, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Biceps/elbow_flexion/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_pull, eq=bodyweight, suit=beginner, excluded=1): 0
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt4DropEquipment)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Lat Pulldown, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Lat Pulldown, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Push Up, Lat Pulldown, Inverted Row, Walking Lunge, Russian Twist
  - A1 (mp=elbow_flexion, tm="Biceps", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=bodyweight, type=isolation, suit=beginner, excluded=5): 0
  - A3 (mp=elbow_flexion, eq=bodyweight, suit=beginner, excluded=5): 0
  - A4 (mp=elbow_flexion, suit=beginner, excluded=5): 8 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt4DropEquipment)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Biceps/elbow_flexion/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_pull, eq=bodyweight, suit=beginner, excluded=1): 0
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt4DropEquipment)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Lat Pulldown, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Lat Pulldown, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Push Up, Lat Pulldown, Inverted Row, Walking Lunge, Russian Twist
  - A1 (mp=elbow_flexion, tm="Biceps", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=bodyweight, type=isolation, suit=beginner, excluded=5): 0
  - A3 (mp=elbow_flexion, eq=bodyweight, suit=beginner, excluded=5): 0
  - A4 (mp=elbow_flexion, suit=beginner, excluded=5): 8 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt4DropEquipment)

#### Day "Full Body C" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2, Calves/knee_dominant/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=2): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=2): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Push Up, Inverted Row, Walking Lunge
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, excluded=3): 0
  - A3 (mp=hip_dominant, eq=bodyweight, suit=beginner, excluded=3): 0
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 5 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Hyperextension]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt4DropEquipment)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Inverted Row, Walking Lunge, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (5): Push Up, Inverted Row, Walking Lunge, Trap Bar Deadlift, Russian Twist
  - A1 (mp=knee_dominant, tm="Calves", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=bodyweight, type=isolation, suit=beginner, excluded=5): 1 → [Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=5): 4 → [Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=5): 13 → [Goblet Squat, Leg Press, Step Up, Reverse Lunge, Sumo Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Donkey Calf Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2, Calves/knee_dominant/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=2): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=2): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Push Up, Inverted Row, Walking Lunge
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, excluded=3): 0
  - A3 (mp=hip_dominant, eq=bodyweight, suit=beginner, excluded=3): 0
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 5 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Hyperextension]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt4DropEquipment)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Inverted Row, Walking Lunge, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (5): Push Up, Inverted Row, Walking Lunge, Trap Bar Deadlift, Russian Twist
  - A1 (mp=knee_dominant, tm="Calves", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=bodyweight, type=isolation, suit=beginner, excluded=5): 1 → [Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=5): 4 → [Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=5): 13 → [Goblet Squat, Leg Press, Step Up, Reverse Lunge, Sumo Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Donkey Calf Raise (attempt2DropSubFocus)

---

## Combo: intermediate/home_dumbbells/lose_fat/4d/P2

**INPUT:**
- goal=lose_fat
- equipment=home_dumbbells
- daysPerWeek=4
- experience=intermediate
- phase=2
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=intermediate
- equipmentTier=home_dumbbells

### Week baseline

#### Day "Upper Push" (push, strength)

**Variant A**

- PRE-VolumeFilter: 9 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Rear Delts/shoulder_isolation/isolation/P4, Core/core/isolation/P5
- POST-VolumeFilter: 7 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4
  - ⚠️ Dropped by VolumeFilter: Rear Delts/shoulder_isolation/isolation/P4, Core/core/isolation/P5

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate): 11 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A4 (mp=horizontal_push, suit=intermediate): 23 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Dumbbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A3 (mp=vertical_push, eq=home_dumbbells, suit=intermediate, excluded=1): 6 → [Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press, Pike Push Up]
  - A4 (mp=vertical_push, suit=intermediate, excluded=1): 10 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P2
  - excludeNames-in (2): Dumbbell Bench Press, Dumbbell Shoulder Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate, excluded=2): 10 → [Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=intermediate, excluded=2): 22 → [Barbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Single Arm Dumbbell Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 1 → [Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=home_dumbbells, suit=intermediate, excluded=3): 2 → [Lateral Raise, Band Pull Apart]
  - A4 (mp=shoulder_isolation, suit=intermediate, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 2 → [Overhead Tricep Extension, Dumbbell Kickback]
  - A2 (mp=elbow_extension, tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 2 → [Overhead Tricep Extension, Dumbbell Kickback]
  - A3 (mp=elbow_extension, eq=home_dumbbells, suit=intermediate, excluded=4): 3 → [Bench Dips, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=intermediate, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Overhead Tricep Extension (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P3
  - excludeNames-in (5): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press, Lateral Raise, Overhead Tricep Extension
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 1 → [Dumbbell Fly]
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate, excluded=5): 9 → [Chest Squeeze Press, Deficit Push-Up, Floor Press, Push Up, Diamond Push Up]
  - A4 (mp=horizontal_push, suit=intermediate, excluded=5): 21 → [Barbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press, Lateral Raise, Overhead Tricep Extension, Dumbbell Fly
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 1 → [Dumbbell Kickback]
  - A3 (mp=elbow_extension, eq=home_dumbbells, suit=intermediate, excluded=6): 2 → [Bench Dips, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=intermediate, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Dumbbell Kickback (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 9 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Rear Delts/shoulder_isolation/isolation/P4, Core/core/isolation/P5
- POST-VolumeFilter: 7 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4
  - ⚠️ Dropped by VolumeFilter: Rear Delts/shoulder_isolation/isolation/P4, Core/core/isolation/P5

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate): 11 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A4 (mp=horizontal_push, suit=intermediate): 23 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Dumbbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A3 (mp=vertical_push, eq=home_dumbbells, suit=intermediate, excluded=1): 6 → [Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press, Pike Push Up]
  - A4 (mp=vertical_push, suit=intermediate, excluded=1): 10 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P2
  - excludeNames-in (2): Dumbbell Bench Press, Dumbbell Shoulder Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate, excluded=2): 10 → [Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=intermediate, excluded=2): 22 → [Barbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Single Arm Dumbbell Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 1 → [Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=home_dumbbells, suit=intermediate, excluded=3): 2 → [Lateral Raise, Band Pull Apart]
  - A4 (mp=shoulder_isolation, suit=intermediate, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 2 → [Overhead Tricep Extension, Dumbbell Kickback]
  - A2 (mp=elbow_extension, tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 2 → [Overhead Tricep Extension, Dumbbell Kickback]
  - A3 (mp=elbow_extension, eq=home_dumbbells, suit=intermediate, excluded=4): 3 → [Bench Dips, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=intermediate, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Overhead Tricep Extension (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P3
  - excludeNames-in (5): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press, Lateral Raise, Overhead Tricep Extension
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 1 → [Dumbbell Fly]
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate, excluded=5): 9 → [Chest Squeeze Press, Deficit Push-Up, Floor Press, Push Up, Diamond Push Up]
  - A4 (mp=horizontal_push, suit=intermediate, excluded=5): 21 → [Barbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Dumbbell Bench Press, Dumbbell Shoulder Press, Single Arm Dumbbell Press, Lateral Raise, Overhead Tricep Extension, Dumbbell Fly
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 1 → [Dumbbell Kickback]
  - A3 (mp=elbow_extension, eq=home_dumbbells, suit=intermediate, excluded=6): 2 → [Bench Dips, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=intermediate, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Dumbbell Kickback (attempt2DropSubFocus)

#### Day "Lower Body" (legs, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 9 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Quads/isolation/knee_dominant/isolation/P4, Hamstrings/knee_dominant/isolation/P4, Hip/hip_isolation/isolation/P5, Core/obliques/core/isolation/P5
- POST-VolumeFilter: 7 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Quads/isolation/knee_dominant/isolation/P4, Hamstrings/knee_dominant/isolation/P4
  - ⚠️ Dropped by VolumeFilter: Hip/hip_isolation/isolation/P5, Core/obliques/core/isolation/P5

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 27 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A3 (mp=hip_dominant, eq=home_dumbbells, suit=intermediate, excluded=1): 4 → [Single Leg Romanian Deadlift, Kettlebell Swing, Banded Hip Thrust, B-Stance RDL]
  - A4 (mp=hip_dominant, suit=intermediate, excluded=1): 15 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Single Leg Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Banded Squat, Single Leg Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A2 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=home_dumbbells, suit=intermediate, excluded=2): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=intermediate, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (3): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate, excluded=3): 6 → [High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat, Split Jump]
  - A4 (mp=knee_dominant, suit=intermediate, excluded=3): 26 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** High Box Step-Up (attempt3DropTypeAndTarget)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (4): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge, High Box Step-Up
  - A1 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=4): 12 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=4): 29 → [Ab Wheel Rollout, Farmers Carry, Suitcase Carry, Landmine Rotation, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P4
  - excludeNames-in (5): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge, High Box Step-Up, Hanging Leg Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 0
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate, excluded=5): 5 → [Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat, Split Jump, Broad Jump]
  - A4 (mp=knee_dominant, suit=intermediate, excluded=5): 25 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Deficit Reverse Lunge (attempt3DropTypeAndTarget)

- **Slot:** Hamstrings/knee_dominant/isolation/P4
  - excludeNames-in (6): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge, High Box Step-Up, Hanging Leg Raise, Deficit Reverse Lunge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate, excluded=6): 4 → [Baithak (Hindu Squat), Jump Squat, Split Jump, Broad Jump]
  - A4 (mp=knee_dominant, suit=intermediate, excluded=6): 24 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Baithak (Hindu Squat) (attempt3DropTypeAndTarget)

**Variant B**

- PRE-VolumeFilter: 9 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Quads/isolation/knee_dominant/isolation/P4, Hamstrings/knee_dominant/isolation/P4, Hip/hip_isolation/isolation/P5, Core/obliques/core/isolation/P5
- POST-VolumeFilter: 7 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Quads/isolation/knee_dominant/isolation/P4, Hamstrings/knee_dominant/isolation/P4
  - ⚠️ Dropped by VolumeFilter: Hip/hip_isolation/isolation/P5, Core/obliques/core/isolation/P5

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 27 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A3 (mp=hip_dominant, eq=home_dumbbells, suit=intermediate, excluded=1): 4 → [Single Leg Romanian Deadlift, Kettlebell Swing, Banded Hip Thrust, B-Stance RDL]
  - A4 (mp=hip_dominant, suit=intermediate, excluded=1): 15 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Single Leg Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Banded Squat, Single Leg Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A2 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=home_dumbbells, suit=intermediate, excluded=2): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=intermediate, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (3): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate, excluded=3): 6 → [High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat, Split Jump]
  - A4 (mp=knee_dominant, suit=intermediate, excluded=3): 26 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** High Box Step-Up (attempt3DropTypeAndTarget)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (4): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge, High Box Step-Up
  - A1 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=4): 12 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=4): 29 → [Ab Wheel Rollout, Farmers Carry, Suitcase Carry, Landmine Rotation, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P4
  - excludeNames-in (5): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge, High Box Step-Up, Hanging Leg Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=5): 0
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate, excluded=5): 5 → [Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat, Split Jump, Broad Jump]
  - A4 (mp=knee_dominant, suit=intermediate, excluded=5): 25 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Deficit Reverse Lunge (attempt3DropTypeAndTarget)

- **Slot:** Hamstrings/knee_dominant/isolation/P4
  - excludeNames-in (6): Banded Squat, Single Leg Romanian Deadlift, Kas Glute Bridge, High Box Step-Up, Hanging Leg Raise, Deficit Reverse Lunge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate, excluded=6): 4 → [Baithak (Hindu Squat), Jump Squat, Split Jump, Broad Jump]
  - A4 (mp=knee_dominant, suit=intermediate, excluded=6): 24 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Baithak (Hindu Squat) (attempt3DropTypeAndTarget)

#### Day "Upper Pull" (pull, strength)

**Variant A**

- PRE-VolumeFilter: 9 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4, Rear Delts/cable/shoulder_isolation/isolation/P4, Core/core/isolation/P5
- POST-VolumeFilter: 7 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4
  - ⚠️ Dropped by VolumeFilter: Rear Delts/cable/shoulder_isolation/isolation/P4, Core/core/isolation/P5

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate): 2 → [Chin Up, Dumbbell Pullover]
  - A3 (mp=vertical_pull, eq=home_dumbbells, suit=intermediate): 3 → [Chin Up, Dumbbell Pullover, Pull Up]
  - A4 (mp=vertical_pull, suit=intermediate): 7 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (1): Chin Up
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Row, Kettlebell Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Chin Up, Dumbbell Row
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 1 → [Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 1 → [Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=home_dumbbells, suit=intermediate, excluded=2): 2 → [Lateral Raise, Band Pull Apart]
  - A4 (mp=shoulder_isolation, suit=intermediate, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Chin Up, Dumbbell Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 3 → [Dumbbell Curl, Hammer Curl, Concentration Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 3 → [Dumbbell Curl, Hammer Curl, Concentration Curl]
  - A3 (mp=elbow_flexion, eq=home_dumbbells, suit=intermediate, excluded=3): 3 → [Dumbbell Curl, Hammer Curl, Concentration Curl]
  - A4 (mp=elbow_flexion, suit=intermediate, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (4): Chin Up, Dumbbell Row, Band Pull Apart, Dumbbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 2 → [Hammer Curl, Concentration Curl]
  - A3 (mp=elbow_flexion, eq=home_dumbbells, suit=intermediate, excluded=4): 2 → [Hammer Curl, Concentration Curl]
  - A4 (mp=elbow_flexion, suit=intermediate, excluded=4): 11 → [Barbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Hammer Curl (attempt2DropSubFocus)

- **Slot:** Lats/lower/vertical_pull/compound/P3
  - excludeNames-in (5): Chin Up, Dumbbell Row, Band Pull Apart, Dumbbell Curl, Hammer Curl
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 1 → [Dumbbell Pullover]
  - A3 (mp=vertical_pull, eq=home_dumbbells, suit=intermediate, excluded=5): 2 → [Dumbbell Pullover, Pull Up]
  - A4 (mp=vertical_pull, suit=intermediate, excluded=5): 6 → [Lat Pulldown, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Dumbbell Pullover (attempt2DropSubFocus)

- **Slot:** Biceps/short_head/elbow_flexion/isolation/P4
  - excludeNames-in (6): Chin Up, Dumbbell Row, Band Pull Apart, Dumbbell Curl, Hammer Curl, Dumbbell Pullover
  - A1 (mp=elbow_flexion, tf="Biceps (short_head)", tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 1 → [Concentration Curl]
  - A3 (mp=elbow_flexion, eq=home_dumbbells, suit=intermediate, excluded=6): 1 → [Concentration Curl]
  - A4 (mp=elbow_flexion, suit=intermediate, excluded=6): 10 → [Barbell Curl, Concentration Curl, Cable Curl, Preacher Curl, Rope Hammer Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Concentration Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 9 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4, Rear Delts/cable/shoulder_isolation/isolation/P4, Core/core/isolation/P5
- POST-VolumeFilter: 7 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4
  - ⚠️ Dropped by VolumeFilter: Rear Delts/cable/shoulder_isolation/isolation/P4, Core/core/isolation/P5

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate): 2 → [Chin Up, Dumbbell Pullover]
  - A3 (mp=vertical_pull, eq=home_dumbbells, suit=intermediate): 3 → [Chin Up, Dumbbell Pullover, Pull Up]
  - A4 (mp=vertical_pull, suit=intermediate): 7 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (1): Chin Up
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Row, Kettlebell Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 2 → [Dumbbell Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Chin Up, Dumbbell Row
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 1 → [Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 1 → [Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=home_dumbbells, suit=intermediate, excluded=2): 2 → [Lateral Raise, Band Pull Apart]
  - A4 (mp=shoulder_isolation, suit=intermediate, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Chin Up, Dumbbell Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 3 → [Dumbbell Curl, Hammer Curl, Concentration Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 3 → [Dumbbell Curl, Hammer Curl, Concentration Curl]
  - A3 (mp=elbow_flexion, eq=home_dumbbells, suit=intermediate, excluded=3): 3 → [Dumbbell Curl, Hammer Curl, Concentration Curl]
  - A4 (mp=elbow_flexion, suit=intermediate, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (4): Chin Up, Dumbbell Row, Band Pull Apart, Dumbbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 2 → [Hammer Curl, Concentration Curl]
  - A3 (mp=elbow_flexion, eq=home_dumbbells, suit=intermediate, excluded=4): 2 → [Hammer Curl, Concentration Curl]
  - A4 (mp=elbow_flexion, suit=intermediate, excluded=4): 11 → [Barbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Hammer Curl (attempt2DropSubFocus)

- **Slot:** Lats/lower/vertical_pull/compound/P3
  - excludeNames-in (5): Chin Up, Dumbbell Row, Band Pull Apart, Dumbbell Curl, Hammer Curl
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 1 → [Dumbbell Pullover]
  - A3 (mp=vertical_pull, eq=home_dumbbells, suit=intermediate, excluded=5): 2 → [Dumbbell Pullover, Pull Up]
  - A4 (mp=vertical_pull, suit=intermediate, excluded=5): 6 → [Lat Pulldown, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Dumbbell Pullover (attempt2DropSubFocus)

- **Slot:** Biceps/short_head/elbow_flexion/isolation/P4
  - excludeNames-in (6): Chin Up, Dumbbell Row, Band Pull Apart, Dumbbell Curl, Hammer Curl, Dumbbell Pullover
  - A1 (mp=elbow_flexion, tf="Biceps (short_head)", tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=6): 1 → [Concentration Curl]
  - A3 (mp=elbow_flexion, eq=home_dumbbells, suit=intermediate, excluded=6): 1 → [Concentration Curl]
  - A4 (mp=elbow_flexion, suit=intermediate, excluded=6): 10 → [Barbell Curl, Concentration Curl, Cable Curl, Preacher Curl, Rope Hammer Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Concentration Curl (attempt2DropSubFocus)

#### Day "Full Body + Core" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 9 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3, Shoulders/vertical_push/compound/P3, Hamstrings/hip_dominant/compound/P4, Lateral Delts/shoulder_isolation/isolation/P4, Calves/knee_dominant/isolation/P5
- POST-VolumeFilter: 7 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3, Shoulders/vertical_push/compound/P3, Hamstrings/hip_dominant/compound/P4
  - ⚠️ Dropped by VolumeFilter: Lateral Delts/shoulder_isolation/isolation/P4, Calves/knee_dominant/isolation/P5

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 27 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Banded Squat, Dumbbell Row
  - A1 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=2): 12 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=2): 29 → [Ab Wheel Rollout, Farmers Carry, Suitcase Carry, Landmine Rotation, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Banded Squat, Dumbbell Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 4 → [V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=3): 11 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hollow Body Hold, Bear Crawl]
  - A4 (mp=core, suit=intermediate, excluded=3): 28 → [Ab Wheel Rollout, Farmers Carry, Suitcase Carry, Landmine Rotation, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** V-Ups (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P3
  - excludeNames-in (4): Banded Squat, Dumbbell Row, Hanging Leg Raise, V-Ups
  - A1 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A2 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=home_dumbbells, suit=intermediate, excluded=4): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=intermediate, excluded=4): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P3
  - excludeNames-in (5): Banded Squat, Dumbbell Row, Hanging Leg Raise, V-Ups, Kas Glute Bridge
  - A1 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A3 (mp=vertical_push, eq=home_dumbbells, suit=intermediate, excluded=5): 6 → [Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press, Pike Push Up]
  - A4 (mp=vertical_push, suit=intermediate, excluded=5): 10 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P4
  - excludeNames-in (6): Banded Squat, Dumbbell Row, Hanging Leg Raise, V-Ups, Kas Glute Bridge, Dumbbell Shoulder Press
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=6): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=6): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A3 (mp=hip_dominant, eq=home_dumbbells, suit=intermediate, excluded=6): 4 → [Single Leg Romanian Deadlift, Kettlebell Swing, Banded Hip Thrust, B-Stance RDL]
  - A4 (mp=hip_dominant, suit=intermediate, excluded=6): 15 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Single Leg Romanian Deadlift (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 9 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3, Shoulders/vertical_push/compound/P3, Hamstrings/hip_dominant/compound/P4, Lateral Delts/shoulder_isolation/isolation/P4, Calves/knee_dominant/isolation/P5
- POST-VolumeFilter: 7 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3, Shoulders/vertical_push/compound/P3, Hamstrings/hip_dominant/compound/P4
  - ⚠️ Dropped by VolumeFilter: Lateral Delts/shoulder_isolation/isolation/P4, Calves/knee_dominant/isolation/P5

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 27 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Banded Squat, Dumbbell Row
  - A1 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 5 → [Hanging Leg Raise, V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=2): 12 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=2): 29 → [Ab Wheel Rollout, Farmers Carry, Suitcase Carry, Landmine Rotation, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Banded Squat, Dumbbell Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 4 → [V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=3): 11 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hollow Body Hold, Bear Crawl]
  - A4 (mp=core, suit=intermediate, excluded=3): 28 → [Ab Wheel Rollout, Farmers Carry, Suitcase Carry, Landmine Rotation, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** V-Ups (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P3
  - excludeNames-in (4): Banded Squat, Dumbbell Row, Hanging Leg Raise, V-Ups
  - A1 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A2 (mp=hip_isolation, tm="Glutes", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=4): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=home_dumbbells, suit=intermediate, excluded=4): 3 → [Kas Glute Bridge, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=intermediate, excluded=4): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P3
  - excludeNames-in (5): Banded Squat, Dumbbell Row, Hanging Leg Raise, V-Ups, Kas Glute Bridge
  - A1 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=5): 2 → [Dumbbell Shoulder Press, Arnold Press]
  - A3 (mp=vertical_push, eq=home_dumbbells, suit=intermediate, excluded=5): 6 → [Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press, Pike Push Up]
  - A4 (mp=vertical_push, suit=intermediate, excluded=5): 10 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P4
  - excludeNames-in (6): Banded Squat, Dumbbell Row, Hanging Leg Raise, V-Ups, Kas Glute Bridge, Dumbbell Shoulder Press
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=6): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=6): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A3 (mp=hip_dominant, eq=home_dumbbells, suit=intermediate, excluded=6): 4 → [Single Leg Romanian Deadlift, Kettlebell Swing, Banded Hip Thrust, B-Stance RDL]
  - A4 (mp=hip_dominant, suit=intermediate, excluded=6): 15 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Single Leg Romanian Deadlift (attempt1Exact)

---

## Combo: advanced/full_gym/strength/5d/P3

**INPUT:**
- goal=strength
- equipment=full_gym
- daysPerWeek=5
- experience=advanced
- phase=3
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=full_gym

### Week baseline

#### Day "Push" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P4, Rear Delts/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P4, Rear Delts/shoulder_isolation/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=5): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lower Chest/horizontal_push/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise, Tricep Pushdown (Cable), Skull Crusher
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=6): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=6): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=6): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=6): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise, Tricep Pushdown (Cable), Skull Crusher, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P4, Rear Delts/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Lower Chest/horizontal_push/isolation/P4, Rear Delts/shoulder_isolation/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=5): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lower Chest/horizontal_push/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise, Tricep Pushdown (Cable), Skull Crusher
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=6): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=6): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=6): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=6): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Barbell Overhead Press, Lateral Raise, Tricep Pushdown (Cable), Skull Crusher, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Pull" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Rear Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Rear Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any): 2 → [Lat Pulldown, Machine High Row]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=6): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=6): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=6): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=6): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Rear Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Rear Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any): 2 → [Lat Pulldown, Machine High Row]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=6): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=6): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=6): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=6): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

#### Day "Legs" (legs, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hamstrings/knee_dominant/isolation/P4, Hip/hip_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hamstrings/knee_dominant/isolation/P4, Hip/hip_isolation/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=5): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=5): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=5): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=5): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Hanging Leg Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=6): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=6): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Hanging Leg Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hamstrings/knee_dominant/isolation/P4, Hip/hip_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hamstrings/knee_dominant/isolation/P4, Hip/hip_isolation/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=5): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=5): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=5): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=5): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Hanging Leg Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=6): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=6): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Hanging Leg Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt1Exact)

#### Day "Upper" (upper, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Lats/horizontal_pull/compound/P3, Biceps/long_head/elbow_flexion/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Lats/horizontal_pull/compound/P3, Biceps/long_head/elbow_flexion/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=5): 10 → [Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row, Meadows Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=5): 10 → [Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row, Meadows Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Row
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=6): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=6): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=6): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=6): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Row, Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Lats/horizontal_pull/compound/P3, Biceps/long_head/elbow_flexion/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Lats/horizontal_pull/compound/P3, Biceps/long_head/elbow_flexion/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=5): 10 → [Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row, Meadows Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=5): 10 → [Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row, Meadows Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Row
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=6): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=6): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=6): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=6): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Lateral Raise, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Row, Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Lower + Core" (legs, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/hip_dominant/compound/P3, Glutes/hip_isolation/isolation/P4, Hip/hip_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/hip_dominant/compound/P3, Glutes/hip_isolation/isolation/P4, Hip/hip_isolation/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch, Standing Calf Raise
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=5): 9 → [Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=5): 9 → [Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=5): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=5): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch, Standing Calf Raise, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=6): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=6): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch, Standing Calf Raise, Romanian Deadlift, Glute Bridge
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/hip_dominant/compound/P3, Glutes/hip_isolation/isolation/P4, Hip/hip_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/hip_dominant/compound/P3, Glutes/hip_isolation/isolation/P4, Hip/hip_isolation/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch, Standing Calf Raise
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=5): 9 → [Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=5): 9 → [Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=5): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=5): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch, Standing Calf Raise, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=6): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=6): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Hanging Leg Raise, Cable Crunch, Standing Calf Raise, Romanian Deadlift, Glute Bridge
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=7): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt1Exact)

---

## Combo: advanced/basic_gym/build_muscle/6d/P1

**INPUT:**
- goal=build_muscle
- equipment=basic_gym
- daysPerWeek=6
- experience=advanced
- phase=1
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=basic_gym

### Week baseline

#### Day "Push A" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Mid Chest/horizontal_push/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Mid Chest/horizontal_push/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any): 7 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=1): 17 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=2): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=isolation, suit=any, excluded=4): 3 → [Dumbbell Fly, Cable Fly, Cable Crossover]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=4): 16 → [Dumbbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable), Dumbbell Fly
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=5): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable), Dumbbell Fly, Skull Crusher
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=basic_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=6): 5 → [Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise, Cable Front Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable), Dumbbell Fly, Skull Crusher, Cable Front Raise
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, excluded=7): 2 → [Cable Fly, Cable Crossover]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=7): 15 → [Dumbbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A4 (mp=horizontal_push, suit=any, excluded=7): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Mid Chest/horizontal_push/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Mid Chest/horizontal_push/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any): 7 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=1): 17 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=2): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=isolation, suit=any, excluded=4): 3 → [Dumbbell Fly, Cable Fly, Cable Crossover]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=4): 16 → [Dumbbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable), Dumbbell Fly
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=5): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable), Dumbbell Fly, Skull Crusher
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=basic_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=6): 5 → [Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise, Cable Front Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Lateral Raise, Tricep Pushdown (Cable), Dumbbell Fly, Skull Crusher, Cable Front Raise
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, excluded=7): 2 → [Cable Fly, Cable Crossover]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=7): 15 → [Dumbbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A4 (mp=horizontal_push, suit=any, excluded=7): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

#### Day "Pull A" (pull, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Core/core/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any): 8 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Dumbbell Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 7 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any, excluded=2): 7 → [Chin Up, Dumbbell Pullover, Machine High Row, Pull Up, Muscle Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=3): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 5 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=4): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=4): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=5): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=5): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=6): 3 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=6): 6 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Kettlebell Row, Pendlay Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=6): 7 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=6): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 3 → [Hanging Leg Raise, Cable Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=7): 8 → [Hanging Leg Raise, Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=7): 18 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P4, Core/core/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any): 8 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Dumbbell Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 7 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any, excluded=2): 7 → [Chin Up, Dumbbell Pullover, Machine High Row, Pull Up, Muscle Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=3): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 5 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=4): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=4): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=5): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=5): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=6): 3 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=6): 6 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Kettlebell Row, Pendlay Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=6): 7 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=6): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Dumbbell Curl, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 3 → [Hanging Leg Raise, Cable Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=7): 8 → [Hanging Leg Raise, Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=7): 18 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Legs A" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hip/hip_isolation/isolation/P4, Calves/soleus/knee_dominant/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hip/hip_isolation/isolation/P4, Calves/soleus/knee_dominant/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any): 5 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any): 13 → [Sumo Deadlift, Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Zercher Squat (attempt2DropSubFocus)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Zercher Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, excluded=1): 8 → [Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 11 → [Deadlift, Hip Thrust, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Zercher Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=2): 12 → [Sumo Deadlift, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Sumo Deadlift (attempt3DropTypeAndTarget)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Zercher Squat, Deadlift, Sumo Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt2DropSubFocus)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, excluded=4): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=4): 11 → [Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Pistol Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Jefferson Squat (attempt3DropTypeAndTarget)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (5): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge, Jefferson Squat
  - A1 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 3 → [Hanging Leg Raise, Cable Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=5): 8 → [Hanging Leg Raise, Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=5): 18 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise]
  - A4 (mp=core, suit=any, excluded=5): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge, Jefferson Squat, Hanging Leg Raise
  - A1 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, excluded=6): 0
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=6): 3 → [Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abductor Machine (attempt3DropTypeAndTarget)

- **Slot:** Calves/soleus/knee_dominant/isolation/P4
  - excludeNames-in (7): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge, Jefferson Squat, Hanging Leg Raise, Hip Abductor Machine
  - A1 (mp=knee_dominant, tf="Calves (soleus)", tm="Calves", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, excluded=7): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=7): 10 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Pistol Squat, Baithak (Hindu Squat)]
  - A4 (mp=knee_dominant, suit=any, excluded=7): 31 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt3DropTypeAndTarget)

**Variant B**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hip/hip_isolation/isolation/P4, Calves/soleus/knee_dominant/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3, Hip/hip_isolation/isolation/P4, Calves/soleus/knee_dominant/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any): 5 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any): 13 → [Sumo Deadlift, Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Zercher Squat (attempt2DropSubFocus)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Zercher Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, excluded=1): 8 → [Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 11 → [Deadlift, Hip Thrust, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Zercher Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=2): 12 → [Sumo Deadlift, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Sumo Deadlift (attempt3DropTypeAndTarget)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Zercher Squat, Deadlift, Sumo Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt2DropSubFocus)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, excluded=4): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=4): 11 → [Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Pistol Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Jefferson Squat (attempt3DropTypeAndTarget)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (5): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge, Jefferson Squat
  - A1 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 3 → [Hanging Leg Raise, Cable Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=5): 8 → [Hanging Leg Raise, Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=5): 18 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise]
  - A4 (mp=core, suit=any, excluded=5): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge, Jefferson Squat, Hanging Leg Raise
  - A1 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, excluded=6): 0
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=6): 3 → [Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abductor Machine (attempt3DropTypeAndTarget)

- **Slot:** Calves/soleus/knee_dominant/isolation/P4
  - excludeNames-in (7): Zercher Squat, Deadlift, Sumo Deadlift, Kas Glute Bridge, Jefferson Squat, Hanging Leg Raise, Hip Abductor Machine
  - A1 (mp=knee_dominant, tf="Calves (soleus)", tm="Calves", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, excluded=7): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=7): 10 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Pistol Squat, Baithak (Hindu Squat)]
  - A4 (mp=knee_dominant, suit=any, excluded=7): 31 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt3DropTypeAndTarget)

#### Day "Push B" (push, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/compound/P3, Triceps/long_head/elbow_extension/isolation/P3, Mid Chest/horizontal_push/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/compound/P3, Triceps/long_head/elbow_extension/isolation/P3, Mid Chest/horizontal_push/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A3 (mp=vertical_push, eq=basic_gym, suit=any): 7 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=1): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Mid Chest/horizontal_push/compound/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=2): 3 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, excluded=2): 7 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=2): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Barbell Bench Press
  - A1 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=4): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=compound, suit=any, excluded=4): 1 → [Decline Dumbbell Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=4): 17 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Decline Dumbbell Press (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable), Decline Dumbbell Press
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=5): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable), Decline Dumbbell Press, Skull Crusher
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, excluded=6): 3 → [Dumbbell Fly, Cable Fly, Cable Crossover]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=6): 16 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=6): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable), Decline Dumbbell Press, Skull Crusher, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=7): 5 → [Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise, Cable Front Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/compound/P3, Triceps/long_head/elbow_extension/isolation/P3, Mid Chest/horizontal_push/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/compound/P3, Triceps/long_head/elbow_extension/isolation/P3, Mid Chest/horizontal_push/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A3 (mp=vertical_push, eq=basic_gym, suit=any): 7 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=1): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Mid Chest/horizontal_push/compound/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=2): 3 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, excluded=2): 7 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, JM Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=2): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Barbell Bench Press
  - A1 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=3): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=4): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=basic_gym, type=compound, suit=any, excluded=4): 1 → [Decline Dumbbell Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=4): 17 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Decline Dumbbell Press (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable), Decline Dumbbell Press
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=basic_gym, type=isolation, suit=any, excluded=5): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=basic_gym, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=5): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable), Decline Dumbbell Press, Skull Crusher
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=isolation, suit=any, excluded=6): 3 → [Dumbbell Fly, Cable Fly, Cable Crossover]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=6): 16 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=6): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Barbell Bench Press, Tricep Pushdown (Cable), Decline Dumbbell Press, Skull Crusher, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=basic_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=7): 5 → [Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise, Cable Front Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Pull B" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4, Mid Back/horizontal_pull/compound/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4, Mid Back/horizontal_pull/compound/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any): 8 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 7 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Lat Pulldown, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=2): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Barbell Bent Over Row, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 5 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=4): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=4): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Lats/lower/vertical_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl, Dumbbell Curl
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any, excluded=5): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any, excluded=5): 7 → [Chin Up, Dumbbell Pullover, Machine High Row, Pull Up, Muscle Up]
  - A4 (mp=vertical_pull, suit=any, excluded=5): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Biceps/short_head/elbow_flexion/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl, Dumbbell Curl, Chin Up
  - A1 (mp=elbow_flexion, tf="Biceps (short_head)", tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=6): 7 → [Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl, High Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=6): 7 → [Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl, High Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=6): 10 → [Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl, Rope Hammer Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Hammer Curl (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P4
  - excludeNames-in (7): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl, Dumbbell Curl, Chin Up, Hammer Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=7): 3 → [Dumbbell Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=7): 6 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Kettlebell Row, Pendlay Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=7): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=7): 13 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4, Mid Back/horizontal_pull/compound/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3, Lats/lower/vertical_pull/compound/P3, Biceps/short_head/elbow_flexion/isolation/P4, Mid Back/horizontal_pull/compound/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any): 8 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 7 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Lat Pulldown, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=2): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Barbell Bent Over Row, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 5 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=4): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=4): 8 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Lats/lower/vertical_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl, Dumbbell Curl
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any, excluded=5): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any, excluded=5): 7 → [Chin Up, Dumbbell Pullover, Machine High Row, Pull Up, Muscle Up]
  - A4 (mp=vertical_pull, suit=any, excluded=5): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Biceps/short_head/elbow_flexion/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl, Dumbbell Curl, Chin Up
  - A1 (mp=elbow_flexion, tf="Biceps (short_head)", tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=6): 7 → [Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl, High Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=6): 7 → [Hammer Curl, Concentration Curl, Cable Curl, Rope Hammer Curl, High Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=6): 10 → [Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl, Rope Hammer Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Hammer Curl (attempt2DropSubFocus)

- **Slot:** Mid Back/horizontal_pull/compound/P4
  - excludeNames-in (7): Lat Pulldown, Barbell Bent Over Row, Face Pull, Barbell Curl, Dumbbell Curl, Chin Up, Hammer Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=7): 3 → [Dumbbell Row, Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=7): 6 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Kettlebell Row, Pendlay Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=7): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=7): 13 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

#### Day "Legs B" (legs, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Core/core/isolation/P3, Calves/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/obliques/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Core/core/isolation/P3, Calves/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/obliques/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true): 1 → [Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any): 8 → [Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any): 11 → [Deadlift, Hip Thrust, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, excluded=1): 7 → [Hip Thrust, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing, Banded Hip Thrust]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 10 → [Hip Thrust, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Hip Thrust (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Hip Thrust
  - A1 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, excluded=2): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=2): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt2DropSubFocus)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Hip Thrust, Kas Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=basic_gym, type=isolation, suit=any, excluded=3): 1 → [Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=3): 13 → [Sumo Deadlift, Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Single Leg Curl (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (4): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl
  - A1 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Hanging Leg Raise, Cable Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=4): 8 → [Hanging Leg Raise, Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=4): 18 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise]
  - A4 (mp=core, suit=any, excluded=4): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl, Hanging Leg Raise
  - A1 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, excluded=5): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=5): 12 → [Sumo Deadlift, Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Sumo Deadlift (attempt3DropTypeAndTarget)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl, Hanging Leg Raise, Sumo Deadlift
  - A1 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, excluded=6): 0
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=6): 3 → [Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abductor Machine (attempt3DropTypeAndTarget)

- **Slot:** Core/obliques/core/isolation/P4
  - excludeNames-in (7): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl, Hanging Leg Raise, Sumo Deadlift, Hip Abductor Machine
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=7): 7 → [Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups, Flutter Kicks]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=7): 17 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hollow Body Hold]
  - A4 (mp=core, suit=any, excluded=7): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Core/core/isolation/P3, Calves/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/obliques/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Core/core/isolation/P3, Calves/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/obliques/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true): 1 → [Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any): 8 → [Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any): 11 → [Deadlift, Hip Thrust, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, excluded=1): 7 → [Hip Thrust, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing, Banded Hip Thrust]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 10 → [Hip Thrust, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Hip Thrust (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Hip Thrust
  - A1 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, excluded=2): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=2): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt2DropSubFocus)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Hip Thrust, Kas Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=basic_gym, type=isolation, suit=any, excluded=3): 1 → [Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=3): 13 → [Sumo Deadlift, Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Single Leg Curl (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P3
  - excludeNames-in (4): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl
  - A1 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Hanging Leg Raise, Cable Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=4): 8 → [Hanging Leg Raise, Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=4): 18 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise]
  - A4 (mp=core, suit=any, excluded=4): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl, Hanging Leg Raise
  - A1 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Calves", eq=basic_gym, type=isolation, suit=any, excluded=5): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=5): 12 → [Sumo Deadlift, Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Sumo Deadlift (attempt3DropTypeAndTarget)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl, Hanging Leg Raise, Sumo Deadlift
  - A1 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=basic_gym, type=isolation, suit=any, excluded=6): 0
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=6): 3 → [Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abductor Machine (attempt3DropTypeAndTarget)

- **Slot:** Core/obliques/core/isolation/P4
  - excludeNames-in (7): Deadlift, Hip Thrust, Kas Glute Bridge, Standing Single Leg Curl, Hanging Leg Raise, Sumo Deadlift, Hip Abductor Machine
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=core, tm="Core", eq=basic_gym, type=isolation, suit=any, excluded=7): 7 → [Cable Crunch, Pallof Press, Captain's Chair Leg Raise, V-Ups, Flutter Kicks]
  - A3 (mp=core, eq=basic_gym, suit=any, excluded=7): 17 → [Front Lever Hold, Kettlebell Turkish Get Up, Plank, Dead Bug, Hollow Body Hold]
  - A4 (mp=core, suit=any, excluded=7): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

---

## Combo: beginner/full_gym/build_muscle/4d/P1 (vs combo 1 — tests suitable_for path)

**INPUT:**
- goal=build_muscle
- equipment=full_gym
- daysPerWeek=4
- experience=beginner
- phase=1
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=beginner
- equipmentTier=full_gym

### Week baseline

#### Day "Full Body A" (full_body, strength)

**Variant A**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, excluded=1): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner, excluded=1): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=2): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Barbell Overhead Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Barbell Overhead Press, Dumbbell Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, excluded=1): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner, excluded=1): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=2): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Barbell Overhead Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Barbell Overhead Press, Dumbbell Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

#### Day "Full Body B" (full_body, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 3 → [Lat Pulldown, Chin Up, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Lat Pulldown, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Lat Pulldown, Dumbbell Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 3 → [Lat Pulldown, Chin Up, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Lat Pulldown, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Lat Pulldown, Dumbbell Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

#### Day "Full Body C" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=1): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Dumbbell Row, Goblet Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, excluded=3): 2 → [Trap Bar Deadlift, Cable Pull-Through]
  - A3 (mp=hip_dominant, eq=full_gym, suit=beginner, excluded=3): 5 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Hyperextension]
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 5 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Hyperextension]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Dumbbell Row, Goblet Squat, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A4 (mp=horizontal_push, suit=beginner): 11 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Floor Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=1): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 8 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Dumbbell Row, Goblet Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, excluded=3): 2 → [Trap Bar Deadlift, Cable Pull-Through]
  - A3 (mp=hip_dominant, eq=full_gym, suit=beginner, excluded=3): 5 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Hyperextension]
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 5 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Hyperextension]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Dumbbell Row, Goblet Squat, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

#### Day "Full Body D" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 6 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3
- POST-VolumeFilter: 5 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Glutes/hip_isolation/isolation/P3

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 3 → [Lat Pulldown, Chin Up, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Barbell Overhead Press, Lat Pulldown
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lat Pulldown, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=3): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=3): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=3): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=3): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (4): Barbell Overhead Press, Lat Pulldown, Goblet Squat, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 8 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 6 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3
- POST-VolumeFilter: 5 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Glutes/hip_isolation/isolation/P3

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner): 2 → [Barbell Overhead Press, Dumbbell Shoulder Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 3 → [Lat Pulldown, Chin Up, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 4 → [Lat Pulldown, Chin Up, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Barbell Overhead Press, Lat Pulldown
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 14 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lat Pulldown, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=3): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=3): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=3): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=3): 17 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (4): Barbell Overhead Press, Lat Pulldown, Goblet Squat, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 8 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Battle Ropes, Plank, Dead Bug]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

---

## Combo: advanced/full_gym/build_muscle/5d/P1/sd=60 (vs combo 1 — isolates VolumeFilter)

**INPUT:**
- goal=build_muscle
- equipment=full_gym
- daysPerWeek=5
- experience=advanced
- phase=1
- sessionDuration=60
- injuries=[]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=full_gym

### Week baseline

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

---

## Combo: real-profile replay (Upendra; currently same shape as combo 1)

**INPUT:**
- goal=build_muscle
- equipment=full_gym
- daysPerWeek=5
- experience=advanced
- phase=1
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=full_gym

### Week baseline

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

---

## Combo: advanced/full_gym/build_muscle/5d/P1/injuries=[knee]

**INPUT:**
- goal=build_muscle
- equipment=full_gym
- daysPerWeek=5
- experience=advanced
- phase=1
- sessionDuration=null
- injuries=[knee]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=full_gym

### Week baseline

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, injuries=knee): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1, injuries=knee): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1, injuries=knee): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2, injuries=knee): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2, injuries=knee): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, injuries=knee): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1, injuries=knee): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1, injuries=knee): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2, injuries=knee): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2, injuries=knee): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, injuries=knee): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2, injuries=knee): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5, injuries=knee): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5, injuries=knee): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5, injuries=knee): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5, injuries=knee): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6, injuries=knee): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6, injuries=knee): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, injuries=knee): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2, injuries=knee): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5, injuries=knee): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5, injuries=knee): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5, injuries=knee): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5, injuries=knee): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6, injuries=knee): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6, injuries=knee): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, injuries=knee): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1, injuries=knee): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1, injuries=knee): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7, injuries=knee): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7, injuries=knee): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, injuries=knee): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1, injuries=knee): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1, injuries=knee): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2, injuries=knee): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5, injuries=knee): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6, injuries=knee): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7, injuries=knee): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7, injuries=knee): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 1 → [Leg Press]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, injuries=knee): 1 → [Leg Press]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, injuries=knee): 7 → [Leg Press, Sumo Deadlift, Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise]
  - A4 (mp=knee_dominant, suit=any, injuries=knee): 7 → [Leg Press, Sumo Deadlift, Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Press (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Leg Press
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1, injuries=knee): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1, injuries=knee): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Leg Press, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2, injuries=knee): 6 → [Sumo Deadlift, Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise, Standing Single Leg Curl]
  - A4 (mp=knee_dominant, suit=any, excluded=2, injuries=knee): 6 → [Sumo Deadlift, Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise, Standing Single Leg Curl]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Sumo Deadlift (attempt3DropTypeAndTarget)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Leg Press, Deadlift, Sumo Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 7 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=3, injuries=knee): 8 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Leg Press, Deadlift, Sumo Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4, injuries=knee): 5 → [Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise, Standing Single Leg Curl, Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=any, excluded=4, injuries=knee): 5 → [Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise, Standing Single Leg Curl, Donkey Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Leg Press, Deadlift, Sumo Deadlift, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5, injuries=knee): 4 → [Leg Curl (Lying), Seated Calf Raise, Standing Single Leg Curl, Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=any, excluded=5, injuries=knee): 4 → [Leg Curl (Lying), Seated Calf Raise, Standing Single Leg Curl, Donkey Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Leg Press, Deadlift, Sumo Deadlift, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6, injuries=knee): 7 → [Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A4 (mp=hip_isolation, suit=any, excluded=6, injuries=knee): 7 → [Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Leg Press, Deadlift, Sumo Deadlift, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, injuries=knee): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, injuries=knee): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, injuries=knee): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1, injuries=knee): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1, injuries=knee): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 7 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2, injuries=knee): 8 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=2, injuries=knee): 8 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3, injuries=knee): 7 → [Leg Press, Sumo Deadlift, Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise]
  - A4 (mp=knee_dominant, suit=any, excluded=3, injuries=knee): 7 → [Leg Press, Sumo Deadlift, Leg Curl (Lying), Standing Calf Raise, Seated Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4, injuries=knee): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4, injuries=knee): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4, injuries=knee): 6 → [Leg Press, Sumo Deadlift, Standing Calf Raise, Seated Calf Raise, Standing Single Leg Curl]
  - A4 (mp=knee_dominant, suit=any, excluded=4, injuries=knee): 6 → [Leg Press, Sumo Deadlift, Standing Calf Raise, Seated Calf Raise, Standing Single Leg Curl]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5, injuries=knee): 5 → [Leg Press, Sumo Deadlift, Seated Calf Raise, Standing Single Leg Curl, Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=any, excluded=5, injuries=knee): 5 → [Leg Press, Sumo Deadlift, Seated Calf Raise, Standing Single Leg Curl, Donkey Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Press (attempt3DropTypeAndTarget)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Press
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6, injuries=knee): 7 → [Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A4 (mp=hip_isolation, suit=any, excluded=6, injuries=knee): 7 → [Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Press, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7, injuries=knee): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7, injuries=knee): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, injuries=knee): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3, injuries=knee): 36 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=3, injuries=knee): 36 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4, injuries=knee): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4, injuries=knee): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7, injuries=knee): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7, injuries=knee): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, injuries=knee): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2, injuries=knee): 37 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3, injuries=knee): 36 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=3, injuries=knee): 36 → [Ab Wheel Rollout, Yoke Walk, Zercher Carry, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4, injuries=knee): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4, injuries=knee): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4, injuries=knee): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5, injuries=knee): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5, injuries=knee): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5, injuries=knee): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6, injuries=knee): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6, injuries=knee): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6, injuries=knee): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7, injuries=knee): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7, injuries=knee): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7, injuries=knee): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

---

## Combo: combo-1 inputs × all 4 week characters

**INPUT:**
- goal=build_muscle
- equipment=full_gym
- daysPerWeek=5
- experience=advanced
- phase=1
- sessionDuration=null
- injuries=[]

**EFFECTIVE:**
- effectiveExp=advanced
- equipmentTier=full_gym

### Week baseline

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

### Week overreach

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

### Week peak

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Dumbbell Fly]
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 4 → [Dumbbell Fly, Cable Fly, Cable Crossover, Pec Deck]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 23 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Fly (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Mid Chest/cable/horizontal_push/isolation/P3
  - excludeNames-in (5): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable)
  - A1 (mp=horizontal_push, tf="Mid Chest (cable)", tm="Mid Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=isolation, suit=any, excluded=5): 4 → [Cable Fly, Cable Crossover, Pec Deck, Svend Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=5): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Cable Fly (attempt2DropSubFocus)

- **Slot:** Front Delts/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly
  - A1 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Front Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 1 → [Cable Front Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Cable Front Raise (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (7): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Fly, Lateral Raise, Tricep Pushdown (Cable), Cable Fly, Cable Front Raise
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=7): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=7): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Dumbbell Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Dumbbell Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P3
  - excludeNames-in (5): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=5): 4 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=5): 11 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=5): 13 → [Barbell Bent Over Row, Seated Cable Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Rear Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (6): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tf="Rear Delts (cable)", tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=6): 7 → [Lateral Raise, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Band Pull Apart (attempt2DropSubFocus)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P4
  - excludeNames-in (7): Lat Pulldown, Dumbbell Row, Chin Up, Face Pull, Barbell Curl, Barbell Bent Over Row, Band Pull Apart
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=7): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=7): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Lateral Raise
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Biceps/long_head/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=elbow_flexion, tf="Biceps (long_head)", tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 9 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 11 → [Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl, Preacher Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Dumbbell Curl (attempt2DropSubFocus)

- **Slot:** Triceps/long_head/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl
  - A1 (mp=elbow_extension, tf="Triceps (long_head)", tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 6 → [Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension, Cable Tricep Kickback]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 8 → [Bench Dips, Close-Grip Bench Press, Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Skull Crusher (attempt2DropSubFocus)

- **Slot:** Lateral Delts/cable/shoulder_isolation/isolation/P4
  - excludeNames-in (7): Barbell Overhead Press, Lateral Raise, Face Pull, Barbell Curl, Tricep Pushdown (Cable), Dumbbell Curl, Skull Crusher
  - A1 (mp=shoulder_isolation, tf="Lateral Delts (cable)", tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 0
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=7): 2 → [Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A4 (mp=shoulder_isolation, suit=any, excluded=7): 6 → [Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise, Reverse Fly]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Machine Lateral Raise (attempt2DropSubFocus)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 33 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Leg Extension
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 32 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P3
  - excludeNames-in (5): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 31 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying)
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Barbell Back Squat, Deadlift, Leg Extension, Glute Bridge, Standing Calf Raise, Leg Curl (Lying), Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (2): Deadlift, Romanian Deadlift
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=2): 9 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable)]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A4 (mp=hip_isolation, suit=any, excluded=2): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

- **Slot:** Hamstrings/knee_dominant/isolation/P2
  - excludeNames-in (3): Deadlift, Romanian Deadlift, Glute Bridge
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Leg Curl (Lying)]
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 2 → [Leg Curl (Lying), Standing Single Leg Curl]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Curl (Lying) (attempt1Exact)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying)
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 33 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P3
  - excludeNames-in (5): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=5): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=5): 32 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Extension (attempt2DropSubFocus)

- **Slot:** Hip/hip_isolation/isolation/P4
  - excludeNames-in (6): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension
  - A1 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 0
  - A2 (mp=hip_isolation, tm="Hip", eq=full_gym, type=isolation, suit=any, excluded=6): 2 → [Hip Abduction Machine, Hip Adduction Machine]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=6): 9 → [Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Hip Abduction Machine (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P4
  - excludeNames-in (7): Deadlift, Romanian Deadlift, Glute Bridge, Leg Curl (Lying), Standing Calf Raise, Leg Extension, Hip Abduction Machine
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=7): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=7): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=7): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Overhead Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 7 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 14 → [Hanging Leg Raise, Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A4 (mp=core, suit=any, excluded=2): 38 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Sled Push]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Hanging Leg Raise (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A4 (mp=core, suit=any, excluded=3): 37 → [Ab Wheel Rollout, Zercher Carry, Yoke Walk, Farmers Carry, Battle Ropes]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt2DropSubFocus)

- **Slot:** Mid Chest/horizontal_push/compound/P3
  - excludeNames-in (4): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=4): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, excluded=4): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=4): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (5): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=5): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=5): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=5): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P4
  - excludeNames-in (6): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=6): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=6): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=6): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P4
  - excludeNames-in (7): Barbell Overhead Press, Barbell Bent Over Row, Hanging Leg Raise, Cable Crunch, Barbell Bench Press, Barbell Curl, Tricep Pushdown (Cable)
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=7): 2 → [Lat Pulldown, Chin Up]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=7): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any, excluded=7): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

### Week deload

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 2 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4
- POST-VolumeFilter: 2 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Mid Chest/cable/horizontal_push/isolation/P3, Front Delts/shoulder_isolation/isolation/P4, Triceps/long_head/elbow_extension/isolation/P4

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 9 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, JM Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 25 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 24 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 2 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4
- POST-VolumeFilter: 2 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Mid Back/horizontal_pull/compound/P3, Rear Delts/cable/shoulder_isolation/isolation/P4, Biceps/long_head/elbow_flexion/isolation/P4

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any): 4 → [Lat Pulldown, Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A4 (mp=vertical_pull, suit=any): 9 → [Lat Pulldown, Chin Up, Upright Row, Dumbbell Pullover, Machine High Row]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/thickness/horizontal_pull/compound/P1
  - excludeNames-in (1): Lat Pulldown
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 2 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1
  - ⚠️ Dropped by VolumeFilter: Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4
- POST-VolumeFilter: 2 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1
  - ⚠️ Dropped by VolumeFilter: Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3, Triceps/long_head/elbow_extension/isolation/P4, Lateral Delts/cable/shoulder_isolation/isolation/P4

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 6 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press, Single Arm Kettlebell Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=1): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=1): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=1): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 8 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 2 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1
  - ⚠️ Dropped by VolumeFilter: Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Hamstrings/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 34 → [Reverse Lunge, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4
- POST-VolumeFilter: 2 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1
  - ⚠️ Dropped by VolumeFilter: Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3, Quads/isolation/knee_dominant/isolation/P3, Hip/hip_isolation/isolation/P4, Core/core/isolation/P4

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Romanian Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 10 → [Deadlift, Romanian Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any): 20 → [Deadlift, Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Romanian Deadlift, Hip Thrust]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 10 → [Romanian Deadlift, Hip Thrust, Trap Bar Deadlift, Rack Pull, Single Leg Romanian Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 19 → [Romanian Deadlift, Hip Thrust, Power Clean, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 2 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 8 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4
- POST-VolumeFilter: 2 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Core/core/isolation/P2, Core/obliques/core/isolation/P2, Mid Chest/horizontal_push/compound/P3, Biceps/elbow_flexion/isolation/P3, Triceps/elbow_extension/isolation/P4, Lats/vertical_pull/compound/P4

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 4 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Overhead Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 14 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

---

