-- test/sql/workout_templates_delete_final_rename_live_verify.sql
--
-- 2026-09-26 — Live-Postgres verification of migration 145's
-- `workout_templates_delete_final_rename` trigger (OI-252, stable ID rework).
--
-- ⚠ REQUIRES migration 145 to be LIVE first (`supabase/migrations/145_workout_templates_stable_delete.sql`).
-- Do NOT run against a database that hasn't had it applied. This whole file
-- runs inside ONE transaction that ROLLBACKs at the end -- nothing here
-- persists, per CLAUDE.md's warning about a migration's own comments being
-- an unsafe non-transactional trap (this file IS the safe, wrapped form).
--
-- What this proves, and why source-grepping the migration text is not
-- enough (rule 21, "source-greps prove presence only"): the trigger's
-- correctness depends on Postgres's actual BEFORE-UPDATE-return-NULL
-- semantics and the live UNIQUE(user_id,name) index, neither of which a
-- text pin can verify.

begin;

-- Fixture: one real user (any existing auth.users row works; RLS is
-- bypassed here because this runs as a privileged migration-testing role,
-- matching the pattern in test/sql/onconflict_live_arbiter.sql).
do $$
declare
  v_user_id uuid;
  v_id_a uuid := gen_random_uuid();
  v_id_b uuid := gen_random_uuid();
  v_name_after_update text;
  v_deleted_after_update timestamptz;
  v_active_after_update boolean;
  v_row_count int;
begin
  select id into v_user_id from auth.users limit 1;
  if v_user_id is null then
    raise exception 'no auth.users row available to fixture against';
  end if;

  -- Case 1: delete transition renames + deactivates, frees the name.
  insert into public.workout_templates (id, user_id, name, workout_type, source, is_active)
  values (v_id_a, v_user_id, 'SQL Verify Push Day A', 'custom', 'user', true);

  update public.workout_templates set deleted_at = now() where id = v_id_a;

  select name, deleted_at, is_active into v_name_after_update, v_deleted_after_update, v_active_after_update
  from public.workout_templates where id = v_id_a;

  if v_deleted_after_update is null then
    raise exception 'FAIL case 1: deleted_at was not stamped';
  end if;
  if v_active_after_update is not false then
    raise exception 'FAIL case 1: is_active was not set false';
  end if;
  if v_name_after_update = 'SQL Verify Push Day A' then
    raise exception 'FAIL case 1: name was not renamed away -- delete-transition rename did not fire';
  end if;
  if v_name_after_update !~ ('del:' || left(v_id_a::text, 8)) then
    raise exception 'FAIL case 1: renamed name does not carry the expected suffix, got %', v_name_after_update;
  end if;

  -- Case 2: a further write to the now-deleted row is a TOTAL no-op --
  -- simulates a stale device's push landing after the delete, or the
  -- creating push racing the drain's tombstone upsert (either order).
  update public.workout_templates
    set is_active = true, deleted_at = null, name = 'SQL Verify Push Day A RESURRECTED'
    where id = v_id_a;

  select name, deleted_at, is_active into v_name_after_update, v_deleted_after_update, v_active_after_update
  from public.workout_templates where id = v_id_a;

  if v_name_after_update = 'SQL Verify Push Day A RESURRECTED' then
    raise exception 'FAIL case 2: a write to a deleted row was NOT blocked -- delete is not final';
  end if;
  if v_deleted_after_update is null then
    raise exception 'FAIL case 2: deleted_at was cleared by a write to a deleted row';
  end if;
  if v_active_after_update is not false then
    raise exception 'FAIL case 2: is_active was flipped back to true by a write to a deleted row';
  end if;

  -- Case 3: the ORIGINAL name is free again -- a genuine `INSERT ... ON
  -- CONFLICT (user_id, name) DO UPDATE` (the exact shape an unmigrated old
  -- client's push still sends) against the now-freed name must succeed as
  -- a fresh INSERT, not error, and must NOT touch the deleted row.
  insert into public.workout_templates (id, user_id, name, workout_type, source, is_active)
  values (v_id_b, v_user_id, 'SQL Verify Push Day A', 'custom', 'user', true)
  on conflict (user_id, name) do update set workout_type = excluded.workout_type;

  select count(*) into v_row_count from public.workout_templates
    where user_id = v_user_id and name = 'SQL Verify Push Day A' and id = v_id_b;
  if v_row_count <> 1 then
    raise exception 'FAIL case 3: old-client-shaped upsert against the freed name did not create a fresh row';
  end if;

  select deleted_at into v_deleted_after_update from public.workout_templates where id = v_id_a;
  if v_deleted_after_update is null then
    raise exception 'FAIL case 3: the freed-name insert touched the tombstoned row instead of inserting fresh';
  end if;

  raise notice 'workout_templates_delete_final_rename: all 3 cases passed';
end $$;

-- Negative control -- confirms the assertions above actually discriminate
-- (rule 24 / rule 21's "mutate it and run it", applied here by disabling
-- the trigger instead of editing the migration file, since migrations are
-- immutable). Run this block, expect it to RAISE (proving case 2 would
-- fail without the trigger), then roll back regardless:
--
--   alter table public.workout_templates disable trigger workout_templates_delete_final_rename;
--   -- re-run case 1+2 above by hand; case 2's resurrection succeeds, i.e.
--   -- the DO $$ block above would raise 'FAIL case 2: ...' -- confirming
--   -- the assertion is not vacuous.
--   alter table public.workout_templates enable trigger workout_templates_delete_final_rename;

rollback;
