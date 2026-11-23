#!/usr/bin/env bash
# test/sql/play_subscriptions_local.sh
#
# Local proof of migration 182 (OI-519). LOCAL ONLY: it creates and drops databases inside ONE docker container whose name must
# be on the allowlist below, and it never takes a host or URL argument, so it cannot reach the live project.
#
#   sh test/sql/play_subscriptions_local.sh            # build (if needed) + cases N on old and new + cases P on new + mutants
#
# Steps:
#   1. Container oi519-pgtest (public.ecr.aws/supabase/postgres:17.6.1.084, 127.0.0.1:54336) is started if absent.
#   2. Two databases from scratch: oi519_old = replica schema + 159 + 160 (the live bodies; md5 equal to live 2026-11-23),
#      oi519_new = the same + 182 (applied with --single-transaction, so its self-check DO block can abort it).
#   3. Cases N (no Play row) on BOTH databases: same assertions, so 182 changes nothing without a Play row (T-SQL1).
#      Cases P (Play rows) on oi519_new.
#   4. Two-session case S1: another session holds the user's users row FOR UPDATE; store_reward_fall_back must fail with 55P03
#      promptly and leave the deferral row 'pending' (the status flip is rolled back with the error).
#   5. Mutants: each one is a copy of 182 with ONE change, applied to a fresh copy of oi519_old; cases P must FAIL on every one.
set -eu

CONTAINER=oi519-pgtest
case "$CONTAINER" in oi519-pgtest) ;; *) echo "REFUSED: container not on the allowlist"; exit 2 ;; esac

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MIG159="$ROOT/supabase/migrations/159_referral_reward_on_conversion.sql"
MIG160="$ROOT/supabase/migrations/160_referral_hardening.sql"
# Before the live apply the migration lives as a draft in docs/plans (Gate 14 refuses an unapplied file in supabase/migrations).
MIG182="$ROOT/supabase/migrations/182_play_subscriptions.sql"
[ -f "$MIG182" ] || MIG182="$ROOT/docs/plans/2026-11-23-revenuecat-play-billing-51.migration-182-draft.sql"
REPLICA="$ROOT/test/sql/referral_pay_on_conversion_replica_schema.sql"
CASES="$ROOT/test/sql/play_subscriptions_local_cases.sql"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker start "$CONTAINER" >/dev/null
  else
    docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=oi519local -p 127.0.0.1:54336:5432 \
      public.ecr.aws/supabase/postgres:17.6.1.084 >/dev/null
  fi
  for _ in $(seq 1 60); do docker exec "$CONTAINER" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break; sleep 2; done
  sleep 5
fi

psql_db() { db=$1; shift; docker exec -i "$CONTAINER" psql -U postgres -h 127.0.0.1 -q -At -v ON_ERROR_STOP=1 -d "$db" "$@"; }

fresh_db() {  # fresh_db <name> [with182-file]
  psql_db postgres -c "drop database if exists $1" >/dev/null
  psql_db postgres -c "create database $1" >/dev/null
  psql_db "$1" < "$REPLICA" >/dev/null
  psql_db "$1" < "$MIG159" >/dev/null 2>&1
  psql_db "$1" --single-transaction < "$MIG160" >/dev/null 2>&1
  if [ $# -ge 2 ]; then psql_db "$1" --single-transaction < "$2" >/dev/null; fi
}

echo "[build] oi519_old (159 + 160) and oi519_new (+ 182)"
fresh_db oi519_old
fresh_db oi519_new "$MIG182"
psql_db oi519_old -c "select md5(prosrc) from pg_proc where proname = 'grant_referral_days'" | grep -qx 457ffc0cfebcf954abe50f121fc63a44 \
  || { echo "FAIL: oi519_old grant_referral_days is not the live body"; exit 1; }

echo "[cases] N on oi519_old";  psql_db oi519_old -v part=N < "$CASES" | tail -1
echo "[cases] N on oi519_new";  psql_db oi519_new -v part=N < "$CASES" | tail -1
echo "[cases] P on oi519_new";  psql_db oi519_new -v part=P < "$CASES" | tail -1

echo "[S1] fall-back meets a held users row"
psql_db oi519_new -c "delete from store_reward_deferrals; delete from users where id = '00000000-0000-4000-8000-0000000000ee';
  insert into users values ('00000000-0000-4000-8000-0000000000ee');
  insert into store_reward_deferrals (id, user_id, store, days) values ('55555555-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000ee', 'play', 7);" >/dev/null
psql_db oi519_new -c "begin; select 1 from users where id = '00000000-0000-4000-8000-0000000000ee' for update; select pg_sleep(4); commit;" >/dev/null &
HOLDER=$!
sleep 1
START=$(date +%s%N)
if psql_db oi519_new -c "select store_reward_fall_back('55555555-0000-4000-8000-000000000001', NULL)" > "$WORK/s1.out" 2>&1; then
  echo "FAIL S1: fall-back succeeded while the users row was held"; cat "$WORK/s1.out"; exit 1
fi
ELAPSED_MS=$(( ($(date +%s%N) - START) / 1000000 ))
grep -q "could not obtain lock" "$WORK/s1.out" || { echo "FAIL S1: expected 55P03"; cat "$WORK/s1.out"; exit 1; }
[ "$ELAPSED_MS" -lt 2000 ] || { echo "FAIL S1: waited ${ELAPSED_MS} ms (NOWAIT lost?)"; exit 1; }
wait "$HOLDER"
STATUS=$(psql_db oi519_new -c "select status from store_reward_deferrals where id = '55555555-0000-4000-8000-000000000001'")
[ "$STATUS" = "pending" ] || { echo "FAIL S1: row is '$STATUS' after the failed fall-back"; exit 1; }
psql_db oi519_new -c "delete from store_reward_deferrals; delete from users where id = '00000000-0000-4000-8000-0000000000ee'" >/dev/null
echo "S1 passed (55P03 in ${ELAPSED_MS} ms, row still pending)"

echo "[mutants] each must make cases P fail"
mutate() {  # mutate <name> <python-literal old> <python-literal new>
  python3 -I -c '
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert s.count(old) == 1, ("mutation anchor count", s.count(old), old)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
' "$MIG182" "$WORK/$1.sql" "$2" "$3"
  fresh_db oi519_mut "$WORK/$1.sql"
  if psql_db oi519_mut -v part=P < "$CASES" > "$WORK/$1.out" 2>&1; then
    echo "MUTANT SURVIVED: $1"; exit 1
  fi
  echo "killed $1: $(grep -m1 'ERROR' "$WORK/$1.out" | cut -c1-140)"
}
mutate M1_no_play_branch "       AND s.end_date > now()
  ) THEN" "       AND false
  ) THEN"
mutate M2_no_direct_guard "     AND s.store IS DISTINCT FROM 'play'  -- 182: never extend" "     AND true  -- mutant: never extend"
mutate M3_job_paid_razorpay_only "                OR (s.store = 'play' AND s.store_environment = 'PRODUCTION'))  -- 182: a PRODUCTION Play row is a payment" \
  "                OR false)  -- mutant"
mutate M4_redeem_sandbox_paid "            OR (store = 'play' AND store_environment = 'PRODUCTION'))  -- 182: a PRODUCTION Play row is paid; SANDBOX is not" \
  "            OR (store = 'play'))  -- mutant"
mutate M5_fallback_no_token "          OR (d.status IN ('in_flight', 'needs_check') AND d.claim_token = p_token))" \
  "          OR (d.status IN ('in_flight', 'needs_check')))"
mutate M6_upsert_no_stale_guard "   WHERE s.store_read_at <= excluded.store_read_at;" ";"
mutate M7_upsert_start_always_new "CASE WHEN s.status = 'active' THEN s.start_date ELSE excluded.start_date END" "excluded.start_date"
psql_db postgres -c "drop database if exists oi519_mut" >/dev/null
echo "ALL PASSED"
