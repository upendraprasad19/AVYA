-- supabase/tests/nutrition_slot_rpc_live_verify.sql
-- OI-348 Landing 1a-ii, migration 181 (spec docs/plans/nutrition-slot-sync.md §6).
--
-- Run ONCE against project dedsavbjuwgarrhphgnl AFTER the founder's go for the
-- apply, as ONE execute_sql request. Everything happens inside a transaction
-- that ALWAYS rolls back. It acts as an existing TESTING user (pre-launch,
-- CLAUDE.md §1), through `request.jwt.claims` + `SET LOCAL ROLE authenticated`,
-- so RLS and auth.uid() behave as for the app. Each check RAISEs on failure;
-- a clean run ends with the NOTICE 'nutrition_slot live verify: ALL OK'.
--
-- Fill v_uid with a testing user's id that has NO meals on 2001-01-0x (the
-- dates used below are far in the past and are rolled back anyway).
--
-- B-pass seat A (2026-11-23): every RPC reply's status and rev is asserted
-- (a conflicting call no longer passes a later check vacuously); the second
-- user is read BEFORE the role switch (users RLS is own-row only); E2 drives
-- the item trigger's `entries = NULL` arm on an RPC-written row; M pins that an
-- identical old-client re-push changes nothing; C runs AFTER RPC calls in the
-- same transaction, so it also proves the RPC marker does not leak; N reads the
-- marker after every return path of both RPCs.

BEGIN;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';

DO $verify$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-000000000000'; -- REPLACE before running
  v_other uuid;
  r jsonb;
  v_rev bigint;
  v_rev2 bigint;
  v_legacy bigint;
  v_legacy2 bigint;
  v_upd timestamptz;
  v_upd2 timestamptz;
  v_ent jsonb;
  v_items jsonb;
  v_tot jsonb;
  v_n int;
  v_ok boolean;
  v_fn text;
  v_j_ran boolean := false;
BEGIN
  -- Read before the role switch: public.users is own-row only under RLS.
  SELECT id INTO v_other FROM public.users WHERE id <> v_uid LIMIT 1;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';

  v_ent := jsonb_build_array(jsonb_build_object(
    'id', 'e1', 'k', 'nlog_2001-01-01_lunch_aaaaaaaa', 's', 'sig',
    'la', '2001-01-01T04:00:00.123456Z', 'ca', '2001-01-01T04:00:00.123456Z',
    'src', 'manualSearch', 'n', 1,
    't', jsonb_build_object('calories', 0.1, 'protein', 0.2, 'carbs', 1,
                            'fat', 1, 'fiber', 0)));
  v_items := jsonb_build_array(jsonb_build_object(
    'entry_key', 'e1', 'food_name', 'Dal', 'quantity_g', 150, 'calories', 0.1,
    'protein', 0.2, 'carbs', 1, 'fat', 1, 'fiber', 0));
  v_tot := jsonb_build_object('total_calories', 0.1, 'total_protein', 0.2,
    'total_carbs', 1, 'total_fat', 1, 'total_fiber', 0);

  -- A: CAS ok (insert) then conflict on a stale base.
  r := public.nutrition_slot_put('2001-01-01', 'lunch', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 1 THEN RAISE 'A1 %', r; END IF;
  r := public.nutrition_slot_put('2001-01-01', 'lunch', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'conflict' OR (r->>'rev')::int <> 1
     OR r->'row'->>'rev' <> '1' OR jsonb_array_length(r->'row'->'nutrition_log_items') <> 1
     OR r->'tombstone' <> 'null'::jsonb
  THEN RAISE 'A2 %', r; END IF;

  -- B: delete -> tombstone -> put again: rev keeps growing.
  r := public.nutrition_slot_delete('2001-01-01', 'lunch', 1);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 2 OR r->>'deleted_at' IS NULL
  THEN RAISE 'B1 %', r; END IF;
  SELECT rev INTO v_rev FROM public.nutrition_slot_tombstones
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_rev IS DISTINCT FROM 2 THEN RAISE 'B2 tomb rev %', v_rev; END IF;
  r := public.nutrition_slot_put('2001-01-01', 'lunch', 2, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 3 THEN RAISE 'B3 %', r; END IF;
  IF EXISTS (SELECT 1 FROM public.nutrition_slot_tombstones
             WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch')
  THEN RAISE 'B4 tombstone survived the put'; END IF;
  r := public.nutrition_slot_delete('2001-01-01', 'lunch', 3);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 4 THEN RAISE 'B5 %', r; END IF;
  -- A delete at the tombstone's rev is a no-op ...
  r := public.nutrition_slot_delete('2001-01-01', 'lunch', 4);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 4 OR (r->>'noop')::boolean IS NOT TRUE
  THEN RAISE 'B6 %', r; END IF;
  -- ... and at a stale base a conflict that carries the tombstone, no row.
  r := public.nutrition_slot_delete('2001-01-01', 'lunch', 2);
  IF r->>'status' <> 'conflict' OR (r->>'rev')::int <> 4
     OR r->'row' <> 'null'::jsonb OR (r->'tombstone'->>'rev')::int <> 4
  THEN RAISE 'B7 %', r; END IF;
  -- A put at a stale base against the tombstone conflicts the same way.
  r := public.nutrition_slot_put('2001-01-01', 'lunch', 3, v_tot, v_ent, v_items);
  IF r->>'status' <> 'conflict' OR (r->>'rev')::int <> 4 OR r->'row' <> 'null'::jsonb
  THEN RAISE 'B8 %', r; END IF;

  -- C: old-client INSERT after a tombstone, in the SAME transaction as the RPC
  --    calls above (the marker must not leak): rev = tomb + 1, tombstone gone,
  --    entries null, legacy_rev = rev.
  INSERT INTO public.nutrition_logs (user_id, date, meal_type, total_calories)
  VALUES (v_uid, '2001-01-01', 'lunch', 100);
  SELECT rev, legacy_rev INTO v_rev, v_legacy FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_rev <> 5 OR v_legacy <> 5 THEN RAISE 'C1 rev % legacy %', v_rev, v_legacy; END IF;
  IF EXISTS (SELECT 1 FROM public.nutrition_slot_tombstones
             WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch')
  THEN RAISE 'C2 tombstone not consumed'; END IF;

  -- D: a PostgREST-style legacy upsert on the DO UPDATE path bumps rev ONCE
  --    and touches no tombstone; an identical one is suppressed (no bump).
  INSERT INTO public.nutrition_logs (user_id, date, meal_type, total_calories)
  VALUES (v_uid, '2001-01-01', 'lunch', 120)
  ON CONFLICT (user_id, date, meal_type) DO UPDATE SET total_calories = EXCLUDED.total_calories;
  SELECT rev INTO v_rev FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_rev <> 6 THEN RAISE 'D1 rev %', v_rev; END IF;
  INSERT INTO public.nutrition_logs (user_id, date, meal_type, total_calories)
  VALUES (v_uid, '2001-01-01', 'lunch', 120)
  ON CONFLICT (user_id, date, meal_type) DO UPDATE SET total_calories = EXCLUDED.total_calories;
  SELECT rev INTO v_rev FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_rev <> 6 THEN RAISE 'D2 identical upsert bumped: rev %', v_rev; END IF;

  -- E1: two consecutive old-client item edits on the legacy row -> two bumps.
  INSERT INTO public.nutrition_log_items (log_id, item_index, food_name, calories)
  SELECT id, 0, 'A', 10 FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  UPDATE public.nutrition_log_items SET calories = 11
   WHERE log_id = (SELECT id FROM public.nutrition_logs
                    WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch');
  SELECT rev, legacy_rev INTO v_rev, v_legacy FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_rev <> 8 OR v_legacy <> 8 THEN RAISE 'E1 rev % legacy %', v_rev, v_legacy; END IF;

  -- E2: on an RPC-written row (entries NOT null), an old-client item UPDATE and
  --     an item DELETE each bump rev by one and null entries.
  r := public.nutrition_slot_put('2001-01-05', 'breakfast', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 1 THEN RAISE 'E2a %', r; END IF;
  UPDATE public.nutrition_log_items SET calories = 0.5
   WHERE log_id = (SELECT id FROM public.nutrition_logs
                    WHERE user_id = v_uid AND date = '2001-01-05' AND meal_type = 'breakfast');
  SELECT rev, legacy_rev INTO v_rev, v_legacy FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-05' AND meal_type = 'breakfast';
  IF v_rev <> 2 OR v_legacy <> 2 THEN RAISE 'E2b rev % legacy %', v_rev, v_legacy; END IF;
  IF (SELECT entries FROM public.nutrition_logs
       WHERE user_id = v_uid AND date = '2001-01-05' AND meal_type = 'breakfast') IS NOT NULL
  THEN RAISE 'E2c old-client item UPDATE kept entries'; END IF;
  DELETE FROM public.nutrition_log_items
   WHERE log_id = (SELECT id FROM public.nutrition_logs
                    WHERE user_id = v_uid AND date = '2001-01-05' AND meal_type = 'breakfast');
  SELECT rev, legacy_rev INTO v_rev, v_legacy FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-05' AND meal_type = 'breakfast';
  IF v_rev <> 3 OR v_legacy <> 3 THEN RAISE 'E2d rev % legacy %', v_rev, v_legacy; END IF;

  -- F: an RPC put over a legacy row keeps legacy_rev; an old-client UPDATE
  --    nulls entries.
  r := public.nutrition_slot_put('2001-01-01', 'lunch', 8, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 9 THEN RAISE 'F1 %', r; END IF;
  SELECT legacy_rev INTO v_legacy FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_legacy <> 8 THEN RAISE 'F2 legacy_rev changed by the RPC: %', v_legacy; END IF;
  UPDATE public.nutrition_logs SET total_fat = 2
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF (SELECT entries FROM public.nutrition_logs
       WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch') IS NOT NULL
  THEN RAISE 'F3 old-client UPDATE kept entries'; END IF;

  -- G: an RPC delete then re-create keeps legacy_rev (through the tombstone).
  SELECT rev, legacy_rev INTO v_rev, v_legacy FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  r := public.nutrition_slot_delete('2001-01-01', 'lunch', v_rev);
  IF r->>'status' <> 'ok' OR (r->>'rev')::bigint <> v_rev + 1 THEN RAISE 'G1a %', r; END IF;
  r := public.nutrition_slot_put('2001-01-01', 'lunch', v_rev + 1, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::bigint <> v_rev + 2 THEN RAISE 'G1b %', r; END IF;
  IF (SELECT legacy_rev FROM public.nutrition_logs
       WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch') <> v_legacy
  THEN RAISE 'G1 legacy_rev lost across delete/re-create'; END IF;

  -- H: a top-level non-RPC delete of a live user's meal writes ONE tombstone
  --    with legacy_rev = rev + 1.
  SELECT rev INTO v_rev FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  DELETE FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  SELECT rev, legacy_rev INTO v_n, v_legacy FROM public.nutrition_slot_tombstones
   WHERE user_id = v_uid AND date = '2001-01-01' AND meal_type = 'lunch';
  IF v_n IS DISTINCT FROM v_rev + 1 OR v_legacy IS DISTINCT FROM v_rev + 1
  THEN RAISE 'H1 tomb % %', v_n, v_legacy; END IF;

  -- I: bounds raise (22023) and change nothing.
  v_ok := false;
  BEGIN
    r := public.nutrition_slot_put('2001-01-02', 'supper', 0, v_tot, v_ent, v_items);
  EXCEPTION WHEN invalid_parameter_value THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE 'I1 bad meal accepted'; END IF;
  v_ok := false;
  BEGIN
    r := public.nutrition_slot_put('2001-01-02', 'lunch', 0,
      jsonb_set(v_tot, '{total_calories}', '5'), v_ent, v_items);
  EXCEPTION WHEN invalid_parameter_value THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE 'I2 totals mismatch accepted'; END IF;
  v_ok := false;
  BEGIN
    r := public.nutrition_slot_put('2001-01-02', 'lunch', 0, v_tot,
      v_ent || v_ent, v_items || v_items);
  EXCEPTION WHEN invalid_parameter_value THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE 'I3 duplicate entry id accepted'; END IF;
  IF EXISTS (SELECT 1 FROM public.nutrition_logs
             WHERE user_id = v_uid AND date = '2001-01-02')
  THEN RAISE 'I4 a rejected put wrote a row'; END IF;

  -- M: an identical old-client re-push of an RPC-written slot (totals upsert +
  --    item upsert carrying the stored values) changes NOTHING: rev, legacy_rev,
  --    entries and updated_at stay (trg_suppress_redundant_updates fires first).
  r := public.nutrition_slot_put('2001-01-06', 'dinner', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 1 THEN RAISE 'M1 %', r; END IF;
  SELECT rev, legacy_rev, updated_at INTO v_rev, v_legacy, v_upd FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-06' AND meal_type = 'dinner';
  INSERT INTO public.nutrition_logs (user_id, date, meal_type, total_calories,
    total_protein, total_carbs, total_fat, total_fiber)
  SELECT user_id, date, meal_type, total_calories, total_protein, total_carbs,
         total_fat, total_fiber
    FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-06' AND meal_type = 'dinner'
  ON CONFLICT (user_id, date, meal_type) DO UPDATE SET
    total_calories = EXCLUDED.total_calories, total_protein = EXCLUDED.total_protein,
    total_carbs = EXCLUDED.total_carbs, total_fat = EXCLUDED.total_fat,
    total_fiber = EXCLUDED.total_fiber;
  INSERT INTO public.nutrition_log_items (log_id, item_index, food_name, quantity_g,
    calories, protein, carbs, fat, fiber)
  SELECT i.log_id, i.item_index, i.food_name, i.quantity_g, i.calories, i.protein,
         i.carbs, i.fat, i.fiber
    FROM public.nutrition_log_items i
    JOIN public.nutrition_logs l ON l.id = i.log_id
   WHERE l.user_id = v_uid AND l.date = '2001-01-06' AND l.meal_type = 'dinner'
  ON CONFLICT (log_id, item_index) DO UPDATE SET
    food_name = EXCLUDED.food_name, quantity_g = EXCLUDED.quantity_g,
    calories = EXCLUDED.calories, protein = EXCLUDED.protein,
    carbs = EXCLUDED.carbs, fat = EXCLUDED.fat, fiber = EXCLUDED.fiber;
  SELECT rev, legacy_rev, updated_at INTO v_rev2, v_legacy2, v_upd2 FROM public.nutrition_logs
   WHERE user_id = v_uid AND date = '2001-01-06' AND meal_type = 'dinner';
  IF v_rev2 <> v_rev OR v_legacy2 <> v_legacy OR v_upd2 <> v_upd
  THEN RAISE 'M2 identical re-push moved rev % -> %, legacy % -> %', v_rev, v_rev2, v_legacy, v_legacy2; END IF;
  IF (SELECT entries FROM public.nutrition_logs
       WHERE user_id = v_uid AND date = '2001-01-06' AND meal_type = 'dinner') IS NULL
  THEN RAISE 'M3 identical re-push nulled entries'; END IF;
  IF (SELECT entry_key FROM public.nutrition_log_items i
        JOIN public.nutrition_logs l ON l.id = i.log_id
       WHERE l.user_id = v_uid AND l.date = '2001-01-06' AND l.meal_type = 'dinner'
       LIMIT 1) IS DISTINCT FROM 'e1'
  THEN RAISE 'M4 identical item re-push dropped entry_key'; END IF;

  -- J: another user can neither read nor change my slots.
  r := public.nutrition_slot_put('2001-01-03', 'lunch', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 1 THEN RAISE 'J0a %', r; END IF;
  r := public.nutrition_slot_put('2001-01-03', 'dinner', 0, v_tot, v_ent, v_items);
  r := public.nutrition_slot_delete('2001-01-03', 'dinner', 1);
  IF r->>'status' <> 'ok' THEN RAISE 'J0b %', r; END IF;
  IF v_other IS NULL THEN
    RAISE NOTICE 'J skipped: no second user on the project';
  ELSE
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
    r := public.nutrition_slot_state('2001-01-03', 'lunch');
    IF r->'row' <> 'null'::jsonb OR r->'tombstone' <> 'null'::jsonb
    THEN RAISE 'J1 foreign slot visible %', r; END IF;
    -- B's delete of "the same slot" is B's own no-op (B holds nothing there).
    r := public.nutrition_slot_delete('2001-01-03', 'lunch', 0);
    IF r->>'status' <> 'ok' OR (r->>'noop')::boolean IS NOT TRUE THEN RAISE 'J2 %', r; END IF;
    -- B's put creates B's own row; mine is untouched.
    r := public.nutrition_slot_put('2001-01-03', 'lunch', 0, v_tot, v_ent, v_items);
    IF r->>'status' <> 'ok' OR (r->>'rev')::int <> 1 THEN RAISE 'J3 %', r; END IF;
    SELECT count(*) INTO v_n FROM public.nutrition_slot_tombstones WHERE user_id = v_uid;
    IF v_n <> 0 THEN RAISE 'J4 my tombstones visible to another user: %', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.nutrition_logs WHERE user_id = v_uid;
    IF v_n <> 0 THEN RAISE 'J5 my rows visible to another user: %', v_n; END IF;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    SELECT rev INTO v_rev FROM public.nutrition_logs
     WHERE user_id = v_uid AND date = '2001-01-03' AND meal_type = 'lunch';
    IF v_rev IS DISTINCT FROM 1 THEN RAISE 'J6 my slot changed by another user: rev %', v_rev; END IF;
    v_j_ran := true;
  END IF;

  -- N: the marker is put back after EVERY return path of both RPCs (ok,
  --    conflict, delete ok, delete no-op), to the value it had before the call
  --    (the 2026-11-23 apply refused a function-level SET; the body restores).
  PERFORM set_config('app.nutrition_rpc', 'before', true);
  r := public.nutrition_slot_put('2001-01-07', 'snacks', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR current_setting('app.nutrition_rpc', true) <> 'before'
  THEN RAISE 'N1 put ok left marker %', current_setting('app.nutrition_rpc', true); END IF;
  r := public.nutrition_slot_put('2001-01-07', 'snacks', 0, v_tot, v_ent, v_items);
  IF r->>'status' <> 'conflict' OR current_setting('app.nutrition_rpc', true) <> 'before'
  THEN RAISE 'N2 put conflict left marker %', current_setting('app.nutrition_rpc', true); END IF;
  r := public.nutrition_slot_delete('2001-01-07', 'snacks', 0);
  IF r->>'status' <> 'conflict' OR current_setting('app.nutrition_rpc', true) <> 'before'
  THEN RAISE 'N3 delete conflict left marker %', current_setting('app.nutrition_rpc', true); END IF;
  r := public.nutrition_slot_delete('2001-01-07', 'snacks', 1);
  IF r->>'status' <> 'ok' OR current_setting('app.nutrition_rpc', true) <> 'before'
  THEN RAISE 'N4 delete ok left marker %', current_setting('app.nutrition_rpc', true); END IF;
  r := public.nutrition_slot_delete('2001-01-07', 'snacks', 2);
  IF (r->>'noop')::boolean IS NOT TRUE OR current_setting('app.nutrition_rpc', true) <> 'before'
  THEN RAISE 'N5 delete no-op left marker %', current_setting('app.nutrition_rpc', true); END IF;
  PERFORM set_config('app.nutrition_rpc', '', true);
  r := public.nutrition_slot_put('2001-01-07', 'snacks', 2, v_tot, v_ent, v_items);
  IF r->>'status' <> 'ok' OR current_setting('app.nutrition_rpc', true) <> ''
  THEN RAISE 'N6 put ok from empty left marker %', current_setting('app.nutrition_rpc', true); END IF;

  -- K: privileges. The four RPCs: anon no, authenticated yes. The three
  --    trigger functions: authenticated no (they fire without EXECUTE).
  FOREACH v_fn IN ARRAY ARRAY[
    'public.nutrition_slot_put(date,text,bigint,jsonb,jsonb,jsonb)',
    'public.nutrition_slot_delete(date,text,bigint)',
    'public.nutrition_slot_state(date,text)',
    'public.nutrition_server_now()'] LOOP
    IF has_function_privilege('anon', v_fn, 'execute') THEN RAISE 'K1 anon can execute %', v_fn; END IF;
    IF NOT has_function_privilege('authenticated', v_fn, 'execute')
    THEN RAISE 'K2 authenticated cannot execute %', v_fn; END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY ARRAY[
    'public.nutrition_logs_rev_trg()',
    'public.nutrition_log_items_rev_trg()',
    'public.nutrition_logs_tombstone_trg()'] LOOP
    IF has_function_privilege('authenticated', v_fn, 'execute')
       OR has_function_privilege('anon', v_fn, 'execute')
    THEN RAISE 'K3 a client role can execute %', v_fn; END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.nutrition_slot_tombstones', 'select')
  THEN RAISE 'K4 anon can read tombstones'; END IF;

  IF v_j_ran THEN
    RAISE NOTICE 'nutrition_slot live verify: ALL OK';
  ELSE
    -- Not a full pass: the cross-user RLS check never ran (B-pass delta seat).
    RAISE NOTICE 'nutrition_slot live verify: ALL OK EXCEPT J (no second user: cross-user check NOT run)';
  END IF;
END
$verify$;

-- L (by hand, recorded in the diagnose doc): a throwaway user deleted through
-- the real auth.users cascade succeeds with no tombstone (pg_trigger_depth
-- guard). Needs the service role; not part of the rolled-back block above.

ROLLBACK;
