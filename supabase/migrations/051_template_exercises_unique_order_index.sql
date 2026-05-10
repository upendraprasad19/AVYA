-- 051_template_exercises_unique_order_index.sql
-- Backlog #2 — APK Test #15 closeout (2026-05-10)
--
-- Adds UNIQUE (template_id, order_index) to public.template_exercises so
-- the Flutter client can switch _syncWorkoutTemplates from a fragile
-- DELETE-then-INSERT pattern to a real UPSERT with onConflict.
--
-- Pre-migration behavior (sync_service.dart:3538-3548):
--   .from('template_exercises').delete().eq('template_id', cloudTmplId)  -- wipe
--   for (i in exercises) { .insert({template_id, order_index, ...}) }    -- re-insert
--
-- Failure mode: if the DELETE succeeded but a subsequent INSERT errored
-- (network blip, FK constraint, payload error), the user's template was
-- left with PARTIAL children — half the exercises gone, no audit trail.
-- Restore on next sync would re-DELETE the half that survived and try
-- again. Idempotent on success but lossy on partial failure.
--
-- Post-migration behavior:
--   for (i in exercises) {
--     .upsert({template_id, order_index, ...}, onConflict: 'template_id,order_index')
--   }
--
-- Each row is independently upserted. Network blip on row 4 of 8 leaves
-- rows 0..3 + 5..7 intact (5..7 are upserts, not inserts, so they
-- update the existing-but-unchanged row). Next sync retries row 4 alone.
-- No "torn" template state.
--
-- Verified pre-migration: SELECT template_id, order_index, COUNT(*) FROM
-- template_exercises GROUP BY template_id, order_index HAVING COUNT(*) > 1
-- returns ZERO rows (founder's project_id dedsavbjuwgarrhphgnl) on
-- 2026-05-10. The DELETE-then-INSERT pattern was correct in steady
-- state; this migration just hardens it against partial failure.
--
-- Idempotent: ALTER TABLE ADD CONSTRAINT throws if the constraint
-- already exists, but the IF NOT EXISTS clause via DO block handles
-- re-runs.
--
-- closes-diagnose: 2026-05-10-template-exercises-upsert-g7h8i9

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'template_exercises_template_id_order_index_key'
      AND conrelid = 'public.template_exercises'::regclass
  ) THEN
    ALTER TABLE public.template_exercises
      ADD CONSTRAINT template_exercises_template_id_order_index_key
      UNIQUE (template_id, order_index);
  END IF;
END
$$;

COMMENT ON CONSTRAINT
  template_exercises_template_id_order_index_key ON public.template_exercises IS
  'Backlog #2 / APK Test #15 closeout — enables onConflict upsert in '
  '_syncWorkoutTemplates (sync_service.dart). Replaces fragile '
  'DELETE-then-INSERT pattern. See migration 051 header.';
