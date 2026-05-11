# /build-apk — Build Release APK

Build a production-ready APK with all required pre-flight gates, pre-flight checks, and post-build verification.

**Source-of-truth rule (added 2026-05-03):** APKs are ALWAYS built from `main`, never from a feature branch. Before invoking this skill, the work must be committed AND merged to main. The skill verifies this in pre-flight and refuses to build otherwise — the user explicitly chose this discipline so the APK shipped on device is byte-identical to the merged history.

**Emergency bypass:** Pass `--emergency-bypass` in `$ARGUMENTS` to skip optional gates in a P0 situation. See `--emergency-bypass` section below.

---

## Pre-build housekeeping (not gated — always runs)

1. Kill zombie `java.exe` and `gradle.exe` processes that may hold memory from crashed builds:
   ```bash
   taskkill //F //IM "java.exe" 2>/dev/null; true
   ```

2. Remove stale Flutter lock file (prevents silent Flutter SDK hangs):
   ```bash
   # Find Flutter SDK path
   FLUTTER_SDK=$(flutter --version 2>/dev/null | head -1 | grep -oP 'Flutter \K[0-9.]+' || true)
   # Delete lockfile if it exists and no flutter is running
   ls "$(which flutter | xargs dirname)/../bin/cache/lockfile" 2>/dev/null && \
     rm -f "$(which flutter | xargs dirname)/../bin/cache/lockfile" || true
   ```

3. Check for JVM crash dumps from prior builds:
   ```bash
   ls android/hs_err_*.log 2>/dev/null && echo "JVM crash dump found — diagnose before building" || true
   ```

---

## Gates (all must pass before build)

All gates are Dart CLI scripts. Run with `dart run scripts/<name>.dart`. Each exits 0 on pass. Failures are printed to stderr. Gates run in order — first failure stops the build (unless `--emergency-bypass` is active).

### Gate 1 — On `main` with clean working tree (existing)

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "ERROR: Not on main branch (current: $BRANCH). Merge to main first."
  exit 1
fi
STATUS=$(git status --porcelain)
if [ -n "$STATUS" ]; then
  echo "ERROR: Working tree is dirty. Commit or stash changes first."
  git status --short
  exit 1
fi
git log --oneline -1
```

### Gate 2 — versionCode bumped vs last shipped (existing)

Read `version:` from `pubspec.yaml`. If the current versionCode (`+N`) was already shipped in a prior `chore: bump versionCode` commit, STOP and bump it.

```bash
CURRENT=$(grep "^version:" pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
LAST_BUMP=$(git log -1 --format=%H --grep="bump versionCode" -- pubspec.yaml)
echo "Current versionCode: $CURRENT (last bump commit: $LAST_BUMP)"
```

If a bump is needed: `Edit pubspec.yaml → 1.0.0+N → 1.0.0+(N+1)`, commit with `chore: bump versionCode 1.0.0+N → 1.0.0+(N+1) for APK Test #X`, then continue.

**Why this matters:** Android silently rejects a same-versionCode reinstall as a no-op. Founder hit this on Tests #7, #8, #10, #11, #11.1, #12 — all originally built at `1.0.0+6`.

### Gate 3 — `.env` exists (existing)

```bash
if [ ! -f ".env" ]; then
  echo "ERROR: .env not found. Copy from .env.example and fill in Supabase + Razorpay keys."
  exit 1
fi
```

### Gate 4 — `flutter analyze --no-fatal-infos` (existing)

```bash
flutter analyze --no-fatal-infos
```

Note: `--no-fatal-infos` retained for now — there are 20+ pre-existing info-level hints. Goal is `--fatal-infos` but not yet achieved. Do not silently downgrade this gate.

### Gate 5 — `flutter test` full suite (existing)

```bash
flutter test
```

Full unit test suite. Must pass with 0 failures. Pre-commit hook enforces the same gate; this is the build-time confirmation.

### Gate 6 — Integration tests (optional, `--integration` flag only)

```bash
# Only run when --integration flag is in $ARGUMENTS
flutter test --dart-define-from-file=.env integration_test/ --flavor dev
```

Default: skip (requires connected Android device). Pass `--integration` to opt in.

### Gate 7 — SoT registry completeness

```bash
dart run scripts/check_sot_registry_completeness.dart
```

Asserts every write-pattern method in `lib/core/services/*.dart` appears in `docs/sot_registry.yaml`. Warn-don't-fail when < 50 unmatched (registry still being built).

### Gate 8 — Forbidden legacy patterns absent

```bash
dart run scripts/check_naming_audit.dart
```

Greps `lib/`, `supabase/functions/`, `test/`, `integration_test/` for patterns in `forbidden_legacy_patterns[]`. Warn-don't-fail when > 30 violations (T2.3 cleanup may still be in progress).

### Gate 9 — WriteService contract tests present

```bash
dart run scripts/check_writeservice_contracts.dart
```

Every concept with a `hive.key_prefix` in the registry must have `test/contracts/<concept>_writer_to_reader_test.dart`. Warn-don't-fail when > 5 missing (T3.1 will add them).

### Gate 10 — Bug-fix commits reference valid diagnose-docs

```bash
dart run scripts/check_bugfix_commits_have_diagnose.dart
```

Every `fix:` / `bug:` / `regression:` commit since last APK build must have either `closes-diagnose: <6+hex>` (referencing a real `docs/diagnoses/*-<id>.md`) or `regression-test-skipped: <reason>`.

### Gate 11 — Sync fan-out completeness

```bash
dart run scripts/check_sync_fanout.dart
```

Every `sync_methods[]` / `restore_methods[]` entry in the registry must be declared as a `Future<...>` method in `lib/core/services/sync_service.dart`.

### Gate 12 — Edge function payload contracts

```bash
dart run scripts/check_edge_function_payloads.dart
```

Flutter caller body keys ⊆ Edge Function server keys. No-op pass if no `edge_function_payloads` are defined in registry yet.

### Gate 14 — Migrations applied to prod

```bash
dart run scripts/check_migrations_applied.dart
```

Local `supabase/migrations/*.sql` files must all appear in `backups/applied_migrations.json` snapshot. Exit 0 if snapshot is absent (first run). Update `backups/applied_migrations.json` after applying new migrations.

### Gate 15 — Generic error catch blocks must emit telemetry

```bash
dart run scripts/check_generic_error_telemetry.dart
```

Every user-facing generic error message ("Sorry,", "Something went wrong", "temporarily unavailable", "Failed to ...", "Could not ...") inside a `catch (...)` block must be preceded within 30 lines by an `ErrorTelemetry.logEvent` / `recordNonFatal` / `_reportSyncFailure` call. Codifies APK Test #15.1 / Bug D — ai-media-proxy generic else-branch fell through silently with zero telemetry.

Baseline file `backups/generic_error_telemetry_baseline.txt` grandfathers pre-existing violations. NEW violations hard-fail.

### Gate 16 — Repository box.get(key) → Map must inject id

```bash
dart run scripts/check_id_injection_on_get.dart
```

In `lib/**/*_repository.dart`, every `box.get(key)` that returns a Map shape must inject the key as `id` on the returned map within 15 lines, OR carry an explicit `// gate16-exempt: <reason>` annotation. Codifies APK Test #15.1 / Bug F — Test #6 WriteService rewrite stopped writing `id` value fields (id IS the Hive key); consumer filters then silently stripped every row.

Baseline file `backups/id_injection_on_get_baseline.txt` for grandfathered patterns. NEW violations hard-fail.

---

## Build step

After all gates pass, ask user for confirmation before the actual build command. Show:
- Flavor: prod
- Mode: release
- Env file: .env
- versionCode: current from pubspec.yaml
- Estimated time: 15-20 minutes (clean build)

### Clean build environment (skip if `--skip-clean` in `$ARGUMENTS`)

```bash
flutter clean
flutter pub get
```

### Build APK

```bash
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart
```

Run with 10-minute timeout. Long-running command.

---

## Post-build verification and Gate 13

### Verify APK exists

```bash
ls -lh build/app/outputs/flutter-apk/app-prod-release.apk
```

Report file size. Expected ~114 MB for current project state.

### Check for JVM crash dumps

```bash
ls android/hs_err_*.log 2>/dev/null && echo "JVM crash dump found — see Error Recovery" || echo "No crash dumps"
```

If found: read the crash log, diagnose (likely Gradle OOM), suggest reducing `-Xmx` in `android/gradle.properties`.

### Gate 13 — APK size within bounds (post-build)

```bash
dart run scripts/check_apk_size_within_bounds.dart --record
```

Reads `backups/apk_sizes.json`. Fails if APK size changed by > ±10% from last shipped. `--record` flag writes the current size + MD5 into the JSON.

### Report results

```
APK built successfully
Path: build/app/outputs/flutter-apk/app-prod-release.apk
Size: <size> MB
Flavor: prod | Mode: release
versionCode: <N>
MD5: <hash>
```

---

## --emergency-bypass

If `$ARGUMENTS` contains the literal string `--emergency-bypass`:

1. Skip gates: 6, 7, 8, 9, 10, 11, 12, 13, 14
2. Keep gates: 1 (must be on main), 2 (versionCode), 3 (.env), 4 (analyze), 5 (flutter test)
3. After build, rename APK:
   ```bash
   mv build/app/outputs/flutter-apk/app-prod-release.apk \
      build/app/outputs/flutter-apk/app-prod-release-EMERGENCY.apk
   ```
4. Append to `docs/emergency-builds.md`:
   ```markdown
   ## <timestamp>
   - **Reason:** <reason from next arg after --emergency-bypass, or "not provided">
   - **versionCode:** <N>
   - **Gates skipped:** 6, 7, 8, 9, 10, 11, 12, 13, 14
   - **Post-mortem due by:** <today + 7 days>
   - **APK:** app-prod-release-EMERGENCY.apk
   ```

**Emergency bypass should be used only for true P0 incidents** (production down, data-loss risk, security patch). The post-mortem is mandatory; update `docs/emergency-builds.md` when complete.

---

## Error Recovery

If the build fails or hangs:

1. Check `android/hs_err_*.log` — if present, it's a JVM OOM crash
2. Check `android/gradle.properties` — `-Xmx` must be ≤4G on 16GB system
3. Current safe Gradle config: `-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=256m`
4. Kill stale Gradle daemons: `taskkill //F //IM "java.exe"`
5. Remove Flutter lock: delete `<flutter_sdk>/bin/cache/lockfile`
6. Delete JVM crash dumps before retrying: `rm android/hs_err_*.log`
7. Retry from the clean build environment step

---

## Rules

- **ALWAYS** build from `main` with a clean working tree. Never from a feature branch. Never with uncommitted changes.
- **ALWAYS** bump versionCode in `pubspec.yaml` for every shipped APK. Same versionCode = Android silently rejects the install on update.
- **ALWAYS** use `--flavor prod --release` (never build dev APKs for distribution).
- **ALWAYS** include `--dart-define-from-file=.env` (without it, SUPABASE_URL is empty and auth crashes).
- **ALWAYS** run `flutter clean` before release builds unless `--skip-clean` is passed.
- **ALWAYS** ask user for confirmation before the actual build command.
- **ALWAYS** run Gate 13 after every build and record size to `backups/apk_sizes.json`.
- **NEVER** modify `android/gradle.properties` `-Xmx` above 4G on this 16GB system.
- **NEVER** ignore `hs_err_*.log` files — always diagnose and delete them before retrying.
- Entry point is always `lib/main.dart` (single entry point, flavors handled by Gradle).
- Gate scripts live at `scripts/check_*.dart`. Add new gates there; do not inline gate logic in this skill.
