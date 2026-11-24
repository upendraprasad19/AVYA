#!/usr/bin/env bash
# test/sql/play_upsert_start_date_local.sh
#
# Local proof of supabase/migrations/187_play_upsert_start_date.sql (OI-519, hermes H1-3). LOCAL
# ONLY: databases inside the allowlisted docker container started by test/sql/play_subscriptions_local.sh; no host or
# URL argument, so it cannot reach the live project.
#
#   sh test/sql/play_upsert_start_date_local.sh
#
# Two databases from scratch: sd_old = replica + 159 + 160 + 182 (live today), sd_new = the same + the draft (with its
# self-check DO block, --single-transaction). Cases:
#   C1 a row still labelled 'active' whose end_date has passed (not re-read since), then a resubscribe:
#      sd_old keeps the OLD chain's start_date (the defect), sd_new takes the new purchase's start_date.
#   C2 a really running row (end_date in the future) renews: both keep the first start_date (unchanged rule).
#   C3 an 'expired' row, then a resubscribe: both start fresh (unchanged rule).
#   C4 a renewal read LATE (row still 'active', end_date = E + 3 h passed, the new period's P = E): both keep the chain.
#   C5 the same late renewal after the mirror already wrote 'expired': sd_old restarts the chain (the defect),
#      sd_new keeps it.
#   C6 the boundary: a renewal whose period starts EXACTLY at the stored end_date (a re-enable read late) keeps the chain
#      (it tells the draft's <= from a <; 182 keeps it only because the row still says active).
set -eu
CONTAINER=oi519-pgtest
case "$CONTAINER" in oi519-pgtest) ;; *) echo "REFUSED: container not on the allowlist"; exit 2 ;; esac
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || { echo "REFUSED: run test/sql/play_subscriptions_local.sh first (it starts $CONTAINER)"; exit 2; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DRAFT="$ROOT/supabase/migrations/187_play_upsert_start_date.sql"
psql_db() { db=$1; shift; docker exec -i "$CONTAINER" psql -U postgres -h 127.0.0.1 -q -At -v ON_ERROR_STOP=1 -d "$db" "$@"; }
fresh() {
  psql_db postgres -c "drop database if exists $1 with (force)" >/dev/null
  psql_db postgres -c "create database $1" >/dev/null
  psql_db "$1" < "$ROOT/test/sql/referral_pay_on_conversion_replica_schema.sql" >/dev/null
  psql_db "$1" < "$ROOT/supabase/migrations/159_referral_reward_on_conversion.sql" >/dev/null 2>&1
  psql_db "$1" --single-transaction < "$ROOT/supabase/migrations/160_referral_hardening.sql" >/dev/null 2>&1
  psql_db "$1" --single-transaction < "$ROOT/supabase/migrations/182_play_subscriptions.sql" >/dev/null
}
fresh oi519_sd_old
fresh oi519_sd_new
psql_db oi519_sd_new --single-transaction < "$DRAFT" >/dev/null || { echo "FAIL: the draft did not apply (or its self-check failed)"; exit 1; }

# prints: C1 C2 C3 start_date verdicts, one word each (kept | fresh)
cases() {
  psql_db "$1" <<'SQL'
INSERT INTO users SELECT ('00000000-0000-4000-8000-0000000005' || x)::uuid FROM unnest(ARRAY['d1','d2','d3','d4','d5','d6']) x;
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, store, store_product_id, store_environment, store_read_at, auto_renew) VALUES
  ('00000000-0000-4000-8000-0000000005d1', 'monthly', 'active',  now() - interval '40 days', now() - interval '2 hours', 'play', 'avya_pro', 'PRODUCTION', now() - interval '3 hours', false),
  ('00000000-0000-4000-8000-0000000005d2', 'monthly', 'active',  now() - interval '40 days', now() + interval '1 hour',  'play', 'avya_pro', 'PRODUCTION', now() - interval '3 hours', true),
  ('00000000-0000-4000-8000-0000000005d3', 'monthly', 'expired', now() - interval '40 days', now() - interval '2 hours', 'play', 'avya_pro', 'PRODUCTION', now() - interval '1 hour',  false),
  ('00000000-0000-4000-8000-0000000005d4', 'monthly', 'active',  now() - interval '40 days', now() - interval '1 hour',  'play', 'avya_pro', 'PRODUCTION', now() - interval '6 hours', true),
  ('00000000-0000-4000-8000-0000000005d5', 'monthly', 'expired', now() - interval '40 days', now() - interval '1 hour',  'play', 'avya_pro', 'PRODUCTION', now() - interval '30 minutes', true),
  ('00000000-0000-4000-8000-0000000005d6', 'monthly', 'active',  now() - interval '40 days', date_trunc('minute', now()) - interval '1 hour', 'play', 'avya_pro', 'PRODUCTION', now() - interval '2 hours', false);
SELECT public.upsert_play_subscription(u::uuid, 'avya_pro', 'monthly', 'active', now() - interval '5 minutes', now() + interval '30 days',
  true, 'PRODUCTION', 'GPA.new', now() + interval '30 days' - interval '3 hours', now())
  FROM unnest(ARRAY['00000000-0000-4000-8000-0000000005d1','00000000-0000-4000-8000-0000000005d2','00000000-0000-4000-8000-0000000005d3']) u;
-- C4 / C5: the renewal's period started at the old expiry E = end_date - 3 h (4 hours ago), read only now.
SELECT public.upsert_play_subscription(u::uuid, 'avya_pro', 'monthly', 'active', now() - interval '4 hours', now() + interval '30 days',
  true, 'PRODUCTION', 'GPA.renew', now() + interval '30 days' - interval '3 hours', now())
  FROM unnest(ARRAY['00000000-0000-4000-8000-0000000005d4','00000000-0000-4000-8000-0000000005d5']) u;
-- C6: the new period starts exactly at the stored end_date.
SELECT public.upsert_play_subscription('00000000-0000-4000-8000-0000000005d6'::uuid, 'avya_pro', 'monthly', 'active',
  (SELECT end_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000005d6'),
  now() + interval '30 days', true, 'PRODUCTION', 'GPA.reenable', now() + interval '30 days' - interval '3 hours', now());
SELECT string_agg(CASE WHEN start_date < now() - interval '30 days' THEN 'kept' ELSE 'fresh' END, ' ' ORDER BY user_id)
  FROM subscriptions WHERE store = 'play';
SQL
}
OLD=$(cases oi519_sd_old | tail -1)
NEW=$(cases oi519_sd_new | tail -1)
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1 -- $2"; else echo "FAIL $1 -- got '$2' want '$3'"; FAIL=1; fi; }
check "182 alone: C1 stale-active keeps the old start (defect), C2 kept, C3 fresh, C4 kept, C5 restarts (defect), C6 kept (status still active)" "$OLD" "kept kept fresh kept fresh kept"
check "182 + draft: C1 fresh, C2 kept, C3 fresh, C4 kept, C5 kept, C6 kept" "$NEW" "fresh kept fresh kept kept kept"
psql_db postgres -c "drop database if exists oi519_sd_old with (force)" >/dev/null
psql_db postgres -c "drop database if exists oi519_sd_new with (force)" >/dev/null
[ "$FAIL" = 0 ] && echo "ALL PASSED" || exit 1
