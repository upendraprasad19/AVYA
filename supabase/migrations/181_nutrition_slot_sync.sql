-- Intent: Per-meal nutrition slot sync (OI-348 Landing 1a-ii, closes OI-281): rev / updated_at / entries / legacy_rev on nutrition_logs, entry_key on nutrition_log_items, the nutrition_slot_tombstones table, the CAS RPCs nutrition_slot_put / nutrition_slot_delete / nutrition_slot_state / nutrition_server_now (all SECURITY INVOKER), and three triggers that keep writes made outside the RPCs (old clients, manual SQL) visible to new clients.
-- Destructive?: no   -- additive columns (defaults that need no table rewrite), a new table, new functions and triggers; no existing row is rewritten or dropped
-- Rollback strategy: inline   -- reverse DDL commented at the end of this file; the client kill switch configBox['disable_nutrition_slot_sync'] returns every device to the legacy upsert path first
-- Linked diagnose-doc: a6c4e2

-- Spec: docs/plans/nutrition-slot-sync.md §3. Revision rule (every writer): a
-- slot's `rev` only grows over its whole life, across delete and re-create:
-- current = the row's rev, else the tombstone's rev, else 0; a successful
-- write sets current + 1. `legacy_rev` = the rev of the last write that did
-- NOT go through the RPCs (0 for every row that exists before this file).

-- 0. The ALTER takes an ACCESS EXCLUSIVE lock on a live table: give up after
--    5 s instead of queueing every app query behind it (B-pass seat A, P3).
--    Transaction-local; apply_migration runs the file in one transaction.
SET LOCAL lock_timeout = '5s';

-- 1. nutrition_logs: new columns. `now()` is STABLE, so the ADD needs no
--    rewrite; the default then becomes clock_timestamp() for new rows.
ALTER TABLE public.nutrition_logs
  ADD COLUMN IF NOT EXISTS rev bigint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS entries jsonb,
  ADD COLUMN IF NOT EXISTS legacy_rev bigint NOT NULL DEFAULT 0;
ALTER TABLE public.nutrition_logs
  ALTER COLUMN updated_at SET DEFAULT clock_timestamp();

CREATE INDEX IF NOT EXISTS idx_nutrition_logs_user_updated
  ON public.nutrition_logs (user_id, updated_at, id);

-- 2. nutrition_log_items: the entry an item belongs to (null on legacy rows).
ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS entry_key text;

-- 3. Tombstones: one row per deleted slot, so a delete reaches other devices
--    while every server reader of nutrition_logs keeps working unfiltered.
CREATE TABLE IF NOT EXISTS public.nutrition_slot_tombstones (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  date date NOT NULL,
  meal_type text NOT NULL,
  rev bigint NOT NULL,
  deleted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  legacy_rev bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, date, meal_type)
);

CREATE INDEX IF NOT EXISTS idx_nutrition_slot_tombstones_cursor
  ON public.nutrition_slot_tombstones (user_id, deleted_at, date, meal_type);

ALTER TABLE public.nutrition_slot_tombstones ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nutrition_slot_tombstones FROM anon;

DROP POLICY IF EXISTS nutrition_slot_tombstones_select_own ON public.nutrition_slot_tombstones;
CREATE POLICY nutrition_slot_tombstones_select_own ON public.nutrition_slot_tombstones
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS nutrition_slot_tombstones_insert_own ON public.nutrition_slot_tombstones;
CREATE POLICY nutrition_slot_tombstones_insert_own ON public.nutrition_slot_tombstones
  FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS nutrition_slot_tombstones_update_own ON public.nutrition_slot_tombstones;
CREATE POLICY nutrition_slot_tombstones_update_own ON public.nutrition_slot_tombstones
  FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS nutrition_slot_tombstones_delete_own ON public.nutrition_slot_tombstones;
CREATE POLICY nutrition_slot_tombstones_delete_own ON public.nutrition_slot_tombstones
  FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- 4. The current state of one slot of the caller, in the shape the pull reads
--    (`*, nutrition_log_items(*)` and a tombstone row). Used by the conflict
--    replies; a plain read of the caller's own rows under RLS.
CREATE OR REPLACE FUNCTION public.nutrition_slot_state(p_date date, p_meal_type text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'row', (
      SELECT to_jsonb(l) || jsonb_build_object(
        'nutrition_log_items', COALESCE((
          SELECT jsonb_agg(to_jsonb(i) ORDER BY i.item_index)
          FROM public.nutrition_log_items i
          WHERE i.log_id = l.id), '[]'::jsonb))
      FROM public.nutrition_logs l
      WHERE l.user_id = auth.uid() AND l.date = p_date AND l.meal_type = p_meal_type),
    'tombstone', (
      SELECT to_jsonb(t)
      FROM public.nutrition_slot_tombstones t
      WHERE t.user_id = auth.uid() AND t.date = p_date AND t.meal_type = p_meal_type));
$$;

-- 5. Conditional put of one whole slot (compare-and-set on `rev`).
CREATE OR REPLACE FUNCTION public.nutrition_slot_put(
  p_date date,
  p_meal_type text,
  p_base_rev bigint,
  p_totals jsonb,
  p_entries jsonb,
  p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
-- The marker the three triggers read (`app.nutrition_rpc`) is set in the body
-- and put back to its previous value before EVERY return, so a later plain
-- write in the SAME transaction is still seen as an outside write (B-pass
-- seat A, finding 1). An error needs no reset: the rollback of the
-- (sub)transaction undoes a local set_config. A function-level
-- `SET app.nutrition_rpc = 'on'` is refused live (42501: a non-superuser may
-- not attach a custom placeholder to a function; PG 17, 2026-11-23).
AS $$
DECLARE
  v_prev text;
  v_uid uuid := auth.uid();
  v_row_id uuid;
  v_row_rev bigint;
  v_tomb_rev bigint;
  v_tomb_legacy bigint;
  v_current bigint;
  v_legacy bigint := 0;
  v_new_rev bigint;
  v_id uuid;
  v_created timestamptz;
  v_ts timestamptz;
  v_ua timestamptz;
  v_e jsonb;
  v_i jsonb;
  v_n int;
  v_items_total int := 0;
  v_key text;
  v_field text;
  v_num numeric;
  v_sum_cal numeric := 0;
  v_sum_p numeric := 0;
  v_sum_c numeric := 0;
  v_sum_f numeric := 0;
  v_sum_fib numeric := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'nutrition_slot_put: not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_base_rev IS NULL OR p_base_rev < 0 THEN
    RAISE EXCEPTION 'nutrition_slot_put: bad base rev' USING ERRCODE = '22023';
  END IF;
  IF p_date IS NULL OR p_meal_type IS NULL
     OR p_meal_type NOT IN ('breakfast', 'lunch', 'dinner', 'snacks') THEN
    RAISE EXCEPTION 'nutrition_slot_put: bad slot' USING ERRCODE = '22023';
  END IF;

  -- Bounds (the client checks the same before calling; these are the last line).
  IF jsonb_typeof(p_entries) IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_items) IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_totals) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'nutrition_slot_put: bad payload shape' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_entries) < 1 OR jsonb_array_length(p_entries) > 100 THEN
    RAISE EXCEPTION 'nutrition_slot_put: entry count out of bounds' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'nutrition_slot_put: item count out of bounds' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(p_entries) e)
     <> jsonb_array_length(p_entries) THEN
    RAISE EXCEPTION 'nutrition_slot_put: duplicate entry id' USING ERRCODE = '22023';
  END IF;

  FOR v_e IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    IF jsonb_typeof(v_e) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_e->'id') IS DISTINCT FROM 'string'
       OR length(v_e->>'id') < 1 THEN
      RAISE EXCEPTION 'nutrition_slot_put: entry without id' USING ERRCODE = '22023';
    END IF;
    FOREACH v_key IN ARRAY ARRAY['id', 'k', 's', 'la', 'ca', 'src'] LOOP
      IF v_e ? v_key AND jsonb_typeof(v_e->v_key) NOT IN ('string', 'null') THEN
        RAISE EXCEPTION 'nutrition_slot_put: entry field % not text', v_key USING ERRCODE = '22023';
      END IF;
      IF length(coalesce(v_e->>v_key, '')) > 200 THEN
        RAISE EXCEPTION 'nutrition_slot_put: entry field % too long', v_key USING ERRCODE = '22023';
      END IF;
    END LOOP;
    IF jsonb_typeof(v_e->'n') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'nutrition_slot_put: entry item count missing' USING ERRCODE = '22023';
    END IF;
    v_n := (v_e->>'n')::int;
    IF v_n < 0 OR v_n > 500 THEN
      RAISE EXCEPTION 'nutrition_slot_put: entry item count out of bounds' USING ERRCODE = '22023';
    END IF;
    IF (SELECT count(*) FROM jsonb_array_elements(p_items) i
        WHERE i->>'entry_key' = v_e->>'id') <> v_n THEN
      RAISE EXCEPTION 'nutrition_slot_put: entry item count mismatch' USING ERRCODE = '22023';
    END IF;
    v_items_total := v_items_total + v_n;
    IF jsonb_typeof(v_e->'t') IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'nutrition_slot_put: entry totals missing' USING ERRCODE = '22023';
    END IF;
    FOREACH v_field IN ARRAY ARRAY['calories', 'protein', 'carbs', 'fat', 'fiber'] LOOP
      IF jsonb_typeof(v_e->'t'->v_field) IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'nutrition_slot_put: entry total % missing', v_field USING ERRCODE = '22023';
      END IF;
      v_num := (v_e->'t'->>v_field)::numeric;
      IF v_num < 0
         OR (v_field = 'calories' AND v_num > 15000)
         OR (v_field IN ('protein', 'carbs', 'fat') AND v_num > 2000)
         OR (v_field = 'fiber' AND v_num > 500) THEN
        RAISE EXCEPTION 'nutrition_slot_put: entry total % out of bounds', v_field USING ERRCODE = '22023';
      END IF;
    END LOOP;
    v_sum_cal := v_sum_cal + (v_e->'t'->>'calories')::numeric;
    v_sum_p := v_sum_p + (v_e->'t'->>'protein')::numeric;
    v_sum_c := v_sum_c + (v_e->'t'->>'carbs')::numeric;
    v_sum_f := v_sum_f + (v_e->'t'->>'fat')::numeric;
    v_sum_fib := v_sum_fib + (v_e->'t'->>'fiber')::numeric;
  END LOOP;
  IF v_items_total <> jsonb_array_length(p_items) THEN
    RAISE EXCEPTION 'nutrition_slot_put: item count mismatch' USING ERRCODE = '22023';
  END IF;

  FOR v_i IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF jsonb_typeof(v_i) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_i->'entry_key') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_i->'food_name') IS DISTINCT FROM 'string'
       OR length(v_i->>'food_name') > 200 THEN
      RAISE EXCEPTION 'nutrition_slot_put: bad item' USING ERRCODE = '22023';
    END IF;
    FOREACH v_field IN ARRAY ARRAY['quantity_g', 'calories', 'protein', 'carbs', 'fat', 'fiber'] LOOP
      IF jsonb_typeof(v_i->v_field) IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'nutrition_slot_put: item % missing', v_field USING ERRCODE = '22023';
      END IF;
      v_num := (v_i->>v_field)::numeric;
      IF (v_field <> 'quantity_g' AND v_num < 0)
         OR (v_field = 'calories' AND v_num > 10000)
         OR (v_field IN ('protein', 'carbs', 'fat') AND v_num > 2000)
         OR (v_field = 'fiber' AND v_num > 500) THEN
        RAISE EXCEPTION 'nutrition_slot_put: item % out of bounds', v_field USING ERRCODE = '22023';
      END IF;
    END LOOP;
  END LOOP;

  -- p_totals = the sum of entry totals, both rounded to 3 decimals (R16 P2-1).
  IF round(coalesce((p_totals->>'total_calories')::numeric, -1), 3) <> round(v_sum_cal, 3)
     OR round(coalesce((p_totals->>'total_protein')::numeric, -1), 3) <> round(v_sum_p, 3)
     OR round(coalesce((p_totals->>'total_carbs')::numeric, -1), 3) <> round(v_sum_c, 3)
     OR round(coalesce((p_totals->>'total_fat')::numeric, -1), 3) <> round(v_sum_f, 3)
     OR round(coalesce((p_totals->>'total_fiber')::numeric, -1), 3) <> round(v_sum_fib, 3) THEN
    RAISE EXCEPTION 'nutrition_slot_put: totals do not match the entries' USING ERRCODE = '22023';
  END IF;

  -- created_at of a new row = the oldest entry's `ca` (a bad value falls back
  -- to now() instead of raising: a raise would be a permanent failure).
  FOR v_e IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    BEGIN
      v_ts := (v_e->>'ca')::timestamptz;
    EXCEPTION WHEN others THEN
      v_ts := NULL;
    END;
    IF v_ts IS NOT NULL AND (v_created IS NULL OR v_ts < v_created) THEN
      v_created := v_ts;
    END IF;
  END LOOP;
  v_created := coalesce(v_created, now());

  v_prev := current_setting('app.nutrition_rpc', true);
  PERFORM set_config('app.nutrition_rpc', 'on', true);

  PERFORM pg_advisory_xact_lock(
    hashtext(v_uid::text || '|' || p_date::text || '|' || p_meal_type));

  SELECT id, rev INTO v_row_id, v_row_rev
  FROM public.nutrition_logs
  WHERE user_id = v_uid AND date = p_date AND meal_type = p_meal_type
  FOR UPDATE;
  IF v_row_id IS NOT NULL THEN
    v_current := v_row_rev;
  ELSE
    SELECT rev, legacy_rev INTO v_tomb_rev, v_tomb_legacy
    FROM public.nutrition_slot_tombstones
    WHERE user_id = v_uid AND date = p_date AND meal_type = p_meal_type
    FOR UPDATE;
    v_current := coalesce(v_tomb_rev, 0);
    v_legacy := coalesce(v_tomb_legacy, 0);
  END IF;

  IF v_current <> p_base_rev THEN
    PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);
    RETURN jsonb_build_object('status', 'conflict', 'rev', v_current)
      || public.nutrition_slot_state(p_date, p_meal_type);
  END IF;

  v_new_rev := v_current + 1;
  IF v_row_id IS NOT NULL THEN
    UPDATE public.nutrition_logs SET
      rev = v_new_rev,
      entries = p_entries,
      total_calories = (p_totals->>'total_calories')::numeric,
      total_protein = (p_totals->>'total_protein')::numeric,
      total_carbs = (p_totals->>'total_carbs')::numeric,
      total_fat = (p_totals->>'total_fat')::numeric,
      total_fiber = (p_totals->>'total_fiber')::numeric
    WHERE id = v_row_id;
    v_id := v_row_id;
  ELSE
    BEGIN
      INSERT INTO public.nutrition_logs (
        user_id, date, meal_type, rev, legacy_rev, entries,
        total_calories, total_protein, total_carbs, total_fat, total_fiber,
        created_at)
      VALUES (
        v_uid, p_date, p_meal_type, v_new_rev, v_legacy, p_entries,
        (p_totals->>'total_calories')::numeric,
        (p_totals->>'total_protein')::numeric,
        (p_totals->>'total_carbs')::numeric,
        (p_totals->>'total_fat')::numeric,
        (p_totals->>'total_fiber')::numeric,
        v_created)
      RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
      -- An old client inserted the slot after our read: report its row.
      SELECT rev INTO v_row_rev FROM public.nutrition_logs
      WHERE user_id = v_uid AND date = p_date AND meal_type = p_meal_type;
      PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);
      RETURN jsonb_build_object('status', 'conflict', 'rev', coalesce(v_row_rev, v_current))
        || public.nutrition_slot_state(p_date, p_meal_type);
    END;
  END IF;

  DELETE FROM public.nutrition_log_items WHERE log_id = v_id;
  INSERT INTO public.nutrition_log_items (
    log_id, item_index, entry_key, food_name,
    quantity_g, calories, protein, carbs, fat, fiber)
  SELECT v_id, (x.ord - 1)::int, x.item->>'entry_key', x.item->>'food_name',
         (x.item->>'quantity_g')::numeric, (x.item->>'calories')::numeric,
         (x.item->>'protein')::numeric, (x.item->>'carbs')::numeric,
         (x.item->>'fat')::numeric, (x.item->>'fiber')::numeric
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(item, ord);

  DELETE FROM public.nutrition_slot_tombstones
  WHERE user_id = v_uid AND date = p_date AND meal_type = p_meal_type;

  SELECT updated_at INTO v_ua FROM public.nutrition_logs WHERE id = v_id;
  PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);
  RETURN jsonb_build_object('status', 'ok', 'rev', v_new_rev, 'updated_at', v_ua);
END;
$$;

-- 6. Conditional delete of one whole slot; leaves a tombstone.
CREATE OR REPLACE FUNCTION public.nutrition_slot_delete(
  p_date date,
  p_meal_type text,
  p_base_rev bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
-- Marker set in the body and put back before every return; see nutrition_slot_put.
AS $$
DECLARE
  v_prev text;
  v_uid uuid := auth.uid();
  v_row_id uuid;
  v_row_rev bigint;
  v_row_legacy bigint;
  v_tomb_rev bigint;
  v_current bigint;
  v_deleted timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'nutrition_slot_delete: not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_base_rev IS NULL OR p_base_rev < 0 THEN
    RAISE EXCEPTION 'nutrition_slot_delete: bad base rev' USING ERRCODE = '22023';
  END IF;
  IF p_date IS NULL OR p_meal_type IS NULL
     OR p_meal_type NOT IN ('breakfast', 'lunch', 'dinner', 'snacks') THEN
    RAISE EXCEPTION 'nutrition_slot_delete: bad slot' USING ERRCODE = '22023';
  END IF;

  v_prev := current_setting('app.nutrition_rpc', true);
  PERFORM set_config('app.nutrition_rpc', 'on', true);

  PERFORM pg_advisory_xact_lock(
    hashtext(v_uid::text || '|' || p_date::text || '|' || p_meal_type));

  SELECT id, rev, legacy_rev INTO v_row_id, v_row_rev, v_row_legacy
  FROM public.nutrition_logs
  WHERE user_id = v_uid AND date = p_date AND meal_type = p_meal_type
  FOR UPDATE;
  IF v_row_id IS NOT NULL THEN
    v_current := v_row_rev;
  ELSE
    SELECT rev INTO v_tomb_rev
    FROM public.nutrition_slot_tombstones
    WHERE user_id = v_uid AND date = p_date AND meal_type = p_meal_type
    FOR UPDATE;
    v_current := coalesce(v_tomb_rev, 0);
  END IF;

  IF v_current <> p_base_rev THEN
    PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);
    RETURN jsonb_build_object('status', 'conflict', 'rev', v_current)
      || public.nutrition_slot_state(p_date, p_meal_type);
  END IF;

  IF v_row_id IS NULL THEN
    -- Nothing there at the expected rev: already deleted (or never written).
    PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);
    RETURN jsonb_build_object('status', 'ok', 'rev', v_current, 'noop', true);
  END IF;

  DELETE FROM public.nutrition_logs WHERE id = v_row_id;
  v_deleted := clock_timestamp();
  INSERT INTO public.nutrition_slot_tombstones (
    user_id, date, meal_type, rev, legacy_rev, deleted_at)
  VALUES (v_uid, p_date, p_meal_type, v_current + 1, v_row_legacy, v_deleted)
  ON CONFLICT (user_id, date, meal_type) DO UPDATE SET
    rev = EXCLUDED.rev,
    legacy_rev = EXCLUDED.legacy_rev,
    deleted_at = EXCLUDED.deleted_at;

  PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);
  RETURN jsonb_build_object('status', 'ok', 'rev', v_current + 1, 'deleted_at', v_deleted);
END;
$$;

-- 7. Capability probe and the re-baseline's cursor start.
CREATE OR REPLACE FUNCTION public.nutrition_server_now()
RETURNS timestamptz
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT clock_timestamp();
$$;

-- 8. Triggers for writes made outside the RPCs (`app.nutrition_rpc` not on).
--    Named trg_zz_* so each sorts after trg_suppress_redundant_updates (same
--    timing fires alphabetically): a true no-op UPDATE stays suppressed.
CREATE OR REPLACE FUNCTION public.nutrition_logs_rev_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_tomb_rev bigint;
BEGIN
  NEW.updated_at := clock_timestamp();
  IF coalesce(current_setting('app.nutrition_rpc', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  NEW.entries := NULL;
  IF TG_OP = 'INSERT' THEN
    -- An INSERT that will turn into an ON CONFLICT update (the row exists)
    -- changes nothing here: the BEFORE UPDATE run of this trigger bumps rev.
    IF NOT EXISTS (
      SELECT 1 FROM public.nutrition_logs
      WHERE user_id = NEW.user_id AND date = NEW.date AND meal_type = NEW.meal_type) THEN
      SELECT rev INTO v_tomb_rev FROM public.nutrition_slot_tombstones
      WHERE user_id = NEW.user_id AND date = NEW.date AND meal_type = NEW.meal_type;
      NEW.rev := coalesce(v_tomb_rev, 0) + 1;
      DELETE FROM public.nutrition_slot_tombstones
      WHERE user_id = NEW.user_id AND date = NEW.date AND meal_type = NEW.meal_type;
    END IF;
  ELSIF NEW.rev = OLD.rev THEN
    NEW.rev := OLD.rev + 1;
  END IF;
  NEW.legacy_rev := NEW.rev;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_nutrition_rev ON public.nutrition_logs;
CREATE TRIGGER trg_zz_nutrition_rev
  BEFORE INSERT OR UPDATE ON public.nutrition_logs
  FOR EACH ROW EXECUTE FUNCTION public.nutrition_logs_rev_trg();

CREATE OR REPLACE FUNCTION public.nutrition_log_items_rev_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF coalesce(current_setting('app.nutrition_rpc', true), '') = 'on' THEN
    RETURN NULL;
  END IF;
  -- The explicit rev change defeats the redundant-update suppression when
  -- entries is already null; the parent trigger then sees NEW.rev <> OLD.rev
  -- and does not bump a second time.
  IF TG_OP = 'DELETE' THEN
    UPDATE public.nutrition_logs SET rev = rev + 1, entries = NULL WHERE id = OLD.log_id;
  ELSE
    UPDATE public.nutrition_logs SET rev = rev + 1, entries = NULL WHERE id = NEW.log_id;
    IF TG_OP = 'UPDATE' AND OLD.log_id IS DISTINCT FROM NEW.log_id THEN
      UPDATE public.nutrition_logs SET rev = rev + 1, entries = NULL WHERE id = OLD.log_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_nutrition_items_rev ON public.nutrition_log_items;
CREATE TRIGGER trg_zz_nutrition_items_rev
  AFTER INSERT OR UPDATE OR DELETE ON public.nutrition_log_items
  FOR EACH ROW EXECUTE FUNCTION public.nutrition_log_items_rev_trg();

CREATE OR REPLACE FUNCTION public.nutrition_logs_tombstone_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF coalesce(current_setting('app.nutrition_rpc', true), '') = 'on' THEN
    RETURN NULL;
  END IF;
  -- A cascade (account deletion: auth.users -> public.users -> nutrition_logs)
  -- must not insert a tombstone: its FK to users would raise 23503.
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id) THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.nutrition_slot_tombstones (
    user_id, date, meal_type, rev, legacy_rev, deleted_at)
  VALUES (OLD.user_id, OLD.date, OLD.meal_type, OLD.rev + 1, OLD.rev + 1, clock_timestamp())
  ON CONFLICT (user_id, date, meal_type) DO UPDATE SET
    rev = EXCLUDED.rev,
    legacy_rev = EXCLUDED.legacy_rev,
    deleted_at = clock_timestamp();
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_nutrition_tombstone ON public.nutrition_logs;
CREATE TRIGGER trg_zz_nutrition_tombstone
  AFTER DELETE ON public.nutrition_logs
  FOR EACH ROW EXECUTE FUNCTION public.nutrition_logs_tombstone_trg();

-- 9. Privileges: the RPCs for signed-in users only; trigger functions for no one.
REVOKE ALL ON FUNCTION public.nutrition_slot_put(date, text, bigint, jsonb, jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nutrition_slot_delete(date, text, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nutrition_slot_state(date, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nutrition_server_now() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nutrition_slot_put(date, text, bigint, jsonb, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nutrition_slot_delete(date, text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nutrition_slot_state(date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nutrition_server_now() TO authenticated;
REVOKE ALL ON FUNCTION public.nutrition_logs_rev_trg() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nutrition_log_items_rev_trg() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nutrition_logs_tombstone_trg() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Rollback (inline). Switch every device to legacy mode first
-- (configBox['disable_nutrition_slot_sync'] = true), then:
--
-- DROP TRIGGER IF EXISTS trg_zz_nutrition_tombstone ON public.nutrition_logs;
-- DROP TRIGGER IF EXISTS trg_zz_nutrition_items_rev ON public.nutrition_log_items;
-- DROP TRIGGER IF EXISTS trg_zz_nutrition_rev ON public.nutrition_logs;
-- DROP FUNCTION IF EXISTS public.nutrition_logs_tombstone_trg();
-- DROP FUNCTION IF EXISTS public.nutrition_log_items_rev_trg();
-- DROP FUNCTION IF EXISTS public.nutrition_logs_rev_trg();
-- DROP FUNCTION IF EXISTS public.nutrition_server_now();
-- DROP FUNCTION IF EXISTS public.nutrition_slot_delete(date, text, bigint);
-- DROP FUNCTION IF EXISTS public.nutrition_slot_put(date, text, bigint, jsonb, jsonb, jsonb);
-- DROP FUNCTION IF EXISTS public.nutrition_slot_state(date, text);
-- DROP TABLE IF EXISTS public.nutrition_slot_tombstones;
-- DROP INDEX IF EXISTS public.idx_nutrition_logs_user_updated;
-- ALTER TABLE public.nutrition_log_items DROP COLUMN IF EXISTS entry_key;
-- ALTER TABLE public.nutrition_logs
--   DROP COLUMN IF EXISTS legacy_rev,
--   DROP COLUMN IF EXISTS entries,
--   DROP COLUMN IF EXISTS updated_at,
--   DROP COLUMN IF EXISTS rev;
