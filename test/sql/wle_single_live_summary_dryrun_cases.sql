-- test/sql/wle_single_live_summary_dryrun_cases.sql
--
-- L1a-1 (docs/plans/coach-history-correctness-sync.md section 3, R5S-2,
-- R6S-1, R6S-3) -- the OI-312 repair (step 2a) and precondition cases.
-- NOT runnable on its own: these blocks are spliced, between their markers,
-- into the prod rolled-back dry-run harness
-- `test/sql/wle_single_live_summary_dryrun_harness.sql` (generated from the
-- marker blocks of this file and of the two live-verify files, so the text
-- that ran on prod is the committed text), which supplies `v_user` (the
-- fixture user) and `v_mig` (the migration text, sha256-checked). They run
-- ONLY in the harness's "before" phase: once the migration is live, step 3
-- makes the OI-312 shape (a live row next to a suffixed tombstone at the same
-- count) impossible to build.
--
-- Each fixture write runs in its own `begin ... exception when others then
-- raise; end;` block: only a block WITH an exception clause opens a
-- subtransaction, so each write gets its own, increasing xid, and the case
-- asserts the order (age(L.xmin) > age(T.xmin), distinct xmins) instead of
-- assuming it. The migration text is then EXECUTEd as the owner.
--
-- Mutations (recorded in the diagnose-doc): the migration text without step
-- 2a => R1 and R3 red, R2 green (the cleanup alone keeps L2, the youngest);
-- 2a without its age guard => R2 red (L2 tombstoned); the cleanup keeping
-- the OLDEST sibling => R5 red.
-- R6 pins the key predicates of the cleanup and of 2a (B-pass 2026-10-06),
-- R7 precondition (b), R8 the ALREADY_APPLIED guard. The harness supplies a
-- second real user as `v_user2`.

  -- >>> CASE R1
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
  -- <<< CASE R1

  -- >>> CASE R2
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
  -- <<< CASE R2

  -- >>> CASE R3
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
  -- <<< CASE R3

  -- >>> CASE R4
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
  -- <<< CASE R4

  -- >>> CASE R5
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
  -- <<< CASE R5

  -- >>> CASE R6
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
  -- <<< CASE R6

  -- >>> CASE R7
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
  -- <<< CASE R7

  -- >>> CASE R8
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
  -- <<< CASE R8

  -- >>> CASE R9
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
  -- <<< CASE R9

  -- >>> CASE R10
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
  -- <<< CASE R10

  -- >>> CASE R11
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
  -- <<< CASE R11

  -- >>> CASE R12
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
  -- <<< CASE R12
