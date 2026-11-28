#!/usr/bin/env bash
# test/sql/record_paid_subscription_local.sh
#
# The proof of migration 161 (public.record_paid_subscription, OI-341 Piece B1, plan docs/plans/oi341-piece-b-door.md section 3a).
# LOCAL ONLY: it COMMITS rows, truncates tables, creates and drops a schema and runs two sessions at once, so it must never be pointed
# at the live project. It needs the disposable replica of test/sql/referral_pay_on_conversion_replica_schema.sql with migrations 159,
# 160 and 161 applied, in a docker container. It REFUSES any container or database outside the allowlist below and any database
# without the replica marker table public.rpoc_replica_marker (the replica schema creates it LAST; a real project does not have it).
#
# BUILD THE REPLICA (once; nothing here touches a real project):
#   docker run -d --name rpoc-pgtest -e POSTGRES_PASSWORD=<anything> -p 127.0.0.1:54333:5432 public.ecr.aws/supabase/postgres:17.6.1.084
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d postgres -c 'create database rpoc_b1'
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d rpoc_b1 -v ON_ERROR_STOP=1 < test/sql/referral_pay_on_conversion_replica_schema.sql
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d rpoc_b1 -v ON_ERROR_STOP=1 < supabase/migrations/159_referral_reward_on_conversion.sql
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d rpoc_b1 -v ON_ERROR_STOP=1 --single-transaction < supabase/migrations/160_referral_hardening.sql
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d rpoc_b1 -v ON_ERROR_STOP=1 --single-transaction < supabase/migrations/161_record_paid_subscription.sql
#
# MUTATION RUNS. MIG161 points at the function file to (re)install before the cases run (default: the real migration). A mutation run
# copies the migration, edits ONE thing, runs this script with MIG161=<copy> and expects a named case to FAIL; the script reinstalls the
# real migration on exit, so the replica is never left mutated.
#
# Each case ASSERTS its outcome and states the mutation it kills.
#   R1  ordinary payment: no active row -> inserted, start within the call, end = start + 30 days exactly (365 for yearly).
#       Kills: days constants swapped; base := a constant.
#   R2  stacked: an active trial row (NULL payment id) ending in 5 days -> end = trial end + 30 days.
#       Kills: base := now (no stacking); bare <> instead of IS DISTINCT FROM (a NULL-payment-id row is then ignored).
#   R3  expired and cancelled rows are ignored: end = start + 30.  Kills: the status filter dropped. (The end_date > now filter is
#       EQUIVALENT: greatest(now, ...) clamps an expired end back to now.)
#   R4  replay: the same payment again -> inserted = false, the same stored end, one row.  Kills: the step-6 conflict path broken while
#       step 4 is also gone (step 4 alone is an EQUIVALENT fast path, see below).
#   R5  another user's payment id (committed) -> P0001 payment_owned_by_other_user, no row for the caller.  Kills: the step-4 check dropped.
#   R6  another user's payment id inserted by an UNLOCKED writer that commits while the call waits on ON CONFLICT -> P0001 from the
#       step-6 re-select.  Kills: the re-select ownership check dropped.
#   R7  bad plan, bad payment id, NULL user -> 22023, nothing inserted.  Kills: an argument check dropped.
#   R8  grants: anon and authenticated get 42501 'permission denied for FUNCTION record_paid_subscription' (the message is checked:
#       an executable function would still raise 42501 from the TABLE); service_role succeeds.  Kills: a REVOKE dropped.
#   R9  stored values: plan, status 'active', order id, signature are the arguments.  Kills: a column swapped or dropped.
#   R10 the instant is taken AFTER the lock: session 1 holds the key 2 s; session 2's stored start_date >= session 1's release instant.
#       Kills: now() instead of clock_timestamp(); the assignment moved above the lock.
#   R11 an active row ending at 'infinity' -> 22008 invalid_base_end_date, nothing inserted; and a row ending 9999-06-01 (base + 365
#       days would print a 5-digit year JS cannot parse) -> 22008 too.  Kills: the finiteness check dropped; the 366-day margin dropped.
#   R12 search_path: a schema earlier on the CALLER's path holds its own subscriptions table; the row still lands in public.
#       Kills: SET search_path dropped.
#   R13 the DO self-check: applying the migration with the authenticated REVOKE removed FAILS (single transaction) and leaves the
#       installed function untouched.  Kills: the DO block, or its authenticated clause, removed.
#   R14 lock_timeout: session 1 holds the key 9 s; session 2's call fails with 55P03 in 4.5 to 7 s.  Kills: SET lock_timeout dropped.
#   R15 TimeZone: under session TimeZone America/New_York a trial row ending 2099-03-07 12:00 UTC (the US change is 2099-03-08, a date
#       chosen so this test never goes red on a calendar day) -> end - trial end = 30 * 86400 s exactly.  Kills: SET TimeZone dropped.
#   R16 the re-select finds NO row (RLS seam: a temporary policy lets `authenticated` see only A's rows, hiding user B's committed pay_R16, so step 4 sees nothing,
#       the insert conflicts and DO NOTHING skips it) -> 40001 payment_row_vanished, retryable, not P0001.  Kills: the NOT FOUND branch
#       dropped.
#   C1  two DIFFERENT payments for one user queued behind a held key: ends trial+30 and trial+60, no overlap.  Kills: the lock dropped.
#   C2  (i) a referral grant holding the key, then a payment: the payment waits and stacks on (trial end + 7) -> trial + 37.
#   C3  (ii) a payment holding the key, then a referral grant under the key: the grant extends the PAID row -> its end + 7 = trial + 37.
#       Kills (C2, C3): a different lock key in the function (the 7 days are then absorbed in C3).
#   C4  (iii) a payment holding key(referrer) while the referral job runs: the job does not wait (try-lock), counts skipped_locked = 1,
#       and the next run credits.  Kills: the function's key differing from the job's.
#   EQUIVALENT (stated, not a case): the step-4 idempotency block as a whole (the step-6 conflict re-select returns the same stored row
#   or raises the same P0001; R5 still kills dropping only step 4's ownership check, which would return the other user's row), the
#   `end_date > now` base filter (clamped by greatest), and the `razorpay_payment_id IS DISTINCT FROM p_payment_id` exclusion in the base. The idempotency
#   check returns before the base is read whenever this payment's row is visible, and a row inserted by an unlocked writer after that
#   check makes the insert conflict and return the stored row, so the exclusion cannot change any result (it documents intent).
#
# USAGE:  test/sql/record_paid_subscription_local.sh [container=rpoc-pgtest] [database=rpoc_b1]
# EXIT:   0 all assertions held; 1 an assertion failed (the reason is printed); 2 setup problem.

set -u
CONTAINER="${1:-rpoc-pgtest}"
DB="${2:-rpoc_b1}"
REAL161="supabase/migrations/161_record_paid_subscription.sql"
MIG161="${MIG161:-$REAL161}"

if [ "$CONTAINER" != "rpoc-pgtest" ]; then echo "SETUP: refusing container '$CONTAINER' (only rpoc-pgtest)" >&2; exit 2; fi
case "$DB" in
  rpoc|rpoc_*) ;;
  *) echo "SETUP: refusing database '$DB' (allowlist: rpoc, rpoc_*)" >&2; exit 2 ;;
esac
if [ ! -f "$REAL161" ] || [ ! -f "$MIG161" ]; then echo "SETUP: run from the repository root ($REAL161 / $MIG161 not found)" >&2; exit 2; fi

TMP="$(mktemp -d)"
psql_() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$CONTAINER" psql -U postgres -h 127.0.0.1 -d "$DB" -v ON_ERROR_STOP=1 -qAt "$@"; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

cleanup() {
  psql_ -c "drop schema if exists rpsb_evil cascade" >/dev/null 2>&1
  psql_ -c "drop trigger if exists rpsb_slow_insert on public.subscriptions; drop function if exists public.rpsb_slow_insert()" >/dev/null 2>&1
  # Never leave a mutated function installed (dropped first, so the reinstall is a FRESH create, like a real first apply).
  psql_ -c "drop function if exists public.record_paid_subscription(uuid,text,text,text,text)" >/dev/null 2>&1
  psql_ --single-transaction < "$REAL161" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

if ! psql_ -c "select 1" >/dev/null 2>&1; then echo "SETUP: cannot reach $DB in container $CONTAINER" >&2; exit 2; fi
if [ "$(psql_ -c "select to_regclass('public.rpoc_replica_marker') is not null")" != "t" ]; then echo "SETUP: refusing, $DB has no public.rpoc_replica_marker (not the replica)" >&2; exit 2; fi
if [ "$(psql_ -c "select count(*) from public.users")" -gt 100 ]; then echo "SETUP: refusing, $DB has >100 users (not the replica)" >&2; exit 2; fi
if [ "$(psql_ -c "select to_regprocedure('public.referrer_summary()') is not null")" != "t" ]; then echo "SETUP: migration 160 is not applied in $DB" >&2; exit 2; fi
# Drop first: CREATE OR REPLACE KEEPS an existing function's ACL, so a mutant that drops a REVOKE would otherwise inherit the
# earlier install's revoked ACL and look correct. A fresh create gets Supabase's default privileges, exactly as a first apply does.
psql_ -c "drop function if exists public.record_paid_subscription(uuid,text,text,text,text)" >/dev/null || exit 2
if ! psql_ --single-transaction < "$MIG161" >/dev/null 2>"$TMP/install.err"; then echo "SETUP: installing $MIG161 failed:" >&2; cat "$TMP/install.err" >&2; exit 2; fi
# The function is SECURITY INVOKER, so it runs with service_role's own table privileges. On the live project Supabase's default
# privileges grant service_role ALL on public tables (read back live at plan step 6.2 before any writer depends on it); the replica
# schema does not model that grant, so it is given here, exactly as live has it, and nothing else.
psql_ -c "grant select, insert on public.subscriptions to service_role" >/dev/null || exit 2

FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }

reset_tables() { psql_ -c "truncate public.subscriptions, public.referral_redemptions, public.alerts" >/dev/null || exit 2; }

psql_ -c "insert into public.users (id) select gen_random_uuid() from generate_series(1, greatest(0, 30 - (select count(*) from public.users)))" >/dev/null || exit 2
mapfile -t U < <(psql_ -c "select id from public.users order by id limit 30")
if [ "${#U[@]}" -lt 30 ]; then echo "SETUP: need 30 replica users, found ${#U[@]}" >&2; exit 2; fi

# rps <user> <plan> <payment id> [order] [signature]: one call as service_role; prints "end|start|inserted" or the error on stderr.
rps() {
  psql_ -c "set role service_role; select out_end_date, out_start_date, out_inserted from public.record_paid_subscription('$1', '$2', '$3', '${4:-order_x}', '${5:-sig_x}')"
}
# sqlstate_of <sql>: run as service_role, print the SQLSTATE the statement raised (empty if it succeeded).
sqlstate_of() {
  psql_ -c "set role service_role; do \$t\$ begin execute \$q\$ $1 \$q\$; exception when others then raise warning 'STATE=%', sqlstate; end \$t\$" 2>&1 \
    | sed -n 's/.*STATE=\([0-9A-Z]*\).*/\1/p' | head -1
}
trial() { psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date) values ('$1', 'referral_trial', 'active', now() - interval '2 days', $2)" >/dev/null || exit 2; }
days_between() { psql_ -c "select extract(epoch from ($2::timestamptz - $1::timestamptz))"; }

# ---------------------------------------------------------------------------------------------------------------------
# R1 ordinary payment
reset_tables
A="${U[0]}"
T0=$(psql_ -c "select clock_timestamp()")
OUT="$(rps "$A" monthly pay_R1a)"
T1=$(psql_ -c "select clock_timestamp()")
IFS='|' read -r E S I <<<"$OUT"
SPAN=$(days_between "'$S'" "'$E'")
INSIDE=$(psql_ -c "select '$S'::timestamptz between '$T0'::timestamptz and '$T1'::timestamptz")
# Yearly on its own user: a second payment for A would correctly STACK on the monthly one.
OUTY="$(rps "${U[21]}" yearly pay_R1b)"; IFS='|' read -r EY SY IY <<<"$OUTY"
SPANY=$(days_between "'$SY'" "'$EY'")
echo "R1: monthly inserted=$I span=${SPAN}s start-inside-call=$INSIDE; yearly inserted=$IY span=${SPANY}s"
[ "$I" = "t" ] && [ "$SPAN" = "2592000.000000" ] && [ "$INSIDE" = "t" ] || fail "R1 monthly: expected inserted, end = start + 30 days, start inside the call (got $OUT)"
[ "$IY" = "t" ] && [ "$SPANY" = "31536000.000000" ] || fail "R1 yearly: expected end = start + 365 days (got $OUTY)"

# R2 stacked on a trial (NULL payment id)
reset_tables
A="${U[1]}"
trial "$A" "now() + interval '5 days'"
TE=$(psql_ -c "select end_date from public.subscriptions where user_id = '$A'")
OUT="$(rps "$A" monthly pay_R2)"; IFS='|' read -r E S I <<<"$OUT"
GAP=$(days_between "'$TE'" "'$E'")
echo "R2: trial end $TE -> paid end $E (gap ${GAP}s)"
[ "$I" = "t" ] && [ "$GAP" = "2592000.000000" ] || fail "R2 expected the paid end = trial end + 30 days (got gap $GAP, $OUT)"

# R3 expired and cancelled rows ignored
reset_tables
A="${U[2]}"
psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) values
  ('$A', 'monthly', 'active', now() - interval '40 days', now() - interval '1 day', 'pay_R3old'),
  ('$A', 'monthly', 'cancelled', now() - interval '5 days', now() + interval '25 days', 'pay_R3can')" >/dev/null || exit 2
OUT="$(rps "$A" monthly pay_R3)"; IFS='|' read -r E S I <<<"$OUT"
SPAN=$(days_between "'$S'" "'$E'")
echo "R3: span ${SPAN}s"
[ "$SPAN" = "2592000.000000" ] || fail "R3 expired/cancelled rows must not move the base (span $SPAN)"

# R4 replay
reset_tables
A="${U[3]}"
OUT1="$(rps "$A" monthly pay_R4)"; OUT2="$(rps "$A" monthly pay_R4)"
IFS='|' read -r E1 S1 I1 <<<"$OUT1"; IFS='|' read -r E2 S2 I2 <<<"$OUT2"
N=$(psql_ -c "select count(*) from public.subscriptions where razorpay_payment_id = 'pay_R4'")
echo "R4: first inserted=$I1, replay inserted=$I2, same end=$([ "$E1" = "$E2" ] && echo yes || echo no), rows=$N"
[ "$I1" = "t" ] && [ "$I2" = "f" ] && [ "$E1" = "$E2" ] && [ "$S1" = "$S2" ] && [ "$N" = "1" ] || fail "R4 a replay must return the stored row with inserted = false (got '$OUT1' then '$OUT2', rows $N)"

# R5 another user's payment id, committed
reset_tables
A="${U[4]}"; B="${U[5]}"
rps "$A" monthly pay_R5 >/dev/null || exit 2
ST=$(sqlstate_of "select * from public.record_paid_subscription('$B', 'monthly', 'pay_R5', 'o', 's')")
MSG=$(psql_ -c "set role service_role; select public.record_paid_subscription('$B', 'monthly', 'pay_R5', 'o', 's')" 2>&1 | grep -o 'payment_owned_by_other_user' | head -1)
NB=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$B'")
echo "R5: sqlstate=$ST message=$MSG rows-for-B=$NB"
[ "$ST" = "P0001" ] && [ "$MSG" = "payment_owned_by_other_user" ] && [ "$NB" = "0" ] || fail "R5 expected P0001 payment_owned_by_other_user and no row for the caller"

# R6 another user's id inserted by an unlocked writer that commits while the call waits on ON CONFLICT
reset_tables
A="${U[6]}"; B="${U[7]}"
(
  { echo "begin;"; echo "insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) values ('$A', 'monthly', 'active', now(), now() + interval '30 days', 'pay_R6');"; echo "select pg_sleep(2);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/r6h.err"
) &
H_PID=$!
sleep 0.6
R6_ERR="$(psql_ -c "set role service_role; select public.record_paid_subscription('$B', 'monthly', 'pay_R6', 'o', 's')" 2>&1 >/dev/null)"
wait "$H_PID"
NB=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$B'")
echo "R6: error='$(echo "$R6_ERR" | head -1)' rows-for-B=$NB"
case "$R6_ERR" in *payment_owned_by_other_user*) ;; *) fail "R6 expected payment_owned_by_other_user from the ON CONFLICT re-select, got '$R6_ERR'" ;; esac
[ "$NB" = "0" ] || fail "R6 the caller must have no row"

# R7 bad arguments
reset_tables
A="${U[8]}"
S1=$(sqlstate_of "select * from public.record_paid_subscription('$A', 'weekly', 'pay_R7', 'o', 's')")
S2=$(sqlstate_of "select * from public.record_paid_subscription('$A', 'monthly', 'pay_R7?x=1', 'o', 's')")
S3=$(sqlstate_of "select * from public.record_paid_subscription(NULL, 'monthly', 'pay_R7', 'o', 's')")
S4=$(sqlstate_of "select * from public.record_paid_subscription('$A', 'monthly', 'xpay_R7', 'o', 's')")
N=$(psql_ -c "select count(*) from public.subscriptions")
echo "R7: plan=$S1 id=$S2 user=$S3 prefix=$S4 rows=$N"
[ "$S1" = "22023" ] && [ "$S2" = "22023" ] && [ "$S3" = "22023" ] && [ "$S4" = "22023" ] && [ "$N" = "0" ] || fail "R7 every bad argument must raise 22023 and insert nothing"

# R8 grants
reset_tables
A="${U[9]}"
# The denial must be for the FUNCTION: a caller who can execute it would still get 42501 from the table (the function is
# SECURITY INVOKER and client roles have no table grant), so the SQLSTATE alone cannot tell a missing REVOKE apart.
r8_denial() {
  psql_ -c "set role $1; do \$t\$ begin perform public.record_paid_subscription('$A', 'monthly', 'pay_R8$1', 'o', 's'); exception when others then raise warning 'STATE=%|%', sqlstate, sqlerrm; end \$t\$" 2>&1 | sed -n 's/.*STATE=\([0-9A-Z]*\)|\(.*\)$/\1|\2/p' | head -1
}
DA="$(r8_denial anon)"; DU="$(r8_denial authenticated)"
GA=""; GU=""
case "$DA" in "42501|permission denied for function record_paid_subscription"*) GA=42501 ;; *) GA="other($DA)" ;; esac
case "$DU" in "42501|permission denied for function record_paid_subscription"*) GU=42501 ;; *) GU="other($DU)" ;; esac
GS="$(rps "$A" monthly pay_R8s | cut -d'|' -f3)"
echo "R8: anon=$GA authenticated=$GU service_role inserted=$GS"
[ "$GA" = "42501" ] && [ "$GU" = "42501" ] && [ "$GS" = "t" ] || fail "R8 anon and authenticated must get 42501 and service_role must succeed"

# R9 stored values
reset_tables
A="${U[10]}"
rps "$A" yearly pay_R9 order_R9 sig_R9 >/dev/null || exit 2
ROW=$(psql_ -c "select plan, status, razorpay_order_id, razorpay_signature, created_at = start_date from public.subscriptions where razorpay_payment_id = 'pay_R9'")
echo "R9: $ROW"
[ "$ROW" = "yearly|active|order_R9|sig_R9|t" ] || fail "R9 stored values wrong: $ROW"

# R10 the instant is taken after the lock
reset_tables
A="${U[11]}"
psql_ -c "drop table if exists public.rpsb_res; create table public.rpsb_res (released timestamptz)" >/dev/null
(
  { echo "begin;"; echo "select pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$A', 0));"; echo "select pg_sleep(2);"; echo "insert into public.rpsb_res values (clock_timestamp());"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/r10h.err"
) &
H_PID=$!
sleep 0.5
OUT="$(rps "$A" monthly pay_R10)"; IFS='|' read -r E S I <<<"$OUT"
wait "$H_PID"
AFTER=$(psql_ -c "select '$S'::timestamptz >= released from public.rpsb_res")
psql_ -c "drop table public.rpsb_res" >/dev/null
echo "R10: start $S taken after the holder released: $AFTER"
[ "$AFTER" = "t" ] || fail "R10 the stored start_date predates the lock release: the instant must be clock_timestamp() after the lock"

# R11 infinity base
reset_tables
A="${U[12]}"
psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date) values ('$A', 'referral_trial', 'active', now(), 'infinity')" >/dev/null || exit 2
ST=$(sqlstate_of "select * from public.record_paid_subscription('$A', 'monthly', 'pay_R11', 'o', 's')")
N=$(psql_ -c "select count(*) from public.subscriptions where razorpay_payment_id = 'pay_R11'")
echo "R11: sqlstate=$ST rows=$N"
[ "$ST" = "22008" ] && [ "$N" = "0" ] || fail "R11 an infinite base must raise 22008 and insert nothing"
reset_tables
psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date) values ('$A', 'referral_trial', 'active', now(), '9999-06-01 00:00:00+00')" >/dev/null || exit 2
ST=$(sqlstate_of "select * from public.record_paid_subscription('$A', 'yearly', 'pay_R11b', 'o', 's')")
N=$(psql_ -c "select count(*) from public.subscriptions where razorpay_payment_id = 'pay_R11b'")
echo "R11b: sqlstate=$ST rows=$N"
[ "$ST" = "22008" ] && [ "$N" = "0" ] || fail "R11b a base within 366 days of 9999-12-31 must raise 22008 (the end would need a 5-digit year)"

# R16 the re-select finds no row: retryable 40001, not an ownership refusal
reset_tables
A="${U[22]}"; B="${U[23]}"
psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) values ('$B', 'monthly', 'active', now(), now() + interval '30 days', 'pay_R16')" >/dev/null || exit 2
# The seam role is `authenticated` (this session may SET ROLE to it; creating a fresh role and granting it to the session crashes this
# replica image's role hook). Its own select policy sees only A's rows, and the extra grants are revoked straight after.
PRE_TBL=$(psql_ -c "select has_table_privilege('authenticated', 'public.subscriptions', 'SELECT') or has_table_privilege('authenticated', 'public.subscriptions', 'INSERT')")
[ "$PRE_TBL" = "f" ] || { echo "SETUP: R16 expects authenticated to hold no table grant on this replica (it would be revoked)" >&2; exit 2; }
psql_ -c "grant select, insert on public.subscriptions to authenticated; grant execute on function public.record_paid_subscription(uuid, text, text, text, text) to authenticated; create policy rpsb_r16_sel on public.subscriptions for select to authenticated using (user_id = '$A'); create policy rpsb_r16_ins on public.subscriptions for insert to authenticated with check (true)" >/dev/null || exit 2
ST=$(psql_ -c "set role authenticated; do \$t\$ begin perform public.record_paid_subscription('$A', 'monthly', 'pay_R16', 'o', 's'); exception when others then raise warning 'STATE=%', sqlstate; end \$t\$" 2>&1 | sed -n 's/.*STATE=\([0-9A-Z]*\).*/\1/p' | head -1)
NA=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$A'")
psql_ -c "drop policy rpsb_r16_sel on public.subscriptions; drop policy rpsb_r16_ins on public.subscriptions; revoke select, insert on public.subscriptions from authenticated; revoke execute on function public.record_paid_subscription(uuid, text, text, text, text) from authenticated" >/dev/null || exit 2
GRANTED=$(psql_ -c "select has_function_privilege('authenticated', 'public.record_paid_subscription(uuid, text, text, text, text)', 'EXECUTE')")
[ "$GRANTED" = "f" ] || { echo "SETUP: R16 left authenticated able to execute the function" >&2; exit 2; }
echo "R16: sqlstate=$ST caller rows=$NA"
[ "$ST" = "40001" ] && [ "$NA" = "0" ] || fail "R16 a vanished conflicting row must raise retryable 40001 and insert nothing (got $ST)"

# R12 search_path
reset_tables
A="${U[13]}"
psql_ -c "drop schema if exists rpsb_evil cascade; create schema rpsb_evil; create table rpsb_evil.subscriptions (like public.subscriptions including all); grant usage on schema rpsb_evil to service_role; grant all on rpsb_evil.subscriptions to service_role" >/dev/null || exit 2
psql_ -c "set role service_role; set search_path = rpsb_evil, public; select * from public.record_paid_subscription('$A', 'monthly', 'pay_R12', 'o', 's')" >/dev/null 2>"$TMP/r12.err"
NP=$(psql_ -c "select count(*) from public.subscriptions where razorpay_payment_id = 'pay_R12'")
NE=$(psql_ -c "select count(*) from rpsb_evil.subscriptions")
psql_ -c "drop schema rpsb_evil cascade" >/dev/null
echo "R12: public rows=$NP shadow rows=$NE"
[ "$NP" = "1" ] && [ "$NE" = "0" ] || fail "R12 the row must land in public.subscriptions whatever the caller's search_path"

# R13 the DO self-check aborts a half-revoked apply
BEFORE=$(psql_ -c "select md5(pg_get_functiondef('public.record_paid_subscription(uuid,text,text,text,text)'::regprocedure))")
grep -v 'FROM authenticated;' "$MIG161" > "$TMP/r13.sql"
psql_ -c "drop function public.record_paid_subscription(uuid,text,text,text,text)" >/dev/null || exit 2
if psql_ --single-transaction < "$TMP/r13.sql" >/dev/null 2>"$TMP/r13.err"; then R13_RC=0; else R13_RC=1; fi
EXISTS=$(psql_ -c "select to_regprocedure('public.record_paid_subscription(uuid,text,text,text,text)') is not null")
psql_ -c "drop function if exists public.record_paid_subscription(uuid,text,text,text,text)" >/dev/null || exit 2
psql_ --single-transaction < "$MIG161" >/dev/null || exit 2
AFTER=$(psql_ -c "select md5(pg_get_functiondef('public.record_paid_subscription(uuid,text,text,text,text)'::regprocedure))")
echo "R13: half-revoked apply rc=$R13_RC ($(grep -o 'self-check[^"]*' "$TMP/r13.err" | head -1)); function left behind=$EXISTS; reinstalled same=$([ "$BEFORE" = "$AFTER" ] && echo yes || echo no)"
[ "$R13_RC" = "1" ] && [ "$EXISTS" = "f" ] && grep -q 'authenticated can still execute' "$TMP/r13.err" || fail "R13 the self-check must abort an apply that leaves authenticated with EXECUTE"

# R14 lock_timeout
reset_tables
A="${U[14]}"
(
  { echo "begin;"; echo "select pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$A', 0));"; echo "select pg_sleep(9);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/r14h.err"
) &
H_PID=$!
sleep 0.5
T0=$(now_ms)
ST=$(sqlstate_of "select * from public.record_paid_subscription('$A', 'monthly', 'pay_R14', 'o', 's')")
MS=$(( $(now_ms) - T0 ))
wait "$H_PID"
echo "R14: sqlstate=$ST after ${MS} ms"
[ "$ST" = "55P03" ] && [ "$MS" -ge 4500 ] && [ "$MS" -le 7000 ] || fail "R14 a held key must time out with 55P03 after ~5 s (got '$ST' after $MS ms)"

# R15 TimeZone
reset_tables
A="${U[15]}"
trial "$A" "timestamptz '2099-03-07 12:00:00+00'"
OUT="$(psql_ -c "set role service_role; set timezone = 'America/New_York'; select extract(epoch from (out_end_date - timestamptz '2099-03-07 12:00:00+00')) from public.record_paid_subscription('$A', 'monthly', 'pay_R15', 'o', 's')")"
echo "R15: end - trial end = ${OUT}s under a New York session"
[ "$OUT" = "2592000.000000" ] || fail "R15 the 30 days must be 30 * 86400 s across the 2099-03-08 change (got $OUT)"

# C1 two different payments, forced to overlap: a replica-only BEFORE INSERT trigger sleeps 1.5 s on pay_C1a's insert, so
# pay_C1b (started 0.5 s later) reads the base while pay_C1a is still uncommitted. With the lock, pay_C1b waits and stacks.
reset_tables
A="${U[16]}"
trial "$A" "now() + interval '5 days'"
TE=$(psql_ -c "select end_date from public.subscriptions where user_id = '$A'")
psql_ >/dev/null <<'EOSQL' || exit 2
create or replace function public.rpsb_slow_insert() returns trigger language plpgsql as $f$
begin
  if new.razorpay_payment_id = 'pay_C1a' then perform pg_sleep(1.5); end if;
  return new;
end $f$;
drop trigger if exists rpsb_slow_insert on public.subscriptions;
create trigger rpsb_slow_insert before insert on public.subscriptions for each row execute function public.rpsb_slow_insert();
EOSQL
( rps "$A" monthly pay_C1a >"$TMP/c1a.out" 2>&1 ) & P1=$!
sleep 0.5
( rps "$A" monthly pay_C1b >"$TMP/c1b.out" 2>&1 ) & P2=$!
wait "$P1" "$P2"
psql_ -c "drop trigger rpsb_slow_insert on public.subscriptions; drop function public.rpsb_slow_insert()" >/dev/null
ENDS=$(psql_ -c "select string_agg(round(extract(epoch from (end_date - '$TE'::timestamptz)) / 86400.0)::text, ',' order by end_date) from public.subscriptions where user_id = '$A' and razorpay_payment_id is not null")
echo "C1: paid ends relative to the trial end, in days: $ENDS"
[ "$ENDS" = "30,60" ] || fail "C1 two queued payments must stack (30,60), got '$ENDS' ($(cat "$TMP/c1a.out" "$TMP/c1b.out" | tr '\n' ' '))"

# C2 (i) a referral grant holding the key, then a payment
reset_tables
A="${U[17]}"
trial "$A" "now() + interval '5 days'"
TE=$(psql_ -c "select end_date from public.subscriptions where user_id = '$A'")
(
  { echo "begin;"; echo "select pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$A', 0));"; echo "select private.grant_referral_days('$A', 7);"; echo "select pg_sleep(1.5);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c2h.err"
) &
H_PID=$!
sleep 0.4
OUT="$(rps "$A" monthly pay_C2)"; IFS='|' read -r E S I <<<"$OUT"
wait "$H_PID"
GAP=$(psql_ -c "select round(extract(epoch from ('$E'::timestamptz - '$TE'::timestamptz)) / 86400.0)")
echo "C2: grant first, then payment: paid end = trial end + $GAP days"
[ "$GAP" = "37" ] || fail "C2 the payment must stack on the extended trial (37), got $GAP"

# C3 (ii) a payment holding the key, then a referral grant under the key
reset_tables
A="${U[18]}"
trial "$A" "now() + interval '5 days'"
TE=$(psql_ -c "select end_date from public.subscriptions where user_id = '$A'")
(
  { echo "begin;"; echo "set role service_role;"; echo "select * from public.record_paid_subscription('$A', 'monthly', 'pay_C3', 'o', 's');"; echo "select pg_sleep(1.5);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c3h.err"
) &
H_PID=$!
sleep 0.4
psql_ -c "begin; select pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$A', 0)); select private.grant_referral_days('$A', 7); commit;" >/dev/null 2>"$TMP/c3g.err" || fail "C3 the grant failed: $(cat "$TMP/c3g.err")"
wait "$H_PID"
LATEST=$(psql_ -c "select round(extract(epoch from (max(end_date) - '$TE'::timestamptz)) / 86400.0) from public.subscriptions where user_id = '$A' and status = 'active'")
echo "C3: payment first, then grant: latest active end = trial end + $LATEST days"
[ "$LATEST" = "37" ] || fail "C3 the grant must extend the paid row (37); $LATEST means the 7 days were absorbed"

# C4 (iii) a payment holding key(referrer) while the referral job runs
reset_tables
R="${U[19]}"; F="${U[20]}"
psql_ >/dev/null <<EOF || exit 2
insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  values ('AVYA-RPSB', '$R', '$F', now() - interval '20 days', false, true);
insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  values ('$F', 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_C4friend');
EOF
(
  { echo "begin;"; echo "set role service_role;"; echo "select * from public.record_paid_subscription('$R', 'monthly', 'pay_C4ref', 'o', 's');"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c4h.err"
) &
H_PID=$!
sleep 0.6
T0=$(now_ms)
J1="$(psql_ -c "select private.process_referral_conversions()")"
MS=$(( $(now_ms) - T0 ))
wait "$H_PID"
J2="$(psql_ -c "select private.process_referral_conversions()")"
echo "C4: job during the payment's hold took ${MS} ms -> '$J1'; next run -> '$J2'"
[ "$MS" -lt 1500 ] || fail "C4 the job waited ${MS} ms behind the payment's lock"
case "$J1" in *'"skipped_locked": 1}'*) ;; *) fail "C4 expected skipped_locked = 1 while the payment held key(referrer), got '$J1'" ;; esac
case "$J2" in *'"credited": 1,'*) ;; *) fail "C4 the next run should credit the referrer, got '$J2'" ;; esac

echo
if [ "$FAIL" = "0" ]; then echo "SUMMARY ok: every case held (R1-R16, C1-C4)"; exit 0; fi
echo "SUMMARY FAILED"; exit 1
