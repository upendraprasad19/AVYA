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
