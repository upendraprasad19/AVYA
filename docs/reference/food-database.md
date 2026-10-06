---
source: CLAUDE.md §18
migrated: 2026-05-18
status: scaffold
---

# Food Database Reference

**1431 Indian-first foods** bundled in `assets/data/food_database.json`. Same rows are mirrored to Postgres `food_database` table (migration 030 seeded 93; migration 041 expanded to 1431) so server-side tools like AI coach `suggestMeal` can query them.

**V2 expansion (2026-04-26, APK Test #3 batch):** Database expanded from 93 → 1431 items via `assets/data/food_database.json`. Sources: 93 original seed (preserved as F0001-F0093) + 699 manual Indian staples + 228 Western staples + 225 OpenFoodFacts India + 186 fitness supplements. New schema fields: `is_veg`, `is_vegan` (booleans). Build script: `.claude/build_food_db_v2.js`. Re-seeding triggered on app launch via `SeedService._foodLibraryVersion = 2`.

Categories cover staples, street food, restaurant dishes, dairy, pulses, protein, fruits/veg, beverages, sweets, supplements.

Community growth: User adds custom food → Hive + Supabase. Admin approves → promoted to global DB. Other users get it via periodic sync + app updates.

**Re-seeding:** if the bundled JSON is updated, regenerate migration via `node .claude/gen_migration_041.js` (V2 generator) or `node scripts/seed_food_database.js` (legacy 93-item generator), then apply. Idempotent (deterministic v5 UUID per docs/architecture/database.md namespace).
