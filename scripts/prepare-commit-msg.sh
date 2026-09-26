#!/usr/bin/env bash
# .githooks/prepare-commit-msg
#
# Track 2 of the 2026-05-28 six-industry-gap closure batch.
# Auto-prepends a `Blast-radius: <tier>` line to the commit body, computed
# from staged paths via scripts/blast_radius_from_diff.dart.
#
# Founder reviews + can override the line on commit edit. The line is
# informational; the actual enforcement happens in pre-commit + post-commit
# gates that read the diff directly.
#
# Wiring: this hook only runs if `git config core.hooksPath` points at
# `.githooks/` (configured by scripts/setup-hooks.sh).
#
# Skipped scenarios:
#  - merges (COMMIT_SOURCE = merge)
#  - amends without re-staging (founder controls)
#  - rebases (COMMIT_SOURCE = squash / commit)

set -e

COMMIT_MSG_FILE="$1"
COMMIT_SOURCE="$2"

# Resolve the Dart binary ONCE -- `flutter/bin/dart` is a wrapper that takes the
# SDK update lock and shells out to git on EVERY call (~4.0s vs ~0.3s for the
# SDK exe, measured). See scripts/_dart_bin.sh. Falls back to `dart` on PATH, so
# a failure here is exactly the pre-existing behaviour. Sourced AFTER the early
# exits above would be wrong -- they exit before any dart call, but the two
# `case`/`grep` guards are cheap and this must be set before the tier compute.
_PCM_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$_PCM_ROOT" ] && [ -r "$_PCM_ROOT/scripts/_dart_bin.sh" ] && sh -n "$_PCM_ROOT/scripts/_dart_bin.sh" 2>/dev/null; then
  . "$_PCM_ROOT/scripts/_dart_bin.sh" || true
  DART_BIN="$(resolve_dart_bin)" 2>/dev/null || DART_BIN="dart"
else
  DART_BIN="dart"
fi

# Skip merges / squashes / amends — only act on regular commits + templates.
case "$COMMIT_SOURCE" in
  merge|squash|commit) exit 0 ;;
esac

# Skip if Blast-radius: already present (founder added manually or amend).
if grep -qE '^Blast-radius:' "$COMMIT_MSG_FILE" 2>/dev/null; then
  exit 0
fi

# Compute the tier.
# NOTE: `dart run` prepends a "Running build hooks..." preamble to stdout with
# no trailing newline (Dart SDK native-build-hooks message), which pollutes the
# helper's output line. So we extract the tier token with -oE (match anywhere
# on the line) rather than an anchored ^Blast-radius: grep, which the preamble
# defeats. Found during 2026-05-28 cross-check (diagnose b1f4e2 sibling).
TIER_LINE=$("$DART_BIN" run scripts/blast_radius_from_diff.dart 2>/dev/null \
  | grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' \
  | tail -1 || true)
if [ -z "$TIER_LINE" ]; then
  # No staged changes (e.g. `git commit --allow-empty`); leave message untouched.
  exit 0
fi

# Prepend to the commit body. Strategy: insert AFTER the subject + blank line.
# If the message has only a subject (no body), we add a blank line + tier.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

awk -v tier="$TIER_LINE" '
  BEGIN { inserted = 0; in_body = 0 }
  /^# / { print; next }                # comments pass through unchanged
  /^$/ && !in_body { in_body = 1; print; print tier; inserted = 1; next }
  END_OF_INPUT { }
  { print }
' "$COMMIT_MSG_FILE" > "$TMP"

# If the awk loop never saw a blank line (single-line subject only), append.
if ! grep -qE '^Blast-radius:' "$TMP"; then
  {
    cat "$TMP"
    echo ""
    echo "$TIER_LINE"
  } > "${TMP}.2"
  mv "${TMP}.2" "$TMP"
fi

mv "$TMP" "$COMMIT_MSG_FILE"
