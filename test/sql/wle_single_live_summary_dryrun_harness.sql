-- test/sql/wle_single_live_summary_dryrun_harness.sql
--
-- GENERATED -- the L1a-1 prod rolled-back dry-run harness (plan
-- docs/plans/coach-history-correctness-sync.md section 3, "Order of proof").
-- Built from the `-- >>> CASE` marker blocks of
--   test/sql/wle_single_live_summary_live_verify.sql      (N1-N12)
--   test/sql/workout_log_exercises_delete_final_rename_live_verify.sql (C1_4, C5, C6)
--   test/sql/wle_single_live_summary_dryrun_cases.sql     (R1-R12)
-- plus the migration text, embedded verbatim and sha256-checked
-- (expected 62b945e429130399f28c0705a7c1d572562ca6218eca909aa45fe6cb72d226c1).
-- ONE DO block; it ALWAYS ends in RAISE EXCEPTION ('DRYRUN_OK' or
-- 'DRYRUN_MISMATCH' with the per-case log), so every write rolls back.
-- Phases: (0) lock both tables, fixture user, baseline; (i) every case BEFORE
-- the migration, each in its own rolled-back sub-block, with the expected
-- outcome per case; baseline re-read must be unchanged; (ii) EXECUTE the
-- migration text and compare what it touched with the baseline's
-- prediction; (iii) the live-verify cases again, all must pass.

set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $harness$
declare
  v_user uuid;
  v_user2 uuid;
  v_log text := '';
  v_err text;
  v_got text;
  v_mismatch int := 0;
  v_suffix_re constant text :=
    ' ' || chr(8249) || 'del:[0-9a-f]{8}' || chr(8250) || '$';
  v_mig text := $migtext$-- Intent: L1a-1 (docs/plans/coach-history-correctness-sync.md v10). Two
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
$migtext$;
  b_groups int; b_live int; b_tombs int; b_wls int;
  b_pairs uuid[]; b_exp_tomb int; b_exp_sets int;
  c_groups int; c_live int; c_tombs int; c_wls int; c_pairs uuid[];
  c_exp_tomb int; c_exp_sets int;
  a_groups int; a_tomb_now int; a_wls int;
begin
  -- (0)
  perform set_config('lock_timeout', '5s', true);
  lock table public.workout_log_exercises, public.workout_log_sets
    in access exclusive mode;
  if encode(sha256(convert_to(v_mig, 'UTF8')), 'hex') <> '62b945e429130399f28c0705a7c1d572562ca6218eca909aa45fe6cb72d226c1' then
    raise exception 'DRYRUN_ABORT: embedded migration sha256 mismatch';
  end if;
  select u.id into v_user
    from public.users u join auth.users a on a.id = u.id
   order by u.id
   limit 1;
  select u.id into v_user2
    from public.users u join auth.users a on a.id = u.id
   where u.id <> v_user
   order by u.id
   limit 1;
  if v_user is null or v_user2 is null then
    raise exception 'DRYRUN_ABORT: NO_FIXTURE_USER';
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  select count(*) into b_groups from (
    select 1 from public.workout_log_exercises where deleted_at is null
     group by user_id, workout_log_id, exercise_id having count(*) > 1) g;
  select count(*) into b_live from public.workout_log_exercises where deleted_at is null;
  select count(*) into b_tombs from public.workout_log_exercises where deleted_at is not null;
  select count(*) into b_wls from public.workout_log_sets;
  select coalesce(array_agg(distinct l.id), '{}'::uuid[]) into b_pairs
    from public.workout_log_exercises t
    join public.workout_log_exercises l
      on l.user_id = t.user_id and l.workout_log_id = t.workout_log_id
     and l.exercise_id = regexp_replace(t.exercise_id, v_suffix_re, '')
     and l.deleted_at is null
   where t.deleted_at is not null and age(l.xmin) > age(t.xmin);
  with r as (
    select user_id, workout_log_id, exercise_id, set_number,
           row_number() over (partition by user_id, workout_log_id, exercise_id order by age(xmin)) rn,
           count(*) over (partition by user_id, workout_log_id, exercise_id) n
      from public.workout_log_exercises
     where deleted_at is null and id <> all (b_pairs))
  select coalesce(sum(case when rn > 1 then 1 else 0 end), 0),
         (select count(*) from public.workout_log_sets s join r k
             on k.n > 1 and k.rn = 1 and k.set_number <> 0
            and s.user_id = k.user_id and s.workout_log_id::text = k.workout_log_id
            and s.exercise_id = k.exercise_id and s.set_number > k.set_number)
    into b_exp_tomb, b_exp_sets
    from r where n > 1;
  b_exp_tomb := b_exp_tomb + cardinality(b_pairs);
  v_log := v_log || format(E'baseline: dup_groups=%s live=%s tombs=%s wls=%s oi312_pairs=%s expect_tombstoned=%s expect_wls_deleted=%s\n',
    b_groups, b_live, b_tombs, b_wls, cardinality(b_pairs), b_exp_tomb, b_exp_sets);

  -- (i) before the migration

  -- [before] N1, expected F
  v_err := null;
  begin
    begin
  -- pushes at counts 4 -> 7 -> 4 leave ONE live row: the last write.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N1 Bench Press';
    v_live int;
    v_reps int;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 7, 70)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 41)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    select count(*), max(reps) into v_live, v_reps
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_live <> 1 then
      raise exception 'FAIL N1: expected 1 live summary row after pushes 4 -> 7 -> 4, got %', v_live;
    end if;
    if v_reps is distinct from 41 then
      raise exception 'FAIL N1: the live row is not the last write (reps=%)', v_reps;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N1%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N1', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N2, expected F
  v_err := null;
  begin
    begin
  -- an IDENTICAL re-push of the current row (which migration 149's no-op
  -- suppression cancels as an UPDATE) still supersedes a stale live sibling:
  -- the trigger is BEFORE INSERT, so it fires on every upsert.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N2 Row';
    v_ts timestamptz := '2026-10-01 10:00:00+00';
    v_disabled boolean := false;
    v_live int;
    v_set int;
  begin
    -- Build the legacy state {3 stale, 4 current} as the owner, bypassing the
    -- new trigger when it exists (it would refuse to leave two live rows).
    if exists (select 1 from pg_trigger
                where tgrelid = 'public.workout_log_exercises'::regclass
                  and tgname = 'workout_log_exercises_single_live') then
      execute 'alter table public.workout_log_exercises disable trigger workout_log_exercises_single_live';
      v_disabled := true;
    end if;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 3, 30, v_ts),
           (v_user, v_w, v_ex, v_ex, 4, 40, v_ts);
    if v_disabled then
      execute 'alter table public.workout_log_exercises enable trigger workout_log_exercises_single_live';
    end if;

    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 4, 40, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps, completed_at = excluded.completed_at;
    select count(*), max(set_number) into v_live, v_set
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_live <> 1 or v_set is distinct from 4 then
      raise exception 'FAIL N2: identical re-push left % live row(s) (max set_number %); the stale sibling at 3 must be tombstoned', v_live, v_set;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N2%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N2', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N3, expected F
  v_err := null;
  begin
    begin
  -- count 7 -> 4, then the per-set push: per-set rows are exactly 1..4.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N3 Squat';
    v_sets int[];
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 7, 70)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 7) g
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 4) g
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    execute 'reset role';
    if v_sets is distinct from array[1, 2, 3, 4] then
      raise exception 'FAIL N3: per-set rows after 7 -> 4 are %, expected {1,2,3,4}', v_sets;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N3%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N3', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N4, expected P
  v_err := null;
  begin
    begin
  -- legacy gapped per-set numbers {1,2,4} at count 3: after a re-push of the
  -- summary AND the sets, the end state is {1,2,4} again (the sets push
  -- re-inserts its own numbers right after the summary push).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N4 Row';
    v_sets int[];
    v_round int;
  begin
    execute 'set local role authenticated';
    for v_round in 1 .. 2 loop
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 3, 30)
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set reps = excluded.reps;
      insert into public.workout_log_sets
        (user_id, workout_log_id, exercise_id, set_number, reps)
      select v_user, v_w::uuid, v_ex, g, 10 from unnest(array[1, 2, 4]) g
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set reps = excluded.reps;
    end loop;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    execute 'reset role';
    if v_sets is distinct from array[1, 2, 4] then
      raise exception 'FAIL N4: legacy gapped sets ended as %, expected {1,2,4}', v_sets;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N4%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'N4', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N5, expected F
  v_err := null;
  begin
    begin
  -- a count-0 summary push (count unknown, legacy shape) supersedes the live
  -- row like any push but never deletes per-set rows: readers take every
  -- per-set row under a count-0 summary (L1a-2 U2(b)).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N5 Plank';
    v_sets int[];
    v_live int;
    v_live_set int;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 3, 30)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 3) g
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 0, 0)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    select count(*), max(set_number) into v_live, v_live_set
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_sets is distinct from array[1, 2, 3] then
      raise exception 'FAIL N5: a count-0 push changed per-set rows to %, expected {1,2,3}', v_sets;
    end if;
    if v_live <> 1 or v_live_set is distinct from 0 then
      raise exception 'FAIL N5: after a count-0 push expected one live row at count 0, got % live (max set_number %)', v_live, v_live_set;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N5%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N5', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N6, expected P
  v_err := null;
  begin
    begin
  -- a non-uuid workout_log_id (legacy/fixture shape) pushes without error:
  -- the trigger casts the uuid COLUMN to text, never the text to uuid.
  declare
    v_w text := 'sqlv_nonuuid_wlog_' || left(gen_random_uuid()::text, 8);
    v_ex text := 'SQLV N6 Curl';
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 3, 30)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 5, 50)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    execute 'reset role';
  exception when others then
    raise exception 'FAIL N6: a non-uuid workout_log_id push raised % %', sqlstate, sqlerrm;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N6%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'N6', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N7, expected F
  v_err := null;
  begin
    begin
  -- the push takes the per-key advisory transaction lock.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N7 Deadlift';
    v_key bigint;
    v_held int;
    v_ok boolean;
  begin
    v_key := hashtextextended(v_user::text || '|' || v_w || '|' || v_ex, 0);
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 2, 20)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    execute 'reset role';
    select count(*) into v_held
      from pg_locks
     where locktype = 'advisory'
       and pid = pg_backend_pid()
       and classid = ((v_key >> 32) & 4294967295)::oid
       and objid = (v_key & 4294967295)::oid
       and objsubid = 1;
    if v_held = 0 then
      raise exception 'FAIL N7: no advisory lock held for the pushed key';
    end if;
    -- the lock must be taken BEFORE the supersede statement (a lock taken
    -- after it serialises nothing); two-session order is not observable in
    -- one transaction, so this is a position pin on the installed body.
    select strpos(prosrc, 'pg_advisory_xact_lock') > 0
       and strpos(prosrc, 'pg_advisory_xact_lock') < strpos(prosrc, 'update public.workout_log_exercises')
      into v_ok
      from pg_proc
     where proname = 'workout_log_exercises_single_live'
       and pronamespace = 'public'::regnamespace;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL N7: single_live does not take its advisory lock before its UPDATE';
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N7%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N7', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N8, expected F
  v_err := null;
  begin
    begin
  -- key isolation of a PUSH (B-pass 2026-10-06): bystanders are the same
  -- user's other exercise in the same workout, the same exercise in another
  -- workout, and ANOTHER user's same exercise under the same (date-derived)
  -- workout_log_id. Run as the OWNER so RLS cannot mask a missing user_id
  -- predicate. Also pins the per-set boundary BEFORE the sets re-push
  -- (a `>=` or `<>` would show here, N3 re-inserts and cannot see it), and
  -- that an identical re-push keeps the row: same id, no new tombstone.
  declare
    v_w text := gen_random_uuid()::text;
    v_w2 text := gen_random_uuid()::text;
    v_ex text := 'SQLV N8 Press';
    v_by text := 'SQLV N8 Row';
    v_ts timestamptz := '2026-10-01 10:00:00+00';
    v_by_before uuid[];
    v_by_after uuid[];
    v_live int;
    v_live_id uuid;
    v_live_id2 uuid;
    v_tombs int;
    v_tombs2 int;
    v_sets int[];
    v_by_sets int;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 4, 40, v_ts),
           (v_user, v_w, v_by, v_by, 4, 40, v_ts),
           (v_user, v_w2, v_ex, v_ex, 4, 40, v_ts),
           (v_user2, v_w, v_ex, v_ex, 4, 40, v_ts);
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select k.u, k.w::uuid, k.e, g, 10
      from (values (v_user, v_w, v_ex), (v_user, v_w, v_by),
                   (v_user, v_w2, v_ex), (v_user2, v_w, v_ex)) k(u, w, e),
           generate_series(1, 4) g;
    select array_agg(id order by id) into v_by_before
      from public.workout_log_exercises
     where deleted_at is null
       and ((user_id = v_user and workout_log_id = v_w and exercise_id = v_by)
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = v_ex)
         or (user_id = v_user2 and workout_log_id = v_w and exercise_id = v_ex));

    -- the push under test: count 4 -> 3, summary only (no sets re-push yet)
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 3, 30, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps, completed_at = excluded.completed_at;

    select count(*), max(id::text)::uuid into v_live, v_live_id
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    if v_live <> 1 then
      raise exception 'FAIL N8: the pushed key has % live rows after 4 -> 3, expected 1', v_live;
    end if;
    select array_agg(id order by id) into v_by_after
      from public.workout_log_exercises
     where deleted_at is null
       and ((user_id = v_user and workout_log_id = v_w and exercise_id = v_by)
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = v_ex)
         or (user_id = v_user2 and workout_log_id = v_w and exercise_id = v_ex));
    if v_by_after is distinct from v_by_before then
      raise exception 'FAIL N8: a push tombstoned a bystander summary row (live bystanders % -> %)', cardinality(v_by_before), coalesce(cardinality(v_by_after), 0);
    end if;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    if v_sets is distinct from array[1, 2, 3] then
      raise exception 'FAIL N8: per-set rows of the pushed key after the 4 -> 3 summary push are %, expected {1,2,3}', v_sets;
    end if;
    select count(*) into v_by_sets
      from public.workout_log_sets
     where (user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_by)
        or (user_id = v_user and workout_log_id = v_w2::uuid and exercise_id = v_ex)
        or (user_id = v_user2 and workout_log_id = v_w::uuid and exercise_id = v_ex);
    if v_by_sets <> 12 then
      raise exception 'FAIL N8: bystander per-set rows were deleted (% of 12 left)', v_by_sets;
    end if;

    -- an identical re-push keeps the same row and writes no tombstone
    select count(*) into v_tombs
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is not null;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 3, 30, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps, completed_at = excluded.completed_at;
    select max(id::text)::uuid into v_live_id2
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    select count(*) into v_tombs2
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is not null;
    if v_live_id2 is distinct from v_live_id or v_tombs2 <> v_tombs then
      raise exception 'FAIL N8: an identical re-push replaced the live row (id % -> %, tombstones % -> %)', v_live_id, v_live_id2, v_tombs, v_tombs2;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N8%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N8', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N9, expected F
  v_err := null;
  begin
    begin
  -- key isolation of a DRAIN (tombstone-shaped upsert): bystanders at the
  -- SAME count -- the same user's other exercise in the same workout, the
  -- same exercise in another workout, another user's same exercise under the
  -- same workout_log_id -- stay live; the drained row is tombstoned. Owner.
  declare
    v_w text := gen_random_uuid()::text;
    v_w2 text := gen_random_uuid()::text;
    v_ex text := 'SQLV N9 Press';
    v_by text := 'SQLV N9 Row';
    v_by_live int;
    v_live int;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 5, 50),
           (v_user, v_w, v_by, v_by, 5, 50),
           (v_user, v_w2, v_ex, v_ex, 5, 50),
           (v_user2, v_w, v_ex, v_ex, 5, 50);
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 5, now())
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    select count(*) into v_by_live
      from public.workout_log_exercises
     where deleted_at is null and set_number = 5
       and ((user_id = v_user and workout_log_id = v_w and exercise_id = v_by)
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = v_ex)
         or (user_id = v_user2 and workout_log_id = v_w and exercise_id = v_ex));
    if v_by_live <> 3 then
      raise exception 'FAIL N9: a drain tombstoned a bystander (% of 3 still live)', v_by_live;
    end if;
    select count(*) into v_live
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    if v_live <> 0 then
      raise exception 'FAIL N9: the drained row is still live (% live)', v_live;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N9%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N9', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N10, expected F
  v_err := null;
  begin
    begin
  -- the DRAIN path takes the same per-key advisory lock as a push (N7): a
  -- drain racing an in-flight push for the key must wait for it, or the
  -- delete is lost (B-pass 2026-10-06, observed with two sessions).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N10 Press';
    v_key bigint;
    v_held int;
    v_ok boolean;
  begin
    v_key := hashtextextended(v_user::text || '|' || v_w || '|' || v_ex, 0);
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 2, now())
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    execute 'reset role';
    select count(*) into v_held
      from pg_locks
     where locktype = 'advisory'
       and pid = pg_backend_pid()
       and classid = ((v_key >> 32) & 4294967295)::oid
       and objid = (v_key & 4294967295)::oid
       and objsubid = 1;
    if v_held = 0 then
      raise exception 'FAIL N10: a drain-shaped insert holds no advisory lock for its key';
    end if;
    select strpos(prosrc, 'pg_advisory_xact_lock') > 0
       and strpos(prosrc, 'pg_advisory_xact_lock') < strpos(prosrc, 'update public.workout_log_exercises')
      into v_ok
      from pg_proc
     where proname = 'workout_log_exercises_delete_final_rename'
       and pronamespace = 'public'::regnamespace;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL N10: the delete trigger does not take its advisory lock before its UPDATE';
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N10%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N10', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N11, expected P
  v_err := null;
  begin
    begin
  -- a drain sent by ANOTHER authenticated user for this user's key changes
  -- nothing: the delete trigger runs SECURITY INVOKER, so its UPDATE is
  -- filtered by wle_update_own and the INSERT then fails WITH CHECK (42501).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N11 Press';
    v_victim uuid;
    v_state text;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    returning id into v_victim;
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_user2, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
      values (v_user, v_w, v_ex, v_ex, 4, now())
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set exercise_name = excluded.exercise_name,
                      deleted_at = excluded.deleted_at;
    exception when insufficient_privilege then
      null;  -- expected: 42501 from WITH CHECK
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    select case when deleted_at is null then 'live' else 'tombstoned' end
      into v_state
      from public.workout_log_exercises where id = v_victim;
    if v_state is distinct from 'live' then
      raise exception 'FAIL N11: another user''s drain changed this user''s row (now %)', coalesce(v_state, 'missing');
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N11%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'N11', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] N12, expected F
  v_err := null;
  begin
    begin
  -- both trigger functions run SECURITY INVOKER (RLS applies to their
  -- in-trigger statements; N11 is the behavioural proof for the delete
  -- function) with an empty search_path (every name schema-qualified).
  declare
    v_n int;
  begin
    select count(*) into v_n
      from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname in ('workout_log_exercises_delete_final_rename',
                       'workout_log_exercises_single_live')
       and not prosecdef
       and 'search_path=""' = any (proconfig);
    if v_n <> 2 then
      raise exception 'FAIL N12: % of 2 trigger functions are SECURITY INVOKER with an empty search_path', v_n;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N12%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'N12', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] C1_4, expected P
  v_err := null;
  begin
    begin
  -- Cases 1-4 (migrations 150/151), run as the owner. Each case marker block
  -- is reused verbatim by the L1a-1 prod rolled-back dry-run harness.
  declare
  v_user_id uuid := v_user;
  v_wlog_id text := 'sql_verify_wlog_2026_09_28';
  v_id_a uuid := gen_random_uuid();
  v_id_b uuid := gen_random_uuid();
  v_exercise_id_after_update text;
  v_deleted_after_update timestamptz;
  v_row_count int;
  begin
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
  -- the exact suffix bytes (U+0020 U+2039 'del:' 8 hex U+203A, end of
  -- string): the apply-time strip regex of L1a-1 reads exactly this shape.
  if v_exercise_id_after_update !~ ('^SQL Verify Bench Press ' || chr(8249) || 'del:' || left(v_id_a::text, 8) || chr(8250) || '$') then
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

    -- 2026-10-06 (B-pass): without this, a missing row (NULL) passed both
    -- checks below vacuously.
    if v_exercise_id_after_insert is null then
      raise exception 'FAIL case 4: the tombstone-shaped INSERT left no row at all';
    end if;

    if v_exercise_id_after_insert = 'SQL Verify Squat' then
      raise exception 'FAIL case 4: a tombstone-shaped INSERT (deleted_at set) was NOT suffixed -- the natural key stays occupied unsuffixed, exactly OI-246 P1''s unfixed gap. Is migration 151 live?';
    end if;
    if v_exercise_id_after_insert !~ ('^SQL Verify Squat ' || chr(8249) || 'del:' || left(v_id_c::text, 8) || chr(8250) || '$') then
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
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL case%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'C1_4', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] C5, expected F
  v_err := null;
  begin
    begin
  -- L1a-1 (OI-312): a drain-shaped tombstone upsert at the SAME count as the
  -- live row tombstones THAT row and inserts nothing. Before L1a-1, 151
  -- suffixed the incoming row before the ON CONFLICT arbiter, so the live row
  -- stayed live next to a new suffixed tombstone (live probe 2026-10-06:
  -- live=1, tombstones=1). Run as `authenticated`, the installed APK's path.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV C5 Bench Press';
    v_ts timestamptz := '2026-10-02 10:00:00+00';
    v_live int;
    v_total int;
    v_tomb_ex text;
    v_tomb_at timestamptz;
    v_tomb_id uuid;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 4, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    select count(*) filter (where deleted_at is null), count(*)
      into v_live, v_total
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w and exercise_name = v_ex;
    select id, exercise_id, deleted_at into v_tomb_id, v_tomb_ex, v_tomb_at
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w and exercise_name = v_ex
       and deleted_at is not null;
    execute 'reset role';
    if v_live <> 0 then
      raise exception 'FAIL C5: the drain at the live row''s count left % live row(s) -- the delete never reached it (OI-312)', v_live;
    end if;
    if v_total <> 1 then
      raise exception 'FAIL C5: expected the live row itself tombstoned (1 row in total), got % rows', v_total;
    end if;
    if v_tomb_ex !~ ('^' || v_ex || ' ' || chr(8249) || 'del:' || left(v_tomb_id::text, 8) || chr(8250) || '$') then
      raise exception 'FAIL C5: the tombstone''s exercise_id is not 151''s exact suffix shape: %', v_tomb_ex;
    end if;
    if v_tomb_at is distinct from v_ts then
      raise exception 'FAIL C5: the tombstone carries deleted_at % instead of the drain''s %', v_tomb_at, v_ts;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL C5%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=F got=%s: %s\n', 'before', 'C5', v_got, v_err);
  if v_got <> 'F' then v_mismatch := v_mismatch + 1; end if;

  -- [before] C6, expected P
  v_err := null;
  begin
    begin
  -- the documented same-count rule (L1a-1 section 5, residual R2): a drain at
  -- count 3 does NOT tombstone a live row at count 4.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV C6 Row';
    v_live_set int;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 3, now())
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    select max(set_number) into v_live_set
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_live_set is distinct from 4 then
      raise exception 'FAIL C6: a drain at count 3 changed the live row at count 4 (live max set_number %)', v_live_set;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL C6%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'C6', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R1, expected P
  v_err := null;
  begin
    begin
  -- a live row L at count 4, then the drain's tombstone T at count 4 (151
  -- suffixes T, so L stays live: OI-312) => after the migration L is
  -- tombstoned.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R1 Press';
    v_l uuid;
    v_t uuid;
    v_ok boolean;
  begin
    execute 'set local role authenticated';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 4, 40)
      returning id into v_l;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
      values (v_user, v_w, v_ex, v_ex, 4, now())
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set exercise_name = excluded.exercise_name,
                      deleted_at = excluded.deleted_at
      returning id into v_t;
    exception when others then raise;
    end;
    execute 'reset role';
    select age(l.xmin) > age(t.xmin) and l.xmin::text <> t.xmin::text
      into v_ok
      from public.workout_log_exercises l, public.workout_log_exercises t
     where l.id = v_l and t.id = v_t;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL R1: fixture order not proven (L must be older than T; is 151 live and the OI-312 shape buildable?)';
    end if;
    execute v_mig;
    if exists (select 1 from public.workout_log_exercises
                where id = v_l and deleted_at is null) then
      raise exception 'FAIL R1: the live row written before the tombstone is still live after the migration';
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R1%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R1', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R2, expected P
  v_err := null;
  begin
    begin
  -- L at 4, then T at 4, then a re-log L2 at 3 (three subtransactions) =>
  -- L tombstoned, L2 stays live, precondition (b) does not abort.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R2 Press';
    v_l uuid;
    v_t uuid;
    v_l2 uuid;
    v_ok boolean;
  begin
    execute 'set local role authenticated';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 4, 40)
      returning id into v_l;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
      values (v_user, v_w, v_ex, v_ex, 4, now())
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set exercise_name = excluded.exercise_name,
                      deleted_at = excluded.deleted_at
      returning id into v_t;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 3, 30)
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set reps = excluded.reps
      returning id into v_l2;
    exception when others then raise;
    end;
    execute 'reset role';
    select age(l.xmin) > age(t.xmin) and age(t.xmin) > age(l2.xmin)
       and l.xmin::text <> t.xmin::text and t.xmin::text <> l2.xmin::text
      into v_ok
      from public.workout_log_exercises l, public.workout_log_exercises t,
           public.workout_log_exercises l2
     where l.id = v_l and t.id = v_t and l2.id = v_l2;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL R2: fixture order not proven (L older than T older than L2)';
    end if;
    execute v_mig;
    if exists (select 1 from public.workout_log_exercises
                where id = v_l and deleted_at is null) then
      raise exception 'FAIL R2: the live row written before the tombstone is still live';
    end if;
    if not exists (select 1 from public.workout_log_exercises
                    where id = v_l2 and deleted_at is null) then
      raise exception 'FAIL R2: the re-log written after the tombstone was tombstoned (the age guard is missing)';
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R2%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R2', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R3, expected P
  v_err := null;
  begin
    begin
  -- a duplicate group {3, 4}, then T at 4 => 0 live rows (2a covers the whole
  -- group, not only the sibling at the drain's count).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R3 Press';
    v_l3 uuid;
    v_l4 uuid;
    v_t uuid;
    v_ok boolean;
    v_live int;
  begin
    execute 'set local role authenticated';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 3, 30)
      returning id into v_l3;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 4, 40)
      returning id into v_l4;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
      values (v_user, v_w, v_ex, v_ex, 4, now())
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set exercise_name = excluded.exercise_name,
                      deleted_at = excluded.deleted_at
      returning id into v_t;
    exception when others then raise;
    end;
    execute 'reset role';
    select age(l3.xmin) > age(l4.xmin) and age(l4.xmin) > age(t.xmin)
       and l3.xmin::text <> l4.xmin::text and l4.xmin::text <> t.xmin::text
      into v_ok
      from public.workout_log_exercises l3, public.workout_log_exercises l4,
           public.workout_log_exercises t
     where l3.id = v_l3 and l4.id = v_l4 and t.id = v_t;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL R3: fixture order not proven (L3 older than L4 older than T)';
    end if;
    execute v_mig;
    select count(*) into v_live
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    if v_live <> 0 then
      raise exception 'FAIL R3: % live row(s) remain in a duplicate group deleted after both were written', v_live;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R3%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R3', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R4, expected P
  v_err := null;
  begin
    begin
  -- an UNSUFFIXED tombstone (a shape 151 never writes) => the migration aborts
  -- on precondition (a) before changing anything.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R4 Press';
    v_err text;
  begin
    execute 'alter table public.workout_log_exercises disable trigger workout_log_exercises_delete_final_rename';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 2, now());
    execute 'alter table public.workout_log_exercises enable trigger workout_log_exercises_delete_final_rename';
    begin
      execute v_mig;
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'PRECONDITION_A:%' then
      raise exception 'FAIL R4: expected the PRECONDITION_A abort, got %', coalesce(v_err, 'no error');
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R4%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R4', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R5, expected P
  v_err := null;
  begin
    begin
  -- the cleanup keeps the YOUNGEST row of a duplicate group (the last push,
  -- founder rule "last sync or write wins"), even when its count is LOWER:
  -- {4 older, 3 younger} with per-set rows 1..4 => the live row is the 3 and
  -- the per-set rows are 1..3. Prod has 0 per-set rows above a kept count
  -- (V12), so without this case nothing pins WHICH sibling is kept.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R5 Lunge';
    v_old uuid;
    v_young uuid;
    v_ok boolean;
    v_live uuid;
    v_sets int[];
  begin
    execute 'set local role authenticated';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 4, 40)
      returning id into v_old;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_sets
        (user_id, workout_log_id, exercise_id, set_number, reps)
      select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 4) g;
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 3, 30)
      returning id into v_young;
    exception when others then raise;
    end;
    execute 'reset role';
    select age(o.xmin) > age(y.xmin) into v_ok
      from public.workout_log_exercises o, public.workout_log_exercises y
     where o.id = v_old and y.id = v_young;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL R5: fixture order not proven (the count-4 row must be older)';
    end if;
    execute v_mig;
    select id into v_live
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    if v_live is distinct from v_young then
      raise exception 'FAIL R5: the cleanup kept % instead of the youngest row %', v_live, v_young;
    end if;
    if v_sets is distinct from array[1, 2, 3] then
      raise exception 'FAIL R5: per-set rows after the cleanup are %, expected {1,2,3}', v_sets;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R5%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R5', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R6, expected P
  v_err := null;
  begin
    begin
  -- key isolation of the CLEANUP and the 2a REPAIR (B-pass 2026-10-06, rounds
  -- 1 and 2), run as the owner with a second real user. Each fixture row is
  -- written in its own subtransaction, in this order:
  --   X@4 (u1,w1) with sets 1..4; then X@3 (u1,w1) -- the youngest of its
  --   group; THEN the bystanders, younger still: Y@4 (u1,w1), (u2,w1,X) and
  --   (u1,w2,X), so a ranking partition missing exercise_id, user_id or
  --   workout_log_id would rank a bystander above X@3. Every bystander
  --   (Y, and the two X) is a singleton at count 4 carrying legacy per-set
  --   rows 1..5 (one ABOVE its count, like N4's gapped sets): the cleanup must
  --   not touch a non-duplicate group's per-set rows.
  --   Z@4 (u1,w1), Z@4 (u2,w1), Z@4 (u1,w2); then the drain tombstone T for
  --   (u1,w1,Z)@4 (151 suffixes it: an OI-312 pair).
  --   V@4 (u1,w3) with sets 1..4; then V@0 (u1,w3) -- count unknown, youngest.
  -- Expected: (u1,w1,X) live row is the @3, its sets {1,2,3}; the three
  -- bystander summaries live with their 15 per-set rows intact; (u1,w1,Z)
  -- tombstoned, both Z bystanders live; V live at count 0 with all 4 per-set
  -- rows.
  declare
    v_w1 text := gen_random_uuid()::text;
    v_w2 text := gen_random_uuid()::text;
    v_w3 text := gen_random_uuid()::text;
    r record;
    v_x3 uuid;
    v_live uuid;
    v_sets int[];
    v_n int;
    v_vset int;
  begin
    for r in
      select * from (values
        (1, v_user,  v_w1, 'SQLV R6 X', 4),
        (2, v_user,  v_w1, 'SQLV R6 X', 3),
        (3, v_user,  v_w1, 'SQLV R6 Y', 4),
        (4, v_user2, v_w1, 'SQLV R6 X', 4),
        (5, v_user,  v_w2, 'SQLV R6 X', 4),
        (6, v_user,  v_w1, 'SQLV R6 Z', 4),
        (7, v_user2, v_w1, 'SQLV R6 Z', 4),
        (8, v_user,  v_w2, 'SQLV R6 Z', 4),
        (9, v_user,  v_w3, 'SQLV R6 V', 4),
        (10, v_user, v_w3, 'SQLV R6 V', 0)) t(ord, u, w, e, n)
      order by ord
    loop
      begin
        insert into public.workout_log_exercises
          (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
        values (r.u, r.w, r.e, r.e, r.n, r.n * 10);
      exception when others then raise;
      end;
      if r.ord = 2 then
        select id into v_x3 from public.workout_log_exercises
         where user_id = v_user and workout_log_id = v_w1
           and exercise_id = 'SQLV R6 X' and set_number = 3;
      end if;
      if r.ord = 8 then
        begin
          insert into public.workout_log_exercises
            (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
          values (v_user, v_w1, 'SQLV R6 Z', 'SQLV R6 Z', 4, now())
          on conflict (user_id, workout_log_id, exercise_id, set_number)
            do update set exercise_name = excluded.exercise_name,
                          deleted_at = excluded.deleted_at;
        exception when others then raise;
        end;
      end if;
    end loop;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select k.u, k.w::uuid, k.e, g, 10
      from (values (v_user, v_w1, 'SQLV R6 X'), (v_user, v_w3, 'SQLV R6 V')) k(u, w, e),
           generate_series(1, 4) g;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select k.u, k.w::uuid, k.e, g, 10
      from (values (v_user2, v_w1, 'SQLV R6 X'), (v_user, v_w1, 'SQLV R6 Y'),
                   (v_user, v_w2, 'SQLV R6 X')) k(u, w, e),
           generate_series(1, 5) g;

    execute v_mig;

    select id into v_live from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w1
       and exercise_id = 'SQLV R6 X' and deleted_at is null;
    if v_live is distinct from v_x3 then
      raise exception 'FAIL R6: the cleanup did not keep the youngest (u1,w1,X) row';
    end if;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w1::uuid and exercise_id = 'SQLV R6 X';
    if v_sets is distinct from array[1, 2, 3] then
      raise exception 'FAIL R6: (u1,w1,X) per-set rows after the cleanup are %, expected {1,2,3}', v_sets;
    end if;
    select count(*) into v_n from public.workout_log_sets
     where (user_id = v_user2 and workout_log_id = v_w1::uuid and exercise_id = 'SQLV R6 X')
        or (user_id = v_user and workout_log_id = v_w1::uuid and exercise_id = 'SQLV R6 Y')
        or (user_id = v_user and workout_log_id = v_w2::uuid and exercise_id = 'SQLV R6 X');
    if v_n <> 15 then
      raise exception 'FAIL R6: the cleanup deleted bystander per-set rows (% of 15 left)', v_n;
    end if;
    select count(*) into v_n from public.workout_log_exercises
     where deleted_at is null and set_number = 4
       and ((user_id = v_user2 and workout_log_id = v_w1 and exercise_id = 'SQLV R6 X')
         or (user_id = v_user and workout_log_id = v_w1 and exercise_id = 'SQLV R6 Y')
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = 'SQLV R6 X'));
    if v_n <> 3 then
      raise exception 'FAIL R6: the cleanup tombstoned a bystander summary (% of 3 live)', v_n;
    end if;
    select count(*) into v_n from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w1
       and exercise_id = 'SQLV R6 Z' and deleted_at is null;
    if v_n <> 0 then
      raise exception 'FAIL R6: the OI-312 pair''s live row is still live';
    end if;
    select count(*) into v_n from public.workout_log_exercises
     where exercise_id = 'SQLV R6 Z' and deleted_at is null
       and ((user_id = v_user2 and workout_log_id = v_w1)
         or (user_id = v_user and workout_log_id = v_w2));
    if v_n <> 2 then
      raise exception 'FAIL R6: the 2a repair tombstoned a bystander Z row (% of 2 live)', v_n;
    end if;
    select count(*) into v_n from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w3::uuid and exercise_id = 'SQLV R6 V';
    select max(set_number) into v_vset from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w3
       and exercise_id = 'SQLV R6 V' and deleted_at is null;
    if v_n <> 4 or v_vset is distinct from 0 then
      raise exception 'FAIL R6: count-0 youngest: expected live count 0 with 4 per-set rows, got count % and % rows', v_vset, v_n;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R6%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R6', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R7, expected P
  v_err := null;
  begin
    begin
  -- two live siblings written by ONE statement share an xmin, so "youngest"
  -- is undefined => the migration aborts on precondition (b).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R7 Press';
    v_err text;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 3, 30),
           (v_user, v_w, v_ex, v_ex, 4, 40);
    begin
      execute v_mig;
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'PRECONDITION_B:%' then
      raise exception 'FAIL R7: expected the PRECONDITION_B abort, got %', coalesce(v_err, 'no error');
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R7%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R7', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R8, expected P
  v_err := null;
  begin
    begin
  -- the migration is NOT re-runnable (a second run's 2a would tombstone the
  -- rows the first run kept), so a second apply must refuse with
  -- ALREADY_APPLIED and change nothing.
  declare
    v_live_1 int;
    v_live_2 int;
    v_err text;
  begin
    execute v_mig;
    select count(*) into v_live_1 from public.workout_log_exercises where deleted_at is null;
    begin
      execute v_mig;
    exception when others then
      v_err := sqlerrm;
    end;
    select count(*) into v_live_2 from public.workout_log_exercises where deleted_at is null;
    if v_err is null or v_err not like 'ALREADY_APPLIED:%' then
      raise exception 'FAIL R8: a second apply did not refuse (got %)', coalesce(v_err, 'no error');
    end if;
    if v_live_2 <> v_live_1 then
      raise exception 'FAIL R8: a second apply changed live rows (% -> %)', v_live_1, v_live_2;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R8%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R8', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R9, expected P
  v_err := null;
  begin
    begin
  -- the END_STATE duplicate-group assertion is live code, not decoration: a
  -- fixture BEFORE UPDATE trigger (rolled back with the case) swallows the
  -- cleanup's tombstoning for this case's rows, and the migration must abort
  -- instead of installing its triggers over a still-duplicated key.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R9 X';
    v_err text;
  begin
    execute $f$create function public.sqlv_r9_swallow() returns trigger
      language plpgsql as $b$
      begin
        if new.exercise_name like 'SQLV R9 %' and old.deleted_at is null
           and new.deleted_at is not null then
          return null;
        end if;
        return new;
      end $b$$f$;
    execute 'create trigger a_sqlv_r9_swallow before update on public.workout_log_exercises for each row execute function public.sqlv_r9_swallow()';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 3, 30);
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 4, 40);
    exception when others then raise;
    end;
    begin
      execute v_mig;
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'END_STATE: % live duplicate group%' then
      raise exception 'FAIL R9: expected the END_STATE duplicate-group abort, got %', coalesce(v_err, 'no error');
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R9%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R9', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R10, expected P
  v_err := null;
  begin
    begin
  -- the END_STATE OI-312-pair assertion is live code: the fixture trigger
  -- swallows the 2a repair's tombstoning of this case's pair.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV R10 Z';
    v_err text;
  begin
    execute $f$create function public.sqlv_r10_swallow() returns trigger
      language plpgsql as $b$
      begin
        if new.exercise_name like 'SQLV R10 %' and old.deleted_at is null
           and new.deleted_at is not null then
          return null;
        end if;
        return new;
      end $b$$f$;
    execute 'create trigger a_sqlv_r10_swallow before update on public.workout_log_exercises for each row execute function public.sqlv_r10_swallow()';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 4, 40);
    exception when others then raise;
    end;
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
      values (v_user, v_w, v_ex, v_ex, 4, now())
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set exercise_name = excluded.exercise_name,
                      deleted_at = excluded.deleted_at;
    exception when others then raise;
    end;
    begin
      execute v_mig;
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'END_STATE: % OI-312 pair%' then
      raise exception 'FAIL R10: expected the END_STATE OI-312-pair abort, got %', coalesce(v_err, 'no error');
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R10%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R10', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R11, expected P
  v_err := null;
  begin
    begin
  -- rows of DIFFERENT keys written by one statement share an xmin; that is
  -- not a tie inside a duplicate group, so the migration must neither abort
  -- (precondition (b) grouped by the full key) nor tombstone any of them
  -- (the cleanup ranks within the full key).
  declare
    v_w text := gen_random_uuid()::text;
    v_w2 text := gen_random_uuid()::text;
    v_err text;
    v_live int;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user,  v_w,  'SQLV R11 X', 'SQLV R11 X', 3, 30),
           (v_user2, v_w,  'SQLV R11 X', 'SQLV R11 X', 3, 30),
           (v_user,  v_w2, 'SQLV R11 X', 'SQLV R11 X', 3, 30),
           (v_user,  v_w,  'SQLV R11 Y', 'SQLV R11 Y', 3, 30);
    begin
      execute v_mig;
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err is not null then
      raise exception 'FAIL R11: rows of different keys sharing an xmin aborted the migration: %', v_err;
    end if;
    select count(*) into v_live from public.workout_log_exercises
     where exercise_name like 'SQLV R11 %' and deleted_at is null;
    if v_live <> 4 then
      raise exception 'FAIL R11: % of 4 single-row keys stayed live', v_live;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R11%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R11', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [before] R12, expected P
  v_err := null;
  begin
    begin
  -- the migration bounds its own lock wait and takes both table locks FIRST.
  -- The harness already holds those locks, so their presence cannot be
  -- observed here: lock_timeout is checked behaviourally (the caller's '0'
  -- must be replaced by '5s'), the statement order by position in the text.
  declare
    v_set int;
    v_lock int;
    v_first_check int;
  begin
    perform set_config('lock_timeout', '0', true);
    execute v_mig;
    if current_setting('lock_timeout') <> '5s' then
      raise exception 'FAIL R12: the migration did not set its own lock_timeout (now %)', current_setting('lock_timeout');
    end if;
    v_set := strpos(v_mig, 'perform set_config(''lock_timeout'', ''5s'', true);');
    v_lock := strpos(v_mig, 'lock table public.workout_log_exercises, public.workout_log_sets
    in access exclusive mode;');
    v_first_check := strpos(v_mig, 'raise exception ''ALREADY_APPLIED');
    if not (v_set > 0 and v_set < v_lock and v_lock < v_first_check) then
      raise exception 'FAIL R12: lock_timeout (%), LOCK TABLE (%) and the first check (%) are not in that order', v_set, v_lock, v_first_check;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL R12%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'before', 'R12', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- baseline must be unchanged after phase (i)

  select count(*) into c_groups from (
    select 1 from public.workout_log_exercises where deleted_at is null
     group by user_id, workout_log_id, exercise_id having count(*) > 1) g;
  select count(*) into c_live from public.workout_log_exercises where deleted_at is null;
  select count(*) into c_tombs from public.workout_log_exercises where deleted_at is not null;
  select count(*) into c_wls from public.workout_log_sets;
  select coalesce(array_agg(distinct l.id), '{}'::uuid[]) into c_pairs
    from public.workout_log_exercises t
    join public.workout_log_exercises l
      on l.user_id = t.user_id and l.workout_log_id = t.workout_log_id
     and l.exercise_id = regexp_replace(t.exercise_id, v_suffix_re, '')
     and l.deleted_at is null
   where t.deleted_at is not null and age(l.xmin) > age(t.xmin);
  with r as (
    select user_id, workout_log_id, exercise_id, set_number,
           row_number() over (partition by user_id, workout_log_id, exercise_id order by age(xmin)) rn,
           count(*) over (partition by user_id, workout_log_id, exercise_id) n
      from public.workout_log_exercises
     where deleted_at is null and id <> all (c_pairs))
  select coalesce(sum(case when rn > 1 then 1 else 0 end), 0),
         (select count(*) from public.workout_log_sets s join r k
             on k.n > 1 and k.rn = 1 and k.set_number <> 0
            and s.user_id = k.user_id and s.workout_log_id::text = k.workout_log_id
            and s.exercise_id = k.exercise_id and s.set_number > k.set_number)
    into c_exp_tomb, c_exp_sets
    from r where n > 1;
  c_exp_tomb := c_exp_tomb + cardinality(c_pairs);
  if (c_groups, c_live, c_tombs, c_wls, c_exp_tomb, c_exp_sets)
     is distinct from (b_groups, b_live, b_tombs, b_wls, b_exp_tomb, b_exp_sets) then
    v_mismatch := v_mismatch + 1;
    v_log := v_log || format(E'BASELINE CHANGED after phase (i): %s %s %s %s %s %s\n',
      c_groups, c_live, c_tombs, c_wls, c_exp_tomb, c_exp_sets);
  end if;

  -- (ii) the migration
  begin
    execute v_mig;
  exception when others then
    raise exception 'DRYRUN_MIGRATION_FAILED: % %', sqlerrm, v_log;
  end;
  select count(*) into a_groups from (
    select 1 from public.workout_log_exercises where deleted_at is null
     group by user_id, workout_log_id, exercise_id having count(*) > 1) g;
  select count(*) into a_tomb_now from public.workout_log_exercises where deleted_at = now();
  select count(*) into a_wls from public.workout_log_sets;
  v_log := v_log || format(E'migration: dup_groups_after=%s tombstoned=%s (expected %s) wls_deleted=%s (expected %s) oi312_pairs_live_after=%s\n',
    a_groups, a_tomb_now, b_exp_tomb, b_wls - a_wls, b_exp_sets,
    (select count(*) from public.workout_log_exercises where id = any (b_pairs) and deleted_at is null));
  if a_groups <> 0 or a_tomb_now <> b_exp_tomb or b_wls - a_wls <> b_exp_sets
     or exists (select 1 from public.workout_log_exercises where id = any (b_pairs) and deleted_at is null) then
    v_mismatch := v_mismatch + 1;
  end if;

  -- (iii) after the migration

  -- [after] N1, expected P
  v_err := null;
  begin
    begin
  -- pushes at counts 4 -> 7 -> 4 leave ONE live row: the last write.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N1 Bench Press';
    v_live int;
    v_reps int;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 7, 70)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 41)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    select count(*), max(reps) into v_live, v_reps
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_live <> 1 then
      raise exception 'FAIL N1: expected 1 live summary row after pushes 4 -> 7 -> 4, got %', v_live;
    end if;
    if v_reps is distinct from 41 then
      raise exception 'FAIL N1: the live row is not the last write (reps=%)', v_reps;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N1%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N1', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N2, expected P
  v_err := null;
  begin
    begin
  -- an IDENTICAL re-push of the current row (which migration 149's no-op
  -- suppression cancels as an UPDATE) still supersedes a stale live sibling:
  -- the trigger is BEFORE INSERT, so it fires on every upsert.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N2 Row';
    v_ts timestamptz := '2026-10-01 10:00:00+00';
    v_disabled boolean := false;
    v_live int;
    v_set int;
  begin
    -- Build the legacy state {3 stale, 4 current} as the owner, bypassing the
    -- new trigger when it exists (it would refuse to leave two live rows).
    if exists (select 1 from pg_trigger
                where tgrelid = 'public.workout_log_exercises'::regclass
                  and tgname = 'workout_log_exercises_single_live') then
      execute 'alter table public.workout_log_exercises disable trigger workout_log_exercises_single_live';
      v_disabled := true;
    end if;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 3, 30, v_ts),
           (v_user, v_w, v_ex, v_ex, 4, 40, v_ts);
    if v_disabled then
      execute 'alter table public.workout_log_exercises enable trigger workout_log_exercises_single_live';
    end if;

    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 4, 40, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps, completed_at = excluded.completed_at;
    select count(*), max(set_number) into v_live, v_set
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_live <> 1 or v_set is distinct from 4 then
      raise exception 'FAIL N2: identical re-push left % live row(s) (max set_number %); the stale sibling at 3 must be tombstoned', v_live, v_set;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N2%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N2', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N3, expected P
  v_err := null;
  begin
    begin
  -- count 7 -> 4, then the per-set push: per-set rows are exactly 1..4.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N3 Squat';
    v_sets int[];
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 7, 70)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 7) g
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 4) g
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    execute 'reset role';
    if v_sets is distinct from array[1, 2, 3, 4] then
      raise exception 'FAIL N3: per-set rows after 7 -> 4 are %, expected {1,2,3,4}', v_sets;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N3%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N3', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N4, expected P
  v_err := null;
  begin
    begin
  -- legacy gapped per-set numbers {1,2,4} at count 3: after a re-push of the
  -- summary AND the sets, the end state is {1,2,4} again (the sets push
  -- re-inserts its own numbers right after the summary push).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N4 Row';
    v_sets int[];
    v_round int;
  begin
    execute 'set local role authenticated';
    for v_round in 1 .. 2 loop
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
      values (v_user, v_w, v_ex, v_ex, 3, 30)
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set reps = excluded.reps;
      insert into public.workout_log_sets
        (user_id, workout_log_id, exercise_id, set_number, reps)
      select v_user, v_w::uuid, v_ex, g, 10 from unnest(array[1, 2, 4]) g
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set reps = excluded.reps;
    end loop;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    execute 'reset role';
    if v_sets is distinct from array[1, 2, 4] then
      raise exception 'FAIL N4: legacy gapped sets ended as %, expected {1,2,4}', v_sets;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N4%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N4', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N5, expected P
  v_err := null;
  begin
    begin
  -- a count-0 summary push (count unknown, legacy shape) supersedes the live
  -- row like any push but never deletes per-set rows: readers take every
  -- per-set row under a count-0 summary (L1a-2 U2(b)).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N5 Plank';
    v_sets int[];
    v_live int;
    v_live_set int;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 3, 30)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select v_user, v_w::uuid, v_ex, g, 10 from generate_series(1, 3) g
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 0, 0)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    select count(*), max(set_number) into v_live, v_live_set
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_sets is distinct from array[1, 2, 3] then
      raise exception 'FAIL N5: a count-0 push changed per-set rows to %, expected {1,2,3}', v_sets;
    end if;
    if v_live <> 1 or v_live_set is distinct from 0 then
      raise exception 'FAIL N5: after a count-0 push expected one live row at count 0, got % live (max set_number %)', v_live, v_live_set;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N5%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N5', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N6, expected P
  v_err := null;
  begin
    begin
  -- a non-uuid workout_log_id (legacy/fixture shape) pushes without error:
  -- the trigger casts the uuid COLUMN to text, never the text to uuid.
  declare
    v_w text := 'sqlv_nonuuid_wlog_' || left(gen_random_uuid()::text, 8);
    v_ex text := 'SQLV N6 Curl';
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 3, 30)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 5, 50)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    execute 'reset role';
  exception when others then
    raise exception 'FAIL N6: a non-uuid workout_log_id push raised % %', sqlstate, sqlerrm;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N6%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N6', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N7, expected P
  v_err := null;
  begin
    begin
  -- the push takes the per-key advisory transaction lock.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N7 Deadlift';
    v_key bigint;
    v_held int;
    v_ok boolean;
  begin
    v_key := hashtextextended(v_user::text || '|' || v_w || '|' || v_ex, 0);
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 2, 20)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    execute 'reset role';
    select count(*) into v_held
      from pg_locks
     where locktype = 'advisory'
       and pid = pg_backend_pid()
       and classid = ((v_key >> 32) & 4294967295)::oid
       and objid = (v_key & 4294967295)::oid
       and objsubid = 1;
    if v_held = 0 then
      raise exception 'FAIL N7: no advisory lock held for the pushed key';
    end if;
    -- the lock must be taken BEFORE the supersede statement (a lock taken
    -- after it serialises nothing); two-session order is not observable in
    -- one transaction, so this is a position pin on the installed body.
    select strpos(prosrc, 'pg_advisory_xact_lock') > 0
       and strpos(prosrc, 'pg_advisory_xact_lock') < strpos(prosrc, 'update public.workout_log_exercises')
      into v_ok
      from pg_proc
     where proname = 'workout_log_exercises_single_live'
       and pronamespace = 'public'::regnamespace;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL N7: single_live does not take its advisory lock before its UPDATE';
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N7%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N7', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N8, expected P
  v_err := null;
  begin
    begin
  -- key isolation of a PUSH (B-pass 2026-10-06): bystanders are the same
  -- user's other exercise in the same workout, the same exercise in another
  -- workout, and ANOTHER user's same exercise under the same (date-derived)
  -- workout_log_id. Run as the OWNER so RLS cannot mask a missing user_id
  -- predicate. Also pins the per-set boundary BEFORE the sets re-push
  -- (a `>=` or `<>` would show here, N3 re-inserts and cannot see it), and
  -- that an identical re-push keeps the row: same id, no new tombstone.
  declare
    v_w text := gen_random_uuid()::text;
    v_w2 text := gen_random_uuid()::text;
    v_ex text := 'SQLV N8 Press';
    v_by text := 'SQLV N8 Row';
    v_ts timestamptz := '2026-10-01 10:00:00+00';
    v_by_before uuid[];
    v_by_after uuid[];
    v_live int;
    v_live_id uuid;
    v_live_id2 uuid;
    v_tombs int;
    v_tombs2 int;
    v_sets int[];
    v_by_sets int;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 4, 40, v_ts),
           (v_user, v_w, v_by, v_by, 4, 40, v_ts),
           (v_user, v_w2, v_ex, v_ex, 4, 40, v_ts),
           (v_user2, v_w, v_ex, v_ex, 4, 40, v_ts);
    insert into public.workout_log_sets
      (user_id, workout_log_id, exercise_id, set_number, reps)
    select k.u, k.w::uuid, k.e, g, 10
      from (values (v_user, v_w, v_ex), (v_user, v_w, v_by),
                   (v_user, v_w2, v_ex), (v_user2, v_w, v_ex)) k(u, w, e),
           generate_series(1, 4) g;
    select array_agg(id order by id) into v_by_before
      from public.workout_log_exercises
     where deleted_at is null
       and ((user_id = v_user and workout_log_id = v_w and exercise_id = v_by)
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = v_ex)
         or (user_id = v_user2 and workout_log_id = v_w and exercise_id = v_ex));

    -- the push under test: count 4 -> 3, summary only (no sets re-push yet)
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 3, 30, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps, completed_at = excluded.completed_at;

    select count(*), max(id::text)::uuid into v_live, v_live_id
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    if v_live <> 1 then
      raise exception 'FAIL N8: the pushed key has % live rows after 4 -> 3, expected 1', v_live;
    end if;
    select array_agg(id order by id) into v_by_after
      from public.workout_log_exercises
     where deleted_at is null
       and ((user_id = v_user and workout_log_id = v_w and exercise_id = v_by)
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = v_ex)
         or (user_id = v_user2 and workout_log_id = v_w and exercise_id = v_ex));
    if v_by_after is distinct from v_by_before then
      raise exception 'FAIL N8: a push tombstoned a bystander summary row (live bystanders % -> %)', cardinality(v_by_before), coalesce(cardinality(v_by_after), 0);
    end if;
    select array_agg(set_number order by set_number) into v_sets
      from public.workout_log_sets
     where user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_ex;
    if v_sets is distinct from array[1, 2, 3] then
      raise exception 'FAIL N8: per-set rows of the pushed key after the 4 -> 3 summary push are %, expected {1,2,3}', v_sets;
    end if;
    select count(*) into v_by_sets
      from public.workout_log_sets
     where (user_id = v_user and workout_log_id = v_w::uuid and exercise_id = v_by)
        or (user_id = v_user and workout_log_id = v_w2::uuid and exercise_id = v_ex)
        or (user_id = v_user2 and workout_log_id = v_w::uuid and exercise_id = v_ex);
    if v_by_sets <> 12 then
      raise exception 'FAIL N8: bystander per-set rows were deleted (% of 12 left)', v_by_sets;
    end if;

    -- an identical re-push keeps the same row and writes no tombstone
    select count(*) into v_tombs
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is not null;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps, completed_at)
    values (v_user, v_w, v_ex, v_ex, 3, 30, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps, completed_at = excluded.completed_at;
    select max(id::text)::uuid into v_live_id2
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    select count(*) into v_tombs2
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is not null;
    if v_live_id2 is distinct from v_live_id or v_tombs2 <> v_tombs then
      raise exception 'FAIL N8: an identical re-push replaced the live row (id % -> %, tombstones % -> %)', v_live_id, v_live_id2, v_tombs, v_tombs2;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N8%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N8', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N9, expected P
  v_err := null;
  begin
    begin
  -- key isolation of a DRAIN (tombstone-shaped upsert): bystanders at the
  -- SAME count -- the same user's other exercise in the same workout, the
  -- same exercise in another workout, another user's same exercise under the
  -- same workout_log_id -- stay live; the drained row is tombstoned. Owner.
  declare
    v_w text := gen_random_uuid()::text;
    v_w2 text := gen_random_uuid()::text;
    v_ex text := 'SQLV N9 Press';
    v_by text := 'SQLV N9 Row';
    v_by_live int;
    v_live int;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 5, 50),
           (v_user, v_w, v_by, v_by, 5, 50),
           (v_user, v_w2, v_ex, v_ex, 5, 50),
           (v_user2, v_w, v_ex, v_ex, 5, 50);
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 5, now())
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    select count(*) into v_by_live
      from public.workout_log_exercises
     where deleted_at is null and set_number = 5
       and ((user_id = v_user and workout_log_id = v_w and exercise_id = v_by)
         or (user_id = v_user and workout_log_id = v_w2 and exercise_id = v_ex)
         or (user_id = v_user2 and workout_log_id = v_w and exercise_id = v_ex));
    if v_by_live <> 3 then
      raise exception 'FAIL N9: a drain tombstoned a bystander (% of 3 still live)', v_by_live;
    end if;
    select count(*) into v_live
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    if v_live <> 0 then
      raise exception 'FAIL N9: the drained row is still live (% live)', v_live;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N9%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N9', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N10, expected P
  v_err := null;
  begin
    begin
  -- the DRAIN path takes the same per-key advisory lock as a push (N7): a
  -- drain racing an in-flight push for the key must wait for it, or the
  -- delete is lost (B-pass 2026-10-06, observed with two sessions).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N10 Press';
    v_key bigint;
    v_held int;
    v_ok boolean;
  begin
    v_key := hashtextextended(v_user::text || '|' || v_w || '|' || v_ex, 0);
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 2, now())
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    execute 'reset role';
    select count(*) into v_held
      from pg_locks
     where locktype = 'advisory'
       and pid = pg_backend_pid()
       and classid = ((v_key >> 32) & 4294967295)::oid
       and objid = (v_key & 4294967295)::oid
       and objsubid = 1;
    if v_held = 0 then
      raise exception 'FAIL N10: a drain-shaped insert holds no advisory lock for its key';
    end if;
    select strpos(prosrc, 'pg_advisory_xact_lock') > 0
       and strpos(prosrc, 'pg_advisory_xact_lock') < strpos(prosrc, 'update public.workout_log_exercises')
      into v_ok
      from pg_proc
     where proname = 'workout_log_exercises_delete_final_rename'
       and pronamespace = 'public'::regnamespace;
    if not coalesce(v_ok, false) then
      raise exception 'FAIL N10: the delete trigger does not take its advisory lock before its UPDATE';
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N10%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N10', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N11, expected P
  v_err := null;
  begin
    begin
  -- a drain sent by ANOTHER authenticated user for this user's key changes
  -- nothing: the delete trigger runs SECURITY INVOKER, so its UPDATE is
  -- filtered by wle_update_own and the INSERT then fails WITH CHECK (42501).
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV N11 Press';
    v_victim uuid;
    v_state text;
  begin
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    returning id into v_victim;
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_user2, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      insert into public.workout_log_exercises
        (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
      values (v_user, v_w, v_ex, v_ex, 4, now())
      on conflict (user_id, workout_log_id, exercise_id, set_number)
        do update set exercise_name = excluded.exercise_name,
                      deleted_at = excluded.deleted_at;
    exception when insufficient_privilege then
      null;  -- expected: 42501 from WITH CHECK
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    select case when deleted_at is null then 'live' else 'tombstoned' end
      into v_state
      from public.workout_log_exercises where id = v_victim;
    if v_state is distinct from 'live' then
      raise exception 'FAIL N11: another user''s drain changed this user''s row (now %)', coalesce(v_state, 'missing');
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N11%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N11', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] N12, expected P
  v_err := null;
  begin
    begin
  -- both trigger functions run SECURITY INVOKER (RLS applies to their
  -- in-trigger statements; N11 is the behavioural proof for the delete
  -- function) with an empty search_path (every name schema-qualified).
  declare
    v_n int;
  begin
    select count(*) into v_n
      from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname in ('workout_log_exercises_delete_final_rename',
                       'workout_log_exercises_single_live')
       and not prosecdef
       and 'search_path=""' = any (proconfig);
    if v_n <> 2 then
      raise exception 'FAIL N12: % of 2 trigger functions are SECURITY INVOKER with an empty search_path', v_n;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL N12%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'N12', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] C1_4, expected P
  v_err := null;
  begin
    begin
  -- Cases 1-4 (migrations 150/151), run as the owner. Each case marker block
  -- is reused verbatim by the L1a-1 prod rolled-back dry-run harness.
  declare
  v_user_id uuid := v_user;
  v_wlog_id text := 'sql_verify_wlog_2026_09_28';
  v_id_a uuid := gen_random_uuid();
  v_id_b uuid := gen_random_uuid();
  v_exercise_id_after_update text;
  v_deleted_after_update timestamptz;
  v_row_count int;
  begin
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
  -- the exact suffix bytes (U+0020 U+2039 'del:' 8 hex U+203A, end of
  -- string): the apply-time strip regex of L1a-1 reads exactly this shape.
  if v_exercise_id_after_update !~ ('^SQL Verify Bench Press ' || chr(8249) || 'del:' || left(v_id_a::text, 8) || chr(8250) || '$') then
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

    -- 2026-10-06 (B-pass): without this, a missing row (NULL) passed both
    -- checks below vacuously.
    if v_exercise_id_after_insert is null then
      raise exception 'FAIL case 4: the tombstone-shaped INSERT left no row at all';
    end if;

    if v_exercise_id_after_insert = 'SQL Verify Squat' then
      raise exception 'FAIL case 4: a tombstone-shaped INSERT (deleted_at set) was NOT suffixed -- the natural key stays occupied unsuffixed, exactly OI-246 P1''s unfixed gap. Is migration 151 live?';
    end if;
    if v_exercise_id_after_insert !~ ('^SQL Verify Squat ' || chr(8249) || 'del:' || left(v_id_c::text, 8) || chr(8250) || '$') then
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
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL case%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'C1_4', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] C5, expected P
  v_err := null;
  begin
    begin
  -- L1a-1 (OI-312): a drain-shaped tombstone upsert at the SAME count as the
  -- live row tombstones THAT row and inserts nothing. Before L1a-1, 151
  -- suffixed the incoming row before the ON CONFLICT arbiter, so the live row
  -- stayed live next to a new suffixed tombstone (live probe 2026-10-06:
  -- live=1, tombstones=1). Run as `authenticated`, the installed APK's path.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV C5 Bench Press';
    v_ts timestamptz := '2026-10-02 10:00:00+00';
    v_live int;
    v_total int;
    v_tomb_ex text;
    v_tomb_at timestamptz;
    v_tomb_id uuid;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 4, v_ts)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    select count(*) filter (where deleted_at is null), count(*)
      into v_live, v_total
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w and exercise_name = v_ex;
    select id, exercise_id, deleted_at into v_tomb_id, v_tomb_ex, v_tomb_at
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w and exercise_name = v_ex
       and deleted_at is not null;
    execute 'reset role';
    if v_live <> 0 then
      raise exception 'FAIL C5: the drain at the live row''s count left % live row(s) -- the delete never reached it (OI-312)', v_live;
    end if;
    if v_total <> 1 then
      raise exception 'FAIL C5: expected the live row itself tombstoned (1 row in total), got % rows', v_total;
    end if;
    if v_tomb_ex !~ ('^' || v_ex || ' ' || chr(8249) || 'del:' || left(v_tomb_id::text, 8) || chr(8250) || '$') then
      raise exception 'FAIL C5: the tombstone''s exercise_id is not 151''s exact suffix shape: %', v_tomb_ex;
    end if;
    if v_tomb_at is distinct from v_ts then
      raise exception 'FAIL C5: the tombstone carries deleted_at % instead of the drain''s %', v_tomb_at, v_ts;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL C5%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'C5', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  -- [after] C6, expected P
  v_err := null;
  begin
    begin
  -- the documented same-count rule (L1a-1 section 5, residual R2): a drain at
  -- count 3 does NOT tombstone a live row at count 4.
  declare
    v_w text := gen_random_uuid()::text;
    v_ex text := 'SQLV C6 Row';
    v_live_set int;
  begin
    execute 'set local role authenticated';
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, reps)
    values (v_user, v_w, v_ex, v_ex, 4, 40)
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set reps = excluded.reps;
    insert into public.workout_log_exercises
      (user_id, workout_log_id, exercise_id, exercise_name, set_number, deleted_at)
    values (v_user, v_w, v_ex, v_ex, 3, now())
    on conflict (user_id, workout_log_id, exercise_id, set_number)
      do update set exercise_name = excluded.exercise_name,
                    deleted_at = excluded.deleted_at;
    select max(set_number) into v_live_set
      from public.workout_log_exercises
     where user_id = v_user and workout_log_id = v_w
       and exercise_name = v_ex and deleted_at is null;
    execute 'reset role';
    if v_live_set is distinct from 4 then
      raise exception 'FAIL C6: a drain at count 3 changed the live row at count 4 (live max set_number %)', v_live_set;
    end if;
  end;
  
    end;
    raise exception 'CASE_PASSED';
  exception when others then
    v_err := sqlerrm;
  end;
  v_got := case when v_err = 'CASE_PASSED' then 'P'
                when v_err like 'FAIL C6%' then 'F'
                else 'E' end;
  v_log := v_log || format(E'%s %s expect=P got=%s: %s\n', 'after', 'C6', v_got, v_err);
  if v_got <> 'P' then v_mismatch := v_mismatch + 1; end if;

  if v_mismatch = 0 then
    raise exception 'DRYRUN_OK %', E'\n' || v_log;
  end if;
  raise exception 'DRYRUN_MISMATCH (%) %', v_mismatch, E'\n' || v_log;
end
$harness$;
