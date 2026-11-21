-- Intent: L1a-1 (docs/plans/coach-history-correctness-sync.md v10). Two
--   server-side defects on workout_log_exercises (exercise-log summary rows):
--   D0 / OI-312 -- migration 151's BEFORE INSERT branch suffixes exercise_id
--     on a tombstone-shaped INSERT before the ON CONFLICT arbiter runs, so the
--     delete drain's upsert never meets the live row it was meant to delete:
--     the live row stays live and a separate suffixed tombstone is inserted
--     (rolled-back live probe 2026-10-06: live=1 tombstones=1). Deletes have
--     never reached the cloud.
--   D1 / OI-307 (writer half) -- set_number (the summary's set COUNT) is part
--     of the natural key (uniq_wle_user_wlog_ex_set, migration 082), so a
--     push after the count changed inserts a second live summary row for the
--     same (user, workout_log_id, exercise_id) instead of replacing the old
--     one (live 2026-10-06: 44 groups / 99 rows / 1 account).
--   NOT re-runnable: after a first apply the kept rows are older than the
--   tombstones the cleanup wrote, so a second run's step 2a would tombstone
--   them. The body therefore refuses to run when the single_live trigger
--   already exists (ALREADY_APPLIED) -- a retried apply after an uncertain
--   result is safe.
--   Count 0 (unknown set count, legacy shape): a count-0 push supersedes a
--   live sibling like any other push but deletes no per-set rows; readers
--   take every per-set row under a count-0 summary (L1a-2 U2(b)).
--   One statement (a single DO block) so it is atomic whether or not the
--   apply path wraps the file in a transaction, and byte-identical to the
--   text the prod rolled-back dry-run executed (sha256 checked there).
--   Steps, in order, all inside the DO block:
--     0. lock_timeout 5s; LOCK both tables ACCESS EXCLUSIVE (no push or drain
--        can commit between the repair/cleanup and the new triggers).
--     1. Precondition (a): every tombstoned summary row is 151-suffixed.
--     2a. OI-312 repair: for each suffixed tombstone T, tombstone every live
--        row L at (user_id, workout_log_id, strip(T.exercise_id)) -- any
--        set_number -- written BEFORE T (age(L.xmin) > age(T.xmin)). Live rows
--        written after T (a re-log) stay.
--     1b. Precondition (b), after 2a: within every remaining duplicate group
--        the sibling xmins are distinct (so "youngest" is well defined).
--     2. Cleanup: per duplicate group keep the youngest-xmin row (the last
--        push -- founder rule "last sync or write wins"), delete the
--        workout_log_sets rows above the kept row's set_number (unless 0),
--        tombstone the other siblings (151's UPDATE branch renames them).
--     2e. End-state assertion: no live duplicate group remains and every live
--        row captured as an OI-312 pair before 2a is now tombstoned.
--     3. D0 fix: replace workout_log_exercises_delete_final_rename. UPDATE
--        branch unchanged. INSERT with deleted_at set: take the per-key lock;
--        if a live row exists at the SAME (user_id, workout_log_id,
--        exercise_id, set_number), UPDATE it SET deleted_at (the UPDATE branch
--        renames it) and RETURN NULL; otherwise suffix and insert as 151.
--     4. D1 fix: new BEFORE INSERT trigger workout_log_exercises_single_live
--        WHEN (new.deleted_at is null): take the per-key lock; tombstone live
--        siblings with a different set_number; unless new.set_number = 0,
--        delete the workout_log_sets rows above new.set_number for the key.
--     5. Per-key lock (both trigger bodies): pg_advisory_xact_lock on
--        hashtextextended(user_id|workout_log_id|exercise_id).
--   Trigger order on INSERT is by name: ..._delete_final_rename fires before
--   ..._single_live; in the drain path step 3 returns NULL, so single_live and
--   the arbiter never run for that row. Both functions are SECURITY INVOKER
--   with an empty search_path, like 151.
--   The angle quotes of 151's suffix (U+2039 / U+203A) are built with chr()
--   and never typed (CLAUDE.md section 4.9, invisible/separator characters row).
-- Destructive?: yes -- tombstones the superseded summary rows (step 2a + 2)
--   and deletes workout_log_sets rows above a kept row's count (step 2;
--   0 rows on 2026-10-06). At runtime the new trigger tombstones superseded
--   siblings and deletes per-set rows above the new count. Every affected
--   row is snapshotted before the apply to
--   backups/wle_single_live_cleanup_snapshot.json (all columns + xmin).
-- Rollback strategy: inline -- the commented-out reverse block at the end of
--   this file (DDL: drop the new trigger + function, restore 151's function
--   body and comment verbatim; data: restore the snapshot's summary rows
--   unless a newer live row now holds the same key, re-insert its per-set
--   rows on conflict do nothing). A migration cannot un-tombstone by itself.
-- Linked diagnose-doc: bd79b1 (D0, OI-312; recurrence of e1c8b4), 4b5c38
--   (D1, OI-307 writer half; related 3f8a91)

do $mig$
declare
  v_suffix_re constant text :=
    ' ' || chr(8249) || 'del:[0-9a-f]{8}' || chr(8250) || '$';
  v_pairs uuid[];
  v_bad int;
begin
  perform set_config('lock_timeout', '5s', true);
  lock table public.workout_log_exercises, public.workout_log_sets
    in access exclusive mode;

  -- 0b. Not re-runnable (see the header): refuse a second apply.
  if exists (select 1 from pg_catalog.pg_trigger
              where tgrelid = 'public.workout_log_exercises'::regclass
                and tgname = 'workout_log_exercises_single_live'
                and not tgisinternal) then
    raise exception 'ALREADY_APPLIED: workout_log_exercises_single_live exists; this migration must not run twice';
  end if;

  -- 1. Precondition (a): every tombstone carries 151's suffix.
  select count(*) into v_bad
    from public.workout_log_exercises
   where deleted_at is not null
     and exercise_id !~ v_suffix_re;
  if v_bad > 0 then
    raise exception 'PRECONDITION_A: % tombstoned summary row(s) are not 151-suffixed', v_bad;
  end if;

  -- Capture the OI-312 pairs before the repair (used by 2a and by 2e).
  select coalesce(array_agg(distinct l.id), '{}'::uuid[]) into v_pairs
    from public.workout_log_exercises t
    join public.workout_log_exercises l
      on l.user_id = t.user_id
     and l.workout_log_id = t.workout_log_id
     and l.exercise_id = regexp_replace(t.exercise_id, v_suffix_re, '')
     and l.deleted_at is null
   where t.deleted_at is not null
     and age(l.xmin) > age(t.xmin);

  -- 2a. OI-312 repair.
  update public.workout_log_exercises
     set deleted_at = now()
   where id = any (v_pairs)
     and deleted_at is null;

  -- 1b. Precondition (b): distinct sibling xmins in every duplicate group.
  select count(*) into v_bad
    from (
      select 1
        from public.workout_log_exercises
       where deleted_at is null
       group by user_id, workout_log_id, exercise_id
      having count(*) > 1
         and count(distinct xmin::text) < count(*)
    ) g;
  if v_bad > 0 then
    raise exception 'PRECONDITION_B: % duplicate group(s) have siblings sharing an xmin', v_bad;
  end if;

  -- 2. Cleanup: keep the youngest-xmin row of each duplicate group. One
  -- statement: the per-set delete and the tombstoning read the same ranking.
  with ranked as (
    select id, user_id, workout_log_id, exercise_id, set_number,
           row_number() over w as rn,
           count(*) over (partition by user_id, workout_log_id, exercise_id) as n
      from public.workout_log_exercises
     where deleted_at is null
    window w as (partition by user_id, workout_log_id, exercise_id
                 order by age(xmin) asc)
  ), dropped_sets as (
    delete from public.workout_log_sets s
     using ranked k
     where k.n > 1
       and k.rn = 1
       and k.set_number <> 0
       and s.user_id = k.user_id
       and s.workout_log_id::text = k.workout_log_id
       and s.exercise_id = k.exercise_id
       and s.set_number > k.set_number
    returning s.id
  )
  update public.workout_log_exercises e
     set deleted_at = now()
    from ranked k
   where k.n > 1
     and k.rn > 1
     and e.id = k.id;

  -- 2e. End-state assertion (atomic with the repair and the cleanup).
  select count(*) into v_bad
    from (
      select 1
        from public.workout_log_exercises
       where deleted_at is null
       group by user_id, workout_log_id, exercise_id
      having count(*) > 1
    ) g;
  if v_bad > 0 then
    raise exception 'END_STATE: % live duplicate group(s) remain after cleanup', v_bad;
  end if;
  select count(*) into v_bad
    from public.workout_log_exercises
   where id = any (v_pairs)
     and deleted_at is null;
  if v_bad > 0 then
    raise exception 'END_STATE: % OI-312 pair row(s) are still live after repair', v_bad;
  end if;

  -- 3. D0 fix: the delete trigger meets the live row at the same count.
  execute $fn_rename$
create or replace function public.workout_log_exercises_delete_final_rename()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $body$
begin
  -- Any UPDATE to an already-deleted row is a full no-op (150/151, unchanged).
  if tg_op = 'UPDATE' and old.deleted_at is not null then
    return null;
  end if;

  if tg_op = 'INSERT' and new.deleted_at is not null then
    -- L1a-1 (OI-312): a tombstone-shaped INSERT (the delete drain's upsert)
    -- first looks for the live row it was meant to delete at the SAME
    -- natural key. 151 suffixed the incoming row here, before the ON
    -- CONFLICT arbiter, so the live row was never reached.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      new.user_id::text || '|' || new.workout_log_id || '|' || new.exercise_id, 0));
    update public.workout_log_exercises
       set deleted_at = new.deleted_at
     where user_id = new.user_id
       and workout_log_id = new.workout_log_id
       and exercise_id = new.exercise_id
       and set_number = new.set_number
       and deleted_at is null;
    if found then
      -- The UPDATE branch below renamed that row; nothing to insert.
      return null;
    end if;
  end if;

  -- Transition to deleted frees the natural key (150/151): suffix
  -- exercise_id on either firing event.
  if new.deleted_at is not null then
    new.exercise_id := new.exercise_id || ' ' || chr(8249) || 'del:'
      || left(new.id::text, 8) || chr(8250);
  end if;

  return new;
end;
$body$
$fn_rename$;

  execute $cm_rename$
comment on function public.workout_log_exercises_delete_final_rename() is
  'OI-246 (150/151) + L1a-1 (OI-312): BEFORE INSERT OR UPDATE on workout_log_exercises. '
  'A tombstone-shaped INSERT first tombstones the live row at the same natural key '
  '(and inserts nothing); otherwise the delete transition suffixes exercise_id to '
  'free the natural key. Every UPDATE to a deleted row is a no-op.'
$cm_rename$;

  -- 4 + 5. D1 fix: one live summary row per (user, workout_log_id, exercise_id).
  execute $fn_single$
create or replace function public.workout_log_exercises_single_live()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $body$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    new.user_id::text || '|' || new.workout_log_id || '|' || new.exercise_id, 0));

  -- The latest push supersedes every live sibling at another count (the
  -- UPDATE fires ..._delete_final_rename, which renames each one).
  update public.workout_log_exercises
     set deleted_at = now()
   where user_id = new.user_id
     and workout_log_id = new.workout_log_id
     and exercise_id = new.exercise_id
     and set_number <> new.set_number
     and deleted_at is null;

  -- Per-set rows above the new count belong to a superseded version.
  -- workout_log_sets.workout_log_id is uuid: cast the COLUMN to text, never
  -- the incoming text to uuid (non-uuid ids must not throw).
  if new.set_number <> 0 then
    delete from public.workout_log_sets
     where user_id = new.user_id
       and workout_log_id::text = new.workout_log_id
       and exercise_id = new.exercise_id
       and set_number > new.set_number;
  end if;

  return new;
end;
$body$
$fn_single$;

  execute $cm_single$
comment on function public.workout_log_exercises_single_live() is
  'L1a-1 (OI-307): BEFORE INSERT on workout_log_exercises WHEN deleted_at is null. '
  'Serialises pushes per (user_id, workout_log_id, exercise_id), tombstones live '
  'siblings at another set_number and deletes per-set rows above the new count, '
  'so one live summary row remains per key (last push wins).'
$cm_single$;

  execute $tg_single$
drop trigger if exists workout_log_exercises_single_live
  on public.workout_log_exercises
$tg_single$;

  execute $tg_single2$
create trigger workout_log_exercises_single_live
  before insert on public.workout_log_exercises
  for each row
  when (new.deleted_at is null)
  execute function public.workout_log_exercises_single_live()
$tg_single2$;
end
$mig$;

-- Reverse block (commented out; run by hand, as the table owner, only with a
-- founder go). 151's suffix characters are written with chr() here too.
--
-- -- DDL
-- drop trigger if exists workout_log_exercises_single_live on public.workout_log_exercises;
-- drop function if exists public.workout_log_exercises_single_live();
-- -- then re-run, verbatim, the `create or replace function
-- -- public.workout_log_exercises_delete_final_rename()` statement AND the
-- -- `comment on function ...` statement from
-- -- 151_workout_log_exercises_delete_trigger_insert_path.sql.
--
-- -- DATA (snapshot loaded into a temp table _snap_wle with the original
-- -- columns, and _snap_wls with the deleted per-set rows)
-- alter table public.workout_log_exercises disable trigger workout_log_exercises_delete_final_rename;
-- update public.workout_log_exercises e
--    set exercise_id = s.exercise_id, deleted_at = s.deleted_at
--   from _snap_wle s
--  where e.id = s.id
--    and not exists (                       -- a newer push now holds the key: it wins
--      select 1 from public.workout_log_exercises o
--       where o.user_id = s.user_id and o.workout_log_id = s.workout_log_id
--         and o.exercise_id = s.exercise_id and o.set_number = s.set_number
--         and o.id <> s.id);
-- alter table public.workout_log_exercises enable trigger workout_log_exercises_delete_final_rename;
-- insert into public.workout_log_sets
--   select * from _snap_wls
--   on conflict (user_id, workout_log_id, exercise_id, set_number) do nothing;
--
-- -- After this reverse block, the restored siblings of one key share ONE
-- -- xmin (one UPDATE wrote them) and are younger than any post-apply push,
-- -- so a corrected re-apply would stop on PRECONDITION_B: before re-applying,
-- -- tombstone the unwanted siblings of each restored group by hand (founder
-- -- decides which version stays).
