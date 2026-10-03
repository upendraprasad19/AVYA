-- Intent: OI-246 follow-up (adversarial review round 1, finding P1, on this
--   same unmerged branch). Migration 150's
--   `workout_log_exercises_delete_final_rename` trigger is `before update`
--   ONLY -- the exact same gap OI-252's B-pass Finding 1 already found and
--   fixed one day earlier for the sibling `workout_templates` table via
--   migration 146 (this precedent was missed during OI-246's own
--   bug-history lookup; see the diagnose-doc's `recurrence:` field). If
--   `_drainPendingExlogDeletes`'s tombstone UPSERT (onConflict:
--   user_id,workout_log_id,exercise_id,set_number) is the FIRST cloud write
--   for that natural key -- i.e. the exercise log was logged and deleted
--   before its creating push ever reached the cloud, a realistic sequence
--   since `_drainPendingExlogDeletes` runs before the per-key push loop on
--   every sync pass, not a corner case -- PostgREST's upsert lands as a
--   plain INSERT. A `before update` trigger never fires on an INSERT, so the
--   row is created with `deleted_at` set but `exercise_id` is NEVER
--   suffixed -- `uniq_wle_user_wlog_ex_set` still occupies that exact
--   natural key. A later, ordinary re-log of the SAME exercise on the SAME
--   date at the SAME computed set count then becomes an UPDATE against the
--   tombstoned row (the upsert hits the still-occupied key), and the
--   "already deleted -> no-op" branch silently swallows the re-log's data --
--   it never reaches workout_log_exercises, and the exercise never restores
--   again even though it is correct and current in the user's local Hive.
--
--   Fix: extend the trigger to fire `before insert or update`, applying the
--   identical exercise_id-suffix transform whenever `new.deleted_at is not
--   null`, regardless of TG_OP. `OLD` does not exist on an INSERT-fired
--   invocation, so `new.exercise_id` (the drain's un-suffixed original
--   value) is the base to suffix on INSERT; on UPDATE this reads
--   `new.exercise_id` instead of 150's `old.exercise_id` -- safe because by
--   the time this branch runs, `old.exercise_id` and `new.exercise_id` are
--   byte-identical on every real caller (the drain's upsert payload never
--   changes exercise_id, only sets deleted_at). `CREATE OR REPLACE FUNCTION`
--   preserves the function's ACL (body-only edit, per this file's own
--   CLAUDE.md pitfalls table); the trigger itself must be dropped and
--   re-created since its firing EVENT is changing, not just its body.
-- Destructive?: no -- replaces one trigger's firing event + its function
--   body; no column, no constraint, no existing row touched. A row already
--   suffixed by 150's UPDATE-only trigger keeps its existing (suffixed)
--   exercise_id unchanged by this migration.
-- Rollback strategy: inline (drop trigger, recreate 150's original
--   UPDATE-only function + trigger verbatim, at end of file, commented out).
--   Rolling back re-opens this exact INSERT-path gap -- acceptable only as
--   an emergency revert before a corrected forward-fix.
-- Linked diagnose-doc: docs/diagnoses/2026-09-28-exlog-tombstone-resurrection-e1c8b4.md
--   (same OI-246 unit as migration 150; this is pre-merge remediation of an
--   adversarial-review finding on the same unmerged branch, not a new bug
--   against a shipped migration).

create or replace function public.workout_log_exercises_delete_final_rename()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Any UPDATE to an already-deleted row is a full no-op, regardless of what
  -- the incoming NEW row claims -- this is what makes the tombstone final
  -- irrespective of arrival order between a creating push and a deleting
  -- drain. Returning NULL from a BEFORE trigger skips the UPDATE entirely.
  -- OLD does not exist on an INSERT-fired invocation, so this check is
  -- TG_OP-guarded (an INSERT can never be "already deleted" -- the row does
  -- not exist yet).
  if tg_op = 'UPDATE' and old.deleted_at is not null then
    return null;
  end if;

  -- Transition to deleted: free the natural key
  -- (user_id, workout_log_id, exercise_id, set_number) so a re-create (a
  -- fresh log of the same exercise on the same date landing at the same set
  -- count) or an unmigrated old client's natural-key upsert can both succeed
  -- as a plain INSERT without colliding on uniq_wle_user_wlog_ex_set. Fires
  -- on BOTH INSERT and UPDATE (151) -- 150 covered UPDATE only, missing the
  -- case where the deleting drain performs the very first cloud write for a
  -- log created and deleted in the same offline session.
  if new.deleted_at is not null then
    new.exercise_id := new.exercise_id || ' ‹del:' || left(new.id::text, 8) || '›';
  end if;

  return new;
end;
$$;

comment on function public.workout_log_exercises_delete_final_rename() is
  'OI-246 (151 extends 150): BEFORE INSERT OR UPDATE on workout_log_exercises. '
  'Suffixes exercise_id on the delete transition on EITHER firing event (frees '
  'the natural key under uniq_wle_user_wlog_ex_set); makes every subsequent '
  'UPDATE to a deleted row a total no-op, so a delete can never be revived by '
  'a stale or racing upsert.';

drop trigger if exists workout_log_exercises_delete_final_rename on public.workout_log_exercises;

create trigger workout_log_exercises_delete_final_rename
  before insert or update on public.workout_log_exercises
  for each row
  execute function public.workout_log_exercises_delete_final_rename();

-- Post-apply verification (transactional -- this DOES perform a write, so it
-- MUST be wrapped exactly as below; never run the INSERT lines outside a
-- transaction you intend to roll back):
--   BEGIN;
--     INSERT INTO workout_log_exercises (id, user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
--       VALUES (gen_random_uuid(), '<any real user_id>', 'oi246-f1-repro', 'OI246 F1 Repro', 'OI246 F1 Repro', 1, now());
--     SELECT exercise_id FROM workout_log_exercises WHERE exercise_name = 'OI246 F1 Repro';
--     -- expect: exercise_id now ends in ' <del:xxxxxxxx>' (suffixed) -- pre-151
--     -- this would show the UNSUFFIXED 'OI246 F1 Repro' (the exact gap this migration closes).
--     INSERT INTO workout_log_exercises (id, user_id, workout_log_id, exercise_id, exercise_name, set_number)
--       VALUES (gen_random_uuid(), '<same user_id>', 'oi246-f1-repro', 'OI246 F1 Repro', 'OI246 F1 Repro', 1)
--       ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET reps = excluded.reps;
--     -- expect: SUCCEEDS (no 23505) -- the natural key was freed by the rename above.
--   ROLLBACK;
--
--   select tgtype from pg_trigger
--     where tgrelid = 'public.workout_log_exercises'::regclass
--       and tgname = 'workout_log_exercises_delete_final_rename';
--   -- expect 23 (ROW+BEFORE+INSERT+UPDATE bits) -- read-only, safe to run outside a transaction

-- Rollback strategy detail (inline -- reverts to migration 150's original
-- UPDATE-only trigger):
-- create or replace function public.workout_log_exercises_delete_final_rename()
-- returns trigger
-- language plpgsql
-- security invoker
-- set search_path = ''
-- as $$
-- begin
--   if old.deleted_at is not null then
--     return null;
--   end if;
--   if new.deleted_at is not null then
--     new.exercise_id := old.exercise_id || ' ‹del:' || left(new.id::text, 8) || '›';
--   end if;
--   return new;
-- end;
-- $$;
-- drop trigger if exists workout_log_exercises_delete_final_rename on public.workout_log_exercises;
-- create trigger workout_log_exercises_delete_final_rename
--   before update on public.workout_log_exercises
--   for each row
--   execute function public.workout_log_exercises_delete_final_rename();
