#!/usr/bin/env bash
# Local rehearsal of migration 178 (OI-503, diagnose d4a7c9; plan
# docs/plans/2026-11-13-coach-chat-time-dup.md section 4, C1) in a throwaway
# supabase/postgres container. Never touches prod.
#
# Fixture: public.users + public.ai_coach_interactions with the live column set
# (id, user_id, snapshot_id, channel, user_message, ai_response, model_used,
# tokens_used, was_helpful, created_at, summarized, tool_calls) and own-row RLS for
# select / insert / update. Then migration 178 is applied VERBATIM (twice: it must be
# re-runnable) and each case runs as `authenticated` with request.jwt.claims set, the
# way PostgREST runs the client's orphan upsert.
#
# Cases (each names the mutation it kills):
#   K1 the column exists, text, nullable.                    Kills: the ADD COLUMN removed.
#   K2 NULL and a 13-digit key are stored.                   Kills: a CHECK that refuses NULL.
#   K3 malformed keys are refused with 23514: wrong prefix, 9 digits, 17 digits, hex,
#      a trailing newline, an injection string.             Kills: the CHECK removed or unanchored.
#   K4 authenticated inserts its own keyed row; another user's row is refused (RLS).
#   K5 the partial index exists with predicate client_key IS NOT NULL, and the push
#      lookup (user_id, client_key) uses it with seqscan off. Kills: the index removed.
#   K6 lock_timeout is reset at the end of the file (the session value is back to 0).
#                                                            Kills: RESET removed.
#
# Usage: bash test/sql/coach_client_key_local.sh   (exit 0 = every case passed)
# Mutation runs: F178=<edited copy> bash test/sql/coach_client_key_local.sh
set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
F178="${F178:-$ROOT/supabase/migrations/178_coach_client_key.sql}"
C="oi503-pgtest"
IMG="public.ecr.aws/supabase/postgres:17.6.1.084"
FAILS=0

cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; }
trap cleanup EXIT

[ -f "$F178" ] || { echo "MISSING FILE: $F178"; exit 2; }
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

pg <<SQL || { echo "fixture failed"; exit 2; }
CREATE TABLE public.users (id uuid PRIMARY KEY);
CREATE TABLE public.ai_coach_interactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  snapshot_id uuid,
  channel text,
  user_message text,
  ai_response text,
  model_used text,
  tokens_used integer,
  was_helpful boolean,
  created_at timestamptz DEFAULT now(),
  summarized boolean DEFAULT false,
  tool_calls jsonb
);
CREATE INDEX ON public.ai_coach_interactions (user_id, created_at);
ALTER TABLE public.ai_coach_interactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY aci_sel ON public.ai_coach_interactions FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY aci_ins ON public.ai_coach_interactions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY aci_upd ON public.ai_coach_interactions FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE ON public.ai_coach_interactions TO authenticated;
INSERT INTO public.users VALUES ('$UA'), ('$UB');
SQL

pg < "$F178" || { echo "migration 178 failed to apply"; exit 2; }
pg < "$F178" || { echo "migration 178 is not re-runnable"; exit 2; }

as_user() { # $1 sub, $2 sql
  pg -t -A <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '$1', true);
$2
COMMIT;
SQL
}

check() { # $1 name, $2 expected, $3 actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAILS=$((FAILS + 1)); fi
}

# K1
check "K1 column type and nullability" "text|YES" "$(pg -t -A -c "select data_type||'|'||is_nullable from information_schema.columns where table_schema='public' and table_name='ai_coach_interactions' and column_name='client_key'")"

# K2
pg -c "insert into public.ai_coach_interactions (user_id, channel, user_message) values ('$UA','app','null key')" >/dev/null 2>&1 \
  && r=stored || r=refused
check "K2 NULL key stored" "stored" "$r"
pg -c "insert into public.ai_coach_interactions (user_id, channel, user_message, client_key) values ('$UA','app','keyed','coach_1763000000000')" >/dev/null 2>&1 \
  && r=stored || r=refused
check "K2 13-digit key stored" "stored" "$r"

# K3
nl=$(printf 'coach_1763000000000\n')
for bad in 'chat_1763000000000' 'coach_123456789' 'coach_17630000000001234' 'coach_17630abc' "x', 'y"; do
  out=$(pg -c "insert into public.ai_coach_interactions (user_id, channel, client_key) values ('$UA','app',\$k\$$bad\$k\$)" 2>&1)
  case "$out" in *"ai_coach_interactions_client_key_format"*) r=refused ;; *) r="accepted: $out" ;; esac
  check "K3 malformed key refused: $bad" "refused" "$r"
done
out=$(pg -c "insert into public.ai_coach_interactions (user_id, channel, client_key) values ('$UA','app',E'coach_1763000000000\\n')" 2>&1)
case "$out" in *"ai_coach_interactions_client_key_format"*) r=refused ;; *) r="accepted: $out" ;; esac
check "K3 malformed key refused: trailing newline" "refused" "$r"
: "$nl"

# K4
out=$(as_user "$UA" "insert into public.ai_coach_interactions (user_id, channel, user_message, client_key) values ('$UA','in_app_orphan','own','coach_1763000000001');" 2>&1)
case "$out" in *ERROR*) r="refused: $out" ;; *) r=stored ;; esac
check "K4 authenticated own keyed row" "stored" "$r"
out=$(as_user "$UA" "insert into public.ai_coach_interactions (user_id, channel, user_message, client_key) values ('$UB','in_app_orphan','other','coach_1763000000002');" 2>&1)
case "$out" in *"row-level security"*) r=refused ;; *) r="accepted: $out" ;; esac
check "K4 another user's row refused" "refused" "$r"

# K5
check "K5 partial index predicate" "(client_key IS NOT NULL)" "$(pg -t -A -c "select pg_get_expr(i.indpred, i.indrelid) from pg_index i join pg_class c on c.oid=i.indexrelid where c.relname='idx_ai_coach_interactions_user_client_key'")"
plan=$(pg -t -A <<SQL
SET enable_seqscan = off;
EXPLAIN SELECT id FROM public.ai_coach_interactions WHERE user_id='$UA' AND client_key='coach_1763000000000' LIMIT 1;
SQL
)
case "$plan" in *idx_ai_coach_interactions_user_client_key*) r=used ;; *) r="not used: $plan" ;; esac
check "K5 push lookup uses the index" "used" "$r"

# K6: run the file in ONE session and read lock_timeout afterwards.
lt=$( { cat "$F178"; echo; echo "SHOW lock_timeout;"; } | pg -t -A 2>/dev/null | tail -1)
check "K6 lock_timeout reset after the file" "0" "$lt"

echo
if [ "$FAILS" -eq 0 ]; then echo "SUMMARY: all cases passed"; exit 0; else echo "SUMMARY: $FAILS failed"; exit 1; fi
