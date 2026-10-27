#!/bin/sh
# Resolve a Dart binary ONCE per hook run, preferring the SDK executable over
# the Flutter `dart` wrapper. Sourced (never executed) by the git hooks.
#
# WHY THIS EXISTS
# ---------------
# `flutter/bin/dart` is not the Dart binary. It is a shell script that, on
# Windows/MSYS, `exec`s `flutter/bin/dart.bat` (see the `if [[ $OS =~ MINGW.*`
# branch in that file); on POSIX it sources `internal/shared.sh`. Either path
# does the same work on EVERY invocation, before Dart starts:
#   - acquires the shared update lock `flutter/bin/cache/.upgrade_lock`
#   - runs `git rev-parse HEAD` on the Flutter checkout
#   - re-verifies the SDK stamp (`internal/update_dart_sdk.sh`)
#
# That is correct for interactive use and pure waste for a hook that invokes
# dart 18 times (13 in pre-commit alone), where the SDK cannot change between
# the first call and the last.
#
# MEASURED on this machine (2026-08-17, quiet, alternating order):
#   dart --version   via wrapper : 3916 / 3939 / 4113 ms
#   dart --version   via SDK exe :  282 /  385 /  280 ms      (~13x)
#   full 72-gate loop at j=4, same gates, both 0 failing:
#                    via wrapper : 303935 ms
#                    via SDK exe : 116177 ms                  (~2.6x, -188s)
#
# The LOCK is what dominates in a parallel loop: N concurrent wrappers
# serialize on one `.upgrade_lock`, so the wrapper's cost scales with the job
# count instead of dividing by it. That is why raising PRE_COMMIT_GATE_JOBS
# bought only ~20% while the wrapper was in the path, and why it buys nothing
# measurable now that it is not -- do not re-derive this, and do not "fix"
# gate-loop latency by raising the job count.
#
# NOT the cause, both tested and refuted so nobody re-runs them:
#   - Windows Defender / AV scanning: the SDK exe is scanned identically and
#     costs 280 ms. The wrapper's cost is its own work, not the scanner's.
#   - The hook's GIT_DIR leak reaching `dart.bat`'s `git rev-parse`: wrapper
#     costs 3916-4113 ms without the leak and 4029-4201 ms with it. No effect.
#
# CONTRACT: this must never wedge a hook. Every failure path falls back to
# whatever `dart` is on PATH, which is exactly the pre-existing behaviour.

# ---------------------------------------------------------------------------
# EXECUTION GUARD (2026-08-30). This file DEFINES A FUNCTION AND NOTHING ELSE,
# so running it as a script is a silent no-op that exits 0 having done nothing.
#
# That is not hypothetical. On 2026-08-30 a session ran
#   sh scripts/_dart_bin.sh run scripts/validate_diagnose_doc.dart <path>
# repeatedly, read the exit 0, and reported gates as passing and diagnose-docs
# as validating. NOTHING had run. The mistake is easy to make because the
# CORRECT hook usage is `. scripts/_dart_bin.sh` + `"$DART_BIN" run <script>`,
# and the wrong form looks like a plausible shorthand for it. It cost several
# turns of false confidence, and the class -- an exit code that reports success
# about work that never happened -- is the one this repo tracks hardest
# (`feedback_green_check_input_set_width.md`, `feedback_bad_news_vs_no_news.md`).
#
# `$0` is this file's path ONLY when it is executed. When sourced -- by the five
# hooks, or by a test driver -- `$0` belongs to the CALLER, so this cannot fire
# on the supported path. `sh -n` (the parse-check every hook runs before
# sourcing) never executes it either. Verified against all five hooks and both
# tests that reference this file before landing.
#
# ⚠ `$0` is BACKSLASH-NORMALIZED first (B-pass finding 2, same batch). Without
# it, `sh 'scripts\_dart_bin.sh'` -- a Windows-form path, the DOMINANT spelling
# in this environment's own tooling -- slipped past a forward-slash-only pattern
# and exited 0 silently, reproducing the exact bug this guard exists to close.
# A guard that catches only the spelling its author happened to type is the
# `feedback_mistake_guard_without_its_mirror` class. Same `tr '\\' '/'`
# normalization `safe_merge.sh`'s `_norm()` already uses for git paths.
case "$(printf '%s' "$0" | tr '\\' '/')" in
  */_dart_bin.sh|_dart_bin.sh)
    echo "ERROR: scripts/_dart_bin.sh must be SOURCED, not executed." >&2
    echo "  It only defines resolve_dart_bin(); running it does nothing." >&2
    echo "  In a hook:  . scripts/_dart_bin.sh && DART_BIN=\"\$(resolve_dart_bin)\"" >&2
    echo "  One-shot:   DART_BIN=\$(sh -c '. scripts/_dart_bin.sh && resolve_dart_bin')" >&2
    exit 64  # EX_USAGE
    ;;
esac
# ---------------------------------------------------------------------------

# Sets DART_BIN. Callers use "$DART_BIN" run <script.dart> in place of
# `dart run <script.dart>`.
resolve_dart_bin() {
  # 1. Explicit override wins -- an unusual SDK layout or a CI image that
  #    ships a standalone Dart should not have to match our path guess.
  if [ -n "${DART_BIN_OVERRIDE:-}" ] && [ -x "${DART_BIN_OVERRIDE}" ]; then
    printf '%s' "${DART_BIN_OVERRIDE}"
    return 0
  fi

  _dbin_on_path="$(command -v dart 2>/dev/null || true)"
  if [ -z "${_dbin_on_path}" ]; then
    # No dart at all. Emit the bare name so the caller's own error path
    # reports "dart: not found" exactly as it did before this file existed.
    printf '%s' 'dart'
    return 0
  fi

  # 2. The Flutter-bundled SDK sits at <flutter>/bin/cache/dart-sdk/bin/dart[.exe]
  #    relative to the wrapper we just found at <flutter>/bin/dart.
  _dbin_dir="$(dirname "${_dbin_on_path}")"
  for _dbin_cand in \
    "${_dbin_dir}/cache/dart-sdk/bin/dart.exe" \
    "${_dbin_dir}/cache/dart-sdk/bin/dart"
  do
    if [ -x "${_dbin_cand}" ]; then
      printf '%s' "${_dbin_cand}"
      return 0
    fi
  done

  # 3. No cache/dart-sdk beside it. Two ways to get here, and the same answer
  #    is right for both: a standalone Dart SDK (the thing on PATH IS the real
  #    binary -- no wrapper, no tax), or a Flutter checkout not yet
  #    bootstrapped (the wrapper is what bootstraps it, so we MUST use it).
  printf '%s' "${_dbin_on_path}"
}
