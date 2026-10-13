#!/usr/bin/env bash
# test/sql/referral_pay_on_conversion_concurrency_local.sh
#
# The concurrency half of the proof of migration 159 (the referrer is rewarded when the friend PAYS). LOCAL ONLY: it COMMITS
# rows, truncates two tables, installs two test triggers, and inserts then deletes users, so it must never be pointed at the
# live project. It needs the disposable replica of test/sql/referral_pay_on_conversion_replica_schema.sql with migration 159
# already applied, in a docker container. It REFUSES any container or database name outside the allowlist below, and any
# database without the replica marker table public.rpoc_replica_marker (the replica schema creates it LAST; a real project
# does not have it).
#
# BUILD THE REPLICA (once; nothing here touches a real project):
#   docker run -d --name rpoc-pgtest -e POSTGRES_PASSWORD=<anything> -p 127.0.0.1:54333:5432 public.ecr.aws/supabase/postgres:17.6.1.084
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d postgres -c 'create database rpoc_a'
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d rpoc_a -v ON_ERROR_STOP=1 < test/sql/referral_pay_on_conversion_replica_schema.sql
#   docker exec -i rpoc-pgtest psql -U postgres -h 127.0.0.1 -d rpoc_a -v ON_ERROR_STOP=1 < supabase/migrations/159_referral_reward_on_conversion.sql
#
# WHY A SECOND FILE. test/sql/referral_pay_on_conversion_live_verify.sql runs in ONE transaction, so it cannot show two sessions
# racing or one session holding a lock. Every case below ASSERTS its outcome; each also states the mutation it kills.
#
#   C1 redemption vs credit (same user). Session A runs the job, which credits user U as a REFERRER, and holds its transaction
#      open. Session B redeems a code with U as the REFEREE 1.5 s later. B must WAIT (the job holds key(U); the redeem takes
#      it), then see A's committed row and EXTEND it: one subscription row for U, ~14 days out. Without the redeem's lock B
#      would not wait, would find no active row, and would INSERT a second one.  Kills: drop the redeem's advisory lock.
#   C2 two overlapping runs. A runs the job and holds; B runs the job: B returns {"skipped":"locked"} at once, and the
#      referrer is credited once.  Kills: drop the job-level try-lock.
#   C2b the stall watch runs BEFORE the job lock: a session holds the job's advisory lock, a reward has stood pending 11 days;
#      the overlapping run returns {skipped: locked} AND has written ONE warn `referral_conversions_stalled` alert; the row is
#      still pending.  Kills: move the stall watch after the lock (a zombie lock would then hide a stall), drop its dedup.
#   C3 another session holds key(referrer). The job must NOT wait: it returns in well under a second with skipped_locked = 1
#      and the row stays pending; after the holder commits, the next run credits it.  Kills: replace the referrer try-lock
#      with the blocking call.
#   C4 the helper meets a locked subscription row (another session holds the referrer's active row FOR UPDATE): 55P03,
#      counted as skipped_locked, no failed alert, prompt; the next run credits.  Kills: drop NOWAIT in the helper.
#   C5 an uncommitted DELETE of the referrer's users row, issued while the job is crediting that referrer (a test trigger
#      makes the grant slow so the order is deterministic): neither side gets 40P01 and the credit commits; the deleter
#      waits behind the job's key-share and then succeeds.  Kills: drop the FOR KEY SHARE NOWAIT pre-check (MEASURED: the
#      deleter's cascade waits for the row the job holds, the job's foreign-key check waits for the deleter: deadlock).
#   C5c the same with the referrer's users row held FOR UPDATE by another session (not the redemption row): skipped_locked,
#      prompt.  Kills: FOR KEY SHARE without NOWAIT.
#   C5d an ALREADY converted and vested redemption row held FOR UPDATE by another session (an account deletion's cascade):
#      the job returns promptly with credited = 0 and the referrer untouched; the next run credits.  Kills: drop SKIP LOCKED
#      from the credit select (C5b cannot: its row is not yet converted, so only the reconcile meets it).
#   C5e the referrer's users row held FOR NO KEY UPDATE (an ordinary UPDATE of a non-key column): the job still credits, promptly -
#      FOR KEY SHARE is compatible with it, FOR SHARE is not.  Kills: FOR KEY SHARE becomes FOR SHARE.
#   C6 the flag UPDATE matches no row (a BEFORE UPDATE trigger swallows it): the ROW_COUNT check raises, the grant is rolled
#      back, failed = 1, the referrer has NO new row, a failed alert is written; with the trigger gone the next run credits.
#      Kills: drop the ROW_COUNT = 1 check.
#   C7 the volume alert: exactly 20 redemptions in 24 hours raise nothing, 21 raise one warn alert (a second run writes no
#      second one); exactly 10 credits in one run raise nothing, 11 raise one.  Kills: flip > to >= on either threshold, drop
#      either dedup, put both alerts under one source.
#   C10 no SESSION-level advisory lock is left behind: one session runs the redeem RPC and the job as separate autocommit statements
#      and stays connected; a second session must be able to take the redeem key, the job key and the referrer key.  Kills: any
#      of the three xact locks becoming a session lock (pg_advisory_lock / pg_try_advisory_lock): a pooled backend would keep it.
#   C11 an alert that cannot be WRITTEN never undoes a credit: a trigger on public.alerts raises on every INSERT; the run has one
#      failing referrer, one stalled reward, one healthy referrer and 21 recent redemptions (so all three alert blocks try to write);
#      the job still returns and credits the healthy ones.  Kills: dropping the EXCEPTION clause of any alert block.
#   C12 the reconcile does not wait for a PAYMENT row: another session holds the friend's subscriptions row FOR UPDATE; the run
#      returns promptly and still reconciles and credits.  Kills: FOR UPDATE OF s in the lateral subquery.
#   C13 the batch cap: 55 vested pending rewards of one referrer: the first run credits exactly 50 (c_batch), the second the other 5.
#      Kills: dropping the LIMIT, raising the constant.
#   C8 a job run and a redemption of the same REFEREE do not deadlock under load: pgbench, 2 clients (job and redeem) over
#      DL_PAIRS users; zero errors other than the expected unique_violation / referee_has_paid_plan, every redemption audited.
#      STATISTICAL and supplementary (a pass proves the lock order only as far as the run was long).
#
# USAGE:  test/sql/referral_pay_on_conversion_concurrency_local.sh [container=rpoc-pgtest] [database=rpoc_a]
# EXIT:   0 all assertions held; 1 an assertion failed (the reason is printed); 2 setup problem.

set -u
CONTAINER="${1:-rpoc-pgtest}"
DB="${2:-rpoc_a}"
DL_PAIRS="${DL_PAIRS:-400}"

if [ "$CONTAINER" != "rpoc-pgtest" ]; then echo "SETUP: refusing container '$CONTAINER' (only rpoc-pgtest)" >&2; exit 2; fi
case "$DB" in
  rpoc|rpoc_*) ;;
  *) echo "SETUP: refusing database '$DB' (allowlist: rpoc, rpoc_*)" >&2; exit 2 ;;
esac

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

psql_() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$CONTAINER" psql -U postgres -h 127.0.0.1 -d "$DB" -v ON_ERROR_STOP=1 -qAt "$@"; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

if ! psql_ -c "select 1" >/dev/null 2>&1; then echo "SETUP: cannot reach $DB in container $CONTAINER" >&2; exit 2; fi
# Refuse anything that is not the disposable replica: it must carry the marker table, and be small.
if [ "$(psql_ -c "select to_regclass('public.rpoc_replica_marker') is not null")" != "t" ]; then echo "SETUP: refusing, $DB has no public.rpoc_replica_marker (not the replica)" >&2; exit 2; fi
if [ "$(psql_ -c "select count(*) from public.users")" -gt 100 ]; then echo "SETUP: refusing, $DB has >100 users (not the replica)" >&2; exit 2; fi
if [ "$(psql_ -c "select to_regprocedure('private.process_referral_conversions()') is not null")" != "t" ]; then echo "SETUP: migration 159 is not applied in $DB" >&2; exit 2; fi

FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }

reset_tables() {
  psql_ >/dev/null <<'EOF' || exit 2
drop trigger if exists rpoc_slow_grant on public.subscriptions;
drop trigger if exists rpoc_swallow_flag on public.referral_redemptions;
drop trigger if exists rpoc_alert_boom on public.alerts;
drop function if exists public.rpoc_alert_boom();
drop function if exists public.rpoc_slow_grant();
drop function if exists public.rpoc_swallow_flag();
truncate public.subscriptions, public.referral_redemptions, public.alerts;
EOF
}

# A user pool: the 30 replica users, ordered. U[0..] below. The script is re-runnable: a case that deletes a user (C5b) leaves the
# replica one short, so top it up to 30 first.
psql_ -c "insert into public.users (id) select gen_random_uuid() from generate_series(1, greatest(0, 30 - (select count(*) from public.users)))" >/dev/null || exit 2
mapfile -t U < <(psql_ -c "select id from public.users order by id limit 30")
if [ "${#U[@]}" -lt 30 ]; then echo "SETUP: need 30 replica users, found ${#U[@]}" >&2; exit 2; fi

# seed_pending <referrer> <referee> [plan=monthly] [payment_age_days=10]: a redemption 20 days old whose referee paid.
seed_pending() {
  local rr="$1" re="$2" plan="${3:-monthly}" age="${4:-10}"
  psql_ >/dev/null <<EOF || exit 2
insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  values ('AVYA-CONC', '$rr', '$re', now() - interval '20 days', false, true);
insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  values ('$re', '$plan', 'active', now() - interval '$age days', now() + interval '20 days', 'pay_conc_' || gen_random_uuid());
EOF
}

job() { psql_ -c "select private.process_referral_conversions()"; }

# ---------------------------------------------------------------------------------------------------------------------
# C1 - redemption vs credit, same user
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[0]}"; F="${U[1]}"; OTHER="${U[2]}"
seed_pending "$R" "$F"          # the job will credit R
(
  { echo "begin;"; echo "select private.process_referral_conversions();"; echo "select pg_sleep(4);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c1a.err"
) &
A_PID=$!
sleep 1.5
T0=$(now_ms)
psql_ -c "select public.redeem_referral_atomic('AVYA-C1', '$OTHER', '$R', 7)" >/dev/null 2>"$TMP/c1b.err"
B_RC=$?
B_MS=$(( $(now_ms) - T0 ))
wait "$A_PID"
C1_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
C1_DAYS=$(psql_ -c "select round(extract(epoch from (max(end_date) - min(start_date))) / 86400.0) from public.subscriptions where user_id = '$R'")
C1_FLAG=$(psql_ -c "select referrer_rewarded from public.referral_redemptions where referee_id = '$F'")
echo "C1: B waited ${B_MS} ms (min 1500); B rc=$B_RC; subscription rows for the user=$C1_ROWS; span ~${C1_DAYS} days; credited flag=$C1_FLAG"
[ "$B_RC" -eq 0 ]       || fail "C1 B's redemption errored: $(cat "$TMP/c1b.err")"
[ "$B_MS" -ge 1500 ]    || fail "C1 B did not wait for the job (${B_MS} ms): the redeem is not serialised against the job on the user's key"
[ "$C1_ROWS" = "1" ]    || fail "C1 expected ONE subscription row (B must extend the job's), got $C1_ROWS"
[ "$C1_DAYS" = "14" ]   || fail "C1 expected ~14 days (7 reward + 7 trial), got $C1_DAYS"
[ "$C1_FLAG" = "t" ]    || fail "C1 the job should have credited the pending row"

# ---------------------------------------------------------------------------------------------------------------------
# C2 - two overlapping runs
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[0]}"; F="${U[1]}"
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "select private.process_referral_conversions();"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c2a.err"
) &
A_PID=$!
sleep 1
T0=$(now_ms)
C2_RET="$(job 2>"$TMP/c2b.err")"
C2_MS=$(( $(now_ms) - T0 ))
wait "$A_PID"
C2_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
echo "C2: B returned '$C2_RET' in ${C2_MS} ms; referrer rows=$C2_ROWS"
case "$C2_RET" in *'"skipped": "locked"'*) ;; *) fail "C2 the overlapping run should return {skipped: locked}, got '$C2_RET' $(cat "$TMP/c2b.err")" ;; esac
[ "$C2_MS" -lt 1000 ]   || fail "C2 the overlapping run waited ${C2_MS} ms: the job-level lock must be a try-lock"
[ "$C2_ROWS" = "1" ]    || fail "C2 expected the referrer credited once (1 row), got $C2_ROWS"

# ---------------------------------------------------------------------------------------------------------------------
# C2b - the stall watch fires while ANOTHER session holds the job lock (it runs before the try-lock)
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[0]}"; F="${U[1]}"
seed_pending "$R" "$F"
psql_ -c "update public.referral_redemptions set converted_at = now() - interval '11 days', referrer_reward_days = 7 where referee_id = '$F'" >/dev/null || exit 2
(
  { echo "begin;"; echo "select pg_advisory_xact_lock(hashtextextended('process_referral_conversions', 0));"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c2bh.err"
) &
H_PID=$!
sleep 1
C2B_RET="$(job 2>"$TMP/c2b2.err")"
C2B_ALERTS=$(psql_ -c "select count(*) from public.alerts where source = 'referral_conversions_stalled' and severity = 'warn'")
C2B_FLAG=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$F'")
C2B_RET2="$(job 2>>"$TMP/c2b2.err")"   # still locked? (the holder sleeps 3 s: this may or may not overlap) - only the dedup is asserted below
C2B_ALERTS2=$(psql_ -c "select count(*) from public.alerts where source = 'referral_conversions_stalled'")
wait "$H_PID"
echo "C2b: run while the job lock is held -> '$C2B_RET'; stalled alerts=$C2B_ALERTS; row credited=$C2B_FLAG; a second run -> '$C2B_RET2', alerts after it=$C2B_ALERTS2"
case "$C2B_RET" in *'"skipped": "locked"'*) ;; *) fail "C2b the run during the lock hold should return {skipped: locked}, got '$C2B_RET' $(cat "$TMP/c2b2.err")" ;; esac
[ "$C2B_ALERTS" = "1" ]  || fail "C2b the stall watch must have written ONE warn alert before the lock check, got $C2B_ALERTS"
[ "$C2B_FLAG" = "f" ]    || fail "C2b nothing may be credited by a run that did not get the job lock"
[ "$C2B_ALERTS2" = "1" ] || fail "C2b a second run must be suppressed by the open alert (dedup), got $C2B_ALERTS2 alerts"

# ---------------------------------------------------------------------------------------------------------------------
# C3 - another session holds key(referrer): the job must not wait
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[0]}"; F="${U[1]}"
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "select pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$R', 0));"; echo "select pg_sleep(4);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c3h.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C3_RET="$(job 2>"$TMP/c3.err")"
C3_MS=$(( $(now_ms) - T0 ))
C3_FLAG=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$F'")
C3_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
wait "$H_PID"
C3_RET2="$(job 2>>"$TMP/c3.err")"
C3_FLAG2=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$F'")
echo "C3: run during the hold took ${C3_MS} ms -> '$C3_RET' (flag=$C3_FLAG rows=$C3_ROWS); run after the hold -> '$C3_RET2' (flag=$C3_FLAG2)"
[ "$C3_MS" -lt 1500 ]   || fail "C3 the job waited ${C3_MS} ms behind a held advisory lock: the referrer lock must be a try-lock"
case "$C3_RET" in *'"skipped_locked": 1'*) ;; *) fail "C3 expected skipped_locked = 1 during the hold, got '$C3_RET'" ;; esac
[ "$C3_FLAG" = "f" ] && [ "$C3_ROWS" = "0" ] || fail "C3 the row must stay pending and the referrer untouched during the hold (flag=$C3_FLAG rows=$C3_ROWS)"
case "$C3_RET2" in *'"credited": 1'*) ;; *) fail "C3 the next run should credit the row, got '$C3_RET2'" ;; esac
case "$C3_RET2" in *'"reconciled": 0'*) ;; *) fail "C3 the second run must change no column of the already-converted row (reconciled 0), got '$C3_RET2': the IS DISTINCT FROM guard is missing" ;; esac
[ "$C3_FLAG2" = "t" ]   || fail "C3 the row should be credited after the hold ended"

# ---------------------------------------------------------------------------------------------------------------------
# C4 - the helper meets a locked subscription row
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[0]}"; F="${U[1]}"
psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) values ('$R', 'monthly', 'active', now() - interval '5 days', now() + interval '25 days', 'pay_c4_' || gen_random_uuid())" >/dev/null || exit 2
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "select 1 from public.subscriptions where user_id = '$R' for update;"; echo "select pg_sleep(4);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c4h.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C4_RET="$(job 2>"$TMP/c4.err")"
C4_MS=$(( $(now_ms) - T0 ))
C4_ALERTS=$(psql_ -c "select count(*) from public.alerts where source = 'referral_conversions_failed'")
C4_FLAG=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$F'")
wait "$H_PID"
C4_RET2="$(job 2>>"$TMP/c4.err")"
C4_END=$(psql_ -c "select round(extract(epoch from (end_date - now())) / 86400.0) from public.subscriptions where user_id = '$R'")
echo "C4: run during the row lock took ${C4_MS} ms -> '$C4_RET' (failed alerts=$C4_ALERTS flag=$C4_FLAG); next run -> '$C4_RET2'; referrer ends in ~${C4_END} days"
[ "$C4_MS" -lt 1500 ]   || fail "C4 the job waited ${C4_MS} ms behind a row lock: the helper's read must be NOWAIT"
case "$C4_RET" in *'"skipped_locked": 1'*) ;; *) fail "C4 expected skipped_locked = 1, got '$C4_RET'" ;; esac
case "$C4_RET" in *'"failed": 0'*) ;; *) fail "C4 a held row is a skip, not a failure: '$C4_RET'" ;; esac
[ "$C4_ALERTS" = "0" ]  || fail "C4 no failed alert for a skipped row, got $C4_ALERTS"
[ "$C4_FLAG" = "f" ]    || fail "C4 the row must stay pending"
case "$C4_RET2" in *'"credited": 1'*) ;; *) fail "C4 the next run should credit, got '$C4_RET2'" ;; esac
case "$C4_RET2" in *'"reconciled": 0'*) ;; *) fail "C4 the second run must change no column of the already-converted row (reconciled 0), got '$C4_RET2'" ;; esac
[ "$C4_END" = "32" ]    || fail "C4 expected the paid row extended by 7 (25 + 7 = 32 days out), got $C4_END"

# ---------------------------------------------------------------------------------------------------------------------
# C5 - the job vs an account deletion of the referrer
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[3]}"; F="${U[4]}"
seed_pending "$R" "$F"
# A TEST trigger slows the job's grant INSERT (after it holds the redemption row and the users key-share) so the order is
# deterministic: job holds the redemption row -> deleter starts -> job's INSERT runs its foreign-key check.
psql_ >/dev/null <<'EOF' || exit 2
create function public.rpoc_slow_grant() returns trigger language plpgsql as $f$
begin
  if new.plan = 'referral_trial' then perform pg_sleep(3); end if;
  return new;
end $f$;
create trigger rpoc_slow_grant before insert on public.subscriptions for each row execute function public.rpoc_slow_grant();
EOF
(
  { echo "select private.process_referral_conversions();"; } | psql_ >"$TMP/c5job.out" 2>"$TMP/c5job.err"
) &
J_PID=$!
sleep 1
T0=$(now_ms)
psql_ -c "delete from public.users where id = '$R'" >/dev/null 2>"$TMP/c5del.err"
DEL_RC=$?
DEL_MS=$(( $(now_ms) - T0 ))
wait "$J_PID"
C5_OUT="$(cat "$TMP/c5job.out")"
C5_DEAD=$(cat "$TMP/c5job.err" "$TMP/c5del.err" | grep -c "deadlock detected" || true)
C5_FLAG=$(psql_ -c "select referrer_rewarded is true and referrer_id is null from public.referral_redemptions where referee_id = '$F'")
C5_GONE=$(psql_ -c "select count(*) from public.users where id = '$R'")
psql_ -c "drop trigger if exists rpoc_slow_grant on public.subscriptions; drop function if exists public.rpoc_slow_grant()" >/dev/null
echo "C5: job -> '$C5_OUT'; deleter rc=$DEL_RC after ${DEL_MS} ms; deadlocks=$C5_DEAD; row credited and orphaned=$C5_FLAG; referrer still present=$C5_GONE"
[ "$C5_DEAD" = "0" ]    || fail "C5 deadlock detected between the job and an account deletion: the key-share pre-check is missing or misplaced ($(cat "$TMP/c5job.err" "$TMP/c5del.err"))"
[ "$DEL_RC" -eq 0 ]     || fail "C5 the deletion errored: $(cat "$TMP/c5del.err")"
[ "$DEL_MS" -ge 1500 ]  || fail "C5 the deleter did not queue behind the job's key-share (${DEL_MS} ms): the pre-check holds no lock"
case "$C5_OUT" in *'"credited": 1'*) ;; *) fail "C5 the job should have credited the referrer before the deletion, got '$C5_OUT'" ;; esac
[ "$C5_FLAG" = "t" ]    || fail "C5 the row should be credited AND orphaned (referrer_id NULL) after the deletion"
[ "$C5_GONE" = "0" ]    || fail "C5 the referrer's account should be deleted"
# the uncommitted-delete half: the deleter goes first, the job must skip the locked row and finish promptly.
reset_tables
psql_ -c "insert into public.users (id) values ('$R') on conflict do nothing" >/dev/null || exit 2
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "delete from public.users where id = '$R';"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c5h.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C5B_RET="$(job 2>"$TMP/c5b.err")"
C5B_MS=$(( $(now_ms) - T0 ))
wait "$H_PID"
C5B_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
echo "C5b: job during an uncommitted deletion took ${C5B_MS} ms -> '$C5B_RET'; referrer rows=$C5B_ROWS"
[ "$C5B_MS" -lt 1500 ]  || fail "C5b the job waited ${C5B_MS} ms behind an uncommitted deletion"
case "$C5B_RET" in *'"credited": 0'*) ;; *) fail "C5b nothing may be credited to a referrer being deleted, got '$C5B_RET'" ;; esac
[ "$C5B_ROWS" = "0" ]   || fail "C5b the deleted referrer must hold no subscription row, got $C5B_ROWS"

# the users-row lock half: a session holds FOR UPDATE on the REFERRER's users row (not the redemption row), so the job's
# FOR KEY SHARE must not wait for it.
reset_tables
psql_ -c "insert into public.users (id) values ('$R') on conflict do nothing" >/dev/null || exit 2
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "select 1 from public.users where id = '$R' for update;"; echo "select pg_sleep(4);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c5ch.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C5C_RET="$(job 2>"$TMP/c5c.err")"
C5C_MS=$(( $(now_ms) - T0 ))
C5C_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
wait "$H_PID"
C5C_RET2="$(job 2>>"$TMP/c5c.err")"
echo "C5c: job while the referrer's users row is locked took ${C5C_MS} ms -> '$C5C_RET' (referrer rows=$C5C_ROWS); next run -> '$C5C_RET2'"
[ "$C5C_MS" -lt 1500 ]  || fail "C5c the job waited ${C5C_MS} ms for a lock on the referrer's users row: the key-share must be NOWAIT"
case "$C5C_RET" in *'"skipped_locked": 1'*) ;; *) fail "C5c expected skipped_locked = 1, got '$C5C_RET'" ;; esac
[ "$C5C_ROWS" = "0" ]   || fail "C5c nothing may be granted while the users row is held, got $C5C_ROWS rows"
case "$C5C_RET2" in *'"credited": 1'*) ;; *) fail "C5c the next run should credit, got '$C5C_RET2'" ;; esac

# the key-share half: the referrer's users row is held FOR NO KEY UPDATE (what an ordinary UPDATE of a non-key column takes). The job's
# FOR KEY SHARE NOWAIT is compatible with it, so the job must still credit and must not wait.
reset_tables
psql_ -c "insert into public.users (id) values ('$R') on conflict do nothing" >/dev/null || exit 2
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "select 1 from public.users where id = '$R' for no key update;"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c5eh.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C5E_RET="$(job 2>"$TMP/c5e.err")"
C5E_MS=$(( $(now_ms) - T0 ))
C5E_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
wait "$H_PID"
echo "C5e: job while the referrer's users row is held FOR NO KEY UPDATE took ${C5E_MS} ms -> '$C5E_RET' (referrer rows=$C5E_ROWS)"
[ "$C5E_MS" -lt 1500 ]  || fail "C5e the job waited ${C5E_MS} ms behind a FOR NO KEY UPDATE on the referrer's users row"
case "$C5E_RET" in *'"credited": 1'*) ;; *) fail "C5e FOR KEY SHARE is compatible with FOR NO KEY UPDATE: the job must credit, got '$C5E_RET'" ;; esac
[ "$C5E_ROWS" = "1" ]   || fail "C5e the referrer should hold one subscription row, got $C5E_ROWS"

# the credit-select half: the redemption row is ALREADY converted and vested (so the credit loop, not only the reconcile, meets
# it) and another session holds that ROW (as an account deletion's cascade does). The reconcile and the credit select both
# skip a locked row; only the credit select is under test here.
reset_tables
psql_ -c "insert into public.users (id) values ('$R') on conflict do nothing" >/dev/null || exit 2
seed_pending "$R" "$F"
psql_ -c "update public.referral_redemptions set converted_at = (select start_date from public.subscriptions where user_id = '$F'), referrer_reward_days = 7 where referee_id = '$F'" >/dev/null || exit 2
(
  { echo "begin;"; echo "select 1 from public.referral_redemptions where referee_id = '$F' for update;"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c5dh.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C5D_RET="$(job 2>"$TMP/c5d.err")"
C5D_MS=$(( $(now_ms) - T0 ))
C5D_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
wait "$H_PID"
C5D_RET2="$(job 2>>"$TMP/c5d.err")"
echo "C5d: job while a converted+vested row is held took ${C5D_MS} ms -> '$C5D_RET' (referrer rows=$C5D_ROWS); next run -> '$C5D_RET2'"
[ "$C5D_MS" -lt 1500 ]  || fail "C5d the job waited ${C5D_MS} ms behind a held, already-converted redemption row: the credit select must be SKIP LOCKED"
case "$C5D_RET" in *'"credited": 0'*) ;; *) fail "C5d nothing may be credited while the row is held, got '$C5D_RET'" ;; esac
[ "$C5D_ROWS" = "0" ]   || fail "C5d nothing may be granted while the row is held, got $C5D_ROWS rows"
case "$C5D_RET2" in *'"credited": 1'*) ;; *) fail "C5d the next run should credit the row, got '$C5D_RET2'" ;; esac

# ---------------------------------------------------------------------------------------------------------------------
# C10 - no session-level advisory lock survives a statement
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R10="${U[10]}"; F10="${U[11]}"; R11="${U[12]}"; F11="${U[13]}"
seed_pending "$R11" "$F11"
(
  { echo "select public.redeem_referral_atomic('AVYA-C10', '$R10', '$F10', 7);"; echo "select private.process_referral_conversions();"; echo "select pg_sleep(3);"; } | psql_ >/dev/null 2>"$TMP/c10h.err"
) &
H_PID=$!
sleep 1.5
C10_KEYS=$(psql_ <<SQLEND
begin;
select pg_try_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$F10', 0))::text
  || ',' || pg_try_advisory_xact_lock(hashtextextended('process_referral_conversions', 0))::text
  || ',' || pg_try_advisory_xact_lock(hashtextextended('redeem_referral_atomic:$R11', 0))::text;
commit;
SQLEND
)
wait "$H_PID"
C10_FLAG=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$F11'")
echo "C10: a second session tried the redeem key, the job key and the referrer key while the first stayed connected -> '$C10_KEYS' (job credited the pending row: $C10_FLAG)"
[ "$C10_FLAG" = "t" ]              || fail "C10 setup: the job should have credited the pending row, flag=$C10_FLAG $(cat "$TMP/c10h.err")"
[ "$C10_KEYS" = "true,true,true" ] || fail "C10 a session-level advisory lock survived its statement (redeem, job, referrer keys -> '$C10_KEYS'): a pooled backend would keep it for good"

# ---------------------------------------------------------------------------------------------------------------------
# C11 - an alert that cannot be written never undoes a credit
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
RA="${U[14]}"; FA="${U[15]}"; RB="${U[16]}"; FB="${U[17]}"; RC="${U[18]}"; FC="${U[19]}"
seed_pending "$RA" "$FA"          # healthy
seed_pending "$RC" "$FC"          # stalled: converted 12 days ago, still pending, creditable
psql_ -c "update public.referral_redemptions set converted_at = now() - interval '12 days', referrer_reward_days = 7 where referee_id = '$FC'" >/dev/null || exit 2
seed_pending "$RB" "$FB"          # failing: the referrer's active row ends at the largest timestamp, so + 7 days raises 22008
psql_ -c "insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) values ('$RB', 'monthly', 'active', now() - interval '5 days', '294276-12-31 00:00:00+00', 'pay_c11_' || gen_random_uuid())" >/dev/null || exit 2
psql_ >/dev/null <<'SQLEND' || exit 2
insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  select 'AVYA-C11', NULL, NULL, now() - interval '1 hour', false, true from generate_series(1, 21);
create function public.rpoc_alert_boom() returns trigger language plpgsql as $f$
begin raise exception 'rpoc: the alert cannot be written'; end $f$;
create trigger rpoc_alert_boom before insert on public.alerts for each row execute function public.rpoc_alert_boom();
SQLEND
C11_RET="$(job 2>"$TMP/c11.err")"
C11_RC=$?
C11_ALERTS=$(psql_ -c "select count(*) from public.alerts")
C11_A=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$FA'")
C11_C=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$FC'")
C11_B=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$FB'")
psql_ -c "drop trigger if exists rpoc_alert_boom on public.alerts; drop function if exists public.rpoc_alert_boom()" >/dev/null
echo "C11: job with every alert INSERT raising -> rc=$C11_RC '$C11_RET'; alerts written=$C11_ALERTS; healthy credited=$C11_A; stalled credited=$C11_C; failing credited=$C11_B"
[ "$C11_RC" -eq 0 ]       || fail "C11 the job itself failed because an alert could not be written: $(cat "$TMP/c11.err")"
case "$C11_RET" in *'"credited": 2'*) ;; *) fail "C11 the two creditable rows must still be credited, got '$C11_RET'" ;; esac
case "$C11_RET" in *'"failed": 1'*) ;; *) fail "C11 the failing row should be counted failed, got '$C11_RET'" ;; esac
[ "$C11_ALERTS" = "0" ]   || fail "C11 the trigger should have refused every alert, got $C11_ALERTS rows"
[ "$C11_A" = "t" ] && [ "$C11_C" = "t" ] && [ "$C11_B" = "f" ] || fail "C11 credited flags wrong (healthy=$C11_A stalled=$C11_C failing=$C11_B)"

# ---------------------------------------------------------------------------------------------------------------------
# C12 - the reconcile does not wait for a PAYMENT row
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[20]}"; F="${U[21]}"
seed_pending "$R" "$F"
(
  { echo "begin;"; echo "select 1 from public.subscriptions where user_id = '$F' for update;"; echo "select pg_sleep(3);"; echo "commit;"; } | psql_ >/dev/null 2>"$TMP/c12h.err"
) &
H_PID=$!
sleep 1
T0=$(now_ms)
C12_RET="$(job 2>"$TMP/c12.err")"
C12_MS=$(( $(now_ms) - T0 ))
wait "$H_PID"
echo "C12: job while the friend's payment row is held FOR UPDATE took ${C12_MS} ms -> '$C12_RET'"
[ "$C12_MS" -lt 1500 ]  || fail "C12 the reconcile waited ${C12_MS} ms behind a lock on a PAYMENT row (payment rows are read, never locked)"
case "$C12_RET" in *'"reconciled": 1'*) ;; *) fail "C12 the row should have been reconciled, got '$C12_RET'" ;; esac
case "$C12_RET" in *'"credited": 1'*) ;; *) fail "C12 the vested row should have been credited, got '$C12_RET'" ;; esac

# ---------------------------------------------------------------------------------------------------------------------
# C13 - at most 50 rewards per run (c_batch)
# ---------------------------------------------------------------------------------------------------------------------
KEEP="$(printf "'%s'," "${U[@]}")"; KEEP="${KEEP%,}"
reset_tables
R="${U[22]}"
psql_ >/dev/null <<SQLEND || exit 2
with newu as (insert into public.users (id) select gen_random_uuid() from generate_series(1, 55) returning id)
, ins as (
  insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  select 'AVYA-B13', '$R', id, now() - interval '20 days', false, true from newu returning referee_id)
insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  select referee_id, 'monthly', 'active', now() - interval '8 days', now() + interval '22 days', 'pay_b13_' || gen_random_uuid() from ins;
SQLEND
C13_R1="$(job 2>"$TMP/c13.err")"
C13_R2="$(job 2>>"$TMP/c13.err")"
C13_CRED=$(psql_ -c "select count(*) from public.referral_redemptions where code = 'AVYA-B13' and referrer_rewarded")
psql_ -c "delete from public.users where id not in ($KEEP)" >/dev/null
echo "C13: 55 vested rewards -> first run '$C13_R1', second run '$C13_R2'; credited in total=$C13_CRED"
case "$C13_R1" in *'"credited": 50'*) ;; *) fail "C13 the first run must credit exactly 50 (c_batch), got '$C13_R1'" ;; esac
case "$C13_R2" in *'"credited": 5'*) ;; *) fail "C13 the second run must credit the remaining 5, got '$C13_R2'" ;; esac
[ "$C13_CRED" = "55" ] || fail "C13 all 55 must end credited, got $C13_CRED"

# ---------------------------------------------------------------------------------------------------------------------
# C6 - the flag UPDATE matches no row: the ROW_COUNT check raises and the grant is rolled back
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
R="${U[5]}"; F="${U[6]}"
seed_pending "$R" "$F"
psql_ >/dev/null <<'EOF' || exit 2
create function public.rpoc_swallow_flag() returns trigger language plpgsql as $f$
begin
  if new.referrer_rewarded is true and old.referrer_rewarded is not true then return null; end if;
  return new;
end $f$;
create trigger rpoc_swallow_flag before update on public.referral_redemptions for each row execute function public.rpoc_swallow_flag();
EOF
C6_RET="$(job 2>"$TMP/c6.err")"
C6_ROWS=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
C6_FLAG=$(psql_ -c "select referrer_rewarded is true from public.referral_redemptions where referee_id = '$F'")
C6_ALERT=$(psql_ -c "select count(*) from public.alerts where source = 'referral_conversions_failed' and severity = 'warn'")
psql_ -c "drop trigger rpoc_swallow_flag on public.referral_redemptions; drop function public.rpoc_swallow_flag()" >/dev/null
C6_RET2="$(job 2>>"$TMP/c6.err")"
C6_ROWS2=$(psql_ -c "select count(*) from public.subscriptions where user_id = '$R'")
echo "C6: with the flag UPDATE swallowed -> '$C6_RET' (referrer rows=$C6_ROWS flag=$C6_FLAG failed alerts=$C6_ALERT); trigger removed -> '$C6_RET2' (rows=$C6_ROWS2)"
case "$C6_RET" in *'"failed": 1'*) ;; *) fail "C6 expected failed = 1, got '$C6_RET'" ;; esac
[ "$C6_ROWS" = "0" ]    || fail "C6 the grant must be rolled back with the failed flag (a free grant that would repeat every hour): rows=$C6_ROWS"
[ "$C6_FLAG" = "f" ]    || fail "C6 the flag must not read true"
[ "$C6_ALERT" = "1" ]   || fail "C6 expected one failed alert, got $C6_ALERT"
case "$C6_RET2" in *'"credited": 1'*) ;; *) fail "C6 with the trigger gone the next run should credit, got '$C6_RET2'" ;; esac
[ "$C6_ROWS2" = "1" ]   || fail "C6 expected one subscription row after the credit, got $C6_ROWS2"

# ---------------------------------------------------------------------------------------------------------------------
# C7 - the volume alert thresholds and their dedup
# ---------------------------------------------------------------------------------------------------------------------
volume_alerts() { psql_ -c "select count(*) from public.alerts where source = 'referral_conversions_volume'"; }
KEEP="$(printf "'%s'," "${U[@]}")"; KEEP="${KEEP%,}"   # the original 30 replica users: every other user a case adds is deleted again
# C7a: redemptions in the last 24 hours (referrer U[7], N fresh referees, nobody has paid: nothing to credit)
for n in 20 21; do
  reset_tables
  psql_ >/dev/null <<EOF || exit 2
with newu as (insert into public.users (id) select gen_random_uuid() from generate_series(1, $n) returning id)
insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  select 'AVYA-VOL', '${U[7]}', id, now() - interval '1 hour', false, true from newu;
EOF
  job >/dev/null 2>"$TMP/c7.err"
  A1=$(volume_alerts)
  job >/dev/null 2>>"$TMP/c7.err"
  A2=$(volume_alerts)
  eval "C7A_$n=\"$A1/$A2\""
  psql_ -c "delete from public.users where id not in ($KEEP)" >/dev/null
done
# C7b: credits in one run (rows 20 days old, payments 10 days old, 10 or 11 distinct referees paying)
for n in 10 11; do
  reset_tables
  psql_ >/dev/null <<EOF || exit 2
with newu as (insert into public.users (id) select gen_random_uuid() from generate_series(1, $n) returning id), r as (select id from newu)
, ins as (
  insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  select 'AVYA-VOL', '${U[8]}', id, now() - interval '20 days', false, true from r returning referee_id)
insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  select referee_id, 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vol_' || gen_random_uuid() from ins;
EOF
  job >/dev/null 2>"$TMP/c7.err"
  A1=$(volume_alerts)
  eval "C7B_$n=\"$A1\""
  psql_ -c "delete from public.users where id not in ($KEEP)" >/dev/null
done
echo "C7: 24h redemptions: 20 -> alerts after run1/run2 = ${C7A_20}; 21 -> ${C7A_21}; credits in one run: 10 -> ${C7B_10}; 11 -> ${C7B_11}"
[ "$C7A_20" = "0/0" ]   || fail "C7 exactly 20 redemptions in 24 h must not alert (threshold is strictly more than 20), got ${C7A_20}"
[ "$C7A_21" = "1/1" ]   || fail "C7 21 redemptions in 24 h must alert once and a second run must add none (dedup), got ${C7A_21}"
[ "$C7B_10" = "0" ]     || fail "C7 exactly 10 credits in one run must not alert (threshold is strictly more than 10), got ${C7B_10}"
[ "$C7B_11" = "1" ]     || fail "C7 11 credits in one run must alert once, got ${C7B_11}"

# ---------------------------------------------------------------------------------------------------------------------
# C8 - a job run against redemptions of the same users, under load (statistical, supplementary)
# ---------------------------------------------------------------------------------------------------------------------
reset_tables
psql_ >/dev/null <<EOF || exit 2
create table if not exists public.dl_pairs (k int primary key, p uuid not null, q uuid not null);
create table if not exists public.dl_log (k int, who text, sqlstate text, msg text);
truncate public.dl_pairs, public.dl_log;
create temp table dl_new as select gen_random_uuid() as id, g as k, 'p' as side from generate_series(1, $DL_PAIRS) g
  union all select gen_random_uuid(), g, 'q' from generate_series(1, $DL_PAIRS) g;
insert into public.users (id) select id from dl_new;
insert into public.dl_pairs (k, p, q) select a.k, a.id, b.id from dl_new a join dl_new b on a.k = b.k and a.side = 'p' and b.side = 'q';
-- every pair: q paid 8 days ago (vested, but not yet 10 days: a payment that old would trip the stall watch on the first run) for a redemption of p's code 20 days ago, so the job credits p; client 1 redeems a code FOR p (p is
-- the referee of a third party r) at the same time, which takes key(p) and extends p's subscription.
insert into public.users (id) values ('00000000-0000-0000-0000-00000000dead') on conflict do nothing;
insert into public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  select 'AVYA-DL', p, q, now() - interval '20 days', false, true from public.dl_pairs;
insert into public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  select q, 'monthly', 'active', now() - interval '8 days', now() + interval '22 days', 'pay_dl_' || gen_random_uuid() from public.dl_pairs;
create or replace function public.dl_go(k int, who int) returns void language plpgsql as \$f\$
declare v_p uuid;
begin
  select p into v_p from public.dl_pairs where dl_pairs.k = dl_go.k;
  begin
    if who = 0 then perform private.process_referral_conversions();
    else perform public.redeem_referral_atomic('DL', '00000000-0000-0000-0000-00000000dead', v_p, 7); end if;
  exception when others then
    insert into public.dl_log values (k, who::text, sqlstate, sqlerrm);
  end;
end \$f\$;
EOF
printf '\\set i :i + 1\nselect public.dl_go(:i, :client_id);\n' > "$TMP/bench.sql"
docker cp "$TMP/bench.sql" "$CONTAINER:/tmp/rpoc_dl_bench.sql" >/dev/null || exit 2
docker exec "$CONTAINER" pgbench -h 127.0.0.1 -U postgres -n -f /tmp/rpoc_dl_bench.sql -c 2 -j 2 -t "$DL_PAIRS" -D i=0 "$DB" >"$TMP/pgbench.out" 2>&1
PGB_RC=$?
# Client 0 runs the job (idempotent, many times), client 1 redeems for p once per k; run the job to quiescence afterwards.
job >/dev/null 2>&1; job >/dev/null 2>&1
DL_BAD=$(psql_ -c "select count(*) from public.dl_log where sqlstate not in ('23505', 'P0001')")
DL_DEAD=$(psql_ -c "select count(*) from public.dl_log where sqlstate = '40P01'")
DL_AUDIT=$(psql_ -c "select count(*) from public.referral_redemptions where code = 'DL'")
DL_CRED=$(psql_ -c "select count(*) from public.referral_redemptions where code = 'AVYA-DL' and referrer_rewarded")
DL_DUP=$(psql_ -c "select count(*) from (select user_id from public.subscriptions where plan = 'referral_trial' group by user_id having count(*) > 1) t")
echo "C8: pgbench rc=$PGB_RC; ${DL_PAIRS} pairs; unexpected errors=$DL_BAD (deadlocks=$DL_DEAD); redemptions audited=$DL_AUDIT; credited=$DL_CRED; users with 2+ trial rows=$DL_DUP"
# Leave the replica as found.
psql_ >/dev/null <<'EOF'
delete from public.referral_redemptions where referrer_id in (select p from public.dl_pairs) or referee_id in (select p from public.dl_pairs union select q from public.dl_pairs);
delete from public.users where id in (select p from public.dl_pairs union select q from public.dl_pairs) or id = '00000000-0000-0000-0000-00000000dead';
drop function if exists public.dl_go(int, int);
drop table if exists public.dl_pairs, public.dl_log;
EOF
[ "$PGB_RC" -eq 0 ]       || fail "C8 pgbench did not complete: $(tail -3 "$TMP/pgbench.out")"
[ "$DL_BAD" = "0" ]       || fail "C8 $DL_BAD unexpected errors ($DL_DEAD deadlocks) between the job and redemptions of the same users"
[ "$DL_AUDIT" = "$DL_PAIRS" ] || fail "C8 expected $DL_PAIRS audited redemptions, got $DL_AUDIT"
[ "$DL_CRED" = "$DL_PAIRS" ]  || fail "C8 every pair's payment is past the vest and must be credited, got $DL_CRED of $DL_PAIRS"
[ "$DL_DUP" = "0" ]       || fail "C8 a user ended with two referral_trial rows (a grant raced another): $DL_DUP"
DL_ALERTS=$(psql_ -c "select count(*) from public.alerts where source in ('referral_conversions_failed', 'referral_conversions_stalled')")
[ "$DL_ALERTS" = "0" ]    || fail "C8 a failed or stalled alert was written under load ($DL_ALERTS): a job-side failure (a deadlock victim inside the credit sub-block is swallowed into the failed counter) would show nowhere else"

reset_tables
if [ "$FAIL" -eq 0 ]; then echo "CONCURRENCY OK"; exit 0; fi
exit 1
