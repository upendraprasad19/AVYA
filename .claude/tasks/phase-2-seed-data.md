# Phase 2: Seed Data (200+ Exercises, 5,000 Foods)

## Agent: @database-agent
## Deps: Phase 1 (Database tables must exist)

## Tasks

### 2.1 Exercise Library JSON
- [ ] Generate `assets/data/exercise_library.json` with 200+ exercises
- [ ] Distribution: Push ~35, Pull ~35, Legs ~40, Core ~25, Cardio ~20, Flexibility ~30, Calisthenics ~10, Indian Traditional 5
- [ ] Every exercise has ALL fields from CLAUDE.md Section 17
- [ ] Include: coaching_cues, common_mistakes, logging_type, difficulty, suitable_for, regression/progression
- [ ] 5 Indian Traditional: Dand, Baithak, Surya Namaskar, Malkhamb, Hindu Warrior Flow

### 2.2 Food Database JSON
- [ ] Generate `assets/data/food_database.json` with 5,000 Indian-first foods
- [ ] Distribution from CLAUDE.md Section 18
- [ ] Every food has: calories/protein/carbs/fat per 100g + standard serving values
- [ ] Categories properly tagged
- [ ] `is_indian: true` for Indian items

### 2.3 Supabase Seed Migrations
- [ ] `supabase/migrations/007_seed_exercises.sql` — INSERT 200+ exercises
- [ ] `supabase/migrations/008_seed_foods.sql` — INSERT 5,000 foods

### 2.4 Hive Seed Service
- [ ] Update `lib/core/services/seed_service.dart` to parse bundled JSON into Hive on first launch
- [ ] Check flag in configBox to avoid re-seeding

## Completion Criteria
- `assets/data/exercise_library.json` exists with 200+ valid entries
- `assets/data/food_database.json` exists with 5,000+ valid entries
- Both files registered in `pubspec.yaml` under `assets:`
- Seed service loads JSON → Hive on first launch
- Supabase migration files for server-side seeding

## Reference
- `/CLAUDE.md` Sections 7, 17, 18
- `Knowledgebase/business model.txt` (exercise and food details)
- `Knowledgebase/schema.txt` (exercise_library full column spec)
- `Knowledgebase/download 1/ICANBEFITTER_Exercise_Library.xlsx` (reference data)
