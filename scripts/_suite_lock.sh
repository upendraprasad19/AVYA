#!/usr/bin/env sh
# scripts/_suite_lock.sh -- SOURCED (not executed). One LOCAL full test suite at a time on this machine.
#
# WHY (2026-11-11, docs/plans/review-ci-suite-lock.md). The VPS has 4 cores, 1 thread each. A local full
# `flutter test` takes 77-116 min there (CI: ~16 min on 4 shards) and keeps ~2 `flutter_tester` processes at ~90 %
# CPU plus a `frontend_server`. Two sessions' suites at once pushed the load to 9.6 with 0 % idle and stretched
# both runs. This lock makes the second local suite wait (scripts/run_full_suite.sh) or refuse at once (the git
# hooks), instead of competing for the cores.
#
# Defines:
#   suite_lock_acquire            wait for the lock (scripts/run_full_suite.sh: run it in the BACKGROUND)
#   suite_lock_acquire --no-wait  never wait: when another suite holds the lock, print the last recorded holder
#                                 and return 1 (the git hooks run inside safe_commit/safe_push's git lock, which
#                                 other callers do not wait for, so a hook must not sit on it for ~100 min)
#   suite_lock_release            close the lock fd (a no-op when nothing was opened)
#
# THE LOCK. `flock` on <git common dir>/avya_full_suite.lock, shared by every worktree of the clone, held through
# file descriptor 9 of the CALLING shell. Callers MUST append `9>&-` to the test command, so `flutter`,
# `frontend_server`, `flutter_tester` and anything a test spawns never inherit fd 9: the lock is then released by
# the kernel when the calling shell exits or dies, and an orphaned test child can never hold it (49 orphaned
# `land_pr.dart` fixture processes, ~9 days old, were found on this box on 2026-11-11). Stated limit: a SIGKILL of
# the calling shell alone releases the lock while its flutter tree may keep running.
#
# FAIL OPEN. The lock saves CPU; it is never a gate. No git repository, no `flock` on the PATH (Windows Git Bash,
# macOS), a lock file that cannot be opened, or a failing `flock`: print a WARNING to stderr and return 0 (run
# unlocked). The one non-zero return is `--no-wait` finding the lock held.
#
# NESTING MARKER. `AVYA_SUITE_LOCK_HELD=1` makes suite_lock_acquire return 0 at once, silently, touching nothing.
# scripts/run_full_suite.sh sets it on its suite, and the two tests that run the REAL hooks in the REAL repo set it
# on their hook, so a hook running inside a locked suite never waits on the lock that suite holds. It is a stripped
# child-env name (scripts/regression_catalog_lib.dart). Also the escape hatch: `AVYA_SUITE_LOCK_HELD=1 <command>`.
#
# Tests: test/scripts/suite_lock_e2e_test.dart. Rule: CLAUDE.md §4.12.8, docs/architecture/hooks.md.

# Refuse to be EXECUTED: running a sourced-only helper is a silent no-op that exits 0 (hooks.md, "Sourced-only shell
# helpers"). `$0` is the file's own path ONLY when executed; when sourced it belongs to the caller.
case "$(printf '%s' "$0" | tr '\\' '/')" in
  */_suite_lock.sh|_suite_lock.sh)
    echo "ERROR: scripts/_suite_lock.sh must be SOURCED, not executed." >&2
    echo "  It only defines suite_lock_acquire / suite_lock_release." >&2
    echo "  Use:  . \"\$(dirname \"\$0\")/_suite_lock.sh\"" >&2
    exit 64  # EX_USAGE
    ;;
esac

suite_lock_acquire() {
  _sl_wait=1
  if [ "${1:-}" = "--no-wait" ]; then
    _sl_wait=0
  fi
  if [ "${AVYA_SUITE_LOCK_HELD:-}" = "1" ]; then
    return 0
  fi
  # `--git-common-dir` may print a RELATIVE path; resolve it with cd/pwd (portable to git < 2.31, which lacks
  # `--path-format=absolute`). Two steps, so an empty answer can never become `cd ""` (= stay here).
  _sl_dir=$(git rev-parse --git-common-dir 2>/dev/null) || _sl_dir=""
  if [ -n "$_sl_dir" ]; then
    _sl_dir=$(cd "$_sl_dir" 2>/dev/null && pwd) || _sl_dir=""
  fi
  if [ -z "$_sl_dir" ]; then
    echo "[suite-lock] WARNING: cannot resolve the git common dir (not inside a git repository?); running WITHOUT the one-suite-at-a-time lock." >&2
    return 0
  fi
  if ! command -v flock >/dev/null 2>&1; then
    echo "[suite-lock] WARNING: no 'flock' on the PATH; running WITHOUT the one-suite-at-a-time lock." >&2
    return 0
  fi
  _sl_file="$_sl_dir/avya_full_suite.lock"
  if ! ( : >>"$_sl_file" ) 2>/dev/null; then
    echo "[suite-lock] WARNING: cannot open $_sl_file; running WITHOUT the one-suite-at-a-time lock." >&2
    return 0
  fi
  # `command` keeps a failed redirection from ending a POSIX shell (exec is a special built-in).
  if ! command exec 9>>"$_sl_file"; then
    echo "[suite-lock] WARNING: cannot open $_sl_file; running WITHOUT the one-suite-at-a-time lock." >&2
    return 0
  fi
  if ! flock -n 9; then
    _sl_holder=$(cat "$_sl_file.holder" 2>/dev/null) || _sl_holder=""
    [ -n "$_sl_holder" ] || _sl_holder="unknown"
    if [ "$_sl_wait" = "0" ]; then
      echo "[suite-lock] another local full suite is running (last recorded holder: $_sl_holder)." >&2
      echo "[suite-lock] One local full suite at a time on this machine: retry when it ends, or let CI run it" >&2
      echo "[suite-lock] (CLAUDE.md §4.12.8). Hatch for a case the lock mis-handles: AVYA_SUITE_LOCK_HELD=1." >&2
      exec 9>&-
      return 1
    fi
    echo "[suite-lock] another local full suite is running (last recorded holder: $_sl_holder); waiting -- one local full suite at a time on this machine." >&2
    if ! flock 9; then
      echo "[suite-lock] WARNING: flock failed; running WITHOUT the one-suite-at-a-time lock." >&2
      return 0
    fi
    echo "[suite-lock] lock acquired." >&2
  fi
  printf 'pid=%s since=%s dir=%s\n' "$$" "$(date '+%Y-%m-%d %H:%M:%S %z')" "$PWD" >"$_sl_file.holder" 2>/dev/null || true
  return 0
}

suite_lock_release() {
  exec 9>&-
}
