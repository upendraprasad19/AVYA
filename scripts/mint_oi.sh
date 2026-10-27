#!/bin/sh
# scripts/mint_oi.sh — the OI-number allocator.
#
# Reserves the next free OI number as the remote branch `oi/N`, using the
# remote's own "a ref cannot be created twice" as a compare-and-swap, then
# appends a board stub. Two sessions on two machines cannot both get N: the
# second create is refused by GitHub (HTTP 422 via the API; `[rejected]`
# with `--force-with-lease=<ref>:` via git) and this script retries with N+1.
#
# Spec: docs/superpowers/specs/2026-09-12-oi-allocator-design.md
#
# Usage:
#   sh scripts/mint_oi.sh "<title>"              reserve next free N, append stub, print OI-N
#   sh scripts/mint_oi.sh --no-append "<title>"  reserve + print only
#   sh scripts/mint_oi.sh --reserve N "<title>"  claim EXACTLY N (for a number filed
#                                                before the allocator existed); never appends
#   sh scripts/mint_oi.sh --prune                delete oi/N whose N is on origin/main's boards
#                                                (laptop/API only — via git it would pay the
#                                                pre-push hook per branch; refused unless
#                                                MINT_OI_TRANSPORT=git was set EXPLICITLY)
#   sh scripts/mint_oi.sh --release N            delete an UNFILED reservation (N on neither
#                                                origin/main's boards nor the local board) —
#                                                the only way an orphan ever goes away
#   sh scripts/mint_oi.sh --next                 read-only: prints NEXT=<n> and UNFILED=<n,n>
#
# An orphan (reserved, never filed — a session died between the CAS and the
# stub) may also be ADOPTED: write `## OI-N — …` by hand; Check C passes
# because oi/N exists. The gate bans UNRESERVED numbers, not hand-typing.
#
# Exit codes:
#   0   done
#   2   cannot reach the remote — NOTHING was written. A number cannot be
#       reserved offline; a local-only mint is exactly how collisions are born.
#   3   taken (--reserve), or 10 consecutive races lost
#   64  usage
#
# Transport (MINT_OI_TRANSPORT=auto|api|git, default auto):
#   api — `gh api`: two POSTs (git/commits, git/refs). Preferred on the laptop
#         because it is NOT a `git push`, so scripts/pre-push.sh (unconditional
#         `flutter analyze` + fail-safe full suite on an empty range) never runs.
#   git — `git push --force-with-lease=refs/heads/oi/N:` (empty expect = "must
#         not exist"; receive-pack enforces old-sha=0 under the ref lock). The
#         cloud has no `gh` and no hooks, so this is its path.
#   auto — api when `gh` is on PATH, else git.
#
# Other env: MINT_OI_REMOTE (origin) · MINT_OI_GH_BIN (gh; word-split on
# purpose so a test can pass "sh /path/shim") · MINT_OI_OWNER_REPO (override the
# owner/repo parsed from the remote URL) · MINT_OI_TEST_HOOK_BEFORE_PUSH (test
# seam: run with `sh -c` between the sync and the CAS write, nowhere else).
set -eu

TAG='[mint_oi]'
BOARD_OPEN=docs/audit/open_issues.md
BOARD_CLOSED=docs/audit/closed_issues.md
REMOTE=${MINT_OI_REMOTE:-origin}
TRANSPORT=${MINT_OI_TRANSPORT:-auto}
# "explicit" means the caller ASKED for the git transport (tests, a cloud user
# who accepts the cost) -- an explicit `auto` is not a request for git.
case "${MINT_OI_TRANSPORT:-}" in git) TRANSPORT_EXPLICIT=1 ;; *) TRANSPORT_EXPLICIT='' ;; esac
GH=${MINT_OI_GH_BIN:-gh}
MAX_ATTEMPTS=10

usage() {
  cat >&2 <<'USAGE'
usage: sh scripts/mint_oi.sh [--no-append] [--] "<title>"
       sh scripts/mint_oi.sh --reserve N [--] "<title>"
       sh scripts/mint_oi.sh --release N
       sh scripts/mint_oi.sh --prune | --next
USAGE
  exit 64
}

MODE=mint
APPEND=1
RESERVE_N=''
RELEASE_N=''
TITLE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --no-append) APPEND=0 ;;
    --reserve)
      [ $# -ge 2 ] && [ -n "$2" ] || usage   # an EMPTY value would vanish from the validator's word list below
      RESERVE_N=$2
      APPEND=0
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
      # End of options (B-pass 2026-09-13, F1): a title that begins with `-`
      # would otherwise be read as an unknown flag and be unmintable.
      shift
      [ $# -gt 0 ] && TITLE=$1
      break ;;
    -*) echo "$TAG unknown flag: $1 (a title starting with '-' goes after '--')" >&2; usage ;;
    *) TITLE=$1 ;;
  esac
  shift
done
# A positive integer with no leading zero: `oi/007` would parse as 7 on the Dart
# side and as the string "007" here, so it would never prune and never block 7.
for n in $RESERVE_N $RELEASE_N; do
  case "$n" in ''|0*|*[!0-9]*) echo "$TAG --reserve/--release need a positive integer without leading zeros" >&2; usage ;; esac
done
if [ "$MODE" = mint ] && [ -z "$TITLE" ]; then
  echo "$TAG a title is required" >&2
  usage
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "$TAG not inside a git repository" >&2; exit 2; }
cd "$ROOT"

if [ "$TRANSPORT" = auto ]; then
  if command -v gh >/dev/null 2>&1; then TRANSPORT=api; else TRANSPORT=git; fi
fi
case "$TRANSPORT" in api|git) ;; *) echo "$TAG MINT_OI_TRANSPORT must be auto|api|git" >&2; exit 64 ;; esac

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)

# ---- sync: the local copy of the allocator state IS git's ref store ----------
# Fetch every reservation into refs/remotes/<remote>/oi/* (pruning ones deleted
# upstream) and refresh <remote>/main, whose boards are the published numbers.
# On the laptop refs/remotes/ lives in the SHARED .git/, so one worktree's
# fetch is every worktree's fetch.
# Bounded: coreutils `timeout` exists on Git Bash and Linux; without it the
# fetch runs unbounded. A real SSH outage otherwise blocks for the TCP connect
# timeout (tens of seconds) — a renamed fixture fails instantly either way.
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi
}
# Captures stderr into SYNC_ERR so "offline" is never the only diagnosis: a
# shared-.git fetch lock held by a sibling worktree, a hook rejection, or a
# missing SSH key all fail here too, and each says so in git's own words.
SYNC_ERR=''
sync_refs() {
  SYNC_ERR=$(bounded git fetch --quiet --prune "$REMOTE" \
    "+refs/heads/oi/*:refs/remotes/$REMOTE/oi/*" \
    "+refs/heads/main:refs/remotes/$REMOTE/main" 2>&1 >/dev/null)
}

# ---- readers -----------------------------------------------------------------
# Every OI number on both boards at $1 (a rev), or in the working tree when $1
# is empty. ASCII prefix only — immune to the em-dash mis-decoding that once
# blanked the Dart gate (check_oi_numbering_unique.dart:53-60).
board_numbers() {
  if [ -n "${1:-}" ]; then
    { git show "$1:$BOARD_OPEN" 2>/dev/null || true
      git show "$1:$BOARD_CLOSED" 2>/dev/null || true; }
  else
    { cat "$BOARD_OPEN" 2>/dev/null || true
      cat "$BOARD_CLOSED" 2>/dev/null || true; }
  fi | grep -oE '^## OI-[0-9]+' | grep -oE '[0-9]+$' || true
}

reserved_numbers() {
  git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE/oi/" \
    | sed 's#.*/oi/##' | grep -E '^[0-9]+$' | sort -n || true
}

# LOCAL main is included because §4.13's merge-locally-then-push workflow makes
# "merged but not yet pushed" the common state: a number on local main that
# origin/main lacks is still taken. Absent ref (a fresh cloud clone) => empty.
local_main_numbers() {
  if git rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then
    board_numbers refs/heads/main
  fi
}

next_free() {
  n=$( { reserved_numbers; board_numbers "refs/remotes/$REMOTE/main"; local_main_numbers; board_numbers ''; } \
       | sort -n | tail -1 )
  echo $(( ${n:-0} + 1 ))
}

contains_line() { # $1 = newline-separated haystack, $2 = exact line
  printf '%s\n' "$1" | grep -qx -- "$2"
}

# ---- the ledger commit ------------------------------------------------------
# Parentless, on <remote>/main's TREE (already on the server ⇒ zero object
# upload), message = the provenance line. Author is pinned so a clone without
# user.name still mints; who minted is in the MESSAGE, not the author.
ledger_commit() { # $1 = N ; prints the local sha
  tree=$(git rev-parse "refs/remotes/$REMOTE/main^{tree}")
  stamp=$(date +%Y-%m-%dT%H:%M:%S%z)
  GIT_AUTHOR_NAME=mint_oi GIT_AUTHOR_EMAIL=mint_oi@local \
  GIT_COMMITTER_NAME=mint_oi GIT_COMMITTER_EMAIL=mint_oi@local \
    git commit-tree "$tree" -m "OI-$1 | branch $BRANCH | $stamp | $TITLE"
}

owner_repo() {
  if [ -n "${MINT_OI_OWNER_REPO:-}" ]; then echo "$MINT_OI_OWNER_REPO"; return; fi
  git remote get-url "$REMOTE" 2>/dev/null \
    | sed -nE 's#^(git@github\.com:|https://github\.com/)([^/]+)/([^/]+)$#\2/\3#p' \
    | sed 's/\.git$//'
}

# ---- the compare-and-swap write ----------------------------------------------
# $1 = N, $2 = local ledger sha. Returns 0 created (RESULT_SHA set), 3 taken,
# 2 unreachable. The distinction between 3 and 2 is the whole point: taken
# means retry; unreachable means stop and write nothing.
cas_write() {
  case "$TRANSPORT" in
    git)
      if err=$(git push --quiet --force-with-lease="refs/heads/oi/$1:" \
                 "$REMOTE" "$2:refs/heads/oi/$1" 2>&1); then
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
          if bounded git ls-remote --exit-code "$REMOTE" "refs/heads/oi/$1" >/dev/null 2>&1; then
            return 3
          fi
          echo "$TAG push REJECTED but refs/heads/oi/$1 does not exist on $REMOTE -- not a lost race, not retried: $err" >&2
          return 2 ;;
        *) echo "$TAG push failed: $err" >&2; return 2 ;;
      esac ;;
    api)
      repo=$(owner_repo)
      [ -n "$repo" ] || { echo "$TAG cannot derive owner/repo from the $REMOTE URL (set MINT_OI_OWNER_REPO)" >&2; return 2; }
      tree=$(git rev-parse "refs/remotes/$REMOTE/main^{tree}")
      msg=$(git log -1 --format=%B "$2")
      if ! csha=$($GH api -X POST "repos/$repo/git/commits" \
                    -f message="$msg" -f tree="$tree" --jq .sha 2>/dev/null); then
        echo "$TAG gh api (create commit) failed — offline, or gh is not authenticated" >&2
        return 2
      fi
      if out=$($GH api -X POST "repos/$repo/git/refs" \
                 -f ref="refs/heads/oi/$1" -f sha="$csha" 2>&1); then
        RESULT_SHA=$csha; return 0
      fi
      case "$out" in
        *"already exists"*) return 3 ;;
        *) echo "$TAG gh api (create ref) failed: $out" >&2; return 2 ;;
      esac ;;
  esac
}

append_stub() { # $1 = N
  today=$(date +%Y-%m-%d)
  # The leading newline terminates an unterminated last line AND yields the
  # blank line before the heading when the file already ends in a newline.
  printf '\n## OI-%s — %s\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n- **Identified**: %s · filed via mint_oi.sh from branch `%s`\n' \
    "$1" "$TITLE" "$today" "$BRANCH" >> "$BOARD_OPEN"
}

# The REMOTE delete is the operation; the local tracking-ref delete is
# bookkeeping and must not turn a successful remote delete into "could not
# delete" (the next sync prunes it anyway).
delete_reservation() { # $1 = N ; 0 iff the remote ref is gone
  case "$TRANSPORT" in
    api) repo=$(owner_repo); $GH api -X DELETE "repos/$repo/git/refs/heads/oi/$1" >/dev/null 2>&1 ;;
    git) git push --quiet "$REMOTE" ":refs/heads/oi/$1" >/dev/null 2>&1 ;;
  esac && { git update-ref -d "refs/remotes/$REMOTE/oi/$1" 2>/dev/null || true; }
}

# Every OI number on the boards of EVERY local branch -- a number in flight on
# a sibling worktree's branch is filed, not orphaned, even though this
# worktree's board and origin/main both lack it.
all_local_branch_numbers() {
  # ONE `git grep` per 150 branches over both boards -- 0.2 s for the 205 local
  # branches this repo carried on 2026-09-12 -- instead of one `git show` per
  # branch per board, which measured 24.6 s for `--next` in the same repo.
  # Chunked so the argument list stays under Windows' 32 KB limit.
  git for-each-ref --format='%(refname)' refs/heads/ | while :; do
    chunk=''; n=0
    while [ "$n" -lt 150 ] && IFS= read -r ref; do chunk="$chunk $ref"; n=$((n + 1)); done
    [ -n "$chunk" ] || break
    # shellcheck disable=SC2086
    git grep -h -o -E '^## OI-[0-9]+' $chunk -- "$BOARD_OPEN" "$BOARD_CLOSED" 2>/dev/null || true
    [ "$n" -lt 150 ] && break
  done | grep -oE '[0-9]+$' | sort -un || true
}

ledger_subject() { git log -1 --format=%s "refs/remotes/$REMOTE/oi/$1" 2>/dev/null || echo '(no ledger line)'; }

do_release() {
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  if contains_line "$published" "$RELEASE_N"; then
    echo "$TAG OI-$RELEASE_N is PUBLISHED on $REMOTE/main — its reservation is pruned, never released." >&2
    exit 3
  fi
  if contains_line "$(board_numbers '')" "$RELEASE_N"; then
    echo "$TAG OI-$RELEASE_N is FILED on THIS board (uncommitted or committed) — remove the entry first if you really mean to release it." >&2
    exit 3
  fi
  if contains_line "$(all_local_branch_numbers)" "$RELEASE_N"; then
    echo "$TAG OI-$RELEASE_N is FILED on a LOCAL BRANCH (a sibling worktree's work in flight) — releasing it would strand that branch at its next commit. Refused." >&2
    exit 3
  fi
  if ! contains_line "$(reserved_numbers)" "$RELEASE_N"; then
    echo "$TAG oi/$RELEASE_N is not reserved on $REMOTE; nothing to release." >&2
    exit 3
  fi
  # A CLOUD branch's in-flight number is invisible here (no local branch for
  # it). The ledger line names who reserved it and when; the operator decides.
  echo "$TAG releasing oi/$RELEASE_N — reserved by: $(ledger_subject "$RELEASE_N")" >&2
  delete_reservation "$RELEASE_N" || { echo "$TAG could not delete oi/$RELEASE_N on $REMOTE" >&2; exit 2; }
  echo "$TAG released oi/$RELEASE_N (it was reserved and never filed)."
}

do_prune() {
  if [ "$TRANSPORT" = git ] && [ -z "$TRANSPORT_EXPLICIT" ]; then
    echo "$TAG --prune deletes branches with git push, which runs scripts/pre-push.sh once PER reservation on the laptop. Install gh (API transport), or set MINT_OI_TRANSPORT=git explicitly to accept that cost." >&2
    exit 64
  fi
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  pruned=0
  for n in $(reserved_numbers); do
    contains_line "$published" "$n" || continue
    delete_reservation "$n" || { echo "$TAG prune: could not delete oi/$n" >&2; continue; }
    pruned=$((pruned + 1))
  done
  echo "$TAG pruned $pruned reservation(s) whose number is already on $REMOTE/main."
}

do_next() {
  published=$(board_numbers "refs/remotes/$REMOTE/main")
  local_nums=$( { board_numbers ''; all_local_branch_numbers; } )
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
    published=$(board_numbers "refs/remotes/$REMOTE/main")
    if contains_line "$published" "$RESERVE_N"; then
      echo "$TAG OI-$RESERVE_N is already on $REMOTE/main's board — a published number needs no reservation." >&2
      exit 3
    fi
  fi
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    if [ -n "$RESERVE_N" ]; then n=$RESERVE_N; else n=$(next_free); fi
    sha=$(ledger_commit "$n")
    if [ -n "${MINT_OI_TEST_HOOK_BEFORE_PUSH:-}" ]; then sh -c "$MINT_OI_TEST_HOOK_BEFORE_PUSH"; fi
    rc=0
    cas_write "$n" "$sha" || rc=$?
    case $rc in
      0) break ;;
      3)
        if [ -n "$RESERVE_N" ]; then
          echo "$TAG TAKEN: oi/$n already exists on $REMOTE — someone else holds OI-$n. Mint a fresh number instead." >&2
          exit 3
        fi
        if [ $attempt -ge $MAX_ATTEMPTS ]; then
          echo "$TAG gave up after $MAX_ATTEMPTS lost races (last tried OI-$n). Nothing reserved." >&2
          exit 3
        fi
        sync_refs || { echo "$TAG lost the remote mid-retry. Nothing reserved." >&2; exit 2; } ;;
      *)
        echo "$TAG cannot reach $REMOTE — an OI number cannot be reserved offline. Nothing was written." >&2
        exit 2 ;;
    esac
  done

  # Make the reservation visible to sibling worktrees NOW, not at their next
  # fetch. git transport: the object is local, point the tracking ref at it.
  # api transport: the commit was created server-side and does NOT exist
  # locally (update-ref would refuse an unknown object) — fetch just that ref.
  # Best-effort on BOTH transports: the reservation already exists on the
  # remote, so a transient ref-lock (a sibling worktree fetching) must not abort
  # before the stub and the OI-N line -- that is exactly how an orphan is made.
  if [ "$TRANSPORT" = git ]; then
    git update-ref "refs/remotes/$REMOTE/oi/$n" "$RESULT_SHA" 2>/dev/null \
      || echo "$TAG note: reserved on $REMOTE, but could not update the local tracking ref; sibling worktrees see it at their next sync." >&2
  else
    git fetch --quiet "$REMOTE" "+refs/heads/oi/$n:refs/remotes/$REMOTE/oi/$n" >/dev/null 2>&1 \
      || echo "$TAG note: reserved on $REMOTE, but could not fetch oi/$n locally; sibling worktrees see it at their next sync." >&2
  fi
  if [ $APPEND -eq 1 ]; then append_stub "$n"; fi
  echo "OI-$n"
  if [ "$TRANSPORT" = api ]; then do_prune >/dev/null 2>&1 || true; fi
}

sync_refs || {
  case "$MODE" in
    mint) echo "$TAG cannot reach $REMOTE — an OI number cannot be reserved offline. Nothing was written." >&2 ;;
    *)    echo "$TAG cannot reach $REMOTE — --$MODE needs the remote's current reservations and board." >&2 ;;
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
