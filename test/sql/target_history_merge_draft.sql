-- Intent: Back up the nutrition target history (which targets were in force from which IST day) in user_profile.target_history, written only through a merge function so a device holding a short list cannot delete a longer cloud one.
-- Destructive?: no   -- ADD COLUMN (nullable, no default) + CREATE FUNCTION + grants; no existing row or column is rewritten
-- Rollback strategy: inline   -- reverse block at the end of this file
-- Linked diagnose-doc: n/a   -- feature (docs/plans/target-history-cloud.md), no bug

-- WHY A MERGE FUNCTION AND NOT A COLUMN IN THE PROFILE UPSERT
--
-- The phone keeps userBox['target_history']: a list, oldest first, of
--   {from: 'YYYY-MM-DD' (IST), calories, protein, carbs, fat, strategy, at_ms}.
-- A plain upsert of that list is assignment (ON CONFLICT DO UPDATE SET col =
-- EXCLUDED.col): a freshly installed device holding one entry would replace a
-- year of history. Same class as migration 123 (diagnose e4a1b7).
--
-- THE RULE (the client's restore merge applies the identical one):
--   union of the stored and the supplied entries keyed by `from`; for one
--   `from` the greatest (at_ms, calories, protein, carbs, fat, strategy)
--   wins; ordered by `from`; the newest 400 kept.
-- There is no delete in the rule and the tie order does not depend on which
-- side an entry came from, so every device converges on the same list.
--
-- SECURITY INVOKER + auth.uid(): the caller's own-row RLS applies
-- (user_profile_select_own / user_profile_update_own) and the row is keyed on
-- the session user, never on a caller-supplied id.
--
-- NOT an integrity boundary: RLS lets a user UPDATE their own user_profile
-- row directly, so the validation below binds this function only. The list
-- is read by that same user's own History screen and by nothing else.
--
-- The function never INSERTs a user_profile row (the profile upsert that runs
-- just before it does); with no row it returns false.

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS target_history jsonb NULL;

COMMENT ON COLUMN public.user_profile.target_history IS
  'Nutrition target history: jsonb array, oldest first, of {from (IST day), calories, protein, '
  'carbs, fat, strategy, at_ms}. Written only by merge_target_history (union by from, newest '
  'at_ms wins, newest 400 kept). NULL = never backed up. docs/plans/target-history-cloud.md.';

CREATE OR REPLACE FUNCTION public.merge_target_history(p_entries jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_stored jsonb;
  v_result jsonb;
  v_last_day date := (now() AT TIME ZONE 'Asia/Kolkata')::date + 1;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'merge_target_history: no authenticated user';
  END IF;
  IF p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' THEN
    RAISE EXCEPTION 'merge_target_history: p_entries must be a jsonb array, got %',
      COALESCE(jsonb_typeof(p_entries), 'null');
  END IF;
  IF jsonb_array_length(p_entries) > 400 THEN
    RAISE EXCEPTION 'merge_target_history: at most 400 entries, got %',
      jsonb_array_length(p_entries);
  END IF;
  IF jsonb_array_length(p_entries) = 0 THEN
    RETURN false;
  END IF;

  -- Row lock: two devices merging at once apply one after the other.
  SELECT up.target_history INTO v_stored
    FROM public.user_profile up
   WHERE up.user_id = auth.uid()
     FOR UPDATE;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF v_stored IS NULL OR jsonb_typeof(v_stored) <> 'array' THEN
    v_stored := '[]'::jsonb;
  END IF;

  WITH raw AS (
    SELECT e FROM jsonb_array_elements(v_stored) AS s(e)
    UNION ALL
    SELECT e FROM jsonb_array_elements(p_entries) AS s(e)
  ),
  shaped AS MATERIALIZED (
    -- Type checks only; no cast happens here, so a malformed element cannot
    -- raise. It is skipped: one bad entry must not block every later push.
    SELECT e
      FROM raw
     -- (`->` on a non-object, and `->>` on a non-string `from`, give NULL or
     -- a text the pattern refuses, so neither needs its own type check.)
     WHERE (e->>'from') ~ '^\d{4}-\d{2}-\d{2}$'
       AND pg_input_is_valid(e->>'from', 'date')
       AND jsonb_typeof(e->'calories') = 'number'
       AND jsonb_typeof(e->'protein') = 'number'
       AND jsonb_typeof(e->'carbs') = 'number'
       AND jsonb_typeof(e->'fat') = 'number'
       AND jsonb_typeof(e->'at_ms') = 'number'
  ),
  typed AS MATERIALIZED (
    SELECT e->>'from' AS d,
           (e->>'calories')::numeric AS calories,
           (e->>'protein')::numeric AS protein,
           (e->>'carbs')::numeric AS carbs,
           (e->>'fat')::numeric AS fat,
           (e->>'at_ms')::numeric AS at_ms,
           CASE WHEN jsonb_typeof(e->'strategy') = 'string'
                THEN left(e->>'strategy', 32) ELSE 'balanced' END AS strategy
      FROM shaped
  ),
  valid AS (
    SELECT d,
           round(calories)::int AS calories,
           round(protein)::int AS protein,
           round(carbs)::int AS carbs,
           round(fat)::int AS fat,
           round(at_ms)::bigint AS at_ms,
           strategy
      FROM typed
     WHERE d::date <= v_last_day
       AND calories BETWEEN 1 AND 20000
       AND protein BETWEEN 0 AND 2000
       AND carbs BETWEEN 0 AND 2000
       AND fat BETWEEN 0 AND 2000
       AND at_ms BETWEEN 0 AND 4102444800000
  ),
  winners AS (
    SELECT DISTINCT ON (d) d, calories, protein, carbs, fat, at_ms, strategy
      FROM valid
     ORDER BY d, at_ms DESC, calories DESC, protein DESC, carbs DESC, fat DESC,
              strategy COLLATE "C" DESC
  ),
  newest AS (
    SELECT * FROM winners ORDER BY d DESC LIMIT 400
  )
  SELECT COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'from', d, 'calories', calories, 'protein', protein, 'carbs', carbs,
               'fat', fat, 'strategy', strategy, 'at_ms', at_ms)
             ORDER BY d),
           '[]'::jsonb)
    INTO v_result
    FROM newest;

  UPDATE public.user_profile
     SET target_history = v_result
   WHERE user_id = auth.uid();
  RETURN true;
END;
$$;

-- Both revokes are required (supabase/migrations/CLAUDE.md, migration 123):
-- Supabase's default privileges grant EXECUTE on a new public function to
-- anon and authenticated directly, not through PUBLIC.
REVOKE ALL ON FUNCTION public.merge_target_history(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.merge_target_history(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.merge_target_history(jsonb) TO authenticated;

COMMENT ON FUNCTION public.merge_target_history(jsonb) IS
  'Merges the supplied nutrition target history into user_profile.target_history for the '
  'session user: union by from, greatest (at_ms, calories, protein, carbs, fat, strategy) wins, '
  'newest 400 kept, malformed or out-of-range entries skipped. Returns true when a row was '
  'updated, false with no user_profile row or an empty array. SECURITY INVOKER + auth.uid(). '
  'Not an integrity boundary (own-row RLS allows a direct UPDATE).';

-- ROLLBACK (inline). The client must be reverted or its kill switch
-- (configBox disable_target_history_cloud) set first, or every profile sync
-- reports a missing function:
--
--   DROP FUNCTION IF EXISTS public.merge_target_history(jsonb);
--   ALTER TABLE public.user_profile DROP COLUMN IF EXISTS target_history;
