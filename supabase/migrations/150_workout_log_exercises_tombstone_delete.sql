-- Intent: OI-246. `WorkoutWriteService.deleteLog` removes only the local Hive
--   `exlog_` key — it never issues a cloud delete for the matching
--   `workout_log_exercises` row. `SyncService._restoreExerciseLogs` re-inserts
--   any cloud row whose Hive key is absent locally (the additive/local-wins
--   restore pattern `restore_local_wins_additive_test.dart` pins for exactly
--   this class), so a user-deleted exercise log silently comes back on the
--   next full restore (fresh install / new device / cleared Hive).
--
--   This migration adds soft-delete support to `workout_log_exercises`,
--   mirroring migration 145's `workout_templates` pattern exactly (same
--   author, same review-tested shape, applied 2026-09-27, 1 day before this
--   one): a nullable `deleted_at` + a BEFORE UPDATE trigger that (a) makes any
--   further write to an already-deleted row a total no-op (so an UPSERT
--   tombstone drain and a delayed creating push can arrive in EITHER order
--   and the delete always wins), and (b) on the delete transition, mutates
--   the row's `exercise_id` (this table's stable-identity column — it is the
--   exercise NAME, per `sync_workout.dart:224`'s "// stable identity"
--   comment) so a later re-log of the SAME exercise, same date, same set
--   count is a plain INSERT under `uniq_wle_user_wlog_ex_set
--   (user_id, workout_log_id, exercise_id, set_number)` (migration 082)
--   rather than an UPDATE that the no-op branch would silently swallow.
--   `workout_log_id` is NOT mutated — unlike templates' `name`, it carries no
--   uniqueness burden here (it is shared by every exercise logged that day)
--   and mutating it would break the `idx_wle_workout_log_id` join other
--   readers use.
--
--   `workout_log_sets` (the per-set table) is deliberately NOT tombstoned by
--   this migration — `_restoreExerciseLogs` only reaches for its per-set join
--   AFTER finding a live (non-deleted) `workout_log_exercises` row via the
--   client-side `deleted_at != null` skip added in the same commit, so an
--   orphaned `workout_log_sets` row for a deleted exercise is never joined
--   back into anything user-visible. It becomes a permanently orphaned row
--   with no resurrection path — acceptable dead data, not a correctness bug.
--   (A cleanup pass for it is separate scope, same shape as OI-218's own
--   residual note for the sibling `moveExerciseLogs` path.)
--
--   Live verified 2026-09-28 (read-only, `pg_constraint` + `pg_trigger` +
--   `information_schema.columns`): no existing trigger on
--   `workout_log_exercises`; `exercise_id` is `text NOT NULL` with no length
--   cap (migration 009); the only unique index touching this table is
--   `uniq_wle_user_wlog_ex_set` (migration 082) — no other constraint
--   references `exercise_id`, so appending a delete-marker suffix cannot
--   violate anything else. `workout_log_id` / `workout_log_sets` (a sibling
--   table, not FK'd to this one — both reference the synthetic
--   `workout_log_id` TEXT value, not a real FK) are unaffected: no row here
--   is physically removed, so nothing can dangle.
-- Destructive?: no -- adds one nullable column (`deleted_at`) and one BEFORE
--   UPDATE trigger; no existing row is touched, no column dropped, no
--   constraint changed.
-- Rollback strategy: inline (drop trigger, drop function, drop column).
--   Any real delete that landed between apply and rollback stays renamed —
--   the ` ‹del:xxxxxxxx›` suffix on `exercise_id` is cosmetic drift (the row
--   would show under a mangled exercise name in raw SQL, never through the
--   client, which always writes/reads via the natural, unsuffixed name), not
--   undone by rollback (same reasoning as migration 145's rollback note — the
--   suffix does not preserve the original value to re-derive it from). A
--   rolled-back schema simply has no way to soft-delete an exercise log going
--   forward, same as before this migration.
-- Linked diagnose-doc: docs/diagnoses/2026-09-28-exlog-tombstone-resurrection-e1c8b4.md
--   (added with the client-side commit landing alongside the live apply).

alter table public.workout_log_exercises
  add column if not exists deleted_at timestamptz;

comment on column public.workout_log_exercises.deleted_at is
  'OI-246: set once, by workout_log_exercises_delete_final_rename, when a '
  'log is deleted (WorkoutWriteService.deleteLog). NULL = live. Never write '
  'this column directly from client code -- it is trigger-owned; a client '
  'sets it only by writing a truthy value (via PendingExlogDeletes'' drain) '
  'and letting the trigger take over.';

create or replace function public.workout_log_exercises_delete_final_rename()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Any write to an already-deleted row is a full no-op, regardless of what
  -- the incoming NEW row claims -- this is what makes the tombstone final
  -- irrespective of arrival order between a creating push and a deleting
  -- drain. Returning NULL from a BEFORE trigger skips the UPDATE entirely.
  if old.deleted_at is not null then
    return null;
  end if;

  -- Transition to deleted: free the natural key
  -- (user_id, workout_log_id, exercise_id, set_number) so a re-create (a
  -- fresh log of the same exercise on the same date landing at the same set
  -- count) or an unmigrated old client's natural-key upsert can both succeed
  -- as a plain INSERT without colliding on uniq_wle_user_wlog_ex_set.
  if new.deleted_at is not null then
    new.exercise_id := old.exercise_id || ' ‹del:' || left(new.id::text, 8) || '›';
  end if;

  return new;
end;
$$;

comment on function public.workout_log_exercises_delete_final_rename() is
  'OI-246: BEFORE UPDATE on workout_log_exercises. Suffixes exercise_id on '
  'the delete transition (frees the natural key under '
  'uniq_wle_user_wlog_ex_set); makes every subsequent write to a deleted row '
  'a total no-op, so a delete can never be revived by a stale or racing '
  'upsert.';

drop trigger if exists workout_log_exercises_delete_final_rename on public.workout_log_exercises;

create trigger workout_log_exercises_delete_final_rename
  before update on public.workout_log_exercises
  for each row
  execute function public.workout_log_exercises_delete_final_rename();

-- Post-apply verification (read-only; safe to run as-is -- there is no write
-- here to wrap in BEGIN/ROLLBACK, unlike the migration-138 trap this repo's
-- own CLAUDE.md documents):
--   select count(*) from pg_trigger
--     where tgrelid = 'public.workout_log_exercises'::regclass
--       and tgname = 'workout_log_exercises_delete_final_rename';
--   -- expect 1
--   select column_name from information_schema.columns
--     where table_schema='public' and table_name='workout_log_exercises'
--       and column_name='deleted_at';
--   -- expect 1 row
