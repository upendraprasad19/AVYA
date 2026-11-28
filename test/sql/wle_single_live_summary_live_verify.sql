-- test/sql/wle_single_live_summary_live_verify.sql
--
-- L1a-1 (docs/plans/coach-history-correctness-sync.md, unit U1.4 + U1.5) --
-- live-Postgres verification of the `workout_log_exercises_single_live`
-- BEFORE INSERT trigger: one live summary row per
-- (user_id, workout_log_id, exercise_id), last push wins, per-set rows above
-- the new count removed, pushes for one key serialised by an advisory lock.
--
-- REQUIRES the L1a-1 migration (`NNN_wle_single_live_summary.sql`) to be live.
-- The whole file runs inside ONE transaction that ROLLBACKs at the end.
-- Fixture writes run as `authenticated` with `request.jwt.claims` for a real
-- user (RLS: wle_update_own, workout_log_sets_delete_own), each case under a
-- fresh random workout_log_id, so no real row is ever touched. The isolation
-- cases (N8, N9) run as the OWNER on purpose, so RLS cannot mask a missing
-- user_id predicate, and use a SECOND real user as a bystander.
--
-- Each case sits between `-- >>> CASE <id>` and `-- <<< CASE <id>` markers.
-- The prod rolled-back dry-run harness (L1a-1 §3, built from these markers)
-- runs the SAME case text before and after the migration. Expected outcome
-- BEFORE the migration (no trigger yet):
--   N1, N2, N3, N5, N7, N8, N9, N10, N12 -- FAIL with their own 'FAIL <id>:' message;
--   N4, N6, N11                     -- PASS (invariants the trigger must not break).
-- AFTER the migration every case must PASS.
-- Mutation evidence lives in the diagnose-doc.

begin;

do $$
declare
  v_user uuid;
  v_user2 uuid;
begin
  select u.id into v_user
    from public.users u
    join auth.users a on a.id = u.id
   order by u.id
   limit 1;
  select u.id into v_user2
    from public.users u
    join auth.users a on a.id = u.id
   where u.id <> v_user
   order by u.id
   limit 1;
  if v_user is null or v_user2 is null then
    raise exception 'NO_FIXTURE_USER';
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  -- >>> CASE N1
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
  -- <<< CASE N1

  -- >>> CASE N2
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
  -- <<< CASE N2

  -- >>> CASE N3
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
  -- <<< CASE N3

  -- >>> CASE N4
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
  -- <<< CASE N4

  -- >>> CASE N5
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
  -- <<< CASE N5

  -- >>> CASE N6
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
  -- <<< CASE N6

  -- >>> CASE N7
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
  -- <<< CASE N7

  -- >>> CASE N8
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
  -- <<< CASE N8

  -- >>> CASE N9
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
  -- <<< CASE N9

  -- >>> CASE N10
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
  -- <<< CASE N10

  -- >>> CASE N11
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
  -- <<< CASE N11

  -- >>> CASE N12
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
  -- <<< CASE N12

  raise notice 'workout_log_exercises_single_live: all 12 cases passed';
end $$;

rollback;
