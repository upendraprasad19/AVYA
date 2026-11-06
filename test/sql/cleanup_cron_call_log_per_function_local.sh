#!/usr/bin/env bash
# test/sql/cleanup_cron_call_log_per_function_local.sh
#
# Local-docker rehearsal for migration 172 (OI-199 + OI-471, diagnose b3e7d2). NEVER touches production: it starts its own
# throwaway container (public.ecr.aws/supabase/postgres:17.6.1.084, no published ports) and removes it on exit.
#
#   1. OLD   reset, apply the REAL migration 169 file, run the verify file: the cases that tell the old two-row keep-set from
#            the per-function one (B, C, D, F2, H, I, J) must go red; A, E, F, G must stay green.
#   2. NEW   reset, apply 169 then the REAL migration 172 file, run the verify file: every check ok. Then apply 172 a second
#            time (IF EXISTS: no error) and run the older pin test/sql/cleanup_cron_call_log_retention_live_verify.sql.
#   2b. APPLY REQUEST  the exact text the plan sends through execute_sql (BEGIN, SET LOCAL timeouts, the file's CREATE..DROP lines, an
#            in-transaction md5/length assertion, COMMIT) is built from the migration file and run on the 169 state: it commits; a
#            wrong md5 aborts it and rolls the CREATE and the DROP back together; an unseen catalog dependent of the orphan makes the
#            DROP fail and rolls the CREATE back with it (Hermes A-1).
#   3. MUTANTS  each on its OWN reset (so M9, "delete the DROP", starts from a state where the orphan exists): a scratch copy
#            of the 172 file is mutated, the change is confirmed applied, applied, and the verify file is run. An apply or
#            verify ERROR is reported as ERROR and fails the run: a compile error is not a kill.
#
# The migration files are applied as files, never as embedded copies, so there is nothing to drift. The table and indexes are
# cut out of 068, the alert command out of 170 (between its two $$ tags). The orphan pruner is created by hand from the LIVE body
# read 2026-11-06 (no migration creates it).
#
# Usage: bash test/sql/cleanup_cron_call_log_per_function_local.sh        (exit 0 = every expectation met; NOT `sh`: /bin/sh is
# dash here and the script uses `set -o pipefail`, so `sh` dies on line 22 before any docker call)
# Needs docker and the image above present locally (no pull is attempted).

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MIG="$ROOT/supabase/migrations"
F068="$MIG/068_cron_call_log.sql"
F169="$MIG/169_cron_call_log_retention_10d.sql"
F170="$MIG/170_oi473_cron_dead_alert_edges.sql"
F172="$MIG/172_cron_call_log_per_function_keep.sql"
VERIFY="$HERE/cleanup_cron_call_log_per_function_verify.sql"
OLDPIN="$HERE/cleanup_cron_call_log_retention_live_verify.sql"
C="oi199-pgtest"
IMG="public.ecr.aws/supabase/postgres:17.6.1.084"
SCR="$(mktemp -d "${TMPDIR:-/tmp}/oi199.XXXXXX")"
FAILS=0

cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; rm -rf "$SCR"; }
trap cleanup EXIT

for f in "$F068" "$F169" "$F170" "$F172" "$VERIFY" "$OLDPIN"; do
  [ -f "$f" ] || { echo "MISSING FILE: $f"; exit 2; }
done
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

reset_db() {
  local alert_body
  alert_body="$(sed -n '/command := \$\$/,/^  \$\$$/p' "$F170" | sed '1d;$d')"
  [ -n "$alert_body" ] || { echo "could not extract the alert command from 170"; return 1; }
  {
    cat <<'SQL'
DROP TABLE IF EXISTS public.cron_call_log CASCADE;
DROP TABLE IF EXISTS public.alerts CASCADE;
DROP TABLE IF EXISTS public._alert_cmd CASCADE;
DROP VIEW IF EXISTS public._dep_on_orphan;
DROP FUNCTION IF EXISTS public.cleanup_cron_call_log();
DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();
CREATE TABLE public.alerts (
  id               bigserial PRIMARY KEY,
  detected_at      timestamptz NOT NULL DEFAULT now(),
  source           text NOT NULL,
  severity         text NOT NULL,
  summary          text NOT NULL,
  context_json     jsonb,
  suggested_action text,
  acknowledged     boolean NOT NULL DEFAULT false,
  resolved_at      timestamptz
);
SQL
    sed -n '/^CREATE TABLE IF NOT EXISTS public.cron_call_log/,/^);/p' "$F068"
    sed -n '/^CREATE INDEX IF NOT EXISTS idx_cron_call_log_function_started/,/;$/p' "$F068"
    sed -n '/^CREATE INDEX IF NOT EXISTS idx_cron_call_log_status_started/,/;$/p' "$F068"
    echo "CREATE TABLE public._alert_cmd (t text);"
    printf 'INSERT INTO public._alert_cmd VALUES ($cmd$%s$cmd$);\n' "$alert_body"
    cat <<'SQL'
CREATE FUNCTION public.cron_call_log_cleanup_7d() RETURNS void LANGUAGE sql SECURITY DEFINER
  SET search_path TO 'public', 'extensions', 'vault', 'private' AS $o$
  DELETE FROM public.cron_call_log
  WHERE started_at < now() - interval '7 days';
$o$;
REVOKE ALL ON FUNCTION public.cron_call_log_cleanup_7d() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cron_call_log_cleanup_7d() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cron_call_log_cleanup_7d() TO postgres, service_role;
SQL
  } | pg -f - || return 1
}

# run the verify file; sets VOUT (raw), VSUM (summary line), and returns 0 when psql itself ran cleanly
run_verify() {
  VOUT="$(pg -A -t -F'|' < "$VERIFY" 2>&1)"; local rc=$?
  VSUM="$(printf '%s\n' "$VOUT" | grep -E '^(ALL OK|FAILED)' | tail -1)"
  return $rc
}
reds() { printf '%s\n' "$VOUT" | grep '|fail|' | cut -d'|' -f1; }
has_red()   { reds | grep -Eq "$1"; }
no_red()    { ! reds | grep -Eq "$1"; }
expect() {  # expect <description> <cmd...>
  local d="$1"; shift
  if "$@"; then echo "  ok    $d"; else echo "  FAIL  $d"; FAILS=$((FAILS + 1)); fi
}

echo "== 1. OLD body (migration 169 applied) =="
reset_db || { echo "reset failed"; exit 2; }
pg -f - < "$F169" || { echo "169 failed to apply"; exit 2; }
run_verify || { echo "verify errored under 169:"; printf '%s\n' "$VOUT" | tail -5; exit 2; }
echo "  summary: $VSUM"; echo "  red labels: $(reds | tr '\n' ' ')"
for g in '^B_' '^C_' '^D_' '^F2_' '^H_' '^H2_dead_fleet_survivors_equal_oracle' '^I_' '^J'; do expect "red under 169: $g" has_red "$g"; done
for g in '^A_' '^E_' '^F_' '^G_' '^K_' '^H2_fixture' '^H2_dead_fleet_old_keep'; do expect "green under 169: $g" no_red "$g"; done

# The verify file must REFUSE to run outside the scaffold (it empties cron_call_log): rename the marker table, expect a non-zero
# exit and the guard's message, restore it. Runs on the 169 state built above.
pg -c 'ALTER TABLE public._alert_cmd RENAME TO _alert_cmd_hidden' >/dev/null || { echo "rename failed"; exit 2; }
GUARD_OUT="$(pg -A -t -F'|' < "$VERIFY" 2>&1)"; GUARD_RC=$?
pg -c 'ALTER TABLE public._alert_cmd_hidden RENAME TO _alert_cmd' >/dev/null || { echo "rename back failed"; exit 2; }
expect "verify file refuses to run without the scaffold (rc=$GUARD_RC)" bash -c '[ "$1" -ne 0 ] && [[ "$2" == *"local harness only"* ]]' _ "$GUARD_RC" "$GUARD_OUT"
ACL169="$(pg -A -t -c "SELECT proacl::text FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure")"
echo "  ACL under 169: $ACL169"

echo "== 2. NEW body (migration 172 applied on top of 169) =="
reset_db || { echo "reset failed"; exit 2; }
pg -f - < "$F169" || { echo "169 failed to apply"; exit 2; }
pg -f - < "$F172" || { echo "172 failed to apply"; exit 2; }
run_verify || { echo "verify errored under 172:"; printf '%s\n' "$VOUT" | tail -5; exit 2; }
echo "  summary: $VSUM"; echo "  red labels: $(reds | tr '\n' ' ')"
expect "verify file all ok under 172" test "${VSUM#ALL OK}" != "$VSUM"
ACL172="$(pg -A -t -c "SELECT proacl::text FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure")"
expect "proacl is IDENTICAL after 172 (169: $ACL169 / 172: $ACL172)" test -n "$ACL169" -a "$ACL169" = "$ACL172"
# The value the live apply asserts: md5 and length of the raw function text, as measured on migration 172's own $fn$ tags.
EXPECT_MD5=6597e3e24f91126b6268b3d54aa7ea57
EXPECT_LEN=460
GOT_SRC="$(pg -A -t -F'|' -c "SELECT md5(prosrc), length(prosrc) FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure")"
expect "md5(prosrc)|length(prosrc) equal the values the live apply asserts (got $GOT_SRC)" test "$GOT_SRC" = "$EXPECT_MD5|$EXPECT_LEN"
expect "172 applies a second time without error (IF EXISTS)" pg -f - < "$F172"
OLDOUT="$(pg -A -t -F'|' < "$OLDPIN" 2>&1)"
echo "  older pin (cleanup_cron_call_log_retention_live_verify.sql): $(printf '%s\n' "$OLDOUT" | grep -E '^(ALL OK|FAILED)' | tail -1)"
expect "older pin all ok under 172" bash -c '[[ "$1" == *"ALL OK"* ]]' _ "$OLDOUT"
reset_db || exit 2
pg -f - < "$F169" || exit 2
OLDOUT169="$(pg -A -t -F'|' < "$OLDPIN" 2>&1)"
expect "older pin all ok under 169 too" bash -c '[[ "$1" == *"ALL OK"* ]]' _ "$OLDOUT169"

echo "== 2b. The live APPLY REQUEST: the exact text the plan sends through execute_sql, run on the 169 state =="
# The request is the migration FILE's statements (CREATE to DROP, about 880 B) inside BEGIN, SET LOCAL timeouts and an
# in-transaction assertion, sent as ONE request. The wrapper below is the text of the plan's "Live apply" section.
build_apply_request() {  # build_apply_request <migration file> <md5 the assertion expects>
  {
    cat <<'SQL'
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '60s';
SQL
    sed -n '/^CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()/,/^DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();/p' "$1"
    cat <<SQL
DO \$a\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure
                   AND md5(prosrc) = '$2' AND length(prosrc) = $EXPECT_LEN)
     OR to_regprocedure('public.cron_call_log_cleanup_7d()') IS NOT NULL THEN
    RAISE EXCEPTION 'migration 172 post-condition failed';
  END IF;
END \$a\$;
COMMIT;
SQL
  }
}
fn_md5() { pg -A -t -c "SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure"; }
MD5_169=0d14570d905770a34f9845683ca4aed4

reset_db || exit 2; pg -f - < "$F169" || exit 2
build_apply_request "$F172" "$EXPECT_MD5" > "$SCR/apply_request.sql"
REQ_BYTES="$(sed -n '/^CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()/,/^DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();/p' "$F172" | wc -c | tr -d ' ')"
expect "the statements extracted from the file are the 880-byte block the plan quotes (got $REQ_BYTES)" test "$REQ_BYTES" = 880
expect "the apply request runs to COMMIT without error" pg -f - < "$SCR/apply_request.sql"
expect "after the request: md5(prosrc) is the asserted value and the orphan is gone" \
  bash -c '[ "$1" = "$2" ]' _ "$(fn_md5)" "$EXPECT_MD5"
expect "after the request: proacl is identical to the 169 state" \
  bash -c '[ "$1" = "$2" ]' _ "$(pg -A -t -c "SELECT proacl::text FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure")" "$ACL169"

# NEGATIVE 1: a wrong expected md5 makes the in-transaction assertion raise, and the CREATE and the DROP roll back TOGETHER.
reset_db || exit 2; pg -f - < "$F169" || exit 2
build_apply_request "$F172" 00000000000000000000000000000000 > "$SCR/apply_bad_md5.sql"
BAD_OUT="$(pg -f - < "$SCR/apply_bad_md5.sql" 2>&1)"; BAD_RC=$?
expect "a wrong md5 aborts the request (rc=$BAD_RC) with the post-condition message" \
  bash -c '[ "$1" -ne 0 ] && [[ "$2" == *"post-condition failed"* ]]' _ "$BAD_RC" "$BAD_OUT"
expect "...and nothing of it persisted: the 169 body and the orphan are both still there" \
  bash -c '[ "$1" = "$2" ] && [ "$3" = t ]' _ "$(fn_md5)" "$MD5_169" "$(pg -A -t -c "SELECT to_regprocedure('public.cron_call_log_cleanup_7d()') IS NOT NULL")"

# NEGATIVE 2: an unseen CATALOG dependent of the orphan makes the DROP (no CASCADE) fail, and the CREATE rolls back with it.
reset_db || exit 2; pg -f - < "$F169" || exit 2
pg -c 'CREATE VIEW public._dep_on_orphan AS SELECT public.cron_call_log_cleanup_7d() IS NULL AS x' >/dev/null || { echo "dependent view failed"; exit 2; }
DEP_OUT="$(pg -f - < "$SCR/apply_request.sql" 2>&1)"; DEP_RC=$?
expect "a catalog dependent makes the request fail closed (rc=$DEP_RC)" \
  bash -c '[ "$1" -ne 0 ] && [[ "$2" == *"depend"* ]]' _ "$DEP_RC" "$DEP_OUT"
expect "...and the CREATE rolled back with the failed DROP (169 body still live)" \
  bash -c '[ "$1" = "$2" ]' _ "$(fn_md5)" "$MD5_169"

mutate() {  # mutate <name> <file>   (in place; every pattern is anchored to a non-comment line)
  case "$1" in
    M1)  sed -i "s/^          WHERE status = 'success' ORDER BY/          ORDER BY/" "$2" ;;
    M2)  sed -i '/^        UNION$/,/^          ORDER BY function_name, started_at DESC, id DESC)$/d' "$2" ;;
    M3)  sed -i 's/^        (SELECT DISTINCT ON (function_name) id FROM/        (SELECT id FROM/' "$2" ;;
    M3b) sed -i -e 's/^        (SELECT DISTINCT ON (function_name) id FROM/        (SELECT id FROM/' \
                -e 's/ORDER BY function_name, started_at DESC, id DESC)$/ORDER BY started_at DESC LIMIT 1)/' "$2" ;;
    M4)  sed -i 's/started_at DESC, id DESC)$/started_at ASC, id DESC)/' "$2" ;;
    M5)  sed -i 's/^        UNION$/        INTERSECT/' "$2" ;;
    M6)  sed -i "s/^  WHERE started_at < now() - interval '10 days'/  WHERE started_at < now() - interval '7 days'/" "$2" ;;
    M7)  sed -i 's/^    AND id NOT IN (/    AND id IN (/' "$2" ;;
    M8)  sed -i -e '/^  WHERE started_at < now() - interval/d' -e 's/^    AND id NOT IN (/  WHERE id NOT IN (/' "$2" ;;
    M9)  sed -i '/^DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();$/d' "$2" ;;
    M10) sed -i "s/^          ORDER BY function_name, started_at DESC, id DESC)\$/          WHERE status <> 'started' ORDER BY function_name, started_at DESC, id DESC)/" "$2" ;;
    M11) sed -i "s/^  WHERE started_at < now() - interval '10 days'/  WHERE started_at <= now() - interval '10 days'/" "$2" ;;
    M12) sed -i 's/started_at DESC, id DESC)$/started_at DESC)/' "$2" ;;
    # The function's security envelope. CREATE OR REPLACE keeps the 169 ACL but RESETS the security mode and proconfig, so M14 and
    # M15 show up in case K and nowhere else; M13 adds a grant. Deleting a REVOKE line is EQUIVALENT in this harness (172 is applied
    # on top of 169's ACL), so the REVOKE/GRANT text is pinned by the Dart attribute fixtures A3 to A5 instead.
    M13) sed -i 's/^GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;$/GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres, anon;/' "$2" ;;
    M14) sed -i 's/^SECURITY DEFINER$/SECURITY INVOKER/' "$2" ;;
    M15) sed -i "/^SET search_path TO 'public'\$/d" "$2" ;;
    # M16 to M18: the grants. A GRANT to PUBLIC, a GRANT to authenticated, and a REVOKE from the cron owner (postgres is a superuser
    # here, so only the ACL text, read in K_postgres_has_acl_execute, can see the last one).
    M16) sed -i 's/^GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;$/GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres, PUBLIC;/' "$2" ;;
    M17) sed -i 's/^GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;$/GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres, authenticated;/' "$2" ;;
    M18) sed -i 's/^GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;$/REVOKE EXECUTE ON FUNCTION public.cleanup_cron_call_log() FROM postgres;/' "$2" ;;
  esac
}

echo "== 3. MUTANTS of the 172 body (each on its own reset) =="
# M12 (drop the id tie-break) may survive in principle: which of two tied rows DISTINCT ON picks is planner-dependent; a
# survivor is reported, never counted as coverage (it was killed through case F2 in every run so far). The text of the tie-break
# is pinned independently by the Dart fixture M12 in test/contracts/cleanup_cron_call_log_per_function_keep_test.dart. Every
# other mutant must go red.
for M in M1 M2 M3 M3b M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14 M15 M16 M17 M18; do
  cp "$F172" "$SCR/m.sql"
  mutate "$M" "$SCR/m.sql"
  CHG="$(diff "$F172" "$SCR/m.sql" | grep -c '^[<>]')"
  if cmp -s "$F172" "$SCR/m.sql" || [ "$CHG" -eq 0 ]; then
    echo "  $M  NOT APPLIED (the sed pattern matched nothing)"; FAILS=$((FAILS + 1)); continue
  fi
  reset_db || { echo "  $M  reset failed"; FAILS=$((FAILS + 1)); continue; }
  pg -f - < "$F169" >/dev/null || { echo "  $M  169 failed"; FAILS=$((FAILS + 1)); continue; }
  if ! pg -f - < "$SCR/m.sql" >"$SCR/apply.out" 2>&1; then
    echo "  $M  ERROR applying the mutant (a compile error is NOT a kill): $(tail -1 "$SCR/apply.out")"; FAILS=$((FAILS + 1)); continue
  fi
  if ! run_verify; then
    echo "  $M  ERROR running the verify file: $(printf '%s\n' "$VOUT" | tail -1)"; FAILS=$((FAILS + 1)); continue
  fi
  N="$(reds | wc -l | tr -d ' ')"
  if [ "$N" -gt 0 ]; then
    echo "  $M  killed  ($CHG changed lines, $N red: $(reds | tr '\n' ' '))"
  elif [ "$M" = "M12" ]; then
    echo "  $M  SURVIVED ($CHG changed lines, 0 red): planner-dependent tie pick, reported, not counted as coverage"
  else
    echo "  $M  SURVIVED ($CHG changed lines, 0 red)  <-- a mutant that reddens nothing"; FAILS=$((FAILS + 1))
  fi
done

echo
if [ "$FAILS" -eq 0 ]; then echo "HARNESS OK (every expectation met)"; else echo "HARNESS FAILED: $FAILS expectation(s) not met"; fi
[ "$FAILS" -eq 0 ]
