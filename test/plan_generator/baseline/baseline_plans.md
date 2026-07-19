# Workout Generator — Baseline Scorecard (current engine)

> Frozen by Batch 0. Every later batch must IMPROVE its targeted
> dimension with NO regression here. Scores 0-100; safety is a hard gate.

## Aggregate (606 personas)
| Dimension | Mean |
|---|---|
| coverage | 92.3 |
| balance | 67.4 |
| volume | 68.0 |
| progression | 100.0 |
| personalization | 100.0 |
| safety | 100.0 |
| realism | 94.4 |
| overall | 87.0 |

- **Unsafe plans (contraindicated exercise present): 0** (HARD invariant — must be 0)
- **Equipment-violating plans: 201** (HARD invariant — must be 0)
- Plans with ≥1 fallback pick: 281 / total fallback picks: 1181
- Fallback picks by tier (baseline — shallow bodyweight pool; no-regression tracked): `{bodyweight: 868, home_dumbbells: 240, basic_gym: 24, full_gym: 49}`

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
`coverage 80.0 · balance 62.5 · volume 82.8 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 87.5**`

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | barbell, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |
| Lats/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Quads/knee_dominant | Goblet Squat | attempt1Exact | Quads, Glutes | dumbbells |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Seated Cable Row | attempt1Exact | Rhomboids, Traps | cables |
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Quads/knee_dominant | Step Up | attempt1Exact | Quads, Glutes | dumbbells, bodyweight |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact | Hamstrings, Glutes | bodyweight |
| Core/core | Reverse Crunch | attempt1Exact | Lower Abs | bodyweight, bench |

**Full Body D** (Balanced — core & conditioning)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | barbell |
| Lats/vertical_pull | Chin Up | attempt1Exact | Biceps, Lats | pull-up bar |
| Quads/knee_dominant | Reverse Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Core/core | Pallof Press | attempt1Exact | Core (anti-rotation) | cables |
| Core/core | Crunches | attempt2DropSubFocus | Abs | bodyweight |

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
| Rear Delts/shoulder_isolation | Bodyweight Rear Delt Raise | attempt1Exact | Rear Deltoid | bodyweight |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | ez-bar, bench |
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt2DropSubFocus | Triceps (long head) | dumbbells |
| Front Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Core/core | Reverse Crunch | attempt2DropSubFocus | Lower Abs | bodyweight, bench |

---
### general_fitness | home_dumbbells | 3d | beginner | p1 | inj:none
`coverage 90.0 · balance 62.5 · volume 76.6 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 88.2**`

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |
| Lats/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Quads/knee_dominant | Goblet Squat | attempt1Exact | Quads, Glutes | dumbbells |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | bodyweight |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Lats/vertical_pull | Negative Pull Up | attempt1Exact | Lats, Biceps | bodyweight |
| Mid Back/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Core/core | Crunches | attempt1Exact | Abs | bodyweight |
| Biceps/elbow_flexion | Dumbbell Curl | attempt1Exact | Biceps | dumbbells |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dand (Hindu Pushup) | attempt2DropSubFocus | Chest, Shoulders, Triceps, Core | bodyweight |
| Lats/horizontal_pull | Kettlebell Row | attempt2DropSubFocus | Lats, Rhomboids | kettlebell |
| Quads/knee_dominant | Step Up | attempt1Exact | Quads, Glutes | dumbbells, bodyweight |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact | Hamstrings, Glutes | bodyweight |
| Core/core | Bicycle Crunch | attempt1Exact | Abs, Obliques | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |

---
### build_muscle | bodyweight | 4d | intermediate | p1 | inj:none
`coverage 90.0 · balance 54.2 · volume 71.5 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 82.1 · **overall 83.0**`

**⚠ violations:** EQUIPMENT: Close-Grip Bench Press equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Lateral Raise equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Barbell Curl equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Face Pull equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Dumbbell Curl equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Tricep Pushdown (Cable) equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Barbell Bent Over Row equipment_tier={basic_gym, full_gym} excludes bodyweight; EQUIPMENT: Hammer Curl equipment_tier={home_dumbbells, basic_gym, full_gym} excludes bodyweight

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Upper Chest/horizontal_push | Dand (Hindu Pushup) | attempt3DropTypeAndTarget ⚠ | Chest, Shoulders, Triceps, Core | bodyweight |
| Lateral Delts/shoulder_isolation | Bodyweight Rear Delt Raise | attempt3DropTypeAndTarget ⚠ | Rear Deltoid | bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | bodyweight |
| Lower Chest/horizontal_push | TRX Pushup | attempt3DropTypeAndTarget ⚠ | Chest, Triceps | bodyweight |
| Triceps/elbow_extension | Close-Grip Bench Press | attempt4DropEquipment | Triceps | barbell, bench |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Negative Pull Up | attempt1Exact | Lats, Biceps | bodyweight |
| Mid Back/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Lateral Raise | attempt4DropEquipment | Side Deltoid | dumbbells |
| Biceps/elbow_flexion | Doorframe Curl | attempt1Exact | Biceps | bodyweight |
| Biceps/elbow_flexion | Barbell Curl | attempt4DropEquipment | Biceps | barbell |
| Mid Back/horizontal_pull | Towel Row | attempt2DropSubFocus | Lats, Mid Back | bodyweight |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact | Hamstrings, Glutes | bodyweight |
| Quads/knee_dominant | Wall Sit | attempt2DropSubFocus | Quads | bodyweight |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Hamstrings/knee_dominant | Reverse Lunge | attempt3DropTypeAndTarget ⚠ | Quads, Glutes | bodyweight |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Chest Dip | attempt3DropTypeAndTarget ⚠ | Lower Chest | bodyweight |
| Lats/horizontal_pull | TRX Row | attempt2DropSubFocus | Rhomboids, Lats | bodyweight |
| Lateral Delts/shoulder_isolation | Face Pull | attempt4DropEquipment | Rear Deltoid, Rhomboids | cables |
| Biceps/elbow_flexion | Dumbbell Curl | attempt4DropEquipment | Biceps | dumbbells |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt4DropEquipment | Triceps | cables |
| Lats/horizontal_pull | Barbell Bent Over Row | attempt4DropEquipment | Lats, Rhomboids | barbell |
| Biceps/elbow_flexion | Hammer Curl | attempt4DropEquipment | Biceps (brachialis), Forearms | dumbbells |

---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:shoulder
`coverage 90.0 · balance 54.2 · volume 80.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 82.1 · **overall 84.4**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Upper Chest/horizontal_push | Push Up | attempt3DropTypeAndTarget ⚠ | Chest | bodyweight |
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
`coverage 90.0 · balance 51.7 · volume 75.5 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 77.8 · **overall 82.5**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Upper Chest/horizontal_push | Push Up | attempt3DropTypeAndTarget ⚠ | Chest | bodyweight |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | cables |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt1Exact | Triceps | cables |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Skull Crusher | attempt2DropSubFocus | Triceps | ez-bar, bench |
| Shoulders/vertical_push | Kettlebell Goblet Press | attempt3DropTypeAndTarget ⚠ | Front Deltoid, Triceps, Chest | kettlebell |
| Front Delts/shoulder_isolation | Band Pull Apart | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids, Traps | resistance band |
| Rear Delts/shoulder_isolation | Bodyweight Rear Delt Raise | attempt1Exact | Rear Deltoid | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Reverse Fly | attempt2DropSubFocus | Rear Deltoid, Rhomboids | dumbbells |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |
| Rear Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Biceps/elbow_flexion | Hammer Curl | attempt2DropSubFocus | Biceps (brachialis), Forearms | dumbbells |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Leg Press | attempt1Exact | Quads, Glutes | machines |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Quads/knee_dominant | Sumo Deadlift | attempt3DropTypeAndTarget ⚠ | Adductors, Glutes, Hamstrings | barbell |
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
| Lateral Delts/shoulder_isolation | Arm Circles | universalPool ⚠ | Shoulders | bodyweight |
| Biceps/elbow_flexion | Concentration Curl | attempt1Exact | Biceps | dumbbells |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt1Exact | Triceps (long head) | dumbbells |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | bodyweight |
| Biceps/elbow_flexion | Cable Curl | attempt2DropSubFocus | Biceps | cables |
| Triceps/elbow_extension | Dumbbell Kickback | attempt2DropSubFocus | Triceps | dumbbells |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |

