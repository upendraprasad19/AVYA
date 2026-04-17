-- Cleanup for F8/F22: `user_custom_exercises` and `user_custom_foods` accumulated
-- duplicate rows because the client was doing `onConflict: 'id'` with a
-- non-stable id. After the client fix deploys (deterministic v5 uuids from
-- `(user_id, type, lower(name))`), upserts dedupe correctly — but we still
-- need to (a) collapse pre-existing duplicates and (b) rewrite remaining row
-- ids to match the client's computation, so future client upserts find an
-- existing row instead of inserting yet another one.
--
-- Namespace (must match client Dart code):
--   CreateCustomExerciseSheet._save           (lib/features/train/widgets/)
--   NutritionNotifier.addCustomFood           (lib/features/nutrition/providers/)
--   customNs = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8'
--   name     = '${userId}|<exercise|food>|${lower(name)}'

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── user_custom_exercises ──────────────────────────────────────────
-- Step 1: dedupe (keep newest row per (user_id, lower(name)))
WITH dedupe AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, lower(name)
      ORDER BY created_at DESC NULLS LAST, id
    ) AS rn
  FROM public.user_custom_exercises
)
DELETE FROM public.user_custom_exercises
WHERE id IN (SELECT id FROM dedupe WHERE rn > 1);

-- Step 2: rewrite remaining ids to the client's stable v5.
-- Only update rows whose id isn't already correct, to avoid churn.
UPDATE public.user_custom_exercises
SET id = uuid_generate_v5(
  '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8'::uuid,
  user_id::text || '|exercise|' || lower(name)
)
WHERE id <> uuid_generate_v5(
  '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8'::uuid,
  user_id::text || '|exercise|' || lower(name)
);

-- ── user_custom_foods ──────────────────────────────────────────────
WITH dedupe AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, lower(name)
      ORDER BY created_at DESC NULLS LAST, id
    ) AS rn
  FROM public.user_custom_foods
)
DELETE FROM public.user_custom_foods
WHERE id IN (SELECT id FROM dedupe WHERE rn > 1);

UPDATE public.user_custom_foods
SET id = uuid_generate_v5(
  '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8'::uuid,
  user_id::text || '|food|' || lower(name)
)
WHERE id <> uuid_generate_v5(
  '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8'::uuid,
  user_id::text || '|food|' || lower(name)
);
