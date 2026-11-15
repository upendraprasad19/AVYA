-- Intent: OI-252 B-pass finding 1 (docs/reviews/template-stable-identity-bpass.md,
--   2026-09-27). Migration 145's `workout_templates_delete_final_rename` trigger is
--   `before update` ONLY. Its own header comment describes the race it exists to survive:
--   "whichever of {creating push, deleting drain} reaches Postgres first via an INSERT wins
--   the row's existence" -- but that sentence is only half-handled. If the DELETING drain is
--   the side whose write is the very first cloud write for a template's id (i.e. the template
--   was created and deleted in the same offline session, so no separate "creating push" for
--   that id ever ran -- confirmed live: `WorkoutWriteService.deleteTemplate` unconditionally
--   does a local Hive delete before queueing the cloud tombstone, so a never-synced template
--   leaves nothing else to push), `_drainPendingTemplateDeletes`'s tombstone UPSERT
--   (`onConflict: 'id'`) lands as a plain INSERT. A `before update` trigger never fires on an
--   INSERT, so the row is created with `deleted_at` set but the name is NEVER renamed --
--   `UNIQUE(user_id, name)` (deliberately kept live by 145, not dropped) still occupies that
--   name. A later, ordinary re-create under the identical name (delete "Leg Day", make a new
--   "Leg Day") then hits a live `23505 duplicate key value violates unique constraint`,
--   reopening the exact "42P10 forever" failure class 145's own header cites as the reason its
--   rev-5 (drop-the-constraint) approach was rejected -- through the one path that header text
--   didn't cover. Does NOT reopen the resurrection bug 145 fixes (restore still filters purely
--   on `deleted_at`, which this migration does not touch) -- this is a distinct, narrower
--   regression in the rename/name-freeing guarantee only.
--
--   Fix: extend the trigger to fire `before insert or update` and apply the identical
--   rename+deactivate transform whenever `new.deleted_at is not null`, regardless of `TG_OP`.
--   `OLD` does not exist on an INSERT-fired invocation, so the base name to suffix is
--   `new.name` itself on INSERT (there is no prior row to read a name from -- the drain's
--   UPSERT payload sends the un-suffixed original name) and `old.name` on UPDATE (unchanged
--   from 145, since by the time this branch runs on UPDATE, the `old.deleted_at is not null`
--   already-deleted short-circuit above it has already returned NULL for any further write to
--   an already-tombstoned row -- so `old.name` here is always the live pre-delete name).
--   `CREATE OR REPLACE FUNCTION` on an existing function preserves its ACL (a body-only edit is
--   safe per this file's own CLAUDE.md pitfalls table); the trigger itself must be dropped and
--   re-created since its firing EVENT is changing, not just its function body.
--
--   Deliberately client-side-fix-free: the reviewer's suggested defense-in-depth
--   (`_drainPendingTemplateDeletes` also suffixing the name itself before sending it) was
--   considered and rejected -- a trigger-side fix covers every writer unconditionally (this
--   client, an unmigrated legacy client, any future direct-INSERT caller) with one change,
--   while a client-side duplicate would need its suffix format kept in permanent lockstep with
--   the trigger's, adding a drift risk for no coverage this migration doesn't already provide.
-- Destructive?: no -- replaces one trigger's firing event + its function body; no column, no
--   constraint, no existing row touched. A row already renamed by 145's UPDATE-only trigger
--   keeps its existing (suffixed) name unchanged by this migration.
-- Rollback strategy: inline (drop trigger, recreate 145's original UPDATE-only function +
--   trigger verbatim, at end of file, commented out). Rolling back re-opens this exact
--   INSERT-path gap -- acceptable only as an emergency revert before a corrected forward-fix.
-- Linked diagnose-doc: 2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2
--   (same OI-252 unit as migration 145; this is pre-merge remediation of a B-pass finding on
--   the same unmerged branch, not a new bug against a shipped migration).

create or replace function public.workout_templates_delete_final_rename()
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
  -- OLD does not exist on an INSERT-fired invocation, so this whole check
  -- is TG_OP-guarded (an INSERT can never be "already deleted" -- the row
  -- does not exist yet).
  if tg_op = 'UPDATE' and old.deleted_at is not null then
    return null;
  end if;

  -- Transition to deleted: stamp is_active false and free the name so a
  -- re-create (new id) or an unmigrated old client's name-keyed upsert can
  -- both succeed as a plain insert without colliding on UNIQUE(user_id,name).
  -- Fires on BOTH INSERT and UPDATE (146) -- 145 covered UPDATE only, missing
  -- the case where the deleting drain performs the very first cloud write for
  -- a template created and deleted in the same offline session.
  if new.deleted_at is not null then
    new.is_active := false;
    if tg_op = 'UPDATE' then
      new.name := old.name || ' ‹del:' || left(new.id::text, 8) || '›';
    else
      new.name := new.name || ' ‹del:' || left(new.id::text, 8) || '›';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.workout_templates_delete_final_rename() is
  'OI-252 (146 extends 145): BEFORE INSERT OR UPDATE on workout_templates. Renames+deactivates '
  'on the delete transition on EITHER firing event (frees the name under '
  'UNIQUE(user_id,name)); makes every subsequent UPDATE to a deleted row a total no-op, so a '
  'delete can never be revived by a stale or racing upsert.';

drop trigger if exists workout_templates_delete_final_rename on public.workout_templates;

create trigger workout_templates_delete_final_rename
  before insert or update on public.workout_templates
  for each row
  execute function public.workout_templates_delete_final_rename();

-- Post-apply verification (transactional -- this DOES perform a write, so it
-- MUST be wrapped exactly as below; never run the INSERT/UPDATE lines outside
-- a transaction you intend to roll back):
--   BEGIN;
--     INSERT INTO workout_templates (id, user_id, name, workout_type, source, is_active, deleted_at)
--       VALUES (gen_random_uuid(), '<any real user_id>', 'OI252 F1 Repro', 'custom', 'user', false, now());
--     SELECT name, is_active FROM workout_templates WHERE name LIKE 'OI252 F1 Repro%';
--     -- expect: name now ends in ' <del:xxxxxxxx>' (suffixed), is_active=false -- pre-146 this
--     -- would show the UNSUFFIXED name with is_active=false (the exact gap this migration closes).
--     INSERT INTO workout_templates (id, user_id, name, workout_type, source, is_active)
--       VALUES (gen_random_uuid(), '<same user_id>', 'OI252 F1 Repro', 'custom', 'user', true);
--     -- expect: SUCCEEDS (no 23505) -- the name was freed by the rename above.
--   ROLLBACK;
--
--   select count(*) from pg_trigger
--     where tgrelid = 'public.workout_templates'::regclass
--       and tgname = 'workout_templates_delete_final_rename'
--       and tgtype & 4 <> 0; -- bit 2 = INSERT event
--   -- expect 1 (read-only, safe to run outside a transaction)

-- Rollback strategy detail (inline -- reverts to migration 145's original UPDATE-only trigger):
-- create or replace function public.workout_templates_delete_final_rename()
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
--     new.is_active := false;
--     new.name := old.name || ' ‹del:' || left(new.id::text, 8) || '›';
--   end if;
--   return new;
-- end;
-- $$;
-- drop trigger if exists workout_templates_delete_final_rename on public.workout_templates;
-- create trigger workout_templates_delete_final_rename
--   before update on public.workout_templates
--   for each row
--   execute function public.workout_templates_delete_final_rename();
