#!/usr/bin/env bash
# Local rehearsal of migration 177 (OI-479, diagnose 5970aa) in a throwaway
# supabase/postgres container. Never touches prod.
#
# Fixture: a minimal public.users + public.user_preferences with the live table's
# shape for the columns that matter (user_id NOT NULL UNIQUE FK, defaults on every
# other NOT NULL column) and own-row RLS for select / insert / update, as live
# (migrations 001, 055, 100). Then migration 177 is applied VERBATIM and each case
# runs as `authenticated` (or `anon`) with request.jwt.claims set, the way
# PostgREST calls an RPC.
#
# Usage: bash test/sql/coach_chat_cleared_at_local.sh   (exit 0 = every case passed)
set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
F177="${F177:-$ROOT/supabase/migrations/177_coach_chat_cleared_at.sql}"
C="oi479-pgtest"
IMG="public.ecr.aws/supabase/postgres:17.6.1.084"
FAILS=0

cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; }
trap cleanup EXIT

[ -f "$F177" ] || { echo "MISSING FILE: $F177"; exit 2; }
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
CREATE TABLE public.user_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  motivational_style text,
  preferred_language text DEFAULT 'en',
  coaching_notes jsonb,
  notification_preferences jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT user_preferences_user_id_unique UNIQUE (user_id)
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY up_sel ON public.user_preferences FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY up_ins ON public.user_preferences FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY up_upd ON public.user_preferences FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE ON public.user_preferences TO authenticated, anon;
-- Supabase's default privileges grant EXECUTE on new public functions to anon and
-- authenticated directly; reproduce that so the migration's REVOKE FROM anon is tested.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
INSERT INTO public.users VALUES ('$UA'), ('$UB'), ('$UC');
-- B already has a preferences row (the UPDATE branch); A has none (the INSERT branch).
INSERT INTO public.user_preferences (user_id, motivational_style) VALUES ('$UB', 'tough');
SQL

pg < "$F177" || { echo "migration 177 failed to apply"; exit 2; }
pg < "$F177" || { echo "migration 177 is not re-runnable"; exit 2; }

# Runs SQL as a role with the given JWT subject inside one transaction.
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

check() { # $1 name, $2 expected, $3 actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAILS=$((FAILS + 1)); fi
}

val() { pg -t -A -c "select coalesce(coach_chat_cleared_at::text,'NULL') from public.user_preferences where user_id='$1'"; }
cnt() { pg -t -A -c "select count(*) from public.user_preferences where user_id='$1'"; }

# C1 INSERT branch: A has no row; the RPC creates one.
as_user authenticated "$UA" "SELECT public.raise_coach_chat_cleared_at('2026-01-01T00:00:00Z');" >/dev/null
check "C1 insert branch creates the row" "1" "$(cnt "$UA")"
check "C1 value stored" "2026-01-01 00:00:00+00" "$(val "$UA")"

# C2 monotonic: an older value never lowers it.
as_user authenticated "$UA" "SELECT public.raise_coach_chat_cleared_at('2025-06-01T00:00:00Z');" >/dev/null
check "C2 older value does not lower" "2026-01-01 00:00:00+00" "$(val "$UA")"

# C3 a newer value raises it.
as_user authenticated "$UA" "SELECT public.raise_coach_chat_cleared_at('2026-02-01T00:00:00Z');" >/dev/null
check "C3 newer value raises" "2026-02-01 00:00:00+00" "$(val "$UA")"

# C4 a future value is clamped to the server's now.
as_user authenticated "$UA" "SELECT public.raise_coach_chat_cleared_at(now() + interval '10 days');" >/dev/null
fut=$(pg -t -A -c "select (coach_chat_cleared_at <= now()) from public.user_preferences where user_id='$UA'")
check "C4 future p_at clamped to now (update branch)" "t" "$fut"
# C4b the INSERT branch clamps too (C has no row yet).
as_user authenticated "$UC" "SELECT public.raise_coach_chat_cleared_at(now() + interval '10 days');" >/dev/null
fut=$(pg -t -A -c "select (coach_chat_cleared_at <= now()) from public.user_preferences where user_id='$UC'")
check "C4b future p_at clamped to now (insert branch)" "t" "$fut"

# C5 NULL p_at is refused and changes nothing.
before=$(val "$UA")
out=$(as_user authenticated "$UA" "SELECT public.raise_coach_chat_cleared_at(NULL);" 2>&1)
case "$out" in *"p_at must not be null"*) r=refused ;; *) r="accepted: $out" ;; esac
check "C5 NULL p_at refused" "refused" "$r"
check "C5 value unchanged after NULL" "$before" "$(val "$UA")"

# C6 UPDATE branch on an existing row (B): other columns untouched.
as_user authenticated "$UB" "SELECT public.raise_coach_chat_cleared_at('2026-03-01T00:00:00Z');" >/dev/null
check "C6 update branch sets the value" "2026-03-01 00:00:00+00" "$(val "$UB")"
check "C6 other column untouched" "tough" "$(pg -t -A -c "select motivational_style from public.user_preferences where user_id='$UB'")"
check "C6 still one row for B" "1" "$(cnt "$UB")"

# C7 user A's call never touches B's row.
as_user authenticated "$UA" "SELECT public.raise_coach_chat_cleared_at('2026-04-01T00:00:00Z');" >/dev/null
check "C7 B untouched by A" "2026-03-01 00:00:00+00" "$(val "$UB")"

# C8 anon cannot execute.
out=$(as_user anon "" "SELECT public.raise_coach_chat_cleared_at('2026-05-01T00:00:00Z');" 2>&1)
case "$out" in *"permission denied"*) r=denied ;; *) r="allowed: $out" ;; esac
check "C8 anon denied" "denied" "$r"
check "C8 ACL: anon has no EXECUTE" "f" "$(pg -t -A -c "select has_function_privilege('anon','public.raise_coach_chat_cleared_at(timestamptz)','execute')")"
check "C8 ACL: authenticated has EXECUTE" "t" "$(pg -t -A -c "select has_function_privilege('authenticated','public.raise_coach_chat_cleared_at(timestamptz)','execute')")"

# C9 authenticated with no subject is refused.
out=$(as_user authenticated "" "SELECT public.raise_coach_chat_cleared_at('2026-05-01T00:00:00Z');" 2>&1)
case "$out" in *"no authenticated user"*) r=refused ;; *) r="accepted: $out" ;; esac
check "C9 no auth.uid() refused" "refused" "$r"

# C10 function shape: invoker, pinned search_path.
check "C10 SECURITY INVOKER" "f" "$(pg -t -A -c "select prosecdef from pg_proc where proname='raise_coach_chat_cleared_at'")"
check "C10 search_path pinned" "{\"search_path=public, pg_temp\"}" "$(pg -t -A -c "select proconfig from pg_proc where proname='raise_coach_chat_cleared_at'")"

echo
if [ "$FAILS" -eq 0 ]; then echo "SUMMARY: all cases passed"; exit 0; else echo "SUMMARY: $FAILS failed"; exit 1; fi
