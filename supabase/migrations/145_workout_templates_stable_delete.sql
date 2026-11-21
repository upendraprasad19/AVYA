-- Intent: OI-252 (docs/superpowers/plans/2026-09-26-template-stable-identity.md, plan-review
--   record docs/plan-reviews/template-stable-identity.md, 3 converged rounds). A workout
--   template deleted on one device resurrects on other devices via restore, because the client
--   never issues a cloud delete and every identity in play today is the template NAME, which is
--   also the only thing a rename changes -- so a rename orphans the old-name row, which restore
--   then brings back as a second template.
--
--   This migration adds soft-delete support to `workout_templates` WITHOUT dropping
--   `UNIQUE(user_id,name)` -- an earlier revision of this plan (rev 5) dropped that constraint
--   and was rejected in round-1 review: doing so makes every pre-upgrade client's template
--   push fail with 42P10 forever (no unique index left for `onConflict: 'user_id,name'` to
--   target), and the client's own every-launch restore sweep would then delete that device's
--   unsynced templates locally, mistaking the perpetual push failure for "cloud has nothing".
--   Kept the constraint instead, and gave the delete-transition trigger a RENAME step: renaming
--   the deleted row frees its original name under the still-live unique constraint, so both a
--   genuine re-create (new client-minted id) and an unmigrated old client's name-keyed upsert
--   succeed as plain inserts, never touching the tombstoned row.
--
--   The second trigger branch makes a delete FINAL: any further write to an already-deleted row
--   (a late upsert from an in-flight push racing the delete, or a stale device that hasn't
--   learned about the delete) is a complete no-op -- the trigger returns NULL, which skips the
--   UPDATE in its entirety. This is what lets the client's delete-drain use an UPSERT (rather
--   than an UPDATE that could silently match zero rows if the creating push hasn't landed yet)
--   without any ordering assumption: whichever of {creating push, deleting drain} reaches
--   Postgres first via an INSERT wins the row's existence, and once `deleted_at` is set, no
--   later write -- from either side -- can undo it.
--
--   `template_exercises` (CASCADE), `scheduled_workouts.template_id` and
--   `workout_logs.template_id` (both NO ACTION) are all FK-safe against a soft delete: no row is
--   physically removed, so no FK ever dangles. Live verified 2026-09-26 (read-only,
--   `pg_constraint` + `pg_policies` + `pg_trigger`): 6 `workout_templates` rows across 2 users,
--   all `is_active=true`, no existing trigger on the table, RLS is already owner-only
--   (`055_workout_templates_rls...sql`), and `workout_templates.name` is unconstrained `text`
--   (no length cap to worry about for the rename suffix).
-- Destructive?: no -- adds one nullable column (`deleted_at`) and one BEFORE UPDATE trigger; no
--   existing row is touched, no column dropped, no constraint changed.
-- Rollback strategy: inline (drop trigger, drop function, drop column). Renamed rows (any real
--   delete that landed between apply and rollback) stay renamed -- the ` ‹del:xxxxxxxx›`
--   suffix on their `name` is cosmetic drift, not a correctness issue, and is NOT undone by the
--   rollback (undoing it would require re-deriving the original name, which the suffix does not
--   preserve). A rolled-back schema simply has no way to soft-delete a template going forward,
--   same as before this migration.
-- Linked diagnose-doc: 2026-09-26-workout-templates-no-stable-identity-<id> (added with the
--   client-side commit that lands alongside the live apply -- migration + client ship together
--   per the plan's apply order, so the diagnose-doc's `closes-diagnose:` trailer lands there).

alter table public.workout_templates
  add column if not exists deleted_at timestamptz;

comment on column public.workout_templates.deleted_at is
  'OI-252: set once, by workout_templates_delete_final_rename, when a template is deleted. '
  'NULL = live. Never write this column directly from client code -- it is trigger-owned; a '
  'client sets it only by writing a truthy value and letting the trigger take over. See '
  'docs/superpowers/plans/2026-09-26-template-stable-identity.md.';

create or replace function public.workout_templates_delete_final_rename()
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

  -- Transition to deleted: stamp is_active false and free the name so a
  -- re-create (new id) or an unmigrated old client's name-keyed upsert can
  -- both succeed as a plain insert without colliding on UNIQUE(user_id,name).
  if new.deleted_at is not null then
    new.is_active := false;
    new.name := old.name || ' ‹del:' || left(new.id::text, 8) || '›';
  end if;

  return new;
end;
$$;

comment on function public.workout_templates_delete_final_rename() is
  'OI-252: BEFORE UPDATE on workout_templates. Renames+deactivates on the delete transition '
  '(frees the name under UNIQUE(user_id,name)); makes every subsequent write to a deleted row '
  'a total no-op, so a delete can never be revived by a stale or racing upsert.';

drop trigger if exists workout_templates_delete_final_rename on public.workout_templates;

create trigger workout_templates_delete_final_rename
  before update on public.workout_templates
  for each row
  execute function public.workout_templates_delete_final_rename();

-- Post-apply verification (read-only; safe to run as-is, NOT a data mutation
-- -- unlike the migration-138 trap this repo's own CLAUDE.md documents, there
-- is no write here to wrap in BEGIN/ROLLBACK):
--   select count(*) from pg_trigger
--     where tgrelid = 'public.workout_templates'::regclass
--       and tgname = 'workout_templates_delete_final_rename';
--   -- expect 1
--   select column_name from information_schema.columns
--     where table_schema='public' and table_name='workout_templates'
--       and column_name='deleted_at';
--   -- expect 1 row
