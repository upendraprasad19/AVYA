#!/bin/sh
# scripts/mint_migration.sh — the migration-number allocator (OI-263, 2026-09-29).
#
# Reserves the next free migration number N as the remote branch `mig/N`, using the remote's own
# "a ref cannot be created twice" as a compare-and-swap. Two sessions on two machines cannot both
# get N: the second create is refused and this script retries with N+1. Sibling of
# scripts/mint_oi.sh — the transport core (bounded / sync_refs / owner_repo / cas_write /
# delete_reservation) is a COPY with `oi/` -> `mig/`, pinned by
# test/scripts/mint_migration_parity_test.dart so an edit to one cannot silently miss the other.
#
# WHY: nothing allocated migration numbers. The next number was read off `ls supabase/migrations/`
# by whoever wrote the file, and the day-swapper migration was renumbered 145 -> 147 -> 148 -> 149
# because 148 had been applied LIVE from a branch that had not merged.
#
# WHAT A RESERVATION IS AND IS NOT: it is a global, server-side record of INTENT to use N, made
# before the file exists. scripts/check_migration_number_reserved.dart requires it for every new
# file. It does NOT prove a branch owns N, and it does not replace Gate 14's same-number check at
# merge; and it cannot see a raw apply that never registered a `schema_migrations` row (OI-223).
# Reconciling live prod against the ledger is OI-272, not this script.
#
# Usage:
#   sh scripts/mint_migration.sh <slug>                  reserve next free N, print MIG-N + the file path
#   sh scripts/mint_migration.sh --stub <slug>           ...and also write the file with the four-tag header
#   sh scripts/mint_migration.sh --live <file> <slug>    also count numbers in a `list_migrations` snapshot
#                                                        (a bare JSON array or {"migrations":[...]}); the
#                                                        agent has MCP, a shell does not
#   sh scripts/mint_migration.sh --reserve N <slug>      claim EXACTLY N (adopt a number already used).
#                                                        UNBOUNDED on purpose: it accepts any N up to 999,
#                                                        and next-free is 1 + the max over every mig/* ref,
#                                                        so `--reserve 900` moves the allocator to 901. Use it
#                                                        to adopt a number that is really in use; undo a
#                                                        mistake with `--release N`.
#   sh scripts/mint_migration.sh --release N             delete an UNFILED reservation
#   sh scripts/mint_migration.sh --prune                 delete mig/N whose N is on origin/main (laptop/API only)
#   sh scripts/mint_migration.sh --next                  read-only: NEXT=<n> and UNFILED=<n,n>
#
# NUMBER SPACE: 3-digit numbers only, printed `%03d`. Letter-suffixed follow-ups (050b, 068b) are
# NOT mintable — they are manual by precedent and need their BASE number published or reserved.
# Only TOP-LEVEL `NNN[x]_*.sql` names count: the three timestamp-scheme files and the `041_chunks/`
# directory are not allocated numbers (a naive `[0-9]+` would read 20260331000001 as the ceiling).
#
# "Next free" = 1 + max over: top-level migration names at origin/main, at local main, in the
# working tree; ledger ids at origin/main and in the working tree; `--live` names; every mig/*.
#
# Exit codes: 0 done · 2 cannot reach the remote (NOTHING written) · 3 taken / lost 10 races /
# refused release · 64 usage.
#
# Env: MINT_MIG_TRANSPORT=auto|api|git · MINT_MIG_REMOTE · MINT_MIG_GH_BIN · MINT_MIG_OWNER_REPO ·
# MINT_MIG_TEST_HOOK_BEFORE_PUSH (test seam, run with `sh -c` between the sync and the CAS write).
set -eu

TAG='[mint_migration]'
LEDGER=backups/applied_migrations.json
MIGDIR=supabase/migrations
REMOTE=${MINT_MIG_REMOTE:-origin}
TRANSPORT=${MINT_MIG_TRANSPORT:-auto}
case "${MINT_MIG_TRANSPORT:-}" in git) TRANSPORT_EXPLICIT=1 ;; *) TRANSPORT_EXPLICIT='' ;; esac
GH=${MINT_MIG_GH_BIN:-gh}
MAX_ATTEMPTS=10

usage() {
  cat >&2 <<'USAGE'
usage: sh scripts/mint_migration.sh [--stub] [--live FILE] [--] <slug>
       sh scripts/mint_migration.sh --reserve N [--stub] [--] <slug>
       sh scripts/mint_migration.sh --release N
       sh scripts/mint_migration.sh --prune | --next
USAGE
  exit 64
}

MODE=mint
STUB=''
LIVE_FILE=''
RESERVE_N=''
RELEASE_N=''
SLUG=''
while [ $# -gt 0 ]; do
  case "$1" in
    --stub) STUB=1 ;;
    --live)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      LIVE_FILE=$2
      shift ;;
    --reserve)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      RESERVE_N=$2
      shift ;;
    --release)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      RELEASE_N=$2
      MODE=release
      shift ;;
    --prune) MODE=prune ;;
    --next) MODE=next ;;
    -h|--help) usage ;;
    --)
      shift
      [ $# -gt 0 ] && SLUG=$1
      break ;;
    -*) echo "$TAG unknown flag: $1" >&2; usage ;;
    *) SLUG=$1 ;;
  esac
  shift
done
# A positive integer with no leading zero (`mig/007` would parse as 7 on the Dart side and as the
# string "007" here, so it would never prune and never block 7), and at most 3 digits (the number
# space is 3-digit; 4+ digits are timestamp-scheme territory).
for n in $RESERVE_N $RELEASE_N; do
  case "$n" in ''|0*|*[!0-9]*|????*) echo "$TAG --reserve/--release need a positive integer of at most 3 digits without leading zeros" >&2; usage ;; esac
done
if [ "$MODE" = mint ]; then
  [ -n "$SLUG" ] || { echo "$TAG a slug is required" >&2; usage; }
  case "$SLUG" in *[!a-z0-9_]*) echo "$TAG slug must match [a-z0-9_]+ (got: $SLUG)" >&2; usage ;; esac
fi
if [ -n "$LIVE_FILE" ] && [ ! -r "$LIVE_FILE" ]; then
  echo "$TAG --live file not readable: $LIVE_FILE" >&2
  exit 64
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "$TAG not inside a git repository" >&2; exit 2; }
cd "$ROOT"

if [ "$TRANSPORT" = auto ]; then
  if command -v gh >/dev/null 2>&1; then TRANSPORT=api; else TRANSPORT=git; fi
fi
case "$TRANSPORT" in api|git) ;; *) echo "$TAG MINT_MIG_TRANSPORT must be auto|api|git" >&2; exit 64 ;; esac

# `rev-parse --abbrev-ref` prints the literal `HEAD` on a detached HEAD (it does not fail), so the
# `|| echo detached` fallback only fires outside a repo. Informational only: it goes in the ledger
# subject, nothing compares it.
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)

# ---- transport core: COPIED from scripts/mint_oi.sh with `oi/` -> `mig/` -------------------
# (pinned by test/scripts/mint_migration_parity_test.dart — edit BOTH or the test goes red)
SYNC_ERR=''
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi
}
sync_refs() {
  SYNC_ERR=$(bounded git fetch --quiet --prune "$REMOTE" \
    "+refs/heads/mig/*:refs/remotes/$REMOTE/mig/*" \
    "+refs/heads/main:refs/remotes/$REMOTE/main" 2>&1 >/dev/null)
}
# ---- readers -------------------------------------------------------------------------------
# Every function below reads only TOP-LEVEL `NNN[x]_*.sql` basenames (allocation grammar). The
# `sed` strips the path so `supabase/migrations/041_chunks/x.sql` never reaches the grep — and
# `ls-tree` is non-recursive, so the chunk directory contributes only its own name (`041_chunks`),
# which the `.sql$` anchor rejects.
names_to_numbers() {
  sed 's#.*/##' | grep -E '^[0-9]{3}[a-z]?_[^/]*\.sql$' | cut -c1-3 | awk '{ print $1 + 0 }' || true
}
tree_numbers() { # $1 = a rev
  git ls-tree --name-only "$1" "$MIGDIR/" 2>/dev/null | names_to_numbers || true
}
# PRUNE must count only UNSUFFIXED names: `003b_followup.sql` on origin/main does not publish
# migration 003 (the gate lets a letter-suffix follow-up land with only its BASE reserved), so
# treating it as "003 is published" would prune the base's reservation while `003_*.sql` is still
# unmerged. next_free / --release / --next keep the wider (suffix-inclusive) reading, where
# over-counting only ever makes the allocator or the release guard more conservative.
published_base_numbers() {
  git ls-tree --name-only "refs/remotes/$REMOTE/main" "$MIGDIR/" 2>/dev/null \
    | sed 's#.*/##' | grep -E '^[0-9]{3}_[^/]*\.sql$' | cut -c1-3 | awk '{ print $1 + 0 }' || true
}
wt_numbers() {
  ls "$MIGDIR" 2>/dev/null | names_to_numbers || true
}
# `"migration": "151"` / `"migration": "120b"`; a 14-digit timestamp id has no closing quote after
# 3 digits, so it is excluded by the pattern itself.
ledger_numbers() { # reads a ledger on stdin
  grep -oE '"migration"[[:space:]]*:[[:space:]]*"[0-9]{3}[a-z]?"' | grep -oE '[0-9]{3}' | awk '{ print $1 + 0 }' || true
}
ledger_numbers_at() { git show "$1:$LEDGER" 2>/dev/null | ledger_numbers || true; }
live_numbers() {
  [ -n "$LIVE_FILE" ] || return 0
  grep -oE '"name"[[:space:]]*:[[:space:]]*"[0-9]{3}[a-z]?_' "$LIVE_FILE" | grep -oE '[0-9]{3}' | awk '{ print $1 + 0 }' || true
}
reserved_numbers() {
  git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE/mig/" \
    | sed 's#.*/mig/##' | grep -E '^[1-9][0-9]*$' | sort -n || true
}
# LOCAL main is included because merge-locally-then-push makes "merged but not yet pushed" the
# common state. Absent ref (a fresh cloud clone) => empty.
local_main_numbers() {
  if git rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then tree_numbers refs/heads/main; fi
}
published_numbers() { tree_numbers "refs/remotes/$REMOTE/main"; }

next_free() {
  n=$( { reserved_numbers; published_numbers; local_main_numbers; wt_numbers
         ledger_numbers_at "refs/remotes/$REMOTE/main"
         if [ -f "$LEDGER" ]; then ledger_numbers < "$LEDGER"; fi
         live_numbers; } | sort -n | tail -1 )
  echo $(( ${n:-0} + 1 ))
}

contains_line() { # $1 = newline-separated haystack, $2 = exact line
  printf '%s\n' "$1" | grep -qx -- "$2"
}

pad3() { printf '%03d' "$1"; }

# ---- the ledger commit ---------------------------------------------------------------------
# Parentless, on <remote>/main's TREE (already on the server => zero object upload), message = the
# provenance line. Author pinned so a clone without user.name still mints. INFORMATIONAL: the gate
# proves a reservation EXISTS, it does not compare the branch or slug recorded here.
# `pid $$` makes every reservation commit UNIQUE: tree + message + author + second would otherwise
# be byte-identical for a repeat mint of the same slug from the same branch, and pushing an object
# the remote ALREADY holds at that ref is an "up-to-date" success even under an empty-expect lease —
# a second claim on a taken number would read as a fresh reservation (found by this script's own
# --reserve test, 2026-09-29).
ledger_commit() { # $1 = N ; prints the local sha
  tree=$(git rev-parse "refs/remotes/$REMOTE/main^{tree}")
  stamp=$(date +%Y-%m-%dT%H:%M:%S%z)
  GIT_AUTHOR_NAME=mint_migration GIT_AUTHOR_EMAIL=mint_migration@local \
  GIT_COMMITTER_NAME=mint_migration GIT_COMMITTER_EMAIL=mint_migration@local \
    git commit-tree "$tree" -m "MIG-$1 | branch $BRANCH | $stamp | $SLUG | pid $$"
}

owner_repo() {
  if [ -n "${MINT_MIG_OWNER_REPO:-}" ]; then echo "$MINT_MIG_OWNER_REPO"; return; fi
  git remote get-url "$REMOTE" 2>/dev/null \
    | sed -nE 's#^(git@github\.com:|https://github\.com/)([^/]+)/([^/]+)$#\2/\3#p' \
    | sed 's/\.git$//'
}
# ---- the compare-and-swap write ------------------------------------------------------------
# $1 = N, $2 = local ledger sha. Returns 0 created (RESULT_SHA set), 3 taken, 2 unreachable. The
# distinction between 3 and 2 is the whole point: taken means retry; unreachable means stop.
cas_write() {
  case "$TRANSPORT" in
    git)
      if err=$(git push --quiet --force-with-lease="refs/heads/mig/$1:" \
                 "$REMOTE" "$2:refs/heads/mig/$1" 2>&1); then
        RESULT_SHA=$2; return 0
      fi
      case "$err" in
        *"stale info"*|*"already exists"*|*"rejected"*|*"failed to lock"*|*"cannot lock"*)
          # A rejection is a LOST RACE only if the ref now exists on the remote
          # (B-pass 2026-09-13, F4). `[rejected]` is also what a pre-receive
          # hook or a branch-protection rule prints; treating that as "taken"
          # would retry N+1 up to ten times and exit 3 with the real reason
          # never shown. `--exit-code`: 0 = ref present, 2 = absent, else the
          # remote could not be asked -- which is not a race either.
          if bounded git ls-remote --exit-code "$REMOTE" "refs/heads/mig/$1" >/dev/null 2>&1; then
            return 3
          fi
          echo "$TAG push REJECTED but refs/heads/mig/$1 does not exist on $REMOTE -- not a lost race, not retried: $err" >&2
          return 2 ;;
        *) echo "$TAG push failed: $err" >&2; return 2 ;;
      esac ;;
    api)
      repo=$(owner_repo)
      [ -n "$repo" ] || { echo "$TAG cannot derive owner/repo from the $REMOTE URL (set MINT_MIG_OWNER_REPO)" >&2; return 2; }
      tree=$(git rev-parse "refs/remotes/$REMOTE/main^{tree}")
      msg=$(git log -1 --format=%B "$2")
      if ! csha=$($GH api -X POST "repos/$repo/git/commits" \
                    -f message="$msg" -f tree="$tree" --jq .sha 2>/dev/null); then
        echo "$TAG gh api (create commit) failed — offline, or gh is not authenticated" >&2
        return 2
      fi
      if out=$($GH api -X POST "repos/$repo/git/refs" \
                 -f ref="refs/heads/mig/$1" -f sha="$csha" 2>&1); then
        RESULT_SHA=$csha; return 0
      fi
      case "$out" in
        *"already exists"*) return 3 ;;
        *) echo "$TAG gh api (create ref) failed: $out" >&2; return 2 ;;
      esac ;;
  esac
}
header_template() {
  cat <<'HDR'
-- Intent: <one-line description of what this migration accomplishes>
-- Destructive?: <yes | no>   -- "yes" if it DROPs, TRUNCATEs, alters constraints in a way that loses data, or rewrites rows
-- Rollback strategy: <inline | migration NNN | not applicable>
-- Linked diagnose-doc: <bug-id from docs/diagnoses/ | n/a>
HDR
}

write_stub() { # $1 = N
  f="$MIGDIR/$(pad3 "$1")_$SLUG.sql"
  if [ -e "$f" ]; then
    echo "$TAG $f already exists — not overwriting" >&2
    return 0
  fi
  mkdir -p "$MIGDIR"
  { header_template; printf '\n'; } > "$f"
}

delete_reservation() { # $1 = N ; 0 iff the remote ref is gone
  case "$TRANSPORT" in
    api) repo=$(owner_repo); $GH api -X DELETE "repos/$repo/git/refs/heads/mig/$1" >/dev/null 2>&1 ;;
    git) git push --quiet "$REMOTE" ":refs/heads/mig/$1" >/dev/null 2>&1 ;;
  esac && { git update-ref -d "refs/remotes/$REMOTE/mig/$1" 2>/dev/null || true; }
}
# Every migration number present on the tree of EVERY branch this clone knows about — local heads
# (a sibling worktree's work in flight) AND remote-tracking branches other than the reservation
# namespace (a cloud session or another machine pushed `claude/x` carrying `003_foo.sql`, which this
# clone never checked out). Without the second half that number looks UNFILED, `--release` would
# delete its live reservation and the next mint would hand it out again. Remote-tracking refs are
# only as fresh as this clone's last fetch — `sync_refs` fetches mig/* and main, not every branch —
# so a branch pushed since then is still invisible; the gate and Gate 14 are the merge-time backstop.
all_branch_numbers() {
  git for-each-ref --format='%(refname)' refs/heads/ "refs/remotes/$REMOTE/" \
    | grep -vE "^refs/remotes/$REMOTE/(mig/|HEAD$)" | while IFS= read -r ref; do
    tree_numbers "$ref"
  done | sort -un || true
}

ledger_subject() { git log -1 --format=%s "refs/remotes/$REMOTE/mig/$1" 2>/dev/null || echo '(no ledger line)'; }

do_release() {
  if contains_line "$(published_numbers)" "$RELEASE_N"; then
    echo "$TAG MIG-$RELEASE_N is PUBLISHED on $REMOTE/main — its reservation is pruned, never released." >&2
    exit 3
  fi
  if contains_line "$(wt_numbers)" "$RELEASE_N"; then
    echo "$TAG MIG-$RELEASE_N is FILED on THIS working tree — remove the file first if you really mean to release it." >&2
    exit 3
  fi
  if contains_line "$(all_branch_numbers)" "$RELEASE_N"; then
    echo "$TAG MIG-$RELEASE_N is FILED on a BRANCH this clone knows (a sibling worktree or a pushed branch — work in flight) — releasing it would strand that branch at its next commit. Refused." >&2
    exit 3
  fi
  if ! contains_line "$(reserved_numbers)" "$RELEASE_N"; then
    echo "$TAG mig/$RELEASE_N is not reserved on $REMOTE; nothing to release." >&2
    exit 3
  fi
  echo "$TAG releasing mig/$RELEASE_N — reserved by: $(ledger_subject "$RELEASE_N")" >&2
  delete_reservation "$RELEASE_N" || { echo "$TAG could not delete mig/$RELEASE_N on $REMOTE" >&2; exit 2; }
  echo "$TAG released mig/$RELEASE_N (it was reserved and never filed)."
}

do_prune() {
  if [ "$TRANSPORT" = git ] && [ -z "$TRANSPORT_EXPLICIT" ]; then
    echo "$TAG --prune deletes branches with a git push, which runs scripts/pre-push.sh once PER reservation on the laptop. Install gh (API transport), or set MINT_MIG_TRANSPORT=git explicitly to accept that cost." >&2
    exit 64
  fi
  published=$(published_base_numbers)
  pruned=0
  for n in $(reserved_numbers); do
    contains_line "$published" "$n" || continue
    delete_reservation "$n" || { echo "$TAG prune: could not delete mig/$n" >&2; continue; }
    pruned=$((pruned + 1))
  done
  echo "$TAG pruned $pruned reservation(s) whose number is already on $REMOTE/main."
}

do_next() {
  published=$(published_numbers)
  local_nums=$( { wt_numbers; all_branch_numbers; } )
  unfiled=''
  for r in $(reserved_numbers); do
    contains_line "$published" "$r" && continue
    contains_line "$local_nums" "$r" && continue
    unfiled="${unfiled:+$unfiled,}$r"
  done
  echo "NEXT=$(next_free)"
  echo "UNFILED=$unfiled"
}

do_mint() {
  if [ -n "$RESERVE_N" ]; then
    if contains_line "$(published_numbers)" "$RESERVE_N"; then
      echo "$TAG MIG-$RESERVE_N is already on $REMOTE/main — a published number needs no reservation." >&2
      exit 3
    fi
  fi
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    if [ -n "$RESERVE_N" ]; then n=$RESERVE_N; else n=$(next_free); fi
    if [ "$n" -gt 999 ]; then
      echo "$TAG the 3-digit number space is exhausted (next would be $n)" >&2
      exit 3
    fi
    sha=$(ledger_commit "$n")
    if [ -n "${MINT_MIG_TEST_HOOK_BEFORE_PUSH:-}" ]; then sh -c "$MINT_MIG_TEST_HOOK_BEFORE_PUSH"; fi
    rc=0
    cas_write "$n" "$sha" || rc=$?
    case $rc in
      0) break ;;
      3)
        if [ -n "$RESERVE_N" ]; then
          echo "$TAG TAKEN: mig/$n already exists on $REMOTE — someone else holds MIG-$n. Mint a fresh number instead." >&2
          exit 3
        fi
        if [ $attempt -ge $MAX_ATTEMPTS ]; then
          echo "$TAG gave up after $MAX_ATTEMPTS lost races (last tried MIG-$n). Nothing reserved." >&2
          exit 3
        fi
        sync_refs || { echo "$TAG lost the remote mid-retry. Nothing reserved." >&2; exit 2; } ;;
      *)
        echo "$TAG cannot reach $REMOTE — a migration number cannot be reserved offline. Nothing was written." >&2
        exit 2 ;;
    esac
  done

  # Make the reservation visible to sibling worktrees NOW, not at their next fetch (see mint_oi.sh).
  if [ "$TRANSPORT" = git ]; then
    git update-ref "refs/remotes/$REMOTE/mig/$n" "$RESULT_SHA" 2>/dev/null \
      || echo "$TAG note: reserved on $REMOTE, but could not update the local tracking ref; sibling worktrees see it at their next sync." >&2
  else
    git fetch --quiet "$REMOTE" "+refs/heads/mig/$n:refs/remotes/$REMOTE/mig/$n" >/dev/null 2>&1 \
      || echo "$TAG note: reserved on $REMOTE, but could not fetch mig/$n locally; sibling worktrees see it at their next sync." >&2
  fi
  if [ -n "$LIVE_FILE" ]; then
    echo "$TAG NOTE: --live sees only live names that carry an NNN_ prefix — live applies recorded under an unprefixed name (roughly half of the live rows, incl. every apply made through the MCP path) are invisible to it. A clean --live is partial coverage, not proof of uniqueness against prod." >&2
  else
    echo "$TAG NOTE: live prod was NOT consulted (no --live snapshot). The number is unique among reservations, origin/main, local main and the ledger — a live apply from an unmerged branch is invisible to those." >&2
  fi
  echo "MIG-$(pad3 "$n")"
  echo "$MIGDIR/$(pad3 "$n")_$SLUG.sql"
  if [ -n "$STUB" ]; then write_stub "$n"; else header_template >&2; fi
  if [ "$TRANSPORT" = api ]; then do_prune >/dev/null 2>&1 || true; fi
}

sync_refs || {
  case "$MODE" in
    mint) echo "$TAG cannot reach $REMOTE — a migration number cannot be reserved offline. Nothing was written." >&2 ;;
    *)    echo "$TAG cannot reach $REMOTE — --$MODE needs the remote's current reservations and tree." >&2 ;;
  esac
  [ -z "$SYNC_ERR" ] || printf '%s\n' "$SYNC_ERR" | sed 's/^/    git: /' >&2
  exit 2
}
case "$MODE" in
  next)    do_next ;;
  prune)   do_prune ;;
  release) do_release ;;
  mint)    do_mint ;;
esac
