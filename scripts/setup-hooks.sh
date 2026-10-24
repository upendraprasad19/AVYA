#!/bin/sh
# Installs the AVYA git hooks into the common git dir's hooks/ folder.
#
# Run once per fresh clone, and again after pulling any change to a hook script.
# Re-running is idempotent (replaces all five hooks from the matching
# scripts/*.sh).
#
# FIVE hooks are installed (see the install_hook calls below — the count said
# "three" while installing four since prepare-commit-msg joined them, and
# pre-merge-commit joined them 2026-08-17):
#   pre-commit        — 77 of 89 discipline gates + Gate 40 + conditional index
#                       regens. NO flutter analyze / flutter test on the default
#                       path (cost split 2026-08-11; PRE_COMMIT_LEGACY=1 or
#                       PRE_COMMIT_FULL=1 bring them back for one run).
#   pre-push          — flutter analyze ALWAYS, then the full flutter test suite
#                       when the pushed range is >=account and the push is NOT a
#                       branch push (audit 2026-05-20 / I10 split; analyze added
#                       2026-08-11; branch-push skip 2026-10-10, OI-275 -- CI on
#                       the open PR is that gate, merge via safe_pr_merge.sh).
#   commit-msg        — bug-fix discipline gate (closes-diagnose /
#                       regression-test-skipped) + the closes-oi gate.
#   prepare-commit-msg— auto-prepends the `Blast-radius:` line.
#   pre-merge-commit  — OI board integrity at the merge (2 gates, ~2s). Git
#                       invokes THIS hook, not pre-commit, for an automatically
#                       created merge commit, so before it existed a CLEAN
#                       auto-merge ran NO hook at all — which is exactly how one
#                       OI number came to name two issues six times over. Two
#                       places in the repo asserted the opposite
#                       (open_issues.md:2426, diagnose b7e3d1:56); both were
#                       corrected in the same batch that added this.
#
# NOTE these are COPIES, not shims, so editing scripts/*.sh changes nothing until
# this script is re-run. Each copy is installed ATOMICALLY and READ-ONLY:
# install_hook() copies to a temp file next to the hook, verifies it, makes it
# executable and non-writable, then renames it over the old hook. A rename swaps
# the directory entry, so a git process that is mid-way through running the old
# hook keeps the old inode; the former in-place `cp` rewrote a running script
# underneath it. Because the installed hooks are non-writable, a plain `cp` over
# one now fails with "Permission denied" on purpose: an OLD tree's installer
# must not silently overwrite hooks that a newer tree installed.
#
# Install ONLY from the primary worktree, after it is current:
#   git fetch origin main && git merge --ff-only origin/main && sh scripts/setup-hooks.sh
# The hooks dir is `git rev-parse --git-common-dir`/hooks, which is SHARED BY
# EVERY WORKTREE — running this from an unmerged or stale branch changes the
# hooks for every concurrent session at once
# (memory/feedback_worktree_per_session.md). The same advice is written into
# AVYA-HOOKS-README.txt next to the hooks, which this script maintains.
#
# Why two hooks? pre-commit runs BEFORE the commit message is finalized, so it
# can't reliably read the proposed message. `git commit -m`/`-F`/`--amend` all
# fail to update .git/COMMIT_EDITMSG before pre-commit fires. The discipline
# gate must run at commit-msg time (which receives the message file path
# as $1). Split established 2026-05-11 — see audit doc.
#
# Windows: run from Git Bash (bundled with Git for Windows). cmd.exe and
# PowerShell will not execute the .sh file directly.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Arguments (arguments, not environment variables, so the env scanner sees no new input):
#   --allow-stale     install although this tree is behind, diverged from, or cannot be
#                     compared with origin/main
#   --allow-unmerged  install although this tree is not on main and its hook sources
#                     differ from origin/main
# Anything else is refused BEFORE anything is touched: a typo must not fall through to a
# full install (and must not override a refusal).
ALLOW_STALE=0
ALLOW_UNMERGED=0
for ARG in "$@"; do
  case "$ARG" in
    --allow-stale) ALLOW_STALE=1 ;;
    --allow-unmerged) ALLOW_UNMERGED=1 ;;
    -h|--help)
      echo "usage: sh scripts/setup-hooks.sh [--allow-stale] [--allow-unmerged]"
      echo "Run it from the primary worktree after: git fetch origin main && git merge --ff-only origin/main"
      exit 0
      ;;
    *)
      echo "[setup-hooks] unknown argument: $ARG" >&2
      echo "usage: sh scripts/setup-hooks.sh [--allow-stale] [--allow-unmerged]" >&2
      exit 2
      ;;
  esac
done

# Hooks live in the COMMON git dir, not "$REPO_ROOT/.git/hooks".
#
# In a linked worktree `.git` is a FILE containing `gitdir: …`, not a directory,
# so the old `$REPO_ROOT/.git/hooks/pre-commit` path failed outright:
#   cp: failed to access '<worktree>/.git/hooks/pre-commit': Not a directory
# CLAUDE.md §4.13 requires every session to work in its own worktree, so the
# installer was broken in exactly the place the workflow mandates. Git also
# shares one hooks dir across all worktrees, so installing to the common dir is
# both the working path AND the correct one.
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOKS_DIR"

# Temp files carry this process's pid, so the glob below can only ever match our
# own leftovers, never a concurrent installer's. dash does not run the EXIT trap
# when a signal kills the shell, hence the second trap turning HUP/INT/TERM into
# an ordinary exit (which does run it).
trap 'rm -f "$HOOKS_DIR"/*.tmp."$$"' EXIT
trap 'exit 1' HUP INT TERM

FAILURES=""
HAVE_PERSISTENT=0
HAVE_TRANSIENT=0

# The hooks are shared by every worktree: installing from a STALE tree downgrades them
# for all sessions, and the read-only bit only stops an OLD installer, not a current
# installer run from an old checkout. So the checks come BEFORE anything is replaced.
# `merge-base --is-ancestor origin/main HEAD` exits 0 when this tree contains origin/main,
# 1 when it does not, and 128 when the ref does not exist (a clone with no origin/main
# installs silently). A local ref only: no fetch, so it is instant and works offline.
# Exit 1 has three causes, told apart so the advice is right: BEHIND (HEAD is an
# ancestor of origin/main: a fast-forward fixes it), DIVERGED (neither contains the
# other: the primary's local main merged but unpushed while origin moved), and
# UNREADABLE (git printed an error while walking history; that error is shown).
BEHIND_RC=0
MB_ERR="$(git -C "$REPO_ROOT" merge-base --is-ancestor origin/main HEAD 2>&1 >/dev/null)" || BEHIND_RC=$?
if [ "$BEHIND_RC" = "1" ]; then
  UP_RC=0
  git -C "$REPO_ROOT" merge-base --is-ancestor HEAD origin/main >/dev/null 2>&1 || UP_RC=$?
  STALE_WHY="behind"
  if [ -n "$MB_ERR" ]; then
    STALE_WHY="unreadable"
  elif [ "$UP_RC" != "0" ]; then
    STALE_WHY="diverged"
  fi
  if [ "$ALLOW_STALE" = "1" ]; then
    echo "[setup-hooks] WARNING: this tree is $STALE_WHY relative to origin/main; installing anyway because --allow-stale was given."
  else
    echo "[setup-hooks] REFUSING to install: this tree is not current with origin/main ($STALE_WHY), and the hooks are shared by every worktree." >&2
    case "$STALE_WHY" in
      behind)
        echo "[setup-hooks] This tree is behind origin/main. Update first (git fetch origin main && git merge --ff-only origin/main), then run this from the primary worktree." >&2
        ;;
      diverged)
        echo "[setup-hooks] This tree has diverged from origin/main (a fast-forward cannot fix it). Merge origin/main into it, or push its commits, then run this from the primary worktree." >&2
        ;;
      *)
        echo "[setup-hooks] git could not tell whether this tree is current; it said: $MB_ERR" >&2
        ;;
    esac
    echo "[setup-hooks] --allow-stale overrides this check." >&2
    exit 1
  fi
fi

# A tree that is AHEAD of origin/main (or has uncommitted edits) installs the hook sources
# it has, for every worktree. The primary on main (merged but not yet pushed) is the normal
# case and only gets a warning; any other branch with differing hook sources is refused.
if [ "$BEHIND_RC" = "0" ]; then
  CHANGED="$(git -C "$REPO_ROOT" diff --name-only origin/main -- scripts/pre-commit.sh scripts/pre-push.sh scripts/commit-msg.sh scripts/prepare-commit-msg.sh scripts/pre-merge-commit.sh scripts/setup-hooks.sh 2>/dev/null)" || CHANGED=""
  if [ -n "$CHANGED" ]; then
    BRANCH="$(git -C "$REPO_ROOT" symbolic-ref -q --short HEAD)" || BRANCH=""
    if [ "$BRANCH" = "main" ] || [ "$ALLOW_UNMERGED" = "1" ]; then
      echo "[setup-hooks] WARNING: these hook sources differ from origin/main and will be installed for EVERY worktree:"
      echo "$CHANGED"
    else
      echo "[setup-hooks] REFUSING to install: this tree is not on main and these hook sources differ from origin/main:" >&2
      echo "$CHANGED" >&2
      echo "[setup-hooks] Merge them to main first. --allow-unmerged overrides this check." >&2
      exit 1
    fi
  fi
fi

# Normally this runs from the PRIMARY worktree. A linked worktree has a git dir that
# differs from the common dir; the hooks it installs are still shared, so say so.
if [ "$(git -C "$REPO_ROOT" rev-parse --git-dir)" != "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)" ]; then
  echo "[setup-hooks] note: this is a linked worktree. The hooks are shared by every worktree; install from the primary unless you mean to."
fi

# record_failure <hook> <what went wrong> <persistent|transient>
# A hook that cannot be installed is RECORDED and the loop carries on: stopping
# at the first failure used to leave the later hooks stale with no list of which.
record_failure() {
  FAILURES="$FAILURES
  - $1: $2"
  if [ "$3" = "persistent" ]; then
    HAVE_PERSISTENT=1
  else
    HAVE_TRANSIENT=1
  fi
}

# record_cmp_failure <hook> <cmp exit code> <what was compared>
# cmp exits 1 when the files differ and 2 when one cannot be read (a hook that is missing
# after a "successful" rename is exactly that): both are a mismatch worth a retry. Any other
# code (126 / 127: cmp is not runnable) cannot compare at all, and retrying will not help.
record_cmp_failure() {
  if [ "$2" = "1" ] || [ "$2" = "2" ]; then
    record_failure "$1" "$3 differs from its source (or is missing)" transient
  else
    record_failure "$1" "could not compare the $3 with its source (cmp exit $2; is cmp installed?)" persistent
  fi
}

install_hook() {
  local src="$1"
  local dst="$2"
  local name="${dst##*/}"
  local tmp="$dst.tmp.$$"
  local rc=0
  if [ ! -f "$src" ]; then
    record_failure "$name" "source $src not found" persistent
    return 0
  fi
  if [ -d "$dst" ]; then
    record_failure "$name" "destination $dst is a directory" persistent
    return 0
  fi
  rm -f "$tmp" || true
  if ! cp "$src" "$tmp"; then
    record_failure "$name" "could not copy to a temp file next to the hook" persistent
    rm -f "$tmp" || true
    return 0
  fi
  # Verify the COPY before it can replace a working hook.
  rc=0
  cmp -s "$src" "$tmp" || rc=$?
  if [ "$rc" != "0" ]; then
    record_cmp_failure "$name" "$rc" "temp copy"
    rm -f "$tmp" || true
    return 0
  fi
  # The mode is set on the TEMP file, before the rename, so the live hook is never
  # non-executable. A hook git cannot execute is silently skipped, so a chmod +x that
  # fails is a failure; a chmod a-w that fails only loses the read-only protection.
  if ! chmod +x "$tmp" && [ ! -x "$tmp" ]; then
    record_failure "$name" "could not make the hook executable (git silently skips a hook that is not)" persistent
    rm -f "$tmp" || true
    return 0
  fi
  chmod a-w "$tmp" || echo "[setup-hooks] warning: could not make $name read-only (the hook still works)" >&2
  if ! mv -f "$tmp" "$dst" 2>/dev/null; then
    # Linux needs no write bit on the target (a rename only needs the directory);
    # Git Bash on Windows can refuse to replace a read-only file, so retry once
    # after making it writable, and put the read-only bit back if that fails too.
    chmod u+w "$dst" 2>/dev/null || true
    if ! mv -f "$tmp" "$dst"; then
      chmod a-w "$dst" 2>/dev/null || true
      record_failure "$name" "could not rename the temp copy over the hook (a commit may be running)" transient
      rm -f "$tmp" || true
      return 0
    fi
  fi
  # A rename that reported success but left something else in place.
  rc=0
  cmp -s "$src" "$dst" || rc=$?
  if [ "$rc" != "0" ]; then
    record_cmp_failure "$name" "$rc" "installed hook"
    return 0
  fi
  echo "[setup-hooks] installed $dst"
}

install_hook "$REPO_ROOT/scripts/pre-commit.sh" "$HOOKS_DIR/pre-commit"
install_hook "$REPO_ROOT/scripts/pre-push.sh" "$HOOKS_DIR/pre-push"
install_hook "$REPO_ROOT/scripts/commit-msg.sh" "$HOOKS_DIR/commit-msg"
install_hook "$REPO_ROOT/scripts/prepare-commit-msg.sh" "$HOOKS_DIR/prepare-commit-msg"
install_hook "$REPO_ROOT/scripts/pre-merge-commit.sh" "$HOOKS_DIR/pre-merge-commit"

# SSH keepalive for pushes (2026-05-30 cross-check fix).
# The pre-push hook runs analyze and (at >=account, except on a branch push) the full flutter test suite,
# so the idle window GREW on 2026-08-11 rather than shrank: analyze now runs on
# EVERY push, including the feature-tier ones that skip the suite and previously
# idled for only a moment. git opens the
# SSH connection to fetch ref advertisements BEFORE running the hook, then the
# connection sits idle for the whole suite — GitHub's SSH server drops the idle
# git-receive-pack channel, so the object transfer AFTER the gate passes dies
# with SIGPIPE (exit 141). ServerAliveInterval sends null packets during the
# hook to keep the connection alive. Repo-local config (not ~/.ssh/config) so
# it ships with the clone via this setup step and touches nothing global.
# A failure here (a stale .git/config.lock, a read-only config) must not end the run
# before the README and the failure list: it is recorded like a hook failure.
if git -C "$REPO_ROOT" config core.sshCommand \
  "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=30 -o TCPKeepAlive=yes"; then
  echo "[setup-hooks] configured core.sshCommand keepalive (survives long pre-push)"
else
  record_failure "core.sshCommand" "could not write the repo config (a stale .git/config.lock?)" transient
fi

# The README next to the hooks is the one channel that reaches an agent standing
# in a stale tree. A failed write is a warning, never a failed hook; the temp file
# has no explicit rm because the EXIT trap above removes it.
write_readme() {
  local rtmp="$HOOKS_DIR/AVYA-HOOKS-README.txt.tmp.$$"
  if cat > "$rtmp" <<'README_EOF'
AVYA git hooks - read this before touching this folder.

These hooks are READ-ONLY COPIES of scripts/pre-commit.sh, scripts/pre-push.sh,
scripts/commit-msg.sh, scripts/prepare-commit-msg.sh and scripts/pre-merge-commit.sh.
One hooks folder is shared by EVERY worktree of this clone.

Install or update them ONLY from the primary worktree, after it is current:
  git fetch origin main && git merge --ff-only origin/main && sh scripts/setup-hooks.sh
The installer refuses to run from a tree that is behind or diverged from origin/main, or
that is not on main and has hook sources differing from origin/main, because installing
from such a tree changes the hooks for every session (--allow-stale and --allow-unmerged
override the two checks).

If an installer or a plain cp says "Permission denied" on a hook FILE, that tree's
setup-hooks.sh is OLD (it overwrites in place). Update the tree and install from
the primary. Do not chmod or rm the hooks by hand. If the hooks DIRECTORY itself is not
writable (for example after an install made with sudo), fix its owner or mode instead.
The one sanctioned exception to never chmod is a rollback: chmod u+w on the hook files,
then run the installer.

Files named *.tmp.* in this folder are leftovers of an interrupted install and are
safe to delete.
README_EOF
  then
    mv -f "$rtmp" "$HOOKS_DIR/AVYA-HOOKS-README.txt" ||
      echo "[setup-hooks] warning: could not write AVYA-HOOKS-README.txt (hooks are unaffected)" >&2
  else
    echo "[setup-hooks] warning: could not write AVYA-HOOKS-README.txt (hooks are unaffected)" >&2
  fi
  return 0
}
write_readme

if [ -n "$FAILURES" ]; then
  echo "[setup-hooks] FAILED: not every hook was installed:$FAILURES" >&2
  if [ "$HAVE_PERSISTENT" = "1" ]; then
    echo "[setup-hooks] fix the tree (missing source, a directory in the way, or a read-only filesystem); retrying will not help." >&2
  fi
  if [ "$HAVE_TRANSIENT" = "1" ]; then
    echo "[setup-hooks] retry when no commit is running in any worktree." >&2
  fi
  exit 1
fi

echo "[setup-hooks] verify: ls -la $HOOKS_DIR/{pre-commit,pre-push,commit-msg,prepare-commit-msg,pre-merge-commit}  (read-only copies; see AVYA-HOOKS-README.txt there)"
