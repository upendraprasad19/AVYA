# Workout Generator — Baseline Scorecard (current engine)

> Frozen by Batch 0. Every later batch must IMPROVE its targeted
> dimension with NO regression here. Scores 0-100; safety is a hard gate.

## Aggregate (606 personas)
| Dimension | Mean |
|---|---|
| coverage | 94.7 |
| balance | 67.1 |
| volume | 70.4 |
| progression | 62.9 |
| personalization | 100.0 |
| safety | 100.0 |
| realism | 91.8 |
| overall | 81.1 |

- **Unsafe plans (contraindicated exercise present): 0** (HARD invariant — must be 0)
- **Equipment-violating plans: 0** (HARD invariant — must be 0)
- Plans with ≥1 fallback pick: 288 / total fallback picks: 1679
- Fallback picks by tier (baseline — shallow bodyweight pool; no-regression tracked): `{bodyweight: 1273, home_dumbbells: 363, full_gym: 43}`

## Curated plans (human face-validity)
---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:none
`coverage 90.0 · balance 54.2 · volume 75.8 · progression 0.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 70.0**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | barbell, bench |
| Upper Chest/horizontal_push | Incline Barbell Bench Press | attempt1Exact | Upper Chest, Front Deltoid | barbell, bench |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt1Exact | Side Deltoid | dumbbells |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | elevated surface |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Cable Rope Pushdown | attempt2DropSubFocus | Triceps | cables |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Rear Delts/shoulder_isolation | Face Pull | attempt1Exact | Rear Deltoid, Rhomboids | cables |
| Biceps/elbow_flexion | Self-Resisted Bicep Curl | attempt1Exact | Biceps | bodyweight |
| Biceps/elbow_flexion | Dumbbell Alternate Bicep Curl | attempt2DropSubFocus | Biceps | dumbbells |
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
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Triceps/elbow_extension | Self-Resisted Triceps Extension | attempt1Exact | Triceps | bodyweight |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | suspension trainer |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |

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
| Quads/knee_dominant | Step Up | attempt1Exact | Quads, Glutes | dumbbells, elevated surface |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact | Hamstrings, Glutes | bodyweight |
| Core/core | Reverse Crunch | attempt1Exact | Lower Abs | bodyweight |

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
`coverage 100.0 · balance 55.0 · volume 65.5 · progression 0.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 70.1**`

**Squat Day** (Squat + accessories)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Front Squat | attempt1Exact | Quads | barbell |
| Quads/knee_dominant | Goblet Squat | attempt1Exact | Quads, Glutes | dumbbells |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Hanging Leg Raise | attempt1Exact | Core, Obliques | pull-up bar |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | machines |
| Hip/hip_isolation | Hip Abduction Machine | attempt1Exact | Abductors, Glutes (medius), Glutes | machines |
| Calves/knee_dominant | Barbell Seated Calf Raise | attempt1Exact | Calves | barbell, bench |

**Bench Day** (Bench + upper push)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Barbell Bench Press | attempt1Exact | Chest | barbell, bench |
| Upper Chest/horizontal_push | Incline Barbell Bench Press | attempt1Exact | Upper Chest, Front Deltoid | barbell, bench |
| Shoulders/vertical_push | Barbell Overhead Press | attempt1Exact | Front Deltoid, Side Deltoid | barbell |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | elevated surface |
| Lower Chest/horizontal_push | Dumbbell Fly | attempt1Exact | Chest | dumbbells, bench |
| Lateral Delts/shoulder_isolation | Lateral Raise | attempt1Exact | Side Deltoid | dumbbells |
| Triceps/elbow_extension | Cable Rope Pushdown | attempt2DropSubFocus | Triceps | cables |
| Front Delts/shoulder_isolation | Cable Front Raise | attempt1Exact | Front Delts | cables |
| Rear Delts/shoulder_isolation | Dumbbell Rear Lateral Raise | attempt1Exact | Rear Delts | dumbbells |

**Deadlift Day** (Deadlift + back)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Hamstrings/hip_dominant | Romanian Deadlift | attempt1Exact | Hamstrings, Glutes | dumbbells |
| Lats/vertical_pull | Lat Pulldown | attempt1Exact | Lats | cables |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Rear Delts/shoulder_isolation | Face Pull | attempt1Exact | Rear Deltoid, Rhomboids | cables |
| Biceps/elbow_flexion | Self-Resisted Bicep Curl | attempt1Exact | Biceps | bodyweight |
| Glutes/hip_dominant | Hip Thrust | attempt1Exact | Glutes | barbell, bench |
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Biceps/elbow_flexion | Dumbbell Alternate Bicep Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |

**OHP Day** (Overhead press + accessories)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Dumbbell Shoulder Press | attempt1Exact | Front Deltoid, Side Deltoid | dumbbells |
| Lateral Delts/shoulder_isolation | Machine Lateral Raise | attempt1Exact | Lateral Delts | machines |
| Rear Delts/shoulder_isolation | Band Pull Apart | attempt1Exact | Rear Deltoid, Rhomboids, Traps | resistance band |
| Core/core | Reverse Crunch | attempt1Exact | Lower Abs | bodyweight |
| Triceps/elbow_extension | Self-Resisted Triceps Extension | attempt1Exact | Triceps | bodyweight |
| Mid Chest/horizontal_push | Dumbbell Bench Press | attempt1Exact | Chest | dumbbells, bench |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | cables |
| Front Delts/shoulder_isolation | Dumbbell Standing Front Raise Above Head | attempt1Exact | Front Delts | dumbbells |
| Core/core | Cable Crunch | attempt2DropSubFocus | Abs | cables |

---
### general_fitness | home_dumbbells | 3d | beginner | p1 | inj:none
`coverage 100.0 · balance 62.5 · volume 80.8 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 100.0 · **overall 90.5**`

**Full Body A** (Push-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |
| Lats/horizontal_pull | Table Row | attempt1Exact | Lats | elevated surface |
| Quads/knee_dominant | Goblet Squat | attempt1Exact | Quads, Glutes | dumbbells |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | elevated surface |

**Full Body B** (Pull-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Dand (Hindu Pushup) | attempt2DropSubFocus | Chest, Shoulders, Triceps, Core | bodyweight |
| Lats/vertical_pull | Band Close Grip Pulldown | attempt2DropSubFocus | Lats | resistance band |
| Mid Back/horizontal_pull | Dumbbell Bent Over Row | attempt2DropSubFocus | Lats, Mid Back | dumbbells |
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Core/core | Reverse Crunch | attempt1Exact | Lower Abs | bodyweight |
| Biceps/elbow_flexion | Self-Resisted Bicep Curl | attempt1Exact | Biceps | bodyweight |

**Full Body C** (Legs-focused)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Floor Press | attempt2DropSubFocus | Chest | dumbbells |
| Lats/horizontal_pull | Doorway Isometric Row | attempt1Exact | Lats | doorway |
| Quads/knee_dominant | Step Up | attempt1Exact | Quads, Glutes | dumbbells, elevated surface |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact | Hamstrings, Glutes | bodyweight |
| Core/core | Crunches | attempt1Exact | Abs | bodyweight |
| Calves/knee_dominant | Dumbbell Calf Raise | attempt1Exact | Calves | dumbbells |

---
### build_muscle | bodyweight | 4d | intermediate | p1 | inj:none
`coverage 100.0 · balance 54.2 · volume 78.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 71.4 · **overall 83.9**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Push Up | attempt1Exact | Chest | bodyweight |
| Upper Chest/horizontal_push | Dand (Hindu Pushup) | attempt3DropTypeAndTarget ⚠ | Chest, Shoulders, Triceps, Core | bodyweight |
| Lateral Delts/shoulder_isolation | Bodyweight Rear Delt Raise | attempt3DropTypeAndTarget ⚠ | Rear Deltoid | bodyweight |
| Triceps/elbow_extension | Bench Dips | attempt1Exact | Triceps | elevated surface |
| Lower Chest/horizontal_push | Deficit Push-Up | attempt3DropTypeAndTarget ⚠ | Chest | elevated surface |
| Triceps/elbow_extension | Self-Resisted Triceps Extension | attempt2DropSubFocus | Triceps | bodyweight |
| Shoulders/vertical_push | Pike Push Up | attempt1Exact | Front Deltoid, Upper Chest | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Prone Lat Pull | attempt3DropTypeAndTarget ⚠ | Lats | bodyweight |
| Mid Back/horizontal_pull | Towel Row | attempt2DropSubFocus | Lats, Mid Back | towel |
| Lats/vertical_pull | Sliding Lat Pull | attempt3DropTypeAndTarget ⚠ | Lats | towel |
| Rear Delts/shoulder_isolation | Prone Y Raise | attempt3DropTypeAndTarget ⚠ | Rear Deltoid | bodyweight |
| Biceps/elbow_flexion | Self-Resisted Bicep Curl | attempt1Exact | Biceps | bodyweight |
| Biceps/elbow_flexion | Doorframe Curl | attempt2DropSubFocus | Biceps | doorway |
| Mid Back/horizontal_pull | Backpack Bent-Over Row | attempt2DropSubFocus | Lats, Mid Back | bodyweight |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Walking Lunge | attempt1Exact | Quads, Glutes | bodyweight |
| Hamstrings/hip_dominant | Bodyweight Good Morning | attempt1Exact | Hamstrings, Glutes | bodyweight |
| Quads/knee_dominant | Wall Sit | attempt2DropSubFocus | Quads | bodyweight |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Bodyweight Standing Calf Raise | attempt2DropSubFocus | Calves | bodyweight |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |
| Hamstrings/knee_dominant | Reverse Lunge | attempt3DropTypeAndTarget ⚠ | Quads, Glutes | bodyweight |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | Elevated Pike Push Up | attempt1Exact | Front Deltoid | elevated surface |
| Lats/horizontal_pull | Table Row | attempt1Exact | Lats | elevated surface |
| Lateral Delts/shoulder_isolation | Towel Lateral Raise | attempt3DropTypeAndTarget ⚠ | Side Deltoid | towel |
| Biceps/elbow_flexion | Towel Bicep Curl | attempt1Exact | Biceps | towel |
| Triceps/elbow_extension | Wall Triceps Extension | attempt1Exact | Triceps | wall |
| Lats/horizontal_pull | Doorway Isometric Row | attempt1Exact | Lats | doorway |
| Biceps/elbow_flexion | Towel Hammer Curl | attempt2DropSubFocus | Biceps | towel |

---
### build_muscle | full_gym | 4d | intermediate | p1 | inj:shoulder
`coverage 90.0 · balance 37.5 · volume 79.0 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 84.6 · **overall 81.9**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Machine Chest Press | attempt1Exact | Chest | machines |
| Upper Chest/horizontal_push | Chest Squeeze Press | attempt3DropTypeAndTarget ⚠ | Chest (inner), Triceps | dumbbells, bench |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | cables |
| Triceps/elbow_extension | Cable Rope Pushdown | attempt1Exact | Triceps | cables |
| Lower Chest/horizontal_push | Sled Push | attempt3DropTypeAndTarget ⚠ | Quads, Glutes, Core | machines |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | cables |
| Shoulders/vertical_push | (safely omitted) | safelyOmitted |  |  |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Machine High Row | attempt2DropSubFocus | Lats (Width) | machines |
| Rear Delts/shoulder_isolation | Band Pull Apart | attempt1Exact | Rear Deltoid, Rhomboids, Traps | resistance band |
| Biceps/elbow_flexion | Self-Resisted Bicep Curl | attempt1Exact | Biceps | bodyweight |
| Biceps/elbow_flexion | Dumbbell Alternate Bicep Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Barbell Back Squat | attempt1Exact | Quads, Glutes | barbell |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Quads/knee_dominant | Leg Extension | attempt2DropSubFocus | Quads | machines |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | machines |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | (safely omitted) | safelyOmitted |  |  |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Lateral Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Biceps/elbow_flexion | Barbell Curl | attempt1Exact | Biceps | barbell |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | ez-bar, bench |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | suspension trainer |
| Biceps/elbow_flexion | Dumbbell Curl | attempt2DropSubFocus | Biceps | dumbbells |

---
### build_muscle | full_gym | 4d | advanced | p1 | inj:shoulder+knee
`coverage 90.0 · balance 35.0 · volume 66.9 · progression 100.0 · personalization 100.0 · safety 100.0 · realism 79.4 · **overall 78.6**`

**Push** (Chest, shoulders, triceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Mid Chest/horizontal_push | Machine Chest Press | attempt1Exact | Chest | machines |
| Upper Chest/horizontal_push | Chest Squeeze Press | attempt3DropTypeAndTarget ⚠ | Chest (inner), Triceps | dumbbells, bench |
| Lateral Delts/shoulder_isolation | Face Pull | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids | cables |
| Triceps/elbow_extension | Cable Rope Pushdown | attempt1Exact | Triceps | cables |
| Lower Chest/horizontal_push | Sled Push | attempt3DropTypeAndTarget ⚠ | Quads, Glutes, Core | machines |
| Triceps/elbow_extension | Tricep Pushdown (Cable) | attempt2DropSubFocus | Triceps | cables |
| Shoulders/vertical_push | (safely omitted) | safelyOmitted |  |  |
| Front Delts/shoulder_isolation | Band Pull Apart | attempt3DropTypeAndTarget ⚠ | Rear Deltoid, Rhomboids, Traps | resistance band |
| Rear Delts/shoulder_isolation | Bodyweight Rear Delt Raise | attempt1Exact | Rear Deltoid | bodyweight |

**Pull** (Back, biceps)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Lats/vertical_pull | Chin Up | attempt2DropSubFocus | Biceps, Lats | pull-up bar |
| Mid Back/horizontal_pull | Dumbbell Row | attempt1Exact | Lats, Rhomboids | dumbbells, bench |
| Lats/vertical_pull | Machine High Row | attempt2DropSubFocus | Lats (Width) | machines |
| Rear Delts/shoulder_isolation | Machine Seated Reverse Fly | attempt2DropSubFocus | Rear Delts | machines |
| Biceps/elbow_flexion | Self-Resisted Bicep Curl | attempt1Exact | Biceps | bodyweight |
| Biceps/elbow_flexion | Dumbbell Alternate Bicep Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Mid Back/horizontal_pull | Barbell Bent Over Row | attempt1Exact | Lats, Rhomboids | barbell |
| Rear Delts/shoulder_isolation | Reverse Fly | attempt2DropSubFocus | Rear Deltoid, Rhomboids | dumbbells |
| Biceps/elbow_flexion | Barbell Curl | attempt2DropSubFocus | Biceps | barbell |

**Legs** (Quads, hams, glutes)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Quads/knee_dominant | Sumo Deadlift | attempt3DropTypeAndTarget ⚠ | Adductors, Glutes, Hamstrings | barbell |
| Hamstrings/hip_dominant | Deadlift | attempt1Exact | Lower Back, Glutes, Hamstrings | barbell |
| Quads/knee_dominant | Machine Glute Ham Raise | attempt3DropTypeAndTarget ⚠ | Hamstrings, Glutes | machines |
| Glutes/hip_isolation | Glute Bridge | attempt1Exact | Glutes | bodyweight |
| Calves/knee_dominant | Standing Calf Raise | attempt1Exact | Calves (Gastrocnemius) | barbell |
| Core/core | Cable Crunch | attempt1Exact | Abs | cables |
| Hamstrings/knee_dominant | Leg Curl (Lying) | attempt1Exact | Hamstrings | machines |
| Hip/hip_isolation | Hip Abduction Machine | attempt1Exact | Abductors, Glutes (medius), Glutes | machines |
| Calves/knee_dominant | Seated Calf Raise | attempt2DropSubFocus | Calves (Soleus) | machines |

**Upper** (Shoulders, back, arms)
| Slot | Exercise | Source | Muscles | Equip |
|---|---|---|---|---|
| Shoulders/vertical_push | (safely omitted) | safelyOmitted |  |  |
| Lats/horizontal_pull | Chest Supported Row | attempt1Exact | Rhomboids, Lats | bench, dumbbells |
| Lateral Delts/shoulder_isolation | Shrug | attempt3DropTypeAndTarget ⚠ | Traps | dumbbells |
| Biceps/elbow_flexion | Dumbbell Curl | attempt1Exact | Biceps | dumbbells |
| Triceps/elbow_extension | Skull Crusher | attempt1Exact | Triceps | ez-bar, bench |
| Lats/horizontal_pull | Inverted Row | attempt1Exact | Rhomboids, Lats | suspension trainer |
| Biceps/elbow_flexion | Concentration Curl | attempt2DropSubFocus | Biceps | dumbbells |
| Triceps/elbow_extension | Overhead Tricep Extension | attempt2DropSubFocus | Triceps (long head) | dumbbells |
| Core/core | Russian Twist | attempt1Exact | Obliques | bodyweight |

