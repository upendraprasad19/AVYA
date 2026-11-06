#!/bin/sh
# Audit 2026-05-20 / T1: device-CI runner for the 4 Patrol critical flows.
#
# Requires: a physical Android device or emulator connected via USB/adb.
# Use `flutter devices` to find the device ID.
#
# Setup (once per workstation):
#   1. Enable Developer Options + USB debugging on the Pixel.
#   2. Plug in via USB; accept the RSA prompt.
#   3. Verify: `flutter devices` lists the device.
#   4. `.env` has `rzp_test_*` Razorpay keys (NOT rzp_live_*).
#   5. `flutter pub get` (patrol + patrol_finders pulled in).
#
# Run all 4 flows:
#   ANDROID_DEVICE_ID=<id> sh scripts/run-device-tests.sh
#
# Run a single flow:
#   ANDROID_DEVICE_ID=<id> sh scripts/run-device-tests.sh razorpay_payment
#
# See docs/operations/DEVICE_TESTING.md for the full operator runbook
# (test-user prep, Razorpay test mode, troubleshooting).

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ -z "$ANDROID_DEVICE_ID" ]; then
  echo "[run-device-tests] ERROR: ANDROID_DEVICE_ID env var not set."
  echo ""
  echo "  Step 1: list devices"
  echo "    flutter devices"
  echo ""
  echo "  Step 2: copy the device id (e.g. 'XYZ123ABC')"
  echo "    ANDROID_DEVICE_ID=XYZ123ABC sh scripts/run-device-tests.sh"
  echo ""
  exit 1
fi

if [ ! -f "$REPO_ROOT/.env" ]; then
  echo "[run-device-tests] ERROR: .env missing at repo root."
  echo "  Copy from a known-good source and ensure RAZORPAY_KEY_ID=rzp_test_*"
  exit 1
fi

# Sanity: confirm we're in test-mode Razorpay. Live keys in a device
# test would charge real money — refuse to proceed.
if grep -q "RAZORPAY_KEY_ID=rzp_live_" "$REPO_ROOT/.env" 2>/dev/null; then
  echo "[run-device-tests] ERROR: .env has rzp_live_* — device tests must run"
  echo "  against rzp_test_* keys only. Swap to test mode and retry."
  exit 1
fi

# Optional positional arg: a single flow name (filename prefix).
SINGLE_FLOW="${1:-}"

if [ -n "$SINGLE_FLOW" ]; then
  TARGET="integration_test/device/${SINGLE_FLOW}_patrol_test.dart"
  if [ ! -f "$TARGET" ]; then
    echo "[run-device-tests] ERROR: $TARGET not found."
    echo "  Available flows:"
    ls integration_test/device/*_patrol_test.dart 2>/dev/null | sed 's|^|    |'
    exit 1
  fi
  echo "[run-device-tests] Running single flow: $TARGET on $ANDROID_DEVICE_ID..."
  patrol test --target "$TARGET" --device "$ANDROID_DEVICE_ID" \
    --dart-define-from-file=.env --flavor dev
else
  echo "[run-device-tests] Running ALL 4 Patrol flows on $ANDROID_DEVICE_ID..."
  patrol test --target integration_test/device/ --device "$ANDROID_DEVICE_ID" \
    --dart-define-from-file=.env --flavor dev
fi

echo "[run-device-tests] OK — flows completed. Review patrol_logs/ for run artifacts."
