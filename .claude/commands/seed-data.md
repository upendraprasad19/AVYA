# /seed-data — Generate seed data for exercise_library or food_database

Generate seed data for the entity specified in $ARGUMENTS.

## Steps
1. Read `/CLAUDE.md` Sections 7 (Schema), 17 (Exercise Library), 18 (Food Database)
2. Generate the data as a JSON file in `assets/data/`
3. Follow the exact schema for each entity

## Exercise Library (200+ exercises)
File: `assets/data/exercise_library.json`

Distribution:
- Push (~35), Pull (~35), Legs (~40), Core (~25)
- Cardio (~20), Flexibility (~30), Calisthenics (~10)
- Indian Traditional (5): Dand, Baithak, Surya Namaskar, Malkhamb, Hindu Warrior Flow

Each exercise MUST have:
```json
{
  "id": "uuid",
  "name": "Bench Press",
  "name_aliases": ["Chest Press", "Flat Bench"],
  "category": "push",
  "movement_pattern": "horizontal_push",
  "exercise_type": "compound",
  "primary_muscles": ["chest", "triceps"],
  "secondary_muscles": ["front_deltoid"],
  "equipment_needed": ["barbell", "bench"],
  "logging_type": "weight_reps",
  "difficulty_level": "beginner",
  "suitable_for": ["beginner", "intermediate", "advanced"],
  "instructions": "Step by step...",
  "coaching_cues": ["Retract scapula", "Drive through heels"],
  "common_mistakes": ["Flaring elbows", "Bouncing bar"],
  "default_sets": 4,
  "default_reps": "8-12",
  "default_rest_secs": 90,
  "is_indian_context": false
}
```

## Food Database (5,000 foods)
File: `assets/data/food_database.json`

Distribution from CLAUDE.md Section 18.

Each food MUST have:
```json
{
  "id": "uuid",
  "name": "Dal Tadka",
  "category": "staples",
  "calories_per_100g": 120,
  "protein_per_100g": 7.5,
  "carbs_per_100g": 15,
  "fat_per_100g": 3.5,
  "fiber_per_100g": 2.5,
  "standard_serving_desc": "1 bowl",
  "standard_serving_g": 200,
  "calories_std": 240,
  "protein_std": 15,
  "carbs_std": 30,
  "fat_std": 7,
  "is_indian": true
}
```
