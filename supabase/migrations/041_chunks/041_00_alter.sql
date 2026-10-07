-- Migration 041: V2 food database seed (1431 items).
-- APK Test #3 batch (2026-04-26).
--
-- Expands food_database from 93 → 1431 items. Sources:
--   - 93 icanbefitter_seed (preserved by deterministic v5 UUID)
--   - 699 manual_indian_staples_v2
--   - 228 manual_western_v2
--   - 225 openfoodfacts_india_v2
--   - 186 manual_fitness_v2
--
-- Adds is_veg + is_vegan columns. is_vegan=true implies is_veg=true.
-- Idempotent: ON CONFLICT (id) DO UPDATE so legacy rows get refreshed in place.

ALTER TABLE food_database
  ADD COLUMN IF NOT EXISTS is_veg BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS is_vegan BOOLEAN DEFAULT FALSE;
