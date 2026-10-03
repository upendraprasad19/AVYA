-- test/sql/workout_log_exercises_delete_final_rename_live_verify.sql
--
-- 2026-09-28 — Live-Postgres verification of migration 150's
-- `workout_log_exercises_delete_final_rename` trigger (OI-246). Extended
-- 2026-09-29 (migration 151, adversarial review round 1 finding P1) with
-- case 4, covering the BEFORE-INSERT firing path 150 alone did not have.
--
-- ⚠ REQUIRES migrations 150 AND 151 to be LIVE first
-- (`supabase/migrations/150_workout_log_exercises_tombstone_delete.sql`,
-- `supabase/migrations/151_workout_log_exercises_delete_trigger_insert_path.sql`).
-- Do NOT run against a database that hasn't had both applied — case 4 below
-- FAILS against 150 alone (that gap is exactly what 151 fixes; verified live
-- 2026-09-29 before 151 existed as a migration, inside a throwaway
-- rollback-wrapped transaction, before drafting the fix). This whole file
-- runs inside ONE transaction that ROLLBACKs at the end -- nothing here
-- persists, per CLAUDE.md's warning about a migration's own comments being
-- an unsafe non-transactional trap (this file IS the safe, wrapped form).
--
-- What this proves, and why source-grepping the migration text is not
-- enough (rule 21, "source-greps prove presence only"): the trigger's
-- correctness depends on Postgres's actual BEFORE-UPDATE-return-NULL
-- semantics and the live `uniq_wle_user_wlog_ex_set` unique index, neither
-- of which a text pin can verify. Mirrors
-- test/sql/workout_templates_delete_final_rename_live_verify.sql's shape
-- (same author, same review-tested pattern, migration 145) with the natural
-- key swapped: (user_id, workout_log_id, exercise_id, set_number) here vs
-- (user_id, name) there — and `exercise_id` (not `name`) is the column the
-- delete-transition suffixes, since this table has no name/is_active pair.
-- Unlike the templates file (which never got an automated case for the same
-- INSERT-path gap its own migration 146 fixed — see
-- docs/diagnoses/2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2.md,
-- which documents the equivalent proof only as a manual live repro, not a
-- committed test), case 4 here is committed as an automated assertion.

begin;

do $$
declare
  v_user_id uuid;
  v_wlog_id text := 'sql_verify_wlog_2026_09_28';
  v_id_a uuid := gen_random_uuid();
  v_id_b uuid := gen_random_uuid();
  v_exercise_id_after_update text;
  v_deleted_after_update timestamptz;
  v_row_count int;
begin
  select id into v_user_id from auth.users limit 1;
  if v_user_id is null then
    raise exception 'no auth.users row available to fixture against';
  end if;

  -- Case 1: delete transition suffixes exercise_id, frees the natural key.
  insert into public.workout_log_exercises
    (id, user_id, workout_log_id, exercise_id, exercise_name, set_number)
  values
    (v_id_a, v_user_id, v_wlog_id, 'SQL Verify Bench Press', 'SQL Verify Bench Press', 3);

  update public.workout_log_exercises set deleted_at = now() where id = v_id_a;

  select exercise_id, deleted_at into v_exercise_id_after_update, v_deleted_after_update
  from public.workout_log_exercises where id = v_id_a;

  if v_deleted_after_update is null then
    raise exception 'FAIL case 1: deleted_at was not stamped';
  end if;
  if v_exercise_id_after_update = 'SQL Verify Bench Press' then
    raise exception 'FAIL case 1: exercise_id was not suffixed away -- delete-transition rename did not fire';
  end if;
  if v_exercise_id_after_update !~ ('del:' || left(v_id_a::text, 8)) then
    raise exception 'FAIL case 1: suffixed exercise_id does not carry the expected marker, got %', v_exercise_id_after_update;
  end if;

  -- Case 2: a further write to the now-deleted row is a TOTAL no-op --
  -- simulates a delayed creating push landing after the delete, or the
  -- creating push racing the drain's tombstone upsert (either order).
  update public.workout_log_exercises
    set deleted_at = null, exercise_id = 'SQL Verify Bench Press RESURRECTED', reps = 999
    where id = v_id_a;

  select exercise_id, deleted_at into v_exercise_id_after_update, v_deleted_after_update
  from public.workout_log_exercises where id = v_id_a;

  if v_exercise_id_after_update = 'SQL Verify Bench Press RESURRECTED' then
    raise exception 'FAIL case 2: a write to a deleted row was NOT blocked -- delete is not final';
  end if;
  if v_deleted_after_update is null then
    raise exception 'FAIL case 2: deleted_at was cleared by a write to a deleted row';
  end if;

  -- Case 3: the ORIGINAL natural key is free again -- a genuine
  -- `INSERT ... ON CONFLICT (user_id, workout_log_id, exercise_id,
  -- set_number) DO UPDATE` (the exact shape `_syncExerciseLogs`'s push
  -- sends) against the now-freed key must succeed as a fresh INSERT, not
  -- error, and must NOT touch the deleted row. This is the case that
  -- matters most: a user deletes a log, then re-logs the SAME exercise on
  -- the SAME date with the SAME set count — the re-log must not be silently
  -- swallowed by the no-op branch above.
  insert into public.workout_log_exercises
    (id, user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
  values
    (v_id_b, v_user_id, v_wlog_id, 'SQL Verify Bench Press', 'SQL Verify Bench Press', 3, 24)
  on conflict (user_id, workout_log_id, exercise_id, set_number)
    do update set reps = excluded.reps;

  select count(*) into v_row_count from public.workout_log_exercises
    where user_id = v_user_id and workout_log_id = v_wlog_id
      and exercise_id = 'SQL Verify Bench Press' and set_number = 3 and id = v_id_b;
  if v_row_count <> 1 then
    raise exception 'FAIL case 3: re-log against the freed natural key did not create a fresh row -- it would be silently dropped in production';
  end if;

  select deleted_at into v_deleted_after_update from public.workout_log_exercises where id = v_id_a;
  if v_deleted_after_update is null then
    raise exception 'FAIL case 3: the freed-key insert touched the tombstoned row instead of inserting fresh';
  end if;

  -- Case 4 (migration 151, adversarial review round 1 finding P1): the
  -- drain's tombstone UPSERT can itself be the FIRST cloud write for a
  -- natural key -- the exercise log was created and deleted before its own
  -- creating push ever reached the cloud, a realistic sequence since
  -- `_drainPendingExlogDeletes` runs before the per-key push loop on every
  -- sync pass. That lands as a plain INSERT, which a BEFORE UPDATE-only
  -- trigger (150 alone) never fires on -- the natural key stays occupied
  -- UNSUFFIXED, and a later genuine re-log silently no-ops instead of
  -- landing (case 2's guard fires against it, not case 3's success path).
  declare
    v_id_c uuid := gen_random_uuid();
    v_id_d uuid := gen_random_uuid();
    v_exercise_id_after_insert text;
    v_reps_after_relog int;
    v_row_count_c int;
  begin
    insert into public.workout_log_exercises
      (id, user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values
      (v_id_c, v_user_id, v_wlog_id, 'SQL Verify Squat', 'SQL Verify Squat', 1, now());

    select exercise_id into v_exercise_id_after_insert
    from public.workout_log_exercises where id = v_id_c;

    if v_exercise_id_after_insert = 'SQL Verify Squat' then
      raise exception 'FAIL case 4: a tombstone-shaped INSERT (deleted_at set) was NOT suffixed -- the natural key stays occupied unsuffixed, exactly OI-246 P1''s unfixed gap. Is migration 151 live?';
    end if;
    if v_exercise_id_after_insert !~ ('del:' || left(v_id_c::text, 8)) then
      raise exception 'FAIL case 4: suffixed exercise_id does not carry the expected marker, got %', v_exercise_id_after_insert;
    end if;

    insert into public.workout_log_exercises
      (id, user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values
      (v_id_d, v_user_id, v_wlog_id, 'SQL Verify Squat', 'SQL Verify Squat', 1, 225)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;

    select count(*) into v_row_count_c from public.workout_log_exercises
      where user_id = v_user_id and workout_log_id = v_wlog_id
        and exercise_id = 'SQL Verify Squat' and set_number = 1 and id = v_id_d;
    if v_row_count_c <> 1 then
      raise exception 'FAIL case 4: re-log after a tombstone-shaped INSERT did not create a fresh row -- it was silently swallowed by the no-op branch (the exact P1 bug).';
    end if;

    select reps into v_reps_after_relog from public.workout_log_exercises where id = v_id_d;
    if v_reps_after_relog is distinct from 225 then
      raise exception 'FAIL case 4: re-logged row does not carry the re-log''s own data, got reps=%', v_reps_after_relog;
    end if;
  end;

  raise notice 'workout_log_exercises_delete_final_rename: all 4 cases passed';
end $$;

-- Negative control -- confirms the assertions above actually discriminate
-- (rule 24 / rule 21's "mutate it and run it", applied here by disabling
-- the trigger instead of editing the migration file, since migrations are
-- immutable). Run this block, expect it to RAISE (proving case 2 would
-- fail without the trigger), then roll back regardless:
--
--   alter table public.workout_log_exercises disable trigger workout_log_exercises_delete_final_rename;
--   -- re-run case 1+2 above by hand; case 2's resurrection succeeds, i.e.
--   -- the DO $$ block above would raise 'FAIL case 2: ...' -- confirming
--   -- the assertion is not vacuous.
--   alter table public.workout_log_exercises enable trigger workout_log_exercises_delete_final_rename;
--
-- Case 4's own negative control is unconditional, not opt-in: run this file
-- against a database with 150 applied but NOT 151, and case 4 raises FAIL on
-- its own (no trigger-disable needed) -- confirmed live 2026-09-29 before
-- 151 was authorized, in a throwaway rollback-wrapped transaction, and this
-- exact case-4 SQL (initially inline, not yet in this file) reproduced
-- `exercise_id='SQL Verify Squat'` unsuffixed + `reps=null` after the re-log,
-- i.e. the re-log's data was silently dropped -- proving case 4 is not
-- vacuous BEFORE the fix it verifies was even drafted.

rollback;
