# Device Testing — Patrol on Physical Pixel

> Tech-debt audit 2026-05-20 / T1 deliverable. Replaces the 64
> Phase-7 skipped `integration_test/flows/*_e2e_test.dart` files —
> the 4 named flows below now run on a physical device under Patrol.

## 1. Tool: Patrol

[Patrol](https://patrol.leancode.co/) wraps `flutter_test` +
`integration_test` and adds the missing piece: native UI driving.
That matters here because three of the four flows touch surfaces
that vanilla flutter_test cannot reach:

- **Razorpay WebView** (native Android overlay) — payment flow.
- **Google OAuth consent screen** (native Activity) — signup.
- **System permission dialogs** (camera, storage, OneSignal) —
  signup + meal-scan.

Patrol versions in `pubspec.yaml`:
- `patrol: ^3.15.2` (currently resolved 3.20.0).
- `patrol_finders: ^2.7.0` (currently resolved 2.9.0).

## 2. Connection: physical Pixel via USB

Founder's primary device. CI runner provisioning is future work
(see §7).

### One-time setup

1. **Enable Developer Options on the Pixel**: Settings → About →
   tap "Build number" 7 times.
2. **Enable USB debugging**: Settings → System → Developer
   options → USB debugging.
3. **Plug in via USB**. Phone shows "Allow USB debugging from this
   computer?" — accept (check "Always").
4. **Verify adb sees it** from the laptop:

   ```bash
   adb devices
   # List of devices attached
   # XXXXX001YYYYY    device
   ```
5. **Verify Flutter sees it**:

   ```bash
   flutter devices
   # Pixel 8 (mobile) • XXXXX001YYYYY • android-arm64 • Android 14
   ```

   Copy the device ID (middle column).
6. **Install Patrol CLI** (one time, system-wide):

   ```bash
   dart pub global activate patrol_cli
   ```

   Ensure `~/.pub-cache/bin` is on `$PATH`.

## 3. Test-user prep

The 4 flows assume specific test-user state. Prep before the run;
re-prep when a flow's contract changes.

| Flow | Required state |
|---|---|
| `razorpay_payment` | Signed in as a free test user. Account is upgraded mid-test; downgrade post-run via Supabase MCP. |
| `cross_device_restore` | Signed out. Test user `device-test@avya.app` pre-seeded with 20 workouts + 50 nutrition logs + 10 weight logs (see `supabase/seeds/device_test_user.sql`). |
| `signup_onboarding` | Signed out. Disposable Google account `icanbefitter.qa1@gmail.com` family — pick the first unused suffix. |
| `delete_account` | Signed in as a DISPOSABLE test account that can be deleted. Re-seed afterward via the seed SQL. |

### Razorpay test mode

`.env` must contain `RAZORPAY_KEY_ID=rzp_test_*`, NOT `rzp_live_*`.
The runner script refuses to proceed if it detects a live key.

Razorpay's universal test card (success path):

| Field | Value |
|---|---|
| Number | `4111 1111 1111 1111` |
| Expiry | any future date (e.g. `12/30`) |
| CVV | any 3 digits (e.g. `123`) |
| OTP | `1111` |

## 4. Running the flows

### Find your device ID

```bash
flutter devices
# Copy the middle column (e.g. XXXXX001YYYYY).
```

### Run all 4 flows

```bash
ANDROID_DEVICE_ID=XXXXX001YYYYY sh scripts/run-device-tests.sh
```

Expected wall-clock: ~6–8 min cold (build + install + run). Re-runs
on the same device are ~3 min (Gradle cache + Patrol incremental).

### Run a single flow

```bash
ANDROID_DEVICE_ID=XXXXX001YYYYY sh scripts/run-device-tests.sh razorpay_payment
# (positional arg is the file prefix; available prefixes:
#  razorpay_payment, cross_device_restore, signup_onboarding,
#  delete_account)
```

### Run Patrol directly (no script)

```bash
patrol test --target integration_test/device/razorpay_payment_patrol_test.dart \
  --device XXXXX001YYYYY --dart-define-from-file=.env --flavor dev
```

## 5. Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter devices` doesn't list the Pixel | Re-plug USB; toggle USB debugging off/on. On Windows, install the Google USB Driver (Android SDK Manager). |
| `adb devices` shows `unauthorized` | The "Allow USB debugging" prompt was dismissed; replug, accept. |
| `patrol: command not found` | Run `dart pub global activate patrol_cli` and ensure `~/.pub-cache/bin` is on `$PATH`. |
| Build hangs at "Running Gradle task ..." | Same as the regular `flutter build apk` hang — `android/gradle.properties` `-Xmx` must be ≤4G. See root CLAUDE.md §0 "Gradle Configuration". |
| Razorpay WebView never appears | `.env` is stale or missing — confirm `RAZORPAY_KEY_ID=rzp_test_*` and that `--dart-define-from-file=.env` is passed (the runner script does this automatically). |
| Test hangs at "waiting for Patrol app service" | Patrol's native runner crashed. Check `adb logcat` for the stack; usually a `MainActivityTest.java` rewrite is needed. |

## 6. The 4 flows

| File | What it pins |
|---|---|
| `integration_test/device/razorpay_payment_patrol_test.dart` | Full payment funnel — paywall tap → Razorpay WebView → test card → `_pollAndActivate` → PRO pill. Exercises `FunctionException` catch path (regression class: project_apk_test_12_5_batch). |
| `integration_test/device/cross_device_restore_patrol_test.dart` | Sign-in restore completeness across 5 domain boxes. Pins the 9-instance writer/reader drift class (`feedback_writer_reader_field_drift_recurring.md`). |
| `integration_test/device/signup_onboarding_patrol_test.dart` | Google OAuth → 4-step onboarding → profileBox + Supabase `users` + OneSignal `player_id` writes. Pins AuthSessionBootstrapper post-signup routing. |
| `integration_test/device/delete_account_patrol_test.dart` | DPDP §17 delete: confirm dialog → Edge Function → cascade → Hive purge → signed-out landing. Pins `SessionHelpers.purgeUserScopedBoxes`. |

## 7. CI runner provisioning

**Status**: future work. Initial flows run on the founder's local
Pixel post-batch. Options for future automation:

- **Firebase Test Lab**: Patrol has first-class support; cost ~$0.10/min
  on a Pixel 7 instance. Quarterly budget impact: ~$50 if all 4 flows
  run once per merge to main.
- **BrowserStack App Live**: similar pricing, broader device matrix.
- **Self-hosted Android farm**: not cost-effective for a solo founder.

Decision deferred until the test suite has stabilised through 2–3
batches of real usage. Tracked under audit 2026-05-20 follow-up
"device-CI provider selection" (no formal ID; revisit at next
quarterly audit cadence per CLAUDE.md §4.10).

## 8. Maintenance

- When a flow's UI changes (button text, navigation path, Hive
  field name), update the corresponding `*_patrol_test.dart` in the
  same commit as the UI change. Patrol tests are now part of the
  SoT contract for these flows.
- The 4 flows are currently `skip: 'T1 scaffold — ...'`. Founder
  flips `skip` to a runtime gate (or removes it entirely) once the
  first real run is green on the Pixel.
- Gate `scripts/check_device_tests_exist.dart` (Gate 54) enforces
  that all 4 named files exist with their named feature mention.
  Deleting one without replacement is a pre-commit fail.
