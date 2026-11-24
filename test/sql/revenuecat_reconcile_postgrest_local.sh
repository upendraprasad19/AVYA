#!/bin/sh
# OI-519 (+51) local proof for the revenuecat-reconcile database adapters (B-pass of the U3 commit, findings 1 and 6):
# a local PostgREST (postgrest/postgrest:v12.2.12) in front of a fresh local database carrying 159 + 160 + 182, then
# test/sql/revenuecat_reconcile_postgrest_local.ts calls the REAL reconcileDb through supabase-js 2.39.3.
# Local docker only (container oi519-pgtest, started by test/sql/play_subscriptions_local.sh); never a live host.
set -u
CONTAINER=oi519-pgtest
PGRST=oi519-postgrest
PORT=54399
DB=oi519_rest
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DENO=${DENO:-$HOME/.deno/bin/deno}
SECRET=oi519-local-jwt-secret-not-a-real-secret-0123456789

docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || { echo "REFUSED: run test/sql/play_subscriptions_local.sh first (it starts $CONTAINER)"; exit 2; }
psql_db() { db=$1; shift; docker exec -i "$CONTAINER" psql -U postgres -h 127.0.0.1 -q -At -v ON_ERROR_STOP=1 -d "$db" "$@"; }

psql_db postgres -c "drop database if exists $DB with (force)" >/dev/null
psql_db postgres -c "create database $DB" >/dev/null
psql_db "$DB" < "$ROOT/test/sql/referral_pay_on_conversion_replica_schema.sql" >/dev/null
psql_db "$DB" < "$ROOT/supabase/migrations/159_referral_reward_on_conversion.sql" >/dev/null 2>&1
psql_db "$DB" --single-transaction < "$ROOT/supabase/migrations/160_referral_hardening.sql" >/dev/null 2>&1
psql_db "$DB" --single-transaction < "$ROOT/supabase/migrations/182_play_subscriptions.sql" >/dev/null || { echo "FAIL: 182 did not apply"; exit 1; }
docker exec -i "$CONTAINER" psql -U supabase_admin -h 127.0.0.1 -q -At -v ON_ERROR_STOP=1 -d postgres -c "alter role authenticator with login password 'oi519local'" >/dev/null || exit 1
psql_db "$DB" -c "grant usage on schema public to anon, authenticated, service_role;
  grant all on all tables in schema public to service_role; grant usage, select on all sequences in schema public to service_role;
  grant execute on all functions in schema public to service_role;" >/dev/null

psql_db "$DB" <<'SQL' >/dev/null
INSERT INTO users SELECT ('00000000-0000-4000-8000-0000000' || x)::uuid
  FROM unnest(ARRAY['0c001','0c002','0c003','0d001','0d002','0d003','0d004','0d005','0d006']) x;
INSERT INTO store_reward_deferrals (id, user_id, store, days, status, created_at) VALUES
  ('66666666-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000c001', 'play', 7, 'pending', now() - interval '30 hours'),
  ('66666666-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000c001', 'play', 7, 'pending', now() - interval '26 hours'),
  ('66666666-0000-4000-8000-000000000003', '00000000-0000-4000-8000-00000000c002', 'play', 30, 'pending', now() - interval '1 hour');
INSERT INTO store_reward_deferrals (id, user_id, store, days, status, claim_token, claimed_at, created_at) VALUES
  ('66666666-0000-4000-8000-000000000004', '00000000-0000-4000-8000-00000000c003', 'play', 7, 'in_flight', gen_random_uuid(),
   now() - interval '90 minutes', now() - interval '3 hours');
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, store, store_product_id, store_environment, store_read_at) VALUES
  ('00000000-0000-4000-8000-00000000d001', 'monthly', 'expired', now() - interval '32 days', now() - interval '2 days', 'play', 'avya_pro', 'PRODUCTION', now() - interval '1 hour'),
  ('00000000-0000-4000-8000-00000000d002', 'monthly', 'active',  now() - interval '29 days', now() + interval '12 hours', 'play', 'avya_pro', 'PRODUCTION', now() - interval '1 hour'),
  ('00000000-0000-4000-8000-00000000d003', 'yearly',  'active',  now() - interval '10 days', now() + interval '20 days', 'play', 'avya_pro', 'PRODUCTION', now() - interval '30 hours'),
  ('00000000-0000-4000-8000-00000000d004', 'yearly',  'active',  now() - interval '10 days', now() + interval '20 days', 'play', 'avya_pro', 'PRODUCTION', now() - interval '1 hour'),
  ('00000000-0000-4000-8000-00000000d005', 'monthly', 'expired', now() - interval '35 days', now() - interval '5 days', 'play', 'avya_pro', 'SANDBOX', now() - interval '1 hour');
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
  ('00000000-0000-4000-8000-00000000d006', 'monthly', 'active', now() - interval '29 days', now() + interval '12 hours', 'pay_local');
SQL

docker rm -f "$PGRST" >/dev/null 2>&1
docker run -d --name "$PGRST" --network host \
  -e PGRST_DB_URI="postgres://authenticator:oi519local@127.0.0.1:54336/$DB" -e PGRST_DB_SCHEMAS=public \
  -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET="$SECRET" -e PGRST_SERVER_PORT=$PORT -e PGRST_SERVER_HOST=127.0.0.1 \
  postgrest/postgrest:v12.2.12 >/dev/null || exit 1
trap 'docker rm -f "$PGRST" >/dev/null 2>&1' EXIT
READY=0; for _ in $(seq 1 60); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/" && { READY=1; break; }; sleep 1; done
[ "$READY" = 1 ] || { echo "FAIL: PostgREST never became ready"; docker logs "$PGRST" 2>&1 | tail -5; exit 1; }

JWT=$(python3 -I -c '
import base64,hmac,hashlib,json,sys,time
b=lambda d: base64.urlsafe_b64encode(d).rstrip(b"=").decode()
h=b(json.dumps({"alg":"HS256","typ":"JWT"}).encode()); p=b(json.dumps({"role":"service_role","exp":int(time.time())+600}).encode())
s=b(hmac.new(sys.argv[1].encode(), (h+"."+p).encode(), hashlib.sha256).digest()); print(h+"."+p+"."+s)' "$SECRET")

OI519_SERVICE_JWT="$JWT" OI519_PGRST_PORT=$PORT "$DENO" run --node-modules-dir=none --allow-net=127.0.0.1,esm.sh,deno.land --allow-env \
  "$ROOT/test/sql/revenuecat_reconcile_postgrest_local.ts"
