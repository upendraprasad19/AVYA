# V4 Diagnostic — 2026-04-16

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
| horizontal_push | basic_gym | beginner | true | 5 |
| horizontal_push | basic_gym | beginner | false | 7 |
| horizontal_push | basic_gym | intermediate | true | 8 |
| horizontal_push | basic_gym | intermediate | false | 17 |
| horizontal_push | basic_gym | advanced | true | 7 |
| horizontal_push | basic_gym | advanced | false | 17 |
| horizontal_push | full_gym | beginner | true | 6 |
| horizontal_push | full_gym | beginner | false | 10 |
| horizontal_push | full_gym | intermediate | true | 9 |
| horizontal_push | full_gym | intermediate | false | 22 |
| horizontal_push | full_gym | advanced | true | 8 |
| horizontal_push | full_gym | advanced | false | 22 |
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
| vertical_push | basic_gym | beginner | true | 3 |
| vertical_push | basic_gym | beginner | false | 4 |
| vertical_push | basic_gym | intermediate | true | 5 |
| vertical_push | basic_gym | intermediate | false | 7 |
| vertical_push | basic_gym | advanced | true | 4 |
| vertical_push | basic_gym | advanced | false | 5 |
| vertical_push | full_gym | beginner | true | 3 |
| vertical_push | full_gym | beginner | false | 4 |
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
| horizontal_pull | full_gym | beginner | true | 4 |
| horizontal_pull | full_gym | beginner | false | 7 |
| horizontal_pull | full_gym | intermediate | true | 5 |
| horizontal_pull | full_gym | intermediate | false | 13 |
| horizontal_pull | full_gym | advanced | true | 4 |
| horizontal_pull | full_gym | advanced | false | 12 |
| vertical_pull | bodyweight | beginner | true | 0 ⚠️ |
| vertical_pull | bodyweight | beginner | false | 0 ⚠️ |
| vertical_pull | bodyweight | intermediate | true | 0 ⚠️ |
| vertical_pull | bodyweight | intermediate | false | 0 ⚠️ |
| vertical_pull | bodyweight | advanced | true | 0 ⚠️ |
| vertical_pull | bodyweight | advanced | false | 0 ⚠️ |
| vertical_pull | home_dumbbells | beginner | true | 0 ⚠️ |
| vertical_pull | home_dumbbells | beginner | false | 0 ⚠️ |
| vertical_pull | home_dumbbells | intermediate | true | 2 |
| vertical_pull | home_dumbbells | intermediate | false | 3 |
| vertical_pull | home_dumbbells | advanced | true | 2 |
| vertical_pull | home_dumbbells | advanced | false | 5 |
| vertical_pull | basic_gym | beginner | true | 1 |
| vertical_pull | basic_gym | beginner | false | 3 |
| vertical_pull | basic_gym | intermediate | true | 3 |
| vertical_pull | basic_gym | intermediate | false | 6 |
| vertical_pull | basic_gym | advanced | true | 3 |
| vertical_pull | basic_gym | advanced | false | 8 |
| vertical_pull | full_gym | beginner | true | 1 |
| vertical_pull | full_gym | beginner | false | 3 |
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
| knee_dominant | basic_gym | beginner | false | 2 |
| knee_dominant | basic_gym | intermediate | true | 0 ⚠️ |
| knee_dominant | basic_gym | intermediate | false | 7 |
| knee_dominant | basic_gym | advanced | true | 0 ⚠️ |
| knee_dominant | basic_gym | advanced | false | 11 |
| knee_dominant | full_gym | beginner | true | 8 |
| knee_dominant | full_gym | beginner | false | 12 |
| knee_dominant | full_gym | intermediate | true | 13 |
| knee_dominant | full_gym | intermediate | false | 23 |
| knee_dominant | full_gym | advanced | true | 13 |
| knee_dominant | full_gym | advanced | false | 30 |
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
| hip_dominant | basic_gym | beginner | false | 3 |
| hip_dominant | basic_gym | intermediate | true | 3 |
| hip_dominant | basic_gym | intermediate | false | 11 |
| hip_dominant | basic_gym | advanced | true | 3 |
| hip_dominant | basic_gym | advanced | false | 13 |
| hip_dominant | full_gym | beginner | true | 1 |
| hip_dominant | full_gym | beginner | false | 7 |
| hip_dominant | full_gym | intermediate | true | 5 |
| hip_dominant | full_gym | intermediate | false | 18 |
| hip_dominant | full_gym | advanced | true | 5 |
| hip_dominant | full_gym | advanced | false | 23 |
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
| core | full_gym | beginner | false | 16 |
| core | full_gym | intermediate | true | 11 |
| core | full_gym | intermediate | false | 27 |
| core | full_gym | advanced | true | 11 |
| core | full_gym | advanced | false | 37 |
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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt3DropTypeAndTarget)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_push, eq=bodyweight, suit=beginner, excluded=1): 1 → [Pike Push Up]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Pike Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Pike Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Pike Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Pike Push Up, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_push, eq=bodyweight, suit=beginner, excluded=1): 1 → [Pike Push Up]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Pike Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Pike Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Pike Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Pike Push Up, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

#### Day "Full Body B" (full_body, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_pull, eq=bodyweight, suit=beginner, excluded=1): 0
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt4DropEquipment)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Lat Pulldown, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Lat Pulldown, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_pull, eq=bodyweight, suit=beginner, excluded=1): 0
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt4DropEquipment)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Push Up, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=bodyweight, type=compound, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=2): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Push Up, Lat Pulldown, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=3): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=3): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Lat Pulldown, Inverted Row, Walking Lunge
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

#### Day "Full Body C" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=2): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=2): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Push Up, Inverted Row, Walking Lunge
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, excluded=3): 0
  - A3 (mp=hip_dominant, eq=bodyweight, suit=beginner, excluded=3): 0
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 7 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Leg Curl (Lying)]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt4DropEquipment)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Inverted Row, Walking Lunge, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=bodyweight, type=compound, suit=beginner): 0
  - A3 (mp=horizontal_push, eq=bodyweight, suit=beginner): 4 → [Push Up, Diamond Push Up, Dand (Hindu Pushup), Incline Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Push Up (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Push Up
  - A1 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=bodyweight, type=compound, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A3 (mp=horizontal_pull, eq=bodyweight, suit=beginner, excluded=1): 1 → [Inverted Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Inverted Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Push Up, Inverted Row
  - A1 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=2): 2 → [Walking Lunge, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=bodyweight, type=compound, suit=beginner, excluded=2): 3 → [Walking Lunge, Reverse Lunge, Sumo Squat]
  - A3 (mp=knee_dominant, eq=bodyweight, suit=beginner, excluded=2): 5 → [Walking Lunge, Reverse Lunge, Sumo Squat, Baithak (Hindu Squat), Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Walking Lunge (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Push Up, Inverted Row, Walking Lunge
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=bodyweight, type=compound, suit=beginner, excluded=3): 0
  - A3 (mp=hip_dominant, eq=bodyweight, suit=beginner, excluded=3): 0
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 7 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Leg Curl (Lying)]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt4DropEquipment)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Push Up, Inverted Row, Walking Lunge, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, foundational=true, excluded=4): 4 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch]
  - A2 (mp=core, tm="Core", eq=bodyweight, type=isolation, suit=beginner, excluded=4): 6 → [Russian Twist, Reverse Crunch, Crunches, Bicycle Crunch, Flutter Kicks]
  - A3 (mp=core, eq=bodyweight, suit=beginner, excluded=4): 10 → [Plank, Dead Bug, Russian Twist, Reverse Crunch, Crunches]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt1Exact)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate): 11 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A4 (mp=horizontal_push, suit=intermediate): 22 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Dumbbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A3 (mp=vertical_push, eq=home_dumbbells, suit=intermediate, excluded=1): 6 → [Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press, Pike Push Up]
  - A4 (mp=vertical_push, suit=intermediate, excluded=1): 10 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt3DropTypeAndTarget)

- **Slot:** Upper Chest/horizontal_push/compound/P2
  - excludeNames-in (2): Dumbbell Bench Press, Dumbbell Shoulder Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate, excluded=2): 10 → [Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=intermediate, excluded=2): 21 → [Barbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Upper Chest/horizontal_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=home_dumbbells, type=compound, suit=intermediate): 5 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate): 11 → [Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press]
  - A4 (mp=horizontal_push, suit=intermediate): 22 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Dumbbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A3 (mp=vertical_push, eq=home_dumbbells, suit=intermediate, excluded=1): 6 → [Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press, Pike Push Up]
  - A4 (mp=vertical_push, suit=intermediate, excluded=1): 10 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt3DropTypeAndTarget)

- **Slot:** Upper Chest/horizontal_push/compound/P2
  - excludeNames-in (2): Dumbbell Bench Press, Dumbbell Shoulder Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=home_dumbbells, type=compound, suit=intermediate, excluded=2): 0
  - A3 (mp=horizontal_push, eq=home_dumbbells, suit=intermediate, excluded=2): 10 → [Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=intermediate, excluded=2): 21 → [Barbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
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

#### Day "Lower Body" (legs, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3
- POST-VolumeFilter: 3 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3, Core/core/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 23 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A3 (mp=hip_dominant, eq=home_dumbbells, suit=intermediate, excluded=1): 4 → [Single Leg Romanian Deadlift, Kettlebell Swing, Banded Hip Thrust, B-Stance RDL]
  - A4 (mp=hip_dominant, suit=intermediate, excluded=1): 18 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3
- POST-VolumeFilter: 3 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3, Core/core/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 23 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Single Leg Romanian Deadlift, Kettlebell Swing, B-Stance RDL]
  - A3 (mp=hip_dominant, eq=home_dumbbells, suit=intermediate, excluded=1): 4 → [Single Leg Romanian Deadlift, Kettlebell Swing, Banded Hip Thrust, B-Stance RDL]
  - A4 (mp=hip_dominant, suit=intermediate, excluded=1): 18 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift]
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

#### Day "Upper Pull" (pull, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt3DropTypeAndTarget)

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

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 0
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt3DropTypeAndTarget)

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

#### Day "Full Body + Core" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Glutes/hip_isolation/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 23 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Banded Squat, Dumbbell Row
  - A1 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 4 → [V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 4 → [V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=2): 12 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=2): 27 → [Farmers Carry, Suitcase Carry, Landmine Rotation, Kettlebell Turkish Get Up, Lunge with Twist]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** V-Ups (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Banded Squat, Dumbbell Row, V-Ups
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 3 → [Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=3): 11 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=3): 26 → [Farmers Carry, Suitcase Carry, Landmine Rotation, Kettlebell Turkish Get Up, Lunge with Twist]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Flutter Kicks (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Glutes/hip_isolation/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Glutes/hip_isolation/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=home_dumbbells, type=compound, suit=intermediate): 3 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=home_dumbbells, suit=intermediate): 7 → [Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Baithak (Hindu Squat), Jump Squat]
  - A4 (mp=knee_dominant, suit=intermediate): 23 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Banded Squat (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Banded Squat
  - A1 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=home_dumbbells, type=compound, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A3 (mp=horizontal_pull, eq=home_dumbbells, suit=intermediate, excluded=1): 3 → [Dumbbell Row, Renegade Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=intermediate, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Banded Squat, Dumbbell Row
  - A1 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 4 → [V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=2): 4 → [V-Ups, Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=2): 12 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=2): 27 → [Farmers Carry, Suitcase Carry, Landmine Rotation, Kettlebell Turkish Get Up, Lunge with Twist]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** V-Ups (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Banded Squat, Dumbbell Row, V-Ups
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=home_dumbbells, type=isolation, suit=intermediate, excluded=3): 3 → [Flutter Kicks, Side Plank, Janda Sit Up]
  - A3 (mp=core, eq=home_dumbbells, suit=intermediate, excluded=3): 11 → [Kettlebell Turkish Get Up, Plank, Dead Bug, Hanging Leg Raise, Hollow Body Hold]
  - A4 (mp=core, suit=intermediate, excluded=3): 26 → [Farmers Carry, Suitcase Carry, Landmine Rotation, Kettlebell Turkish Get Up, Lunge with Twist]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Flutter Kicks (attempt2DropSubFocus)

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

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 1 → [Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Z Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 1 → [Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, excluded=2): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, excluded=2): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Z Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Pull" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 6 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 6 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 6 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Legs" (legs, endurance)

**Variant A**

- PRE-VolumeFilter: 6 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3, Core/core/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

**Variant B**

- PRE-VolumeFilter: 6 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3, Core/core/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

#### Day "Upper" (upper, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Lateral Raise
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=2): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Lateral Raise
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=3): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

#### Day "Lower + Core" (legs, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 12 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Barbell Back Squat, Deadlift, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

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

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any): 6 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=1): 17 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
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

**Variant B**

- PRE-VolumeFilter: 6 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2, Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Lower Chest/horizontal_push/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any): 6 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=basic_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=1): 17 → [Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press, JM Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
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

#### Day "Pull A" (pull, strength)

**Variant A**

- PRE-VolumeFilter: 6 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 4 → [Seated Cable Row, Chest Supported Row, Pendlay Row, Machine Low Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any, excluded=2): 7 → [Chin Up, Dumbbell Pullover, Machine High Row, Pull Up, Muscle Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=3): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3, Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 4 → [Seated Cable Row, Chest Supported Row, Pendlay Row, Machine Low Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=basic_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=basic_gym, suit=any, excluded=2): 7 → [Chin Up, Dumbbell Pullover, Machine High Row, Pull Up, Muscle Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=3): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Legs A" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 6 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3, Core/core/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any): 5 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any): 11 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Zercher Squat (attempt2DropSubFocus)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Zercher Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, excluded=1): 9 → [Deadlift, Sumo Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 13 → [Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Zercher Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=2): 10 → [Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Pistol Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Jefferson Squat (attempt3DropTypeAndTarget)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Zercher Squat, Deadlift, Jefferson Squat
  - A1 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 6 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3, Core/core/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3, Core/core/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=compound, suit=any): 5 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any): 11 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Zercher Squat (attempt2DropSubFocus)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Zercher Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, excluded=1): 9 → [Deadlift, Sumo Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 13 → [Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Zercher Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=basic_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=2): 10 → [Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge, Pistol Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Jefferson Squat (attempt3DropTypeAndTarget)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Zercher Squat, Deadlift, Jefferson Squat
  - A1 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=hip_isolation, tm="Glutes", eq=basic_gym, type=isolation, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A3 (mp=hip_isolation, eq=basic_gym, suit=any, excluded=3): 4 → [Kas Glute Bridge, Hip Abductor Machine, Lateral Band Walk, Frog Pumps]
  - A4 (mp=hip_isolation, suit=any, excluded=3): 10 → [Glute Bridge, Kas Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Kas Glute Bridge (attempt2DropSubFocus)

#### Day "Push B" (push, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 6 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any): 0
  - A3 (mp=vertical_push, eq=basic_gym, suit=any): 7 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt3DropTypeAndTarget)

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
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, excluded=2): 6 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=2): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Barbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=3): 5 → [Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise, Cable Front Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 6 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Mid Chest/horizontal_push/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3, Triceps/long_head/elbow_extension/isolation/P3

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=basic_gym, type=compound, suit=any): 0
  - A3 (mp=vertical_push, eq=basic_gym, suit=any): 7 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Barbell Overhead Press (attempt3DropTypeAndTarget)

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
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=basic_gym, type=compound, suit=any, excluded=2): 6 → [Barbell Bench Press, Dumbbell Bench Press, Single Arm Dumbbell Press, Chest Squeeze Press, Deficit Push-Up]
  - A3 (mp=horizontal_push, eq=basic_gym, suit=any, excluded=2): 18 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Overhead Press, Lateral Raise, Barbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=3): 5 → [Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise, Cable Front Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 7 → [Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise, Egyptian Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Pull B" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 4 → [Seated Cable Row, Chest Supported Row, Pendlay Row, Machine Low Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=2): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 5 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Biceps/long_head/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/long_head/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Seated Cable Row, Chest Supported Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=basic_gym, type=compound, suit=any, excluded=1): 4 → [Seated Cable Row, Chest Supported Row, Pendlay Row, Machine Low Row]
  - A3 (mp=horizontal_pull, eq=basic_gym, suit=any, excluded=1): 8 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Renegade Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=basic_gym, type=isolation, suit=any, excluded=2): 2 → [Face Pull, Band Pull Apart]
  - A3 (mp=shoulder_isolation, eq=basic_gym, suit=any, excluded=2): 6 → [Lateral Raise, Face Pull, Band Pull Apart, Machine Lateral Raise, Egyptian Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=2): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, foundational=true, excluded=3): 5 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=basic_gym, type=isolation, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=basic_gym, suit=any, excluded=3): 9 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=3): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

#### Day "Legs B" (legs, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 6 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Core/core/isolation/P3, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Core/core/isolation/P3, Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any): 9 → [Deadlift, Sumo Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any): 13 → [Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, excluded=1): 8 → [Hip Thrust, Sumo Deadlift, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 12 → [Hip Thrust, Sumo Deadlift, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=basic_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=3): 11 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Zercher Squat (attempt3DropTypeAndTarget)

**Variant B**

- PRE-VolumeFilter: 6 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Core/core/isolation/P3, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Core/core/isolation/P3, Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any, foundational=true): 2 → [Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=basic_gym, type=compound, suit=any): 9 → [Deadlift, Sumo Deadlift, Snatch Grip Deadlift, Single Leg Romanian Deadlift, Good Morning]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any): 13 → [Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Snatch Grip Deadlift]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, foundational=true, excluded=1): 2 → [Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=basic_gym, type=compound, suit=any, excluded=1): 8 → [Hip Thrust, Sumo Deadlift, Single Leg Romanian Deadlift, Good Morning, Kettlebell Swing]
  - A3 (mp=hip_dominant, eq=basic_gym, suit=any, excluded=1): 12 → [Hip Thrust, Sumo Deadlift, Power Clean, Snatch Grip Deadlift, Single Leg Romanian Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=basic_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=basic_gym, suit=any, excluded=3): 11 → [Zercher Squat, Jefferson Squat, Banded Squat, High Box Step-Up, Deficit Reverse Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Zercher Squat (attempt3DropTypeAndTarget)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner, excluded=1): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Dumbbell Shoulder Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=2): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Dumbbell Shoulder Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Dumbbell Shoulder Press, Dumbbell Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, excluded=1): 0
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner, excluded=1): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner, excluded=1): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt3DropTypeAndTarget)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Dumbbell Shoulder Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=2): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Dumbbell Shoulder Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Dumbbell Shoulder Press, Dumbbell Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

#### Day "Full Body B" (full_body, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 2 → [Lat Pulldown, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, excluded=2): 5 → [Seated Cable Row, Chest Supported Row, Inverted Row, TRX Row, Machine Low Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Lat Pulldown, Seated Cable Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Lat Pulldown, Seated Cable Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/width/vertical_pull/compound/P1, Mid Back/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/width/vertical_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=vertical_pull, tf="Lats (width)", tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 2 → [Lat Pulldown, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Mid Back/horizontal_pull/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Lat Pulldown
  - A1 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=beginner, excluded=2): 5 → [Seated Cable Row, Chest Supported Row, Inverted Row, TRX Row, Machine Low Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=2): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Lat Pulldown, Seated Cable Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=3): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=3): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Lat Pulldown, Seated Cable Row, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

#### Day "Full Body C" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=1): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Dumbbell Row, Goblet Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, excluded=3): 2 → [Trap Bar Deadlift, Cable Pull-Through]
  - A3 (mp=hip_dominant, eq=full_gym, suit=beginner, excluded=3): 7 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Leg Curl (Lying)]
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 7 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Leg Curl (Lying)]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Dumbbell Row, Goblet Squat, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Lats/horizontal_pull/compound/P1, Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Core/core/isolation/P2

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner, foundational=true): 3 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=beginner): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A4 (mp=horizontal_push, suit=beginner): 10 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Floor Press, Push Up]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 3 → [Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 5 → [Dumbbell Row, Chest Supported Row, Inverted Row, Kettlebell Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=beginner, excluded=1): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A4 (mp=horizontal_pull, suit=beginner, excluded=1): 7 → [Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row, Kettlebell Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Dumbbell Row (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Barbell Bench Press, Dumbbell Row
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (3): Barbell Bench Press, Dumbbell Row, Goblet Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=3): 0
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=beginner, excluded=3): 2 → [Trap Bar Deadlift, Cable Pull-Through]
  - A3 (mp=hip_dominant, eq=full_gym, suit=beginner, excluded=3): 7 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Leg Curl (Lying)]
  - A4 (mp=hip_dominant, suit=beginner, excluded=3): 7 → [Trap Bar Deadlift, Medicine Ball Slam, Banded Hip Thrust, Cable Pull-Through, Leg Curl (Lying)]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Trap Bar Deadlift (attempt2DropSubFocus)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (4): Barbell Bench Press, Dumbbell Row, Goblet Squat, Trap Bar Deadlift
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=4): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=4): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=4): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

#### Day "Full Body D" (full_body, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner): 0
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt3DropTypeAndTarget)

- **Slot:** Lats/vertical_pull/compound/P1
  - excludeNames-in (1): Dumbbell Shoulder Press
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 2 → [Lat Pulldown, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Dumbbell Shoulder Press, Lat Pulldown
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (3): Dumbbell Shoulder Press, Lat Pulldown, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=3): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=3): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=3): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=3): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/vertical_pull/compound/P1, Quads/knee_dominant/compound/P1, Core/core/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=beginner): 0
  - A3 (mp=vertical_push, eq=full_gym, suit=beginner): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A4 (mp=vertical_push, suit=beginner): 4 → [Dumbbell Shoulder Press, Kettlebell Goblet Press, Pike Push Up, Front Raise]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Dumbbell Shoulder Press (attempt3DropTypeAndTarget)

- **Slot:** Lats/vertical_pull/compound/P1
  - excludeNames-in (1): Dumbbell Shoulder Press
  - A1 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=1): 1 → [Lat Pulldown]
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=beginner, excluded=1): 2 → [Lat Pulldown, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A4 (mp=vertical_pull, suit=beginner, excluded=1): 3 → [Lat Pulldown, Machine High Row, Straight-Arm Pulldown]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Lat Pulldown (attempt1Exact)

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (2): Dumbbell Shoulder Press, Lat Pulldown
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, foundational=true, excluded=2): 5 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=beginner, excluded=2): 7 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A3 (mp=knee_dominant, eq=full_gym, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A4 (mp=knee_dominant, suit=beginner, excluded=2): 12 → [Goblet Squat, Leg Press, Walking Lunge, Step Up, Reverse Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Goblet Squat (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (3): Dumbbell Shoulder Press, Lat Pulldown, Goblet Squat
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, foundational=true, excluded=3): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=beginner, excluded=3): 9 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=beginner, excluded=3): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A4 (mp=core, suit=beginner, excluded=3): 16 → [Farmers Carry, Suitcase Carry, Plank, Dead Bug, Cable Crunch]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

- **Slot:** Triceps/elbow_extension/isolation/P3
  - excludeNames-in (4): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press, Lateral Raise
  - A1 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 3 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A2 (mp=elbow_extension, tm="Triceps", eq=full_gym, type=isolation, suit=any, excluded=4): 7 → [Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension, Dumbbell Kickback, Overhead Cable Extension]
  - A3 (mp=elbow_extension, eq=full_gym, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A4 (mp=elbow_extension, suit=any, excluded=4): 9 → [Bench Dips, Close-Grip Bench Press, Tricep Pushdown (Cable), Skull Crusher, Overhead Tricep Extension]
  - A5 (universal_pool[elbow_extension]): 3 → [Diamond Push Up, Bench Dips, Dip (Parallel Bars)]
  - **PICK:** Tricep Pushdown (Cable) (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Seated Cable Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

- **Slot:** Biceps/elbow_flexion/isolation/P3
  - excludeNames-in (4): Lat Pulldown, Seated Cable Row, Chin Up, Face Pull
  - A1 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 6 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A2 (mp=elbow_flexion, tm="Biceps", eq=full_gym, type=isolation, suit=any, excluded=4): 10 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A3 (mp=elbow_flexion, eq=full_gym, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A4 (mp=elbow_flexion, suit=any, excluded=4): 12 → [Barbell Curl, Dumbbell Curl, Hammer Curl, Concentration Curl, Cable Curl]
  - A5 (universal_pool[elbow_flexion]): 2 → [Chin Up, Inverted Row]
  - **PICK:** Barbell Curl (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 28 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 28 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt3DropTypeAndTarget)

- **Slot:** Calves/knee_dominant/isolation/P3
  - excludeNames-in (4): Deadlift, Romanian Deadlift, Glute Bridge, Barbell Back Squat
  - A1 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=4): 2 → [Standing Calf Raise, Seated Calf Raise]
  - A2 (mp=knee_dominant, tm="Calves", eq=full_gym, type=isolation, suit=any, excluded=4): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=4): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=4): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt3DropTypeAndTarget)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, injuries=knee): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, injuries=knee): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, injuries=knee): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1, injuries=knee): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1, injuries=knee): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, injuries=knee): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, injuries=knee): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any, injuries=knee): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1, injuries=knee): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1, injuries=knee): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2, injuries=knee): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2, injuries=knee): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2, injuries=knee): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2, injuries=knee): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3, injuries=knee): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, injuries=knee): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, injuries=knee): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 1 → [Leg Press]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, injuries=knee): 1 → [Leg Press]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, injuries=knee): 4 → [Leg Press, Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=any, injuries=knee): 4 → [Leg Press, Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Press (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Leg Press
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1, injuries=knee): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1, injuries=knee): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Leg Press, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2, injuries=knee): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=any, excluded=2, injuries=knee): 3 → [Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Standing Calf Raise (attempt3DropTypeAndTarget)

- **Slot:** Glutes/hip_isolation/isolation/P2
  - excludeNames-in (3): Leg Press, Deadlift, Standing Calf Raise
  - A1 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 1 → [Glute Bridge]
  - A2 (mp=hip_isolation, tm="Glutes", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 7 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Glute Kickback (Cable), Lateral Band Walk]
  - A3 (mp=hip_isolation, eq=full_gym, suit=any, excluded=3, injuries=knee): 8 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A4 (mp=hip_isolation, suit=any, excluded=3, injuries=knee): 8 → [Glute Bridge, Hip Abductor Machine, Hip Abduction Machine, Hip Adduction Machine, Glute Kickback (Cable)]
  - A5 (universal_pool[hip_isolation]): 3 → [Glute Bridge, Side Plank, Glute Bridge]
  - **PICK:** Glute Bridge (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, injuries=knee): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, injuries=knee): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, injuries=knee): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1, injuries=knee): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1, injuries=knee): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3, injuries=knee): 4 → [Leg Press, Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A4 (mp=knee_dominant, suit=any, excluded=3, injuries=knee): 4 → [Leg Press, Standing Calf Raise, Seated Calf Raise, Donkey Calf Raise]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Leg Press (attempt3DropTypeAndTarget)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, injuries=knee): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2, injuries=knee): 36 → [Zercher Carry, Farmers Carry, Yoke Walk, Turkish Get Up (Half), GHD Sit Up]
  - A4 (mp=core, suit=any, excluded=2, injuries=knee): 36 → [Zercher Carry, Farmers Carry, Yoke Walk, Turkish Get Up (Half), GHD Sit Up]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3, injuries=knee): 35 → [Yoke Walk, Farmers Carry, Zercher Carry, Turkish Get Up (Half), Suitcase Carry]
  - A4 (mp=core, suit=any, excluded=3, injuries=knee): 35 → [Yoke Walk, Farmers Carry, Zercher Carry, Turkish Get Up (Half), Suitcase Carry]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true, injuries=knee): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, injuries=knee): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any, injuries=knee): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1, injuries=knee): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1, injuries=knee): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1, injuries=knee): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2, injuries=knee): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2, injuries=knee): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2, injuries=knee): 36 → [Zercher Carry, Farmers Carry, Yoke Walk, Turkish Get Up (Half), GHD Sit Up]
  - A4 (mp=core, suit=any, excluded=2, injuries=knee): 36 → [Zercher Carry, Farmers Carry, Yoke Walk, Turkish Get Up (Half), GHD Sit Up]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3, injuries=knee): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3, injuries=knee): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3, injuries=knee): 35 → [Yoke Walk, Farmers Carry, Zercher Carry, Turkish Get Up (Half), Suitcase Carry]
  - A4 (mp=core, suit=any, excluded=3, injuries=knee): 35 → [Yoke Walk, Farmers Carry, Zercher Carry, Turkish Get Up (Half), Suitcase Carry]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

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

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt3DropTypeAndTarget)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

### Week overreach

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt3DropTypeAndTarget)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

### Week peak

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

- **Slot:** Lower Chest/horizontal_push/isolation/P2
  - excludeNames-in (2): Barbell Bench Press, Incline Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=horizontal_push, tm="Lower Chest", eq=full_gym, type=isolation, suit=any, excluded=2): 0
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A4 (mp=horizontal_push, suit=any, excluded=2): 22 → [Dumbbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press, Decline Barbell Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Dumbbell Bench Press (attempt3DropTypeAndTarget)

- **Slot:** Lateral Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press
  - A1 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 1 → [Lateral Raise]
  - A2 (mp=shoulder_isolation, tm="Lateral Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Lateral Raise, Machine Lateral Raise, Egyptian Lateral Raise]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Lateral Raise (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 4 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

- **Slot:** Lats/lower/vertical_pull/compound/P2
  - excludeNames-in (2): Lat Pulldown, Seated Cable Row
  - A1 (mp=vertical_pull, tf="Lats (lower)", tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=vertical_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=2): 3 → [Chin Up, Dumbbell Pullover, Machine High Row]
  - A3 (mp=vertical_pull, eq=full_gym, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A4 (mp=vertical_pull, suit=any, excluded=2): 8 → [Chin Up, Upright Row, Dumbbell Pullover, Machine High Row, Pull Up]
  - A5 (universal_pool[vertical_pull]): 3 → [Pull Up, Chin Up, Inverted Row]
  - **PICK:** Chin Up (attempt2DropSubFocus)

- **Slot:** Rear Delts/shoulder_isolation/isolation/P2
  - excludeNames-in (3): Lat Pulldown, Seated Cable Row, Chin Up
  - A1 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 2 → [Face Pull, Band Pull Apart]
  - A2 (mp=shoulder_isolation, tm="Rear Delts", eq=full_gym, type=isolation, suit=any, excluded=3): 3 → [Face Pull, Band Pull Apart, Reverse Fly]
  - A3 (mp=shoulder_isolation, eq=full_gym, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A4 (mp=shoulder_isolation, suit=any, excluded=3): 8 → [Lateral Raise, Face Pull, Band Pull Apart, Shrug, Machine Lateral Raise]
  - A5 (universal_pool[shoulder_isolation]): 3 → [Pike Push Up, Arm Circles, Band Pull Apart]
  - **PICK:** Face Pull (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 4 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

#### Day "Legs" (legs, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Quads/isolation/knee_dominant/isolation/P2
  - excludeNames-in (2): Barbell Back Squat, Deadlift
  - A1 (mp=knee_dominant, tf="Quads (isolation)", tm="Quads", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 0
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=isolation, suit=any, excluded=2): 2 → [Leg Extension, Sissy Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
  - A4 (mp=knee_dominant, suit=any, excluded=2): 29 → [Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat, Walking Lunge]
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

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 4 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2
  - ⚠️ Dropped by VolumeFilter: Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
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
  - A1 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=knee_dominant, tm="Hamstrings", eq=full_gym, type=isolation, suit=any, excluded=3): 0
  - A3 (mp=knee_dominant, eq=full_gym, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any, excluded=3): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt3DropTypeAndTarget)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

- **Slot:** Core/core/isolation/P2
  - excludeNames-in (2): Z Press, Barbell Bent Over Row
  - A1 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=2): 6 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=2): 13 → [Cable Crunch, Russian Twist, Reverse Crunch, Pallof Press, Crunches]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=2): 37 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Cable Crunch (attempt1Exact)

- **Slot:** Core/obliques/core/isolation/P2
  - excludeNames-in (3): Z Press, Barbell Bent Over Row, Cable Crunch
  - A1 (mp=core, tf="Core (obliques)", tm="Core", eq=full_gym, type=isolation, suit=any, foundational=true, excluded=3): 0
  - A2 (mp=core, tm="Core", eq=full_gym, type=isolation, suit=any, excluded=3): 12 → [Russian Twist, Reverse Crunch, Pallof Press, Crunches, Bicycle Crunch]
  - A3 (mp=core, eq=full_gym, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A4 (mp=core, suit=any, excluded=3): 36 → [Zercher Carry, Yoke Walk, Farmers Carry, Suitcase Carry, Landmine Rotation]
  - A5 (universal_pool[core]): 5 → [Plank, Dead Bug, Hollow Body Hold, Bicycle Crunch, Mountain Climber]
  - **PICK:** Russian Twist (attempt2DropSubFocus)

### Week deload

#### Day "Chest" (push, strength)

**Variant A**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 2 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1, Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 2 slots — Mid Chest/horizontal_push/compound/P1, Upper Chest/horizontal_push/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lower Chest/horizontal_push/isolation/P2, Lateral Delts/shoulder_isolation/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Mid Chest/horizontal_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any, foundational=true): 4 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press]
  - A2 (mp=horizontal_push, tm="Mid Chest", eq=full_gym, type=compound, suit=any): 8 → [Barbell Bench Press, Dumbbell Bench Press, Machine Chest Press, Single Arm Dumbbell Press, Chest Squeeze Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A4 (mp=horizontal_push, suit=any): 24 → [Barbell Bench Press, Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Barbell Bench Press (attempt1Exact)

- **Slot:** Upper Chest/horizontal_push/compound/P1
  - excludeNames-in (1): Barbell Bench Press
  - A1 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 1 → [Incline Barbell Bench Press]
  - A2 (mp=horizontal_push, tm="Upper Chest", eq=full_gym, type=compound, suit=any, excluded=1): 1 → [Incline Barbell Bench Press]
  - A3 (mp=horizontal_push, eq=full_gym, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A4 (mp=horizontal_push, suit=any, excluded=1): 23 → [Dumbbell Bench Press, Incline Barbell Bench Press, Machine Chest Press, Close Grip Bench Press, Single Arm Dumbbell Press]
  - A5 (universal_pool[horizontal_push]): 5 → [Push Up, Incline Push Up, Wall Push Up, Decline Push Up, Diamond Push Up]
  - **PICK:** Incline Barbell Bench Press (attempt1Exact)

#### Day "Back" (pull, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 2 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1, Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3
- POST-VolumeFilter: 2 slots — Lats/width/vertical_pull/compound/P1, Mid Back/thickness/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Lats/lower/vertical_pull/compound/P2, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P3

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
  - A1 (mp=horizontal_pull, tf="Mid Back (thickness)", tm="Mid Back", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Seated Cable Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Mid Back", eq=full_gym, type=compound, suit=any, excluded=1): 7 → [Seated Cable Row, Chest Supported Row, Inverted Row, Seal Row, TRX Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Seated Cable Row (attempt1Exact)

#### Day "Shoulders + Arms" (shoulders_arms, endurance)

**Variant A**

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 2 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1
  - ⚠️ Dropped by VolumeFilter: Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

- PRE-VolumeFilter: 5 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1, Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3
- POST-VolumeFilter: 2 slots — Front Delts/vertical_push/compound/P1, Lateral Delts/shoulder_isolation/isolation/P1
  - ⚠️ Dropped by VolumeFilter: Rear Delts/shoulder_isolation/isolation/P2, Biceps/elbow_flexion/isolation/P2, Triceps/elbow_extension/isolation/P3

- **Slot:** Front Delts/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press]
  - A2 (mp=vertical_push, tm="Front Delts", eq=full_gym, type=compound, suit=any): 5 → [Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Single Arm Kettlebell Press, Kettlebell Goblet Press]
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

- PRE-VolumeFilter: 5 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 2 slots — Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1
  - ⚠️ Dropped by VolumeFilter: Quads/isolation/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3

- **Slot:** Quads/knee_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any, foundational=true): 10 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A2 (mp=knee_dominant, tm="Quads", eq=full_gym, type=compound, suit=any): 17 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A3 (mp=knee_dominant, eq=full_gym, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A4 (mp=knee_dominant, suit=any): 30 → [Barbell Back Squat, Front Squat, Goblet Squat, Leg Press, Bulgarian Split Squat]
  - A5 (universal_pool[knee_dominant]): 4 → [Baithak (Hindu Squat), Reverse Lunge, Bulgarian Split Squat, Jump Squat]
  - **PICK:** Barbell Back Squat (attempt1Exact)

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (1): Barbell Back Squat
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 5 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1, Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3
- POST-VolumeFilter: 2 slots — Hamstrings/hip_dominant/compound/P1, Glutes/hip_dominant/compound/P1
  - ⚠️ Dropped by VolumeFilter: Glutes/hip_isolation/isolation/P2, Hamstrings/knee_dominant/isolation/P2, Calves/knee_dominant/isolation/P3

- **Slot:** Hamstrings/hip_dominant/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any, foundational=true): 3 → [Deadlift, Romanian Deadlift, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Hamstrings", eq=full_gym, type=compound, suit=any): 11 → [Deadlift, Romanian Deadlift, Sumo Deadlift, Trap Bar Deadlift, Snatch Grip Deadlift]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A4 (mp=hip_dominant, suit=any): 23 → [Deadlift, Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Deadlift (attempt1Exact)

- **Slot:** Glutes/hip_dominant/compound/P1
  - excludeNames-in (1): Deadlift
  - A1 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 3 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift]
  - A2 (mp=hip_dominant, tm="Glutes", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Trap Bar Deadlift, Rack Pull]
  - A3 (mp=hip_dominant, eq=full_gym, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A4 (mp=hip_dominant, suit=any, excluded=1): 22 → [Romanian Deadlift, Hip Thrust, Sumo Deadlift, Power Clean, Trap Bar Deadlift]
  - A5 (universal_pool[hip_dominant]): 3 → [Glute Bridge, Single Leg Romanian Deadlift, Good Morning]
  - **PICK:** Romanian Deadlift (attempt1Exact)

#### Day "Upper + Core" (upper, hypertrophy)

**Variant A**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 2 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

**Variant B**

- PRE-VolumeFilter: 4 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1, Core/core/isolation/P2, Core/obliques/core/isolation/P2
- POST-VolumeFilter: 2 slots — Shoulders/vertical_push/compound/P1, Lats/horizontal_pull/compound/P1
  - ⚠️ Dropped by VolumeFilter: Core/core/isolation/P2, Core/obliques/core/isolation/P2

- **Slot:** Shoulders/vertical_push/compound/P1
  - excludeNames-in (0): {}
  - A1 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any, foundational=true): 0
  - A2 (mp=vertical_push, tm="Shoulders", eq=full_gym, type=compound, suit=any): 1 → [Z Press]
  - A3 (mp=vertical_push, eq=full_gym, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A4 (mp=vertical_push, suit=any): 12 → [Chest Dip, Barbell Overhead Press, Dumbbell Shoulder Press, Arnold Press, Landmine Press]
  - A5 (universal_pool[vertical_push]): 3 → [Pike Push Up, Handstand Hold, Dand (Hindu Pushup)]
  - **PICK:** Z Press (attempt2DropSubFocus)

- **Slot:** Lats/horizontal_pull/compound/P1
  - excludeNames-in (1): Z Press
  - A1 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, foundational=true, excluded=1): 4 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row]
  - A2 (mp=horizontal_pull, tm="Lats", eq=full_gym, type=compound, suit=any, excluded=1): 11 → [Barbell Bent Over Row, Dumbbell Row, Chest Supported Row, Inverted Row, T-Bar Row]
  - A3 (mp=horizontal_pull, eq=full_gym, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A4 (mp=horizontal_pull, suit=any, excluded=1): 13 → [Barbell Bent Over Row, Dumbbell Row, Seated Cable Row, Chest Supported Row, Inverted Row]
  - A5 (universal_pool[horizontal_pull]): 4 → [Inverted Row, TRX Row, Inverted Row, Dead Bug]
  - **PICK:** Barbell Bent Over Row (attempt1Exact)

---

