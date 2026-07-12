# Workout Generator — Baseline Scorecard (current engine)

> Frozen by Batch 0. Every later batch must IMPROVE its targeted
> dimension with NO regression here. Scores 0-100; safety is a hard gate.

## Aggregate (597 personas)
| Dimension | Mean |
|---|---|
| coverage | 88.6 |
| balance | 67.6 |
| volume | 70.4 |
| progression | 100.0 |
| personalization | 99.7 |
| safety | 99.7 |
| realism | 94.1 |
| overall | 86.5 |

- **Unsafe plans (contraindicated exercise present): 2** (HARD invariant — must be 0)
- **Equipment-violating plans: 286** (HARD invariant — must be 0)
- Plans with ≥1 fallback pick: 363 / total fallback picks: 1156
- Fallback picks by tier (baseline — shallow bodyweight pool; no-regression tracked): `{bodyweight: 617, home_dumbbells: 379, basic_gym: 119, full_gym: 41}`

## Curated plans (human face-validity)
---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:none
`coverage 90.0 · balance 54.2 · volume 78.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 87.0**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | Barbell, Bench |
| Upper Chest/horizontal_push | Incline Barbell Bench Press | attempt1Exact | Upper Chest, Front Deltoid | Barbell, Incline Bench |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt1Exact | Side Deltoid | Dumbbells |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | Bodyweight |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | Dumbbells, Bench |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | Cable Machine |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | Bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | Cable Machine |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | Dumbbell, Bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | Pull-Up Bar |
| Rear Delts/shoulder_isolation | Face Pull | attempt1Exact | Rear Deltoid, Rhomboids | Cable Machine, Rope |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | Barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | Dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | Barbell |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | Barbell, Squat Rack |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | Barbell |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | Leg Extension Machine |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | Bodyweight or Barbell |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | Machine or Barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | Pull-Up Bar |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | Leg Curl Machine |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | Barbell |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | Incline Bench, Dumbbells |
| Lateral Delts/shoulder_isolation | Machine Lateral Raise | attempt2DropSubFocus | Lateral Delts | Machine |
| Biceps/elbow_flexion | Hammer Curl | attempt1Exact | Biceps (brachialis), Forearms | Dumbbells |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | EZ Bar, Bench |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | Barbell on Rack or TRX |
| Biceps/elbow_flexion | Concentration Curl | attempt2DropSubFocus | Biceps | Dumbbell |

---
### lose_fat | basic_gym | 4d | beginner | p1 | inj:none
`coverage 70.0 · balance 62.5 · volume 70.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 80.0 · **overall 80.4**`

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | Barbell, Bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | Bodyweight |
| Lats/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | Dumbbell, Bench |
| Quads/knee_dominant | Banded Squat | attempt2DropSubFocus | Quads, Glutes | Resistance Band |
| Core/core | Cable Crunch | attempt1Exact | Abs | Cable Machine, Rope |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | Dumbbells, Bench |
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | Cable Machine |
| Mid Back/horizontal_pull | Seated Cable Row | attempt1Exact | Rhomboids, Traps | Cable Machine |
| Quads/knee_dominant | Standing Calf Raise | attempt3DropTypeAndTarget ⚠ | Calves (Gastrocnemius) | Machine or Barbell |
| Core/core | Pallof Press | attempt1Exact | Core (anti-rotation) | Cable Machine |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | Bodyweight |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | Incline Bench, Dumbbells |
| Quads/knee_dominant | Seated Calf Raise | attempt3DropTypeAndTarget ⚠ | Calves (Soleus) | Seated Calf Raise Machine |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact |  | Bodyweight |
| Core/core | Flutter Kicks | attempt2DropSubFocus | Core | Bodyweight |

**Full Body D** (Balanced — core & conditioning)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | Barbell |
| Lats/vertical_pull | Chin Up | attempt1Exact | Biceps, Lats | Pull-Up Bar |
| Quads/knee_dominant | Wall Sit | attempt3DropTypeAndTarget ⚠ |  | Bodyweight |
| Core/core | Side Plank | attempt2DropSubFocus | Core, Obliques | Bodyweight |
| Core/core | Plank | attempt3DropTypeAndTarget ⚠ | Core, Full Body | Bodyweight |

---
### strength | full_gym | 4d | advanced | p2 | inj:none
`coverage 90.0 · balance 55.0 · volume 69.1 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 97.2 · **overall 85.2**`

**Squat Day** (Squat + accessories)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | Barbell, Squat Rack |
| Quads/knee_dominant | Front Squat | attempt1Exact | Quads | Barbell, Squat Rack |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | Barbell |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | Bodyweight or Barbell |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | Machine or Barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | Pull-Up Bar |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | Leg Extension Machine |
| Hip/hip_isolation | Hip Abductor Machine | attempt1Exact | Glutes | Machine |
| Calves/knee_dominant | Seated Calf Raise | attempt2DropSubFocus | Calves (Soleus) | Seated Calf Raise Machine |

**Bench Day** (Bench + upper push)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | Barbell, Bench |
| Upper Chest/horizontal_push | Incline Barbell Bench Press | attempt1Exact | Upper Chest, Front Deltoid | Barbell, Incline Bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | Bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | Bodyweight |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | Dumbbells, Bench |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt1Exact | Side Deltoid | Dumbbells |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | Cable Machine |
| Front Delts/shoulder_isolation | Cable Front Raise | attempt1Exact | Front Delts | Cable Machine |
| Rear Delts/shoulder_isolation | Face Pull | attempt1Exact | Rear Deltoid, Rhomboids | Cable Machine, Rope |

**Deadlift Day** (Deadlift + back)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Hamstrings/hip_dominant | Romanian Deadlift | attempt1Exact | Hamstrings, Glutes | Barbell or Dumbbells |
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | Cable Machine |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | Barbell |
| Rear Delts/shoulder_isolation | Band Pull Apart | attempt1Exact | Rear Deltoid, Rhomboids, Traps | Resistance Band |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | Barbell |
| Glutes/hip_dominant | Hip Thrust | attempt1Exact | Glutes | Barbell, Bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | Pull-Up Bar |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | Dumbbells |
| Core/core | Cable Crunch | attempt1Exact | Abs | Cable Machine, Rope |

**OHP Day** (Overhead press + accessories)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | Barbell |
| Lateral Delts/shoulder_isolation | Machine Lateral Raise | attempt1Exact | Lateral Delts | Machine |
| Rear Delts/shoulder_isolation | Reverse Fly | attempt1Exact | Rear Deltoid, Rhomboids | Dumbbells or Cable Machine |
| Core/core | Russian Twist | attempt1Exact | Obliques | Bodyweight or Plate |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | EZ Bar, Bench |
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | Dumbbells, Bench |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt2DropSubFocus | Triceps (long head) | Dumbbell |
| Front Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | Barbell or Dumbbells |
| Core/core | Reverse Crunch | attempt2DropSubFocus | Lower Abs | Bodyweight, Flat Bench |

---
### general_fitness | home_dumbbells | 3d | beginner | p1 | inj:none
`coverage 90.0 · balance 62.5 · volume 78.9 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 83.3 · **overall 85.8**`

**⚠ violations:** EQUIPMENT: Seated Cable Row equipment_tier={basic_gym, full_gym} excludes home_dumbbells

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | Dumbbells, Bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | Bodyweight |
| Lats/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | Dumbbell, Bench |
| Quads/knee_dominant | Banded Squat | attempt2DropSubFocus | Quads, Glutes | Resistance Band |
| Core/core | Flutter Kicks | attempt2DropSubFocus | Core | Bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | Bodyweight |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | Bodyweight |
| Lats/vertical_pull | Negative Pull Up | attempt1Exact |  | Bodyweight |
| Mid Back/horizontal_pull | Kettlebell Row | attempt2DropSubFocus | Lats, Rhomboids | Kettlebell |
| Quads/knee_dominant | Leg Curl (Lying) | attempt3DropTypeAndTarget ⚠ | Hamstrings | Leg Curl Machine |
| Core/core | Side Plank | attempt2DropSubFocus | Core, Obliques | Bodyweight |
| Biceps/elbow_flexion | Dumbbell Curl | attempt1Exact | Biceps | Dumbbells |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dand (Hindu Pushup) | attempt2DropSubFocus | Chest, Shoulders, Triceps, Core | Bodyweight |
| Lats/horizontal_pull | Seated Cable Row | attempt4DropEquipment | Rhomboids, Traps | Cable Machine |
| Quads/knee_dominant | Standing Calf Raise | attempt3DropTypeAndTarget ⚠ | Calves (Gastrocnemius) | Machine or Barbell |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact |  | Bodyweight |
| Core/core | Plank | attempt3DropTypeAndTarget ⚠ | Core, Full Body | Bodyweight |
| Calves/knee_dominant | Dumbbell Calf Raise | attempt1Exact |  | Dumbbells |

---
### build_muscle | bodyweight | 4d | intermediate | p1 | inj:none
`coverage 80.0 · balance 54.2 · volume 71.8 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 89.3 · **overall 82.5**`

**⚠ violations:** EQUIPMENT: Lateral Raise equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Close-Grip Bench Press equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Face Pull equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Barbell Curl equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Chest Dip equipment_tier={full_gym} excludes bodyweight; EQUIPMENT: Barbell Bent Over Row equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Band Pull Apart equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Dumbbell Curl equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Tricep Pushdown (Cable) equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Dumbbell Row equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Hammer Curl equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | Bodyweight |
| Upper Chest/horizontal_push | Dand (Hindu Pushup) | attempt3DropTypeAndTarget ⚠ | Chest, Shoulders, Triceps, Core | Bodyweight |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt4DropEquipment | Side Deltoid | Dumbbells |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | Bodyweight |
| Lower Chest/horizontal_push | Deficit Push-Up | attempt3DropTypeAndTarget ⚠ | Chest | Bodyweight |
| Triceps/elbow_extension | Close-Grip Bench Press | attempt4DropEquipment | Triceps | Barbell, Bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | Bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Negative Pull Up | attempt1Exact |  | Bodyweight |
| Mid Back/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | Barbell on Rack or TRX |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | Pull-Up Bar |
| Rear Delts/shoulder_isolation | Face Pull | attempt4DropEquipment | Rear Deltoid, Rhomboids | Cable Machine, Rope |
| Biceps/elbow_flexion | Doorframe Curl | attempt1Exact |  | Bodyweight |
| Biceps/elbow_flexion | Barbell Curl | attempt4DropEquipment | Biceps | Barbell |
| Mid Back/horizontal_pull | Towel Row | attempt2DropSubFocus |  | Bodyweight |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | Bodyweight or Dumbbells |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact |  | Bodyweight |
| Quads/knee_dominant | Wall Sit | attempt2DropSubFocus |  | Bodyweight |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | Bodyweight or Barbell |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | Machine or Barbell |
| Core/core | Russian Twist | attempt1Exact | Obliques | Bodyweight or Plate |
| Hamstrings/knee_dominant | Reverse Lunge | attempt3DropTypeAndTarget ⚠ | Quads, Glutes | Bodyweight or Dumbbells |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Chest Dip | attempt4DropEquipment | Lower Chest | Parallel Bars |
| Lats/horizontal_pull | Barbell Bent Over Row | attempt4DropEquipment | Lats, Rhomboids | Barbell |
| Lateral Delts/shoulder_isolation | Band Pull Apart | attempt4DropEquipment | Rear Deltoid, Rhomboids, Traps | Resistance Band |
| Biceps/elbow_flexion | Dumbbell Curl | attempt4DropEquipment | Biceps | Dumbbells |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt4DropEquipment | Triceps | Cable Machine |
| Lats/horizontal_pull | Dumbbell Row | attempt4DropEquipment | Lats, Rhomboids | Dumbbell, Bench |
| Biceps/elbow_flexion | Hammer Curl | attempt4DropEquipment | Biceps (brachialis), Forearms | Dumbbells |

---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:shoulder
`coverage 90.0 · balance 54.2 · volume 81.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 85.7 · **overall 85.1**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | Dumbbells, Bench |
| Upper Chest/horizontal_push | Incline Dumbbell Press | attempt1Exact |  | Dumbbells |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | Cable Machine, Rope |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt1Exact | Triceps | Cable Machine |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | Dumbbells, Bench |
| Triceps/elbow_extension | Skull Crusher | attempt2DropSubFocus | Triceps | EZ Bar, Bench |
| Shoulders/vertical_push | Kettlebell Goblet Press | attempt3DropTypeAndTarget ⚠ | Front Deltoid, Triceps, Chest | Kettlebell |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | Cable Machine |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | Dumbbell, Bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | Pull-Up Bar |
| Rear Delts/shoulder_isolation | Band Pull Apart | attempt1Exact | Rear Deltoid, Rhomboids, Traps | Resistance Band |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | Barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | Dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | Barbell |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | Barbell, Squat Rack |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | Barbell |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | Leg Extension Machine |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | Bodyweight or Barbell |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | Machine or Barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | Pull-Up Bar |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | Leg Curl Machine |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Front Raise | attempt3DropTypeAndTarget ⚠ | Front Deltoid | Dumbbells |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | Incline Bench, Dumbbells |
| Lateral Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | Barbell or Dumbbells |
| Biceps/elbow_flexion | Hammer Curl | attempt1Exact | Biceps (brachialis), Forearms | Dumbbells |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt1Exact | Triceps (long head) | Dumbbell |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | Barbell on Rack or TRX |
| Biceps/elbow_flexion | Concentration Curl | attempt2DropSubFocus | Biceps | Dumbbell |

---
### build_muscle | full_gym | 4d | advanced | p1 | inj:shoulder+knee
`coverage 90.0 · balance 60.0 · volume 74.0 · progression 100.0 · personalization 0.0 · safety 0.0 · realism 80.6 · **overall 0.0**`

**⚠ violations:** Pike Push Up contraindicated for shoulder

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | Dumbbells, Bench |
| Upper Chest/horizontal_push | Incline Dumbbell Press | attempt1Exact |  | Dumbbells |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | Cable Machine, Rope |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt1Exact | Triceps | Cable Machine |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | Dumbbells, Bench |
| Triceps/elbow_extension | Skull Crusher | attempt2DropSubFocus | Triceps | EZ Bar, Bench |
| Shoulders/vertical_push | Kettlebell Goblet Press | attempt3DropTypeAndTarget ⚠ | Front Deltoid, Triceps, Chest | Kettlebell |
| Front Delts/shoulder_isolation | Band Pull Apart | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids, Traps | Resistance Band |
| Rear Delts/shoulder_isolation | Reverse Fly | attempt2DropSubFocus | Rear Deltoid, Rhomboids | Dumbbells or Cable Machine |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | Cable Machine |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | Dumbbell, Bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | Pull-Up Bar |
| Rear Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | Barbell or Dumbbells |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | Barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | Dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | Barbell |
| Rear Delts/shoulder_isolation | Pike Push Up | universalPool ⚠ | Front Deltoid, Upper Chest | Bodyweight |
| Biceps/elbow_flexion | Hammer Curl | attempt2DropSubFocus | Biceps (brachialis), Forearms | Dumbbells |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Leg Press | attempt1Exact | Quads, Glutes | Leg Press Machine |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | Barbell |
| Quads/knee_dominant | Wall Sit | attempt2DropSubFocus |  | Bodyweight |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | Bodyweight or Barbell |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | Machine or Barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | Pull-Up Bar |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | Leg Curl Machine |
| Hip/hip_isolation | Hip Abductor Machine | attempt1Exact | Glutes | Machine |
| Calves/knee_dominant | Seated Calf Raise | attempt2DropSubFocus | Calves (Soleus) | Seated Calf Raise Machine |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Front Raise | attempt3DropTypeAndTarget ⚠ | Front Deltoid | Dumbbells |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | Incline Bench, Dumbbells |
| Lateral Delts/shoulder_isolation | Arm Circles | universalPool ⚠ | Shoulders | Bodyweight |
| Biceps/elbow_flexion | Concentration Curl | attempt1Exact | Biceps | Dumbbell |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt1Exact | Triceps (long head) | Dumbbell |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | Barbell on Rack or TRX |
| Biceps/elbow_flexion | Cable Curl | attempt2DropSubFocus | Biceps | Cable Machine |
| Triceps/elbow_extension | Dumbbell Kickback | attempt2DropSubFocus | Triceps | Dumbbells |
| Core/core | Cable Crunch | attempt1Exact | Abs | Cable Machine, Rope |

