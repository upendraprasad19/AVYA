# Workout Generator — Baseline Scorecard (current engine)

> Frozen by Batch 0. Every later batch must IMPROVE its targeted
> dimension with NO regression here. Scores 0-100; safety is a hard gate.

## Aggregate (606 personas)
| Dimension | Mean |
|---|---|
| coverage | 88.6 |
| balance | 67.4 |
| volume | 70.4 |
| progression | 100.0 |
| personalization | 100.0 |
| safety | 100.0 |
| realism | 94.1 |
| overall | 86.7 |

- **Unsafe plans (contraindicated exercise present): 0** (HARD invariant — must be 0)
- **Equipment-violating plans: 290** (HARD invariant — must be 0)
- Plans with ≥1 fallback pick: 370 / total fallback picks: 1178
- Fallback picks by tier (baseline — shallow bodyweight pool; no-regression tracked): `{bodyweight: 617, home_dumbbells: 387, basic_gym: 135, full_gym: 39}`

## Curated plans (human face-validity)
---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:none
`coverage 90.0 · balance 54.2 · volume 78.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 87.0**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | barbell, bench |
| Upper Chest/horizontal_push | Incline Barbell Bench Press | attempt1Exact | Upper Chest, Front Deltoid | barbell, bench |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt1Exact | Side Deltoid | dumbbells |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | bodyweight |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | cables |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Face Pull | attempt1Exact | Rear Deltoid, Rhomboids | cables |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | barbell |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | machines |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | pull-up bar |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | machines |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | barbell |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Lateral Delts/shoulder_isolation | Machine Lateral Raise | attempt2DropSubFocus | Lateral Delts | machines |
| Biceps/elbow_flexion | Hammer Curl | attempt1Exact | Biceps (brachialis), Forearms | dumbbells |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | ez-bar, bench |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Biceps/elbow_flexion | Concentration Curl | attempt2DropSubFocus | Biceps | dumbbells |

---
### lose_fat | basic_gym | 4d | beginner | p1 | inj:none
`coverage 70.0 · balance 62.5 · volume 70.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 80.0 · **overall 80.4**`

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | barbell, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |
| Lats/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Quads/knee_dominant | Banded Squat | attempt2DropSubFocus | Quads, Glutes | resistance band |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Seated Cable Row | attempt1Exact | Rhomboids, Traps | cables |
| Quads/knee_dominant | Standing Calf Raise | attempt3DropTypeAndTarget ⚠ | Calves (Gastrocnemius) | barbell |
| Core/core | Pallof Press | attempt1Exact | Core (anti-rotation) | cables |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Quads/knee_dominant | Seated Calf Raise | attempt3DropTypeAndTarget ⚠ | Calves (Soleus) | machines |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact |  | bodyweight |
| Core/core | Flutter Kicks | attempt2DropSubFocus | Core | bodyweight |

**Full Body D** (Balanced — core & conditioning)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | barbell |
| Lats/vertical_pull | Chin Up | attempt1Exact | Biceps, Lats | pull-up bar |
| Quads/knee_dominant | Wall Sit | attempt3DropTypeAndTarget ⚠ |  | bodyweight |
| Core/core | Side Plank | attempt2DropSubFocus | Core, Obliques | bodyweight |
| Core/core | Plank | attempt3DropTypeAndTarget ⚠ | Core, Full Body | bodyweight |

---
### strength | full_gym | 4d | advanced | p2 | inj:none
`coverage 90.0 · balance 55.0 · volume 69.1 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 97.2 · **overall 85.2**`

**Squat Day** (Squat + accessories)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | barbell |
| Quads/knee_dominant | Front Squat | attempt1Exact | Quads | barbell |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | pull-up bar |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | machines |
| Hip/hip_isolation | Hip Abductor Machine | attempt1Exact | Glutes | machines |
| Calves/knee_dominant | Seated Calf Raise | attempt2DropSubFocus | Calves (Soleus) | machines |

**Bench Day** (Bench + upper push)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | barbell, bench |
| Upper Chest/horizontal_push | Incline Barbell Bench Press | attempt1Exact | Upper Chest, Front Deltoid | barbell, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | bodyweight |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt1Exact | Side Deltoid | dumbbells |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | cables |
| Front Delts/shoulder_isolation | Cable Front Raise | attempt1Exact | Front Delts | cables |
| Rear Delts/shoulder_isolation | Face Pull | attempt1Exact | Rear Deltoid, Rhomboids | cables |

**Deadlift Day** (Deadlift + back)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Hamstrings/hip_dominant | Romanian Deadlift | attempt1Exact | Hamstrings, Glutes | dumbbells |
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |
| Rear Delts/shoulder_isolation | Band Pull Apart | attempt1Exact | Rear Deltoid, Rhomboids, Traps | resistance band |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Glutes/hip_dominant | Hip Thrust | attempt1Exact | Glutes | barbell, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |

**OHP Day** (Overhead press + accessories)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | barbell |
| Lateral Delts/shoulder_isolation | Machine Lateral Raise | attempt1Exact | Lateral Delts | machines |
| Rear Delts/shoulder_isolation | Reverse Fly | attempt1Exact | Rear Deltoid, Rhomboids | dumbbells |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | ez-bar, bench |
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt2DropSubFocus | Triceps (long head) | dumbbells |
| Front Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Core/core | Reverse Crunch | attempt2DropSubFocus | Lower Abs | bodyweight, bench |

---
### general_fitness | home_dumbbells | 3d | beginner | p1 | inj:none
`coverage 90.0 · balance 62.5 · volume 78.9 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 83.3 · **overall 85.8**`

**⚠ violations:** EQUIPMENT: Seated Cable Row equipment_tier={basic_gym, full_gym} excludes home_dumbbells

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |
| Lats/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Quads/knee_dominant | Banded Squat | attempt2DropSubFocus | Quads, Glutes | resistance band |
| Core/core | Flutter Kicks | attempt2DropSubFocus | Core | bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | bodyweight |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Lats/vertical_pull | Negative Pull Up | attempt1Exact |  | bodyweight |
| Mid Back/horizontal_pull | Kettlebell Row | attempt2DropSubFocus | Lats, Rhomboids | kettlebell |
| Quads/knee_dominant | Leg Curl (Lying) | attempt3DropTypeAndTarget ⚠ | Hamstrings | machines |
| Core/core | Side Plank | attempt2DropSubFocus | Core, Obliques | bodyweight |
| Biceps/elbow_flexion | Dumbbell Curl | attempt1Exact | Biceps | dumbbells |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dand (Hindu Pushup) | attempt2DropSubFocus | Chest, Shoulders, Triceps, Core | bodyweight |
| Lats/horizontal_pull | Seated Cable Row | attempt4DropEquipment | Rhomboids, Traps | cables |
| Quads/knee_dominant | Standing Calf Raise | attempt3DropTypeAndTarget ⚠ | Calves (Gastrocnemius) | barbell |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact |  | bodyweight |
| Core/core | Plank | attempt3DropTypeAndTarget ⚠ | Core, Full Body | bodyweight |
| Calves/knee_dominant | Dumbbell Calf Raise | attempt1Exact |  | dumbbells |

---
### build_muscle | bodyweight | 4d | intermediate | p1 | inj:none
`coverage 80.0 · balance 54.2 · volume 71.8 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 89.3 · **overall 82.5**`

**⚠ violations:** EQUIPMENT: Lateral Raise equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Close-Grip Bench Press equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Face Pull equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Barbell Curl equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Chest Dip equipment_tier={full_gym} excludes bodyweight; EQUIPMENT: Barbell Bent Over Row equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Band Pull Apart equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Dumbbell Curl equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Tricep Pushdown (Cable) equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Dumbbell Row equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Hammer Curl equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Upper Chest/horizontal_push | Dand (Hindu Pushup) | attempt3DropTypeAndTarget ⚠ | Chest, Shoulders, Triceps, Core | bodyweight |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt4DropEquipment | Side Deltoid | dumbbells |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | bodyweight |
| Lower Chest/horizontal_push | Deficit Push-Up | attempt3DropTypeAndTarget ⚠ | Chest | bodyweight |
| Triceps/elbow_extension | Close-Grip Bench Press | attempt4DropEquipment | Triceps | barbell, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Negative Pull Up | attempt1Exact |  | bodyweight |
| Mid Back/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Face Pull | attempt4DropEquipment | Rear Deltoid, Rhomboids | cables |
| Biceps/elbow_flexion | Doorframe Curl | attempt1Exact |  | bodyweight |
| Biceps/elbow_flexion | Barbell Curl | attempt4DropEquipment | Biceps | barbell |
| Mid Back/horizontal_pull | Towel Row | attempt2DropSubFocus |  | bodyweight |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact |  | bodyweight |
| Quads/knee_dominant | Wall Sit | attempt2DropSubFocus |  | bodyweight |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Hamstrings/knee_dominant | Reverse Lunge | attempt3DropTypeAndTarget ⚠ | Quads, Glutes | bodyweight |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Chest Dip | attempt4DropEquipment | Lower Chest | bodyweight |
| Lats/horizontal_pull | Barbell Bent Over Row | attempt4DropEquipment | Lats, Rhomboids | barbell |
| Lateral Delts/shoulder_isolation | Band Pull Apart | attempt4DropEquipment | Rear Deltoid, Rhomboids, Traps | resistance band |
| Biceps/elbow_flexion | Dumbbell Curl | attempt4DropEquipment | Biceps | dumbbells |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt4DropEquipment | Triceps | cables |
| Lats/horizontal_pull | Dumbbell Row | attempt4DropEquipment | Lats, Rhomboids | dumbbells, bench |
| Biceps/elbow_flexion | Hammer Curl | attempt4DropEquipment | Biceps (brachialis), Forearms | dumbbells |

---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:shoulder
`coverage 90.0 · balance 54.2 · volume 81.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 85.7 · **overall 85.1**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Upper Chest/horizontal_push | Incline Dumbbell Press | attempt1Exact |  | dumbbells |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | cables |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt1Exact | Triceps | cables |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Skull Crusher | attempt2DropSubFocus | Triceps | ez-bar, bench |
| Shoulders/vertical_push | Kettlebell Goblet Press | attempt3DropTypeAndTarget ⚠ | Front Deltoid, Triceps, Chest | kettlebell |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Band Pull Apart | attempt1Exact | Rear Deltoid, Rhomboids, Traps | resistance band |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | barbell |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | machines |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | pull-up bar |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | machines |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Front Raise | attempt3DropTypeAndTarget ⚠ | Front Deltoid | dumbbells |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Lateral Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Biceps/elbow_flexion | Hammer Curl | attempt1Exact | Biceps (brachialis), Forearms | dumbbells |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt1Exact | Triceps (long head) | dumbbells |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Biceps/elbow_flexion | Concentration Curl | attempt2DropSubFocus | Biceps | dumbbells |

---
### build_muscle | full_gym | 4d | advanced | p1 | inj:shoulder+knee
`coverage 90.0 · balance 51.7 · volume 74.5 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 82.9 · **overall 83.2**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Upper Chest/horizontal_push | Incline Dumbbell Press | attempt1Exact |  | dumbbells |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | cables |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt1Exact | Triceps | cables |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Skull Crusher | attempt2DropSubFocus | Triceps | ez-bar, bench |
| Shoulders/vertical_push | Kettlebell Goblet Press | attempt3DropTypeAndTarget ⚠ | Front Deltoid, Triceps, Chest | kettlebell |
| Front Delts/shoulder_isolation | Band Pull Apart | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids, Traps | resistance band |
| Rear Delts/shoulder_isolation | Reverse Fly | attempt2DropSubFocus | Rear Deltoid, Rhomboids | dumbbells |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |
| Rear Delts/shoulder_isolation | Arm Circles | universalPool ⚠ | Shoulders | bodyweight |
| Biceps/elbow_flexion | Hammer Curl | attempt2DropSubFocus | Biceps (brachialis), Forearms | dumbbells |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Leg Press | attempt1Exact | Quads, Glutes | machines |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Quads/knee_dominant | Wall Sit | attempt2DropSubFocus |  | bodyweight |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | pull-up bar |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | machines |
| Hip/hip_isolation | Hip Abductor Machine | attempt1Exact | Glutes | machines |
| Calves/knee_dominant | Seated Calf Raise | attempt2DropSubFocus | Calves (Soleus) | machines |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Front Raise | attempt3DropTypeAndTarget ⚠ | Front Deltoid | dumbbells |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Lateral Delts/shoulder_isolation | (safely omitted) | safelyOmitted |  |  |
| Biceps/elbow_flexion | Concentration Curl | attempt1Exact | Biceps | dumbbells |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt1Exact | Triceps (long head) | dumbbells |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Biceps/elbow_flexion | Cable Curl | attempt2DropSubFocus | Biceps | cables |
| Triceps/elbow_extension | Dumbbell Kickback | attempt2DropSubFocus | Triceps | dumbbells |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |

