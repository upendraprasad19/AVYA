#!/usr/bin/env bash
# Local rehearsal of the target-history migration (docs/plans/target-history-cloud.md)
# in a throwaway supabase/postgres container. Never touches prod.
#
# Fixture: public.users + a minimal public.user_profile with the live shape for
# what matters here (user_id NOT NULL UNIQUE FK, RLS with the four own-row
# policies, the trg_onboarding_required_fields trigger; read from pg_policies /
# pg_trigger on 2026-11-25). The SQL file is applied VERBATIM, twice, and each
# case runs as `authenticated` / `anon` with request.jwt.claims set, the way
# PostgREST calls an RPC.
#
# Usage: bash test/sql/target_history_merge_local.sh   (exit 0 = every case passed)
#        F190=<file> overrides the SQL under test (mutation runs).
set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
F190="${F190:-$HERE/target_history_merge_draft.sql}"
C="${THC_CONTAINER:-thc-pgtest}"
IMG="public.ecr.aws/supabase/postgres:17.6.1.084"
FAILS=0

cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; }
trap cleanup EXIT

[ -f "$F190" ] || { echo "MISSING FILE: $F190"; exit 2; }
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "image $IMG is not present locally (no pull attempted)"; exit 2; }

pg() { docker exec -i -e PGOPTIONS='-c client_min_messages=warning' "$C" psql -U postgres -X -q -v ON_ERROR_STOP=1 "$@"; }

docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" -e POSTGRES_PASSWORD=x "$IMG" >/dev/null || { echo "docker run failed"; exit 2; }
ok=0
for _ in $(seq 1 120); do
  if pg -c 'select 1' >/dev/null 2>&1; then ok=$((ok + 1)); [ "$ok" -ge 3 ] && break; else ok=0; fi
  sleep 1
done
[ "$ok" -ge 3 ] || { echo "postgres did not become ready"; exit 2; }

UA='aaaaaaaa-0000-0000-0000-00000000000a'
UB='bbbbbbbb-0000-0000-0000-00000000000b'
UC='cccccccc-0000-0000-0000-00000000000c'

pg <<SQL || { echo "fixture failed"; exit 2; }
CREATE TABLE public.users (id uuid PRIMARY KEY);
CREATE TABLE public.user_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  onboarding_completed_at timestamptz,
  date_of_birth date, gender text, height_cm numeric, current_weight_kg numeric,
  target_weight_kg numeric, primary_goal text, fitness_experience text,
  days_per_week int, equipment_access text,
  daily_calories int,
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT user_profile_user_id_unique UNIQUE (user_id)
);
ALTER TABLE public.user_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_profile_select_own ON public.user_profile FOR SELECT USING ((SELECT auth.uid()) = user_id);
CREATE POLICY user_profile_insert_own ON public.user_profile FOR INSERT WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY user_profile_update_own ON public.user_profile FOR UPDATE USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY user_profile_delete_own ON public.user_profile FOR DELETE USING ((SELECT auth.uid()) = user_id);
GRANT ALL ON public.user_profile TO authenticated, anon;
CREATE FUNCTION public.enforce_onboarding_required_fields() RETURNS trigger LANGUAGE plpgsql AS \$f\$
BEGIN
  IF NEW.onboarding_completed_at IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.onboarding_completed_at IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.date_of_birth IS NULL OR NEW.gender IS NULL OR NEW.height_cm IS NULL
     OR NEW.current_weight_kg IS NULL OR NEW.target_weight_kg IS NULL
     OR NEW.primary_goal IS NULL OR NEW.fitness_experience IS NULL
     OR NEW.days_per_week IS NULL OR NEW.equipment_access IS NULL THEN
    RAISE EXCEPTION 'onboarding_completed_with_missing_fields (user_id=%)', NEW.user_id USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END; \$f\$;
CREATE TRIGGER trg_onboarding_required_fields BEFORE INSERT OR UPDATE ON public.user_profile
  FOR EACH ROW EXECUTE FUNCTION enforce_onboarding_required_fields();
-- Supabase's default privileges grant EXECUTE on new public functions to anon and
-- authenticated directly; reproduce that so the REVOKE FROM anon is tested.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
INSERT INTO public.users VALUES ('$UA'), ('$UB'), ('$UC');
-- A: an incomplete profile row (onboarding not finished). B: a row with another column set.
-- C: NO user_profile row.
INSERT INTO public.user_profile (user_id) VALUES ('$UA');
INSERT INTO public.user_profile (user_id, daily_calories) VALUES ('$UB', 2100);
SQL

pg < "$F190" || { echo "the SQL failed to apply"; exit 2; }
pg < "$F190" || { echo "the SQL is not re-runnable"; exit 2; }

as_user() { # $1 role, $2 sub ('' for none), $3 sql
  local claims='{}'
  [ -n "$2" ] && claims="{\"sub\":\"$2\",\"role\":\"$1\"}"
  pg -t -A <<SQL
BEGIN;
SET LOCAL ROLE $1;
SELECT set_config('request.jwt.claims', '$claims', true);
SELECT set_config('request.jwt.claim.sub', '${2}', true);
$3
COMMIT;
SQL
}
call() { # $1 user, $2 json literal -> prints the function's boolean (t/f) or the error
  as_user authenticated "$1" "SELECT public.merge_target_history('$2'::jsonb);" 2>&1 | tail -1
}
raw() { # like call, but the whole output (error text included)
  as_user authenticated "$1" "SELECT public.merge_target_history('$2'::jsonb);" 2>&1
}
check() { # $1 name, $2 expected, $3 actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAILS=$((FAILS + 1)); fi
}
hist() { pg -t -A -c "select coalesce(target_history::text,'NULL') from public.user_profile where user_id='$1'"; }
# One line per entry: from:calories:at_ms
brief() { pg -t -A -c "select coalesce(string_agg((e->>'from')||':'||(e->>'calories')||':'||(e->>'at_ms'), ' ' order by ord),'') from public.user_profile, jsonb_array_elements(coalesce(target_history,'[]'::jsonb)) with ordinality as t(e,ord) where user_id='$1'"; }
reset() { pg -c "update public.user_profile set target_history = $2 where user_id='$1'" >/dev/null; }
E() { # from calories at_ms [strategy]
  printf '{"from":"%s","calories":%s,"protein":150,"carbs":200,"fat":70,"strategy":"%s","at_ms":%s}' "$1" "$2" "${4:-balanced}" "$3"
}

# C1 first write on a row with a NULL column.
check "C1 returns true" "t" "$(call "$UA" "[$(E 2026-01-05 2000 1000)]")"
check "C1 stored" "2026-01-05:2000:1000" "$(brief "$UA")"
check "C1 exact shape" '[{"fat": 70, "from": "2026-01-05", "at_ms": 1000, "carbs": 200, "protein": 150, "calories": 2000, "strategy": "balanced"}]' "$(hist "$UA")"

# C2 union by from, ordered by from whatever the supplied order.
call "$UA" "[$(E 2026-03-01 2300 3000),$(E 2026-02-01 2200 2000)]" >/dev/null
check "C2 union ordered by from" "2026-01-05:2000:1000 2026-02-01:2200:2000 2026-03-01:2300:3000" "$(brief "$UA")"

# C3 a SHORT supplied list never deletes stored entries (the e4a1b7 class).
call "$UA" "[$(E 2026-03-01 2300 3000)]" >/dev/null
check "C3 short list deletes nothing" "2026-01-05:2000:1000 2026-02-01:2200:2000 2026-03-01:2300:3000" "$(brief "$UA")"

# C4 same from: the supplied entry with the greater at_ms wins.
call "$UA" "[$(E 2026-02-01 2250 2500)]" >/dev/null
check "C4 supplied newer wins" "2026-01-05:2000:1000 2026-02-01:2250:2500 2026-03-01:2300:3000" "$(brief "$UA")"
# C5 same from: a supplied entry with a smaller at_ms loses.
call "$UA" "[$(E 2026-02-01 1111 2400)]" >/dev/null
check "C5 stored newer wins" "2026-01-05:2000:1000 2026-02-01:2250:2500 2026-03-01:2300:3000" "$(brief "$UA")"

# C6 tie on at_ms: the greater calories wins from EITHER side (convergence).
reset "$UA" "'[$(E 2026-02-01 2000 5000)]'::jsonb"
call "$UA" "[$(E 2026-02-01 2100 5000)]" >/dev/null
check "C6a tie: supplied greater wins" "2026-02-01:2100:5000" "$(brief "$UA")"
reset "$UA" "'[$(E 2026-02-01 2100 5000)]'::jsonb"
call "$UA" "[$(E 2026-02-01 2000 5000)]" >/dev/null
check "C6b tie: stored greater wins" "2026-02-01:2100:5000" "$(brief "$UA")"
# C6c tie on everything but strategy: the greater text wins, from either side.
reset "$UA" "'[$(E 2026-02-01 2000 5000 balanced)]'::jsonb"
call "$UA" "[$(E 2026-02-01 2000 5000 keto)]" >/dev/null
check "C6c tie: strategy keto over balanced" "keto" "$(pg -t -A -c "select target_history->0->>'strategy' from public.user_profile where user_id='$UA'")"
reset "$UA" "'[$(E 2026-02-01 2000 5000 keto)]'::jsonb"
call "$UA" "[$(E 2026-02-01 2000 5000 balanced)]" >/dev/null
check "C6d tie: stored keto kept" "keto" "$(pg -t -A -c "select target_history->0->>'strategy' from public.user_profile where user_id='$UA'")"

# C7 malformed elements are skipped while the valid ones land; nothing raises.
reset "$UA" "NULL"
BAD='"x", 7, null, [], {"from":"2026-02-31","calories":2000,"protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":"20260201","calories":2000,"protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-02","calories":"2000","protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-03","calories":2000,"protein":1,"carbs":1,"fat":1}, {"from":"2026-02-04","calories":0,"protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-05","calories":20001,"protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-06","calories":2000,"protein":2001,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-07","calories":2000,"protein":1,"carbs":-1,"fat":1,"at_ms":1}, {"from":"2026-02-08","calories":2000,"protein":1,"carbs":1,"fat":2001,"at_ms":1}, {"from":"2026-02-09","calories":2000,"protein":1,"carbs":1,"fat":1,"at_ms":-1}, {"from":"2026-02-10","calories":2000,"protein":1,"carbs":1,"fat":1,"at_ms":4102444800001}, {"from":"2026-02-11","calories":1e400,"protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":2026,"calories":2000,"protein":1,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-12","calories":2000,"protein":"1","carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-13","calories":2000,"protein":1,"carbs":"1","fat":1,"at_ms":1}, {"from":"2026-02-14","calories":2000,"protein":1,"carbs":1,"fat":"1","at_ms":1}, {"from":"2026-02-15","calories":2000,"protein":1,"carbs":1,"fat":1,"at_ms":"1"}, {"from":"2026-02-16","calories":2000,"protein":-1,"carbs":1,"fat":1,"at_ms":1}, {"from":"2026-02-17","calories":2000,"protein":1,"carbs":2001,"fat":1,"at_ms":1}, {"from":"2026-02-18","calories":2000,"protein":1,"carbs":1,"fat":-1,"at_ms":1}'
check "C7 returns true" "t" "$(call "$UA" "[$BAD, $(E 2026-01-05 2000 1000)]")"
check "C7 only the valid entry lands" "2026-01-05:2000:1000" "$(brief "$UA")"

# C8 bounds are inclusive; numbers are rounded; extra keys dropped; strategy cut / defaulted.
reset "$UA" "NULL"
call "$UA" '[{"from":"2026-01-01","calories":1,"protein":0,"carbs":0,"fat":0,"at_ms":0}, {"from":"2026-01-02","calories":20000,"protein":2000,"carbs":2000,"fat":2000,"at_ms":4102444800000,"strategy":"abcdefghijklmnopqrstuvwxyz0123456789","junk":{"a":1}}, {"from":"2026-01-03","calories":1999.6,"protein":150.4,"carbs":200,"fat":70,"at_ms":5,"strategy":7}]' >/dev/null
check "C8 inclusive bounds kept" "2026-01-01:1:0 2026-01-02:20000:4102444800000 2026-01-03:2000:5" "$(brief "$UA")"
check "C8 strategy cut to 32" "abcdefghijklmnopqrstuvwxyz012345" "$(pg -t -A -c "select target_history->1->>'strategy' from public.user_profile where user_id='$UA'")"
check "C8 extra key dropped" "f" "$(pg -t -A -c "select (target_history->1) ? 'junk' from public.user_profile where user_id='$UA'")"
check "C8 exactly seven keys" "7" "$(pg -t -A -c "select count(*) from public.user_profile, jsonb_object_keys(target_history->1) where user_id='$UA'")"
check "C8 non-string strategy defaults" "balanced" "$(pg -t -A -c "select target_history->2->>'strategy' from public.user_profile where user_id='$UA'")"
check "C8 protein rounded" "150" "$(pg -t -A -c "select target_history->2->>'protein' from public.user_profile where user_id='$UA'")"
check "C8 default at first" "balanced" "$(pg -t -A -c "select target_history->0->>'strategy' from public.user_profile where user_id='$UA'")"

# C9 future bound: IST today + 1 is kept, IST today + 2 is dropped.
reset "$UA" "NULL"
T1=$(pg -t -A -c "select to_char((now() at time zone 'Asia/Kolkata')::date + 1,'YYYY-MM-DD')")
T2=$(pg -t -A -c "select to_char((now() at time zone 'Asia/Kolkata')::date + 2,'YYYY-MM-DD')")
call "$UA" "[$(E "$T1" 2000 1),$(E "$T2" 2100 2)]" >/dev/null
check "C9 tomorrow kept, day after dropped" "$T1:2000:1" "$(brief "$UA")"
# C9b a stored future entry is dropped by the next merge too.
reset "$UA" "'[$(E "$T2" 2100 2)]'::jsonb"
call "$UA" "[$(E 2026-01-05 2000 1)]" >/dev/null
check "C9b stored far-future entry dropped" "2026-01-05:2000:1" "$(brief "$UA")"

# C10 cap: stored 400 + 1 newer supplied -> newest 400 (the OLDEST goes).
pg -c "update public.user_profile set target_history = (select jsonb_agg(jsonb_build_object('from', to_char(date '2024-01-01' + g,'YYYY-MM-DD'),'calories',2000,'protein',1,'carbs',1,'fat',1,'strategy','balanced','at_ms',g) order by g) from generate_series(0,399) g) where user_id='$UA'" >/dev/null
call "$UA" "[$(E 2025-12-31 2500 9)]" >/dev/null
check "C10 length stays 400" "400" "$(pg -t -A -c "select jsonb_array_length(target_history) from public.user_profile where user_id='$UA'")"
check "C10 oldest dropped" "2024-01-02" "$(pg -t -A -c "select target_history->0->>'from' from public.user_profile where user_id='$UA'")"
check "C10 newest kept" "2025-12-31" "$(pg -t -A -c "select target_history->399->>'from' from public.user_profile where user_id='$UA'")"
# C10b an OLDER supplied entry does not push out a newer stored one.
call "$UA" "[$(E 2023-06-01 2500 9)]" >/dev/null
check "C10b older supplied entry not kept" "2024-01-02" "$(pg -t -A -c "select target_history->0->>'from' from public.user_profile where user_id='$UA'")"

# C11 argument refusals change nothing.
reset "$UA" "'[$(E 2026-01-05 2000 1)]'::jsonb"
out=$(raw "$UA" '{"from":"2026-01-06"}'); case "$out" in *"must be a jsonb array"*) r=refused ;; *) r="accepted: $out" ;; esac
check "C11 object refused" "refused" "$r"
out=$(as_user authenticated "$UA" "SELECT public.merge_target_history(NULL);" 2>&1); case "$out" in *"must be a jsonb array"*) r=refused ;; *) r="accepted: $out" ;; esac
check "C11 NULL refused" "refused" "$r"
BIG=$(pg -t -A -c "select jsonb_agg(jsonb_build_object('from','2026-01-06','calories',2000,'protein',1,'carbs',1,'fat',1,'at_ms',g))::text from generate_series(1,401) g")
out=$(raw "$UA" "$BIG"); case "$out" in *"at most 400"*) r=refused ;; *) r="accepted" ;; esac
check "C11 401 elements refused" "refused" "$r"
B400=$(pg -t -A -c "select jsonb_agg(jsonb_build_object('from','2026-01-06','calories',2000,'protein',1,'carbs',1,'fat',1,'at_ms',g))::text from generate_series(1,400) g")
check "C11 400 elements accepted" "t" "$(call "$UA" "$B400")"
check "C11 400 same-day elements collapse to the newest" "2026-01-05:2000:1 2026-01-06:2000:400" "$(brief "$UA")"
check "C11 empty array returns false" "f" "$(call "$UA" "[]")"
check "C11 empty array changes nothing" "2026-01-05:2000:1 2026-01-06:2000:400" "$(brief "$UA")"

# C12 a stored non-array is treated as empty.
reset "$UA" "'{\"oops\":1}'::jsonb"
call "$UA" "[$(E 2026-01-05 2000 1)]" >/dev/null
check "C12 stored non-array replaced" "2026-01-05:2000:1" "$(brief "$UA")"

# C13 no user_profile row: false, and no row is created.
check "C13 no row returns false" "f" "$(call "$UC" "[$(E 2026-01-05 2000 1)]")"
check "C13 no row created" "0" "$(pg -t -A -c "select count(*) from public.user_profile where user_id='$UC'")"

# C14 another user's row is untouched; other columns of the caller's row too.
call "$UB" "[$(E 2026-01-07 1800 1)]" >/dev/null
check "C14 B stored" "2026-01-07:1800:1" "$(brief "$UB")"
check "C14 B other column untouched" "2100" "$(pg -t -A -c "select daily_calories from public.user_profile where user_id='$UB'")"
check "C14 A untouched by B" "2026-01-05:2000:1" "$(brief "$UA")"

# C15 privileges and mode.
out=$(as_user anon "" "SELECT public.merge_target_history('[]'::jsonb);" 2>&1); case "$out" in *"permission denied"*) r=denied ;; *) r="allowed: $out" ;; esac
check "C15 anon denied" "denied" "$r"
SIG='public.merge_target_history(jsonb)'
check "C15 ACL anon" "f" "$(pg -t -A -c "select has_function_privilege('anon','$SIG','execute')")"
check "C15 ACL authenticated" "t" "$(pg -t -A -c "select has_function_privilege('authenticated','$SIG','execute')")"
check "C15 no PUBLIC entry in proacl" "0" "$(pg -t -A -c "select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid='$SIG'::regprocedure and a.grantee=0")"
check "C15 SECURITY INVOKER" "f" "$(pg -t -A -c "select prosecdef from pg_proc where oid='$SIG'::regprocedure")"
check "C15 search_path pinned" "{\"search_path=public,pg_temp\"}" "$(pg -t -A -c "select replace(proconfig::text,' ','') from pg_proc where oid='$SIG'::regprocedure")"
out=$(as_user authenticated "" "SELECT public.merge_target_history('[]'::jsonb);" 2>&1); case "$out" in *"no authenticated user"*) r=refused ;; *) r="accepted: $out" ;; esac
check "C15 authenticated with no subject refused" "refused" "$r"

# C16 the onboarding trigger does not reject the update on a completed row.
pg -c "update public.user_profile set date_of_birth='1995-01-01', gender='m', height_cm=170, current_weight_kg=70, target_weight_kg=65, primary_goal='lose_fat', fitness_experience='beginner', days_per_week=4, equipment_access='gym', onboarding_completed_at=now() where user_id='$UB'" >/dev/null
check "C16 update on a completed row" "t" "$(call "$UB" "[$(E 2026-01-08 1900 2)]")"

# C17 two sessions at once: the second waits on the row lock and both entries land.
reset "$UA" "NULL"
( pg >/dev/null 2>&1 <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"$UA","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '$UA', true);
SELECT public.merge_target_history('[$(E 2026-05-01 2000 1)]'::jsonb);
SELECT pg_sleep(3);
COMMIT;
SQL
) &
sleep 1
t0=$(date +%s)
call "$UA" "[$(E 2026-05-02 2100 2)]" >/dev/null
t1=$(date +%s)
wait
check "C17 both concurrent merges land" "2026-05-01:2000:1 2026-05-02:2100:2" "$(brief "$UA")"
if [ $((t1 - t0)) -ge 1 ]; then echo "ok   C17 the second call waited for the lock"; else echo "FAIL C17 the second call did not wait ($((t1 - t0)) s)"; FAILS=$((FAILS + 1)); fi

echo "SUMMARY: fails=$FAILS"
[ "$FAILS" -eq 0 ]
