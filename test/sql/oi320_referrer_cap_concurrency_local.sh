#!/usr/bin/env bash
# test/sql/oi320_referrer_cap_concurrency_local.sh
#
# The concurrency half of the OI-320 proof (migration 158). LOCAL ONLY: it COMMITS rows, truncates two tables and
# inserts then deletes users, so it must never be pointed at the live project. It needs the disposable replica of
# test/sql/oi320_referrer_cap_replica_schema.sql with migration 158 already applied, in a docker container. It REFUSES
# any container or database name outside the allowlist below, and any database without the replica marker table
# public.oi320_replica_marker (the replica schema creates it; a real project does not have it).
#
# BUILD THE REPLICA (once; the commands the author used, nothing here touches a real project):
#   docker run -d --name oi320-pgtest -e POSTGRES_PASSWORD=<anything> -p 127.0.0.1:54332:5432 \
#     public.ecr.aws/supabase/postgres:17.6.1.084
#   docker exec -i oi320-pgtest psql -U postgres -h 127.0.0.1 -d postgres -c 'create database oi320'
#   docker exec -i oi320-pgtest psql -U postgres -h 127.0.0.1 -d oi320 -v ON_ERROR_STOP=1 < test/sql/oi320_referrer_cap_replica_schema.sql
#   docker exec -i oi320-pgtest psql -U postgres -h 127.0.0.1 -d oi320 -v ON_ERROR_STOP=1 < supabase/migrations/158_referral_referrer_cap.sql
# (skip the last command to measure the OLD body: every assertion below is then expected to FAIL).
#
# WHY A SECOND FILE. test/sql/oi320_referrer_cap_live_verify.sql runs in ONE transaction, so it cannot show two
# sessions racing. Two races are real:
#
# PART 1 - same referrer. With the audit insert and the count in separate statements, two concurrent redemptions for
# one referrer both read 6 credited and both credit (8 credited).
#   * The referrer is seeded with 6 COMMITTED credited redemptions (one short of the cap) and NO subscription row, so
#     nothing but the advisory lock can make session B wait: with a subscription row, A's UPDATE would hold a row lock
#     that makes B wait anyway and the timing assertion would pass for the wrong reason (measured on the first draft).
#   * Session A opens a transaction, redeems (7th credit), then HOLDS the transaction open for HOLD_MS.
#   * Session B starts GAP_MS later and redeems for the same referrer.
#   With the lock, B must WAIT for A's commit, then sees 7 credited and is NOT credited:
#       B's elapsed time >= (HOLD_MS - GAP_MS) - slack, credited = 7, B's referee still holds a trial.
#   Without the lock B returns at once, reads 6 (A is uncommitted), credits: elapsed ~ 0, credited = 8.
#
# PART 1b - a SESSION-level lock leaks. Session A redeems in autocommit and then stays connected and idle; session B
# redeems for the same referrer 1 s later and must NOT wait. With pg_advisory_xact_lock (released at the end of A's
# statement) B returns at once; with pg_advisory_lock (held until A disconnects) B waits for A's session to end. Every
# earlier case passes with a session-level lock because each psql session ends right after its statement.
#
# PART 2 - mutual redemption (P redeems Q while Q redeems P). The previous function body took the two users'
# subscription row locks in opposite orders. MEASURED 2026-10-11 on the previous body, 2 clients x 3000 opposite-direction
# pairs: 51 `deadlock detected` (40P01) errors in one run and 2 in another; on migration 158, 0 in both. Two halves:
#   2a LOCK ORDER, deterministic. Users X and Y are picked so that key(X) < key(Y) (the advisory key the function derives
#      from a user id). A helper session HOLDS key(Y); the function is then called with Y as referrer, and again with X as
#      referrer. A function that takes the lower key first must be seen WAITING on key(Y) while HOLDING key(X) in BOTH
#      calls (pg_locks / pg_stat_activity). A single lock, or the two locks in referrer-first or referee-first order,
#      fails one of the two calls. This couples the test to the key formula in the function, on purpose.
#   2b STATISTICAL, supplementary. The race is a window of microseconds, so detection varies from run to run: pgbench
#      runs two clients over DL_PAIRS pairs (each pair: client 0 does P->Q, client 1 does Q->P), every error is caught
#      inside the helper and logged, and the assertion is zero errors with every redemption credited. A pass proves the
#      lock order only as far as the run was long; 2a is the pinned assertion.
#
# USAGE:  test/sql/oi320_referrer_cap_concurrency_local.sh [container=oi320-pgtest] [database=oi320]
# EXIT:   0 all assertions held; 1 an assertion failed (the reason is printed); 2 setup problem.

set -u
CONTAINER="${1:-oi320-pgtest}"
DB="${2:-oi320}"
HOLD_MS=4000
GAP_MS=1500
MIN_WAIT_MS=1500   # B must have waited at least this long (HOLD_MS - GAP_MS = 2500 expected, minus scheduling slack)
DL_PAIRS="${DL_PAIRS:-3000}"

if [ "$CONTAINER" != "oi320-pgtest" ]; then echo "SETUP: refusing container '$CONTAINER' (only oi320-pgtest)" >&2; exit 2; fi
case "$DB" in
  oi320|oi320m|oi320_*) ;;
  *) echo "SETUP: refusing database '$DB' (allowlist: oi320, oi320m, oi320_*)" >&2; exit 2 ;;
esac

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

psql_() { docker exec -i "$CONTAINER" psql -U postgres -h 127.0.0.1 -d "$DB" -v ON_ERROR_STOP=1 -qAt "$@"; }

if ! psql_ -c "select 1" >/dev/null 2>&1; then echo "SETUP: cannot reach $DB in container $CONTAINER" >&2; exit 2; fi
# Refuse anything that is not the disposable replica: it must carry the marker table, and be small.
if [ "$(psql_ -c "select to_regclass('public.oi320_replica_marker') is not null")" != "t" ]; then echo "SETUP: refusing, $DB has no public.oi320_replica_marker (not the replica)" >&2; exit 2; fi
if [ "$(psql_ -c "select count(*) from public.users")" -gt 100 ]; then echo "SETUP: refusing, $DB has >100 users (not the replica)" >&2; exit 2; fi
if ! psql_ -c "select pg_get_functiondef('public.redeem_referral_atomic(text,uuid,uuid,integer)'::regprocedure)" | grep -q "pg_advisory_xact_lock\|c_referrer_cap"; then
  echo "NOTE: the installed function has no cap/lock text; this run measures the OLD or a lock-less body." >&2
fi

FAIL=0

# ---------------------------------------------------------------------------------------------------------------------
# PART 1 - same referrer
# ---------------------------------------------------------------------------------------------------------------------
psql_ -c "truncate public.subscriptions, public.referral_redemptions" >/dev/null || exit 2
mapfile -t U < <(psql_ -c "select id from public.users order by id limit 10")
R="${U[0]}"
# 6 committed credited redemptions (the cap counts referrer_rewarded rows). NO subscription row for the referrer.
for i in 1 2 3 4 5 6; do
  psql_ -c "insert into public.referral_redemptions (code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded) values ('SEED', '$R', '${U[$i]}', 7, true, true)" >/dev/null || exit 2
done
EA="${U[7]}"; EB="${U[8]}"

# Session A: redeem, then hold the transaction open.
(
  {
    echo "begin;"
    echo "select public.redeem_referral_atomic('AVYA-CONC0001', '$R', '$EA', 7);"
    echo "select pg_sleep($(awk "BEGIN{print $HOLD_MS/1000}"));"
    echo "commit;"
  } | psql_ >/dev/null 2>"$TMP/a.err"
) &
A_PID=$!

sleep "$(awk "BEGIN{print $GAP_MS/1000}")"

# Session B: same referrer, timed.
T0=$(date +%s%N)
psql_ -c "select public.redeem_referral_atomic('AVYA-CONC0002', '$R', '$EB', 7)" >/dev/null 2>"$TMP/b.err"
B_RC=$?
T1=$(date +%s%N)
B_MS=$(( (T1 - T0) / 1000000 ))
wait "$A_PID"

CRED=$(psql_ -c "select count(*) from public.referral_redemptions where referrer_id = '$R' and referrer_rewarded")
A_FLAG=$(psql_ -c "select referrer_rewarded from public.referral_redemptions where referee_id = '$EA'")
B_FLAG=$(psql_ -c "select referrer_rewarded from public.referral_redemptions where referee_id = '$EB'")
B_TRIAL=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$EB' and plan = 'referral_trial' and status = 'active'")
R_END_DAYS=$(psql_ -c "select round(extract(epoch from (max(end_date) - now())) / 86400.0) from public.subscriptions where user_id = '$R' and status = 'active'")

echo "PART 1: B waited ${B_MS} ms (min ${MIN_WAIT_MS}); B rc=$B_RC; credited for the referrer=$CRED; A flag=$A_FLAG; B flag=$B_FLAG; B referee trial rows=$B_TRIAL; referrer end in ~${R_END_DAYS} days"

[ "$B_RC" -eq 0 ]            || { echo "FAIL: B's redemption errored: $(cat "$TMP/b.err")"; FAIL=1; }
[ "$B_MS" -ge "$MIN_WAIT_MS" ] || { echo "FAIL: B did not wait for A's lock (${B_MS} ms < ${MIN_WAIT_MS})"; FAIL=1; }
[ "$CRED" = "7" ]            || { echo "FAIL: expected exactly 7 credited, got $CRED (the race credited an 8th)"; FAIL=1; }
[ "$A_FLAG" = "t" ]          || { echo "FAIL: A (the 7th) should be credited"; FAIL=1; }
[ "$B_FLAG" = "f" ]          || { echo "FAIL: B (the 8th) should NOT be credited"; FAIL=1; }
[ "$B_TRIAL" = "1" ]         || { echo "FAIL: B's referee must still hold its trial"; FAIL=1; }
[ "$R_END_DAYS" = "7" ]      || { echo "FAIL: referrer should end ~7 days out (A's single credit), got $R_END_DAYS"; FAIL=1; }

# ---------------------------------------------------------------------------------------------------------------------
# PART 1b - a session-level lock leaks
# ---------------------------------------------------------------------------------------------------------------------
mapfile -t V < <(psql_ -c "select id from public.users order by id offset 10 limit 4")
R2="${V[0]}"; EA2="${V[1]}"; EB2="${V[2]}"
(
  {
    echo "select public.redeem_referral_atomic('AVYA-SESS0001', '$R2', '$EA2', 7);"
    echo "select pg_sleep(4);"
  } | psql_ >/dev/null 2>"$TMP/s_a.err"
) &
S_PID=$!
sleep 1
T0=$(date +%s%N)
psql_ -c "select public.redeem_referral_atomic('AVYA-SESS0002', '$R2', '$EB2', 7)" >/dev/null 2>"$TMP/s_b.err"
S_RC=$?
T1=$(date +%s%N)
S_MS=$(( (T1 - T0) / 1000000 ))
wait "$S_PID"
S_CRED=$(psql_ -c "select count(*) from public.referral_redemptions where referrer_id = '$R2' and referrer_rewarded")
echo "PART 1b: B (while A's session stays open and idle) took ${S_MS} ms; rc=$S_RC; credited=$S_CRED"
[ "$S_RC" -eq 0 ]    || { echo "FAIL: B errored: $(cat "$TMP/s_b.err")"; FAIL=1; }
[ "$S_MS" -lt 1000 ] || { echo "FAIL: B waited ${S_MS} ms behind an IDLE session: the lock is held past the end of the statement (session-level lock)"; FAIL=1; }
[ "$S_CRED" = "2" ]  || { echo "FAIL: both first-time referrals should be credited, got $S_CRED"; FAIL=1; }

# ---------------------------------------------------------------------------------------------------------------------
# PART 2a - lock order (deterministic)
# ---------------------------------------------------------------------------------------------------------------------
psql_ -c "truncate public.subscriptions, public.referral_redemptions" >/dev/null || exit 2
IFS='|' read -r X Y KX KY < <(psql_ -c "with k as (select id, hashtextextended('redeem_referral_atomic:' || id::text, 0) as k from public.users order by id limit 6) select a.id, b.id, a.k, b.k from k a, k b where a.k < b.k order by a.id, b.id limit 1")
if [ -z "${X:-}" ] || [ -z "${Y:-}" ]; then echo "SETUP: could not pick two users with ordered lock keys" >&2; exit 2; fi

# lock_probe <label> <referrer> <referee>: hold key(Y) from a helper session, call the function, and report whether the
# call is WAITING on advisory locks and HOLDING key(X) while it waits.
lock_probe() {
  local label="$1" referrer="$2" referee="$3"
  ( { echo "begin;"; echo "select pg_advisory_xact_lock($KY);"; echo "select pg_sleep(3.5);"; echo "commit;"; } | psql_ >/dev/null 2>&1 ) &
  local h_pid=$!
  sleep 1
  ( psql_ -c "select public.redeem_referral_atomic('AVYA-$label', '$referrer', '$referee', 7)" >/dev/null 2>"$TMP/$label.err" ) &
  local a_pid=$!
  sleep 1
  PROBE_WAIT=$(psql_ -c "select count(*) from pg_stat_activity where pid <> pg_backend_pid() and query like '%AVYA-$label%' and wait_event_type = 'Lock' and wait_event = 'advisory'")
  PROBE_HELD=$(psql_ -c "select count(*) from pg_locks l join pg_stat_activity a on a.pid = l.pid where a.pid <> pg_backend_pid() and a.query like '%AVYA-$label%' and l.locktype = 'advisory' and l.granted and ((l.classid::bigint << 32) | l.objid::bigint) = $KX")
  wait "$a_pid"; PROBE_RC=$?
  wait "$h_pid"
}
lock_probe LOCKORD1 "$Y" "$X"   # referrer holds the HIGHER key
P1_WAIT=$PROBE_WAIT; P1_HELD=$PROBE_HELD; P1_RC=$PROBE_RC
lock_probe LOCKORD2 "$X" "$Y"   # referrer holds the LOWER key
P2_WAIT=$PROBE_WAIT; P2_HELD=$PROBE_HELD; P2_RC=$PROBE_RC
echo "PART 2a: referrer=high key: waiting=$P1_WAIT holding-low-key=$P1_HELD rc=$P1_RC; referrer=low key: waiting=$P2_WAIT holding-low-key=$P2_HELD rc=$P2_RC"
[ "$P1_WAIT" = "1" ] && [ "$P1_HELD" = "1" ] || { echo "FAIL: with the referrer on the HIGHER key the call must hold the lower key while it waits for the higher (waiting=$P1_WAIT held=$P1_HELD): the locks are not taken lowest-key-first"; FAIL=1; }
[ "$P2_WAIT" = "1" ] && [ "$P2_HELD" = "1" ] || { echo "FAIL: with the referrer on the LOWER key the call must hold the lower key while it waits for the higher (waiting=$P2_WAIT held=$P2_HELD): both users' locks must be taken"; FAIL=1; }
[ "$P1_RC" = "0" ] && [ "$P2_RC" = "0" ] || { echo "FAIL: a probed redemption errored: $(cat "$TMP/LOCKORD1.err" "$TMP/LOCKORD2.err" 2>/dev/null)"; FAIL=1; }

# ---------------------------------------------------------------------------------------------------------------------
# PART 2b - mutual redemption (statistical, supplementary)
# ---------------------------------------------------------------------------------------------------------------------
psql_ -c "truncate public.subscriptions, public.referral_redemptions" >/dev/null || exit 2
psql_ >/dev/null <<EOF || exit 2
create table if not exists public.dl_pairs (k int primary key, p uuid not null, q uuid not null);
create table if not exists public.dl_log (k int, dir int, sqlstate text);
truncate public.dl_pairs, public.dl_log;
create temp table dl_new as select gen_random_uuid() as id, g as k, 'p' as side from generate_series(1, $DL_PAIRS) g
  union all select gen_random_uuid(), g, 'q' from generate_series(1, $DL_PAIRS) g;
insert into public.users (id) select id from dl_new;
insert into public.dl_pairs (k, p, q)
  select a.k, a.id, b.id from dl_new a join dl_new b on a.k = b.k and a.side = 'p' and b.side = 'q';
insert into public.subscriptions (user_id, plan, status, start_date, end_date)
  select p, 'referral_trial', 'active', now(), now() + interval '30 days' from public.dl_pairs
  union all select q, 'referral_trial', 'active', now(), now() + interval '30 days' from public.dl_pairs;
create or replace function public.dl_go(k int, dir int) returns void language plpgsql as \$f\$
declare v_p uuid; v_q uuid;
begin
  select p, q into v_p, v_q from public.dl_pairs where dl_pairs.k = dl_go.k;
  begin
    if dir = 0 then perform public.redeem_referral_atomic('DL', v_p, v_q, 7);
    else perform public.redeem_referral_atomic('DL', v_q, v_p, 7); end if;
  exception when others then
    insert into public.dl_log values (k, dir, sqlstate);
  end;
end \$f\$;
EOF
printf '\\set i :i + 1\nselect public.dl_go(:i, :client_id);\n' > "$TMP/bench.sql"
docker cp "$TMP/bench.sql" "$CONTAINER:/tmp/oi320_dl_bench.sql" >/dev/null || exit 2
docker exec "$CONTAINER" pgbench -h 127.0.0.1 -U postgres -n -f /tmp/oi320_dl_bench.sql -c 2 -j 2 -t "$DL_PAIRS" -D i=0 "$DB" >"$TMP/pgbench.out" 2>&1
PGB_RC=$?
DL_ERR=$(psql_ -c "select count(*) from public.dl_log")
DL_DEAD=$(psql_ -c "select count(*) from public.dl_log where sqlstate = '40P01'")
DL_ROWS=$(psql_ -c "select count(*) from public.referral_redemptions")
DL_CRED=$(psql_ -c "select count(*) from public.referral_redemptions where referrer_rewarded and referee_rewarded")
echo "PART 2b: pgbench rc=$PGB_RC; ${DL_PAIRS} pairs x 2 directions; errors=$DL_ERR (deadlocks=$DL_DEAD); redemptions=$DL_ROWS credited=$DL_CRED"

# Leave the replica as found: drop the helper objects, the audit rows and the users this part added. The audit rows go
# FIRST: with both user columns ON DELETE SET NULL (migration 158) deleting a user no longer deletes its audit row, so
# deleting only the users would leave one (NULL, NULL) row per redemption behind (hermes pass: 6000 rows by default).
psql_ >/dev/null <<EOF
delete from public.referral_redemptions where referrer_id in (select p from public.dl_pairs union select q from public.dl_pairs)
                                           or referee_id in (select p from public.dl_pairs union select q from public.dl_pairs);
delete from public.users where id in (select p from public.dl_pairs union select q from public.dl_pairs);
drop function if exists public.dl_go(int, int);
drop table if exists public.dl_pairs, public.dl_log;
EOF

[ "$PGB_RC" -eq 0 ]                                 || { echo "FAIL: pgbench did not complete: $(tail -3 "$TMP/pgbench.out")"; FAIL=1; }
[ "$DL_ERR" = "0" ]                                 || { echo "FAIL: $DL_ERR redemptions errored ($DL_DEAD deadlocks): mutual redemption must not deadlock"; FAIL=1; }
[ "$DL_ROWS" = "$(( DL_PAIRS * 2 ))" ]              || { echo "FAIL: expected $(( DL_PAIRS * 2 )) redemptions, got $DL_ROWS"; FAIL=1; }
[ "$DL_CRED" = "$(( DL_PAIRS * 2 ))" ]              || { echo "FAIL: every one of these is a first referral and must be credited, got $DL_CRED"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "CONCURRENCY OK"; exit 0; fi
exit 1
