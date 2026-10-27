#!/usr/bin/env bash
# AVYA Vercel build — Flutter web (release).
#
# Invoked by vercel.json "buildCommand": "bash scripts/vercel_build.sh".
# Lives here (not inline) because Vercel hard-caps buildCommand at 256 chars
# and the full command is ~446 — https://vercel.com/kb/guide/dynamic-build-commands.
#
# Vercel deploys via GitHub Git-integration: every push to `main` builds in a
# Linux container, cwd = repo root. Env vars come from the Vercel dashboard
# (Project Settings -> Environment Variables), Production target. All three
# below are client-public (shipped in the web bundle), but MUST be set or they
# compile to empty strings and the app crashes on launch with
# "No host specified in URI" (CLAUDE.md §0).
set -euo pipefail

FLUTTER_VERSION="3.41.4"   # must match dev/CI (.github/workflows/test.yml)

# Fail fast if a required build-time env var is missing or empty.
missing=""
for var in SUPABASE_URL SUPABASE_ANON_KEY RAZORPAY_KEY_ID; do
  if [ -z "${!var:-}" ]; then
    missing="$missing $var"
  fi
done
if [ -n "$missing" ]; then
  echo "ERROR: missing required env var(s):$missing" >&2
  echo "Set them in Vercel -> Project Settings -> Environment Variables (Production)." >&2
  exit 1
fi

# Bootstrap the pinned Flutter SDK (reuse Vercel's build cache if present).
if [ -d flutter ]; then
  (cd flutter && git fetch --depth 1 origin "$FLUTTER_VERSION" && git checkout -q "$FLUTTER_VERSION")
else
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" flutter
fi
export PATH="$PWD/flutter/bin:$PATH"

# Build web (release).
flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=RAZORPAY_KEY_ID="$RAZORPAY_KEY_ID"
