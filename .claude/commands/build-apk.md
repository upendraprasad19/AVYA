# /build-apk — Build Release APK

Build a production-ready APK with all required flags, pre-flight checks, and post-build verification.

**Source-of-truth rule (added 2026-05-03):** APKs are ALWAYS built from `main`, never from a feature branch. Before invoking this skill, the work must be committed AND merged to main. The skill verifies this in pre-flight and refuses to build otherwise — the user explicitly chose this discipline so the APK shipped on device is byte-identical to the merged history.

## Steps

1. **Pre-flight checks**
   - **Git: must be on `main` with a clean working tree.**
     ```bash
     git rev-parse --abbrev-ref HEAD          # must equal 'main'
     git status --porcelain                    # must be empty
     git log --oneline -1                      # confirm latest commit is the merge
     ```
     If on a feature branch OR working tree is dirty, STOP. Tell the user the current state and ask them to commit + merge to main first (or do it on their behalf if they've explicitly authorized — the user's CLAUDE.md global rule requires explicit permission for `commit`/`push`/`ship` actions).
   - **versionCode bump check (added 2026-05-06 after Test #12 install bug).**
     Read `version:` from `pubspec.yaml`. If the current versionCode (the `+N` after `1.0.0`) was already used in any commit on `main` since the last `chore(android): bump versionCode` / `chore: bump versionCode` commit, STOP and bump it before building.
     ```bash
     CURRENT=$(grep "^version:" pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
     LAST_BUMP=$(git log -1 --format=%H --grep="bump versionCode" -- pubspec.yaml)
     COMMITS_SINCE_BUMP=$(git rev-list --count "$LAST_BUMP"..HEAD)
     # If COMMITS_SINCE_BUMP > 0 AND any prior APK build shipped at this versionCode,
     # we MUST bump — Android's package manager treats a same-versionCode reinstall as a no-op.
     ```
     **Why this matters:** Tests #7, #8, #10, #11, #11.1, and #12 all originally built at `1.0.0+6`. Founder updated their device with APK #12, observed "none of the changes reflected" — Android silently rejected the install because the on-device APK and the new APK had identical versionCode. Bump on every shipped APK; uninstall-then-install is not a substitute (loses local Hive state).
     If a bump is needed: `Edit pubspec.yaml → 1.0.0+N to 1.0.0+(N+1)`, commit with `chore: bump versionCode 1.0.0+N → 1.0.0+(N+1) for APK Test #X`, push, THEN proceed.
   - Verify `.env` file exists in project root. If missing, STOP and tell the user to create it from `.env.example`.
   - Check for stale Flutter lock file at `<flutter_sdk>/bin/cache/lockfile`. If it exists and no flutter process is actively running, delete it.
   - Kill zombie `java.exe` and `gradle.exe` processes that may be holding memory from crashed builds:
     ```bash
     taskkill //F //IM "java.exe" 2>/dev/null
     ```

2. **Clean build environment** (skip if `$ARGUMENTS` contains `--skip-clean`)
   ```bash
   flutter clean
   flutter pub get
   ```

3. **Ask user for confirmation** before starting the build. Show:
   - Flavor: prod
   - Mode: release
   - Env file: .env
   - Estimated time: 15-20 minutes (clean build)

4. **Build APK**
   ```bash
   flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart
   ```
   Run with 10-minute timeout. This is a long-running command.

5. **Post-build verification**
   - Verify APK exists at `build/app/outputs/flutter-apk/app-prod-release.apk`
   - Report file size (expected ~125MB for this project)
   - Check for JVM crash dumps: `android/hs_err_*.log`
     - If found: read the crash log, diagnose (likely Gradle OOM), suggest reducing `-Xmx` in `android/gradle.properties`
     - If not found: build is clean

6. **Report results**
   ```
   ✅ APK built successfully
   📦 Path: build/app/outputs/flutter-apk/app-prod-release.apk
   📏 Size: <size>MB
   🔧 Flavor: prod | Mode: release
   ```

## Error Recovery

If the build fails or hangs:
1. Check `android/hs_err_*.log` — if present, it's a JVM OOM crash
2. Check `android/gradle.properties` — `-Xmx` must be ≤4G on a 16GB system
3. Current safe Gradle config: `-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=256m`
4. Kill stale Gradle daemons: `taskkill //F //IM "java.exe"`
5. Remove Flutter lock: delete `<flutter_sdk>/bin/cache/lockfile`
6. Retry from step 2

## Rules

- **ALWAYS** build from `main` with a clean working tree. Never from a feature branch. Never with uncommitted changes.
- **ALWAYS** bump versionCode in `pubspec.yaml` for every shipped APK. Same versionCode = Android silently rejects the install on update (founder hit this 2026-05-06 with APK Test #12; ate a rebuild + reship cycle).
- **ALWAYS** use `--flavor prod --release` (never build dev APKs for distribution)
- **ALWAYS** include `--dart-define-from-file=.env` (without it, SUPABASE_URL is empty and auth crashes)
- **ALWAYS** run `flutter clean` before release builds unless `--skip-clean` is passed
- **ALWAYS** ask user for confirmation before the actual build command
- **NEVER** modify `android/gradle.properties` `-Xmx` above 4G on this 16GB system
- **NEVER** ignore `hs_err_*.log` files — always diagnose and delete them
- Entry point is always `lib/main.dart` (single entry point, flavors handled by Gradle)
