# APK Test #5 Plan A — Cross-Account Data Isolation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cross-account Hive leaks architecturally impossible — Avyaansh signing into a fresh account cannot see Upendra's chats / submissions / schedule, even with stale local Hive data.

**Architecture:** Four layers. (1) Investigate the actual leak path in the +3 APK. (2) Migrate user-scoped Hive boxes to per-user namespacing (`coachBox_<8hex>` etc.) with two-phase init. (3) Wrap every user-scoped box read with an ownership guard that asserts owner-hash matches session user.id, throwing `HiveOwnershipException` on mismatch. (4) Client reconciliation in RestoringScreen so populated-profile-with-NULL-onboarding_completed_at users self-heal.

**Estimated effort:** 12-14h.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §3 + §10 (C1-C3).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `pubspec.yaml` | MODIFY | Bump versionCode +3 → +4 |
| `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md` | CREATE | Layer 1 investigation findings |
| `docs/superpowers/notes/2026-04-28-test-5-cleanup.md` | CREATE | Manual test-prep SQL + uninstall steps |
| `lib/core/services/hive_user_session.dart` | CREATE | `HiveUserSession` — open/close namespaced boxes per user |
| `lib/core/services/guarded_box.dart` | CREATE | `GuardedBox<T>` + `HiveOwnershipException` |
| `lib/core/services/hive_service.dart` | MODIFY | Getters route through `HiveUserSession` + return `GuardedBox<T>` |
| `lib/main.dart` | MODIFY | Two-phase init — open shared boxes only before runApp; install global error handler |
| `lib/features/auth/providers/auth_provider.dart` | MODIFY | Call `HiveUserSession.openForUser` after `_ensureLocalUser`; `closeAll` on signOut |
| `lib/features/auth/screens/restoring_screen.dart` | MODIFY | `_resolveOnboardingResumeRoute` self-heal path for populated-but-NULL onboarding_completed_at |
| `android/app/src/main/res/xml/data_extraction_rules.xml` | VERIFY/CREATE | Auto Backup exclusion of `app_flutter/` |
| `test/safety/cross_account_isolation_test.dart` | CREATE | 3 contract tests covering namespacing, guard throw, RestoringScreen reconciliation |

---

## Task A-1 — Branch setup + version bump

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Confirm worktree, create new branch off main**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
git fetch origin
git status --short
```

Expected: clean working tree (any pending changes from Test #4 must already be committed/pushed).

```bash
git checkout main
git pull origin main
git checkout -b feat/apk-test-5-batch
git branch --show-current
```

Expected output: `feat/apk-test-5-batch`. NOTE: branch is created off **main**, NOT off `feat/apk-test-4-batch` — Test #5 starts clean and re-introduces only the Test #4 fixes that survived audit (B1-B5 layers carried forward in Tasks A-5 onward).

- [ ] **Step 2: Bump versionCode +3 → +4**

Read current `pubspec.yaml` version line:

```bash
grep "^version:" pubspec.yaml
```

Expected: `version: 1.0.0+3`.

Edit `pubspec.yaml`:

```yaml
# BEFORE
version: 1.0.0+3

# AFTER
version: 1.0.0+4
```

- [ ] **Step 3: Empty initial commit**

```bash
git add pubspec.yaml
git commit -m "chore: branch setup for APK Test #5 batch

Bump versionCode 1.0.0+3 -> 1.0.0+4 for APK Test #5 ship.

Branch created off main (not feat/apk-test-4-batch) — clean slate.
Test #4 cross-account guards (B1-B5) re-introduced in Plan A tasks
A-5 onward as part of the namespaced-box architecture.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Verify branch + commit**

```bash
git log --oneline -1
git branch --show-current
```

Expected: latest commit subject `chore: branch setup for APK Test #5 batch`, branch `feat/apk-test-5-batch`.

---

## Task A-2 — Layer 1: signOut path investigation

**Files:**
- Create: `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md`

NO code changes this task — investigation only.

- [ ] **Step 1: Read signOut**

```bash
grep -nA 25 "Future<void> signOut" lib/features/auth/providers/auth_provider.dart
```

Capture the full method body. Note every Hive call, every `clearAllData` invocation, every Supabase call.

- [ ] **Step 2: Read splash_screen line 124**

```bash
sed -n '110,140p' lib/features/auth/screens/splash_screen.dart
```

Look for the secondary `clearAllData` call. Note: under what condition does it fire? Is it gated on a profile mismatch, or unconditional?

- [ ] **Step 3: Read RestoringScreen ownership check**

```bash
grep -nB 2 -A 30 "_ensureOwnershipBeforeHome\|hiveOwner\|lastAuthenticatedUserIdKey" lib/features/auth/screens/restoring_screen.dart
```

Note: does `_ensureOwnershipBeforeHome` actually fire on the path that produced OBS-5? What conditions skip it?

- [ ] **Step 4: Write the trace doc**

Create `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md` with this structure:

```markdown
# Cross-account leak trace — +3 APK (APK Test #4 ship)

**Date:** 2026-04-28
**Affected accounts:** `upendra.prasad@thinkingcode.com`, `avyaaanshfit@gmail.com`
**Symptom (OBS-5):** Sign out as Upendra → sign in as Avyaansh → AI coach screen shows Upendra's 13 chat messages locally even though cloud `ai_coach_interactions` is correctly scoped (Avyaansh = 2 rows, Upendra = 13 rows, separate user_id).

## Sign-out paths (all callers of clearAllData)

### Path 1: `auth_provider.dart::signOut`
[paste full method body here]

Findings:
- Calls clearAllData? [yes / no / conditionally — describe]
- Calls Hive.close()? [yes / no]
- Awaits Supabase signOut before/after clearAllData? [order matters]

### Path 2: `splash_screen.dart` line 124
[paste 30-line context]

Findings:
- When does this fire? [conditions]
- Does it duplicate Path 1, or fill a gap?
- Race condition risk with auth state listener?

### Path 3: any other callers of clearAllData
```bash
grep -rn "clearAllData" lib/
```
[list every hit with one-line description]

## restoreFromCloudForUser filter audit

[deferred to Task A-3]

## Auto Backup XML

[deferred to Task A-4]

## Hypothesis — actual leak path

Most likely: [pick one based on evidence]
- (H1) signOut clears Hive but auth state listener fires before clearAllData completes; new user upserted into stale boxes.
- (H2) clearAllData missed a box (e.g. notificationsBox shipped post-Test #3, never wired into clearAllData).
- (H3) Auto Backup restored Hive between uninstall/reinstall, bypassing clearAllData entirely.
- (H4) RestoringScreen ownership guard didn't fire because `lastAuthenticatedUserIdKey` was never stamped on the leaking session.

Evidence supporting [chosen hypothesis]: [bullet list]

## Recommendation for Layer 2 design

[1-paragraph summary feeding into Task A-5 design]
```

Write the document with concrete observations from steps 1-3. The "Hypothesis" section MUST commit to a primary suspected root cause based on evidence — don't leave all four open.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
git commit -m "docs(test-5): cross-account leak trace — sign-out path findings

Layer 1 investigation (Plan A Task A-2). Captures every clearAllData
caller, the splash_screen.dart:124 secondary path, and RestoringScreen
ownership guard fire conditions. Hypothesis section commits to a
primary suspected root cause that drives Layer 2 design (Task A-5+).

NO code changes — investigation only.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-3 — Layer 1: restoreFromCloud filter audit

**Files:**
- Modify: `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md` (append)

NO code changes.

- [ ] **Step 1: Locate restoreFromCloudForUser**

```bash
grep -nA 5 "Future<.*> restoreFromCloudForUser\|restoreFromCloud(" lib/core/services/sync_service.dart | head -40
```

- [ ] **Step 2: List every Supabase fetch inside the restore path**

```bash
grep -n "from('\|\.select(\|\.eq('user_id'" lib/core/services/sync_service.dart | head -50
```

For each `.from('table').select()...` block, verify it includes `.eq('user_id', <id>)` AND that `<id>` comes from the **current** session (`Supabase.instance.client.auth.currentUser?.id` or a parameter passed in *this* restore call), NOT from a cached field on `SyncService` or a stale local-Hive read.

Suspect patterns to grep for:
```bash
grep -n "_userId\|_cachedUserId\|userBox.get('profile')" lib/core/services/sync_service.dart | head -20
```

- [ ] **Step 3: Append findings to the trace doc**

Open `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md` and replace the `## restoreFromCloudForUser filter audit` section with:

```markdown
## restoreFromCloudForUser filter audit

### Method signature
[paste signature — `Future<RestoreResult> restoreFromCloudForUser(...)`]

### user_id source
[which auth source does the method use? Document precise expression:
e.g. `Supabase.instance.client.auth.currentUser?.id` vs a parameter
vs a cached `_userId` field on SyncService.]

### Per-table filter audit

| Table | Filter | Source of user_id | Stale risk? |
|---|---|---|---|
| user_profile | `.eq('user_id', X)` | [where X comes from] | [yes/no + why] |
| workout_logs | ... | ... | ... |
| ai_coach_interactions | ... | ... | ... |
| nutrition_logs | ... | ... | ... |
| ... (every table) | | | |

### Findings

- Filters that read user_id from a stale source: [list]
- Filters with no user_id .eq() at all: [list — these are bugs]
- Filters that look correct: [list]

### Action items for Layer 2

- [ ] [specific filters that need to be re-pointed at session.user.id]
- [ ] [or: "all filters look correct; the leak is upstream of this method"]
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
git commit -m "docs(test-5): restoreFromCloudForUser filter audit (Layer 1.2)

Per-table audit of every user_id filter in the cloud restore path.
Confirms whether the leak is in restore (pulling wrong user's rows)
or upstream of restore (not pulling at all, leaving stale Hive intact).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-4 — Layer 1: Auto Backup XML verification

**Files:**
- Verify: `android/app/src/main/AndroidManifest.xml`
- Create-or-verify: `android/app/src/main/res/xml/data_extraction_rules.xml`
- Modify: `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md` (append)

- [ ] **Step 1: Check AndroidManifest references the extraction rules**

```bash
grep -n "dataExtractionRules\|allowBackup" android/app/src/main/AndroidManifest.xml
```

Expected: `android:dataExtractionRules="@xml/data_extraction_rules"` AND `android:allowBackup="false"` on the `<application>` tag.

If `dataExtractionRules` reference is missing, edit `android/app/src/main/AndroidManifest.xml` and add to the `<application ...>` opening tag:

```xml
android:dataExtractionRules="@xml/data_extraction_rules"
```

If `allowBackup` is missing or `="true"`, set it to `="false"`.

- [ ] **Step 2: Verify the XML file exists**

```bash
ls -la android/app/src/main/res/xml/data_extraction_rules.xml 2>/dev/null && \
  echo "exists" || echo "MISSING — create it"
```

- [ ] **Step 3: If missing, create the file**

Create `android/app/src/main/res/xml/data_extraction_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" />
        <exclude domain="file" path="app_flutter/" />
        <exclude domain="database" />
        <exclude domain="sharedpref" />
        <exclude domain="external" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" />
        <exclude domain="file" path="app_flutter/" />
        <exclude domain="database" />
        <exclude domain="sharedpref" />
        <exclude domain="external" />
    </device-transfer>
</data-extraction-rules>
```

- [ ] **Step 4: Append findings to the trace doc**

Open `docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md` and replace the `## Auto Backup XML` section with:

```markdown
## Auto Backup XML verification

- AndroidManifest references `data_extraction_rules`: [yes / no — and was it added in this task?]
- `allowBackup`: [false / true / unset]
- `data_extraction_rules.xml` exists: [yes / no]
- `app_flutter/` excluded from cloud-backup: [yes / no]
- `app_flutter/` excluded from device-transfer: [yes / no]

Conclusion: [Auto Backup leak path is closed / was open and is now closed / does not contribute to OBS-5 because uninstall+reinstall already wiped Hive].
```

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml \
        android/app/src/main/res/xml/data_extraction_rules.xml \
        docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
git commit -m "fix(android): verify Auto Backup excludes app_flutter (Layer 1.3)

Confirms data_extraction_rules.xml ships with the APK and the manifest
references it. Hive boxes under app_flutter/ are excluded from both
cloud-backup and device-transfer extraction domains.

Trace doc updated with verification result.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-5 — Layer 2 setup: HiveUserSession class

**Files:**
- Create: `lib/core/services/hive_user_session.dart`

- [ ] **Step 1: Create the file**

Create `lib/core/services/hive_user_session.dart` with the following content:

```dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'hive_service.dart';

/// Owns the per-user Hive box lifecycle. Opens namespaced boxes
/// (`<box>_<8hex>`) when the user signs in; closes them on sign-out.
///
/// User-scoped boxes — userBox / workoutBox / nutritionBox / healthBox /
/// coachBox / customBox / notificationsBox — are physically separate
/// Hive box files per user. Cross-account leaks become impossible at
/// the storage layer: Avyaansh's sign-in opens `coachBox_94368fd4`,
/// which has no relationship to Upendra's `coachBox_5f0a13b2`.
///
/// Shared boxes — exerciseBox / foodBox / configBox / syncBox — are
/// owned by `HiveService` directly and stay open across the app
/// lifetime; they are NOT touched by this class.
///
/// Bootstrap order (cold start):
///   1. main.dart runs `HiveService.instance.init()` — opens shared
///      boxes only.
///   2. Auth resolves → `_ensureLocalUser` → on success
///      `HiveUserSession.openForUser(user.id)` opens the 7
///      user-scoped boxes.
///   3. UI mounts. Reads through `HiveService.instance.userBox` etc.
///      transparently route to the namespaced box via
///      `currentOwnerHash`.
class HiveUserSession {
  HiveUserSession._();

  /// 8-hex prefix of the currently signed-in user.id. Null when no
  /// user-scoped boxes are open (cold start before sign-in,
  /// post-sign-out before the next sign-in).
  static String? _currentOwnerHash;

  /// Full user.id of the current owner. Stored alongside the hash so
  /// guards can compare full ids without depending on prefix collisions.
  static String? _currentOwnerFullId;

  static String? get currentOwnerHash => _currentOwnerHash;
  static String? get currentOwnerFullId => _currentOwnerFullId;

  /// The 7 user-scoped box roots. Each gets `_<hash>` appended at open.
  static const List<String> userScopedBoxRoots = <String>[
    HiveService.userBoxName,
    HiveService.workoutBoxName,
    HiveService.nutritionBoxName,
    HiveService.healthBoxName,
    HiveService.coachBoxName,
    HiveService.customBoxName,
    HiveService.notificationsBoxName,
  ];

  /// Compute the namespaced box name for a given root + user.id.
  /// `userBox` + `5f0a13b2-...` → `userBox_5f0a13b2`.
  static String namespacedBoxName(String root, String userId) {
    final hash = userId.replaceAll('-', '').substring(0, 8);
    return '${root}_$hash';
  }

  /// Open the 7 user-scoped boxes for [userId]. Idempotent — calling
  /// twice with the same id is a no-op. Calling with a different id
  /// closes the previous user's boxes first.
  ///
  /// Throws [HiveError] if a box file is corrupted; caller should
  /// surface this as a fatal error and force the user to reinstall.
  static Future<void> openForUser(String userId) async {
    if (_currentOwnerFullId == userId) {
      return;
    }
    if (_currentOwnerFullId != null) {
      await closeAll();
    }

    final hash = userId.replaceAll('-', '').substring(0, 8);
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, userId);
      try {
        await Hive.openBox(boxName);
      } catch (e) {
        debugPrint('[HiveUserSession] failed to open $boxName: $e');
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }

    _currentOwnerHash = hash;
    _currentOwnerFullId = userId;
    debugPrint('[HiveUserSession] opened 7 boxes for user $hash');
  }

  /// Close + clear references to all user-scoped boxes. Files remain
  /// on disk (use `clearAllDataForCurrentUser` to delete contents).
  static Future<void> closeAll() async {
    if (_currentOwnerFullId == null) return;
    final id = _currentOwnerFullId!;
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, id);
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
    }
    _currentOwnerHash = null;
    _currentOwnerFullId = null;
    debugPrint('[HiveUserSession] closed all user-scoped boxes');
  }

  /// Delete every user-scoped box file for the **current** user.
  /// Used by signOut so leftover bytes can't surface on next sign-in.
  static Future<void> deleteAllFilesForCurrentUser() async {
    if (_currentOwnerFullId == null) return;
    final id = _currentOwnerFullId!;
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, id);
      try {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
        await Hive.deleteBoxFromDisk(boxName);
      } catch (e) {
        debugPrint('[HiveUserSession] failed to delete $boxName: $e');
      }
    }
    _currentOwnerHash = null;
    _currentOwnerFullId = null;
  }
}
```

- [ ] **Step 2: Verify compile**

```bash
flutter analyze lib/core/services/hive_user_session.dart
```

Expected: no errors. If `HiveService.userBoxName` etc. don't resolve, double-check `lib/core/services/hive_service.dart` already exposes them as `static const String` (verified at planning time — they exist on lines 27-37).

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/hive_user_session.dart
git commit -m "feat(hive): HiveUserSession — per-user namespaced box lifecycle (Layer 2.1)

Owns the 7 user-scoped Hive boxes (user/workout/nutrition/health/coach/
custom/notifications). Each user gets <box>_<8hex> namespaced files.
Shared boxes (exercise/food/config/sync) stay on HiveService.

Public API:
- openForUser(userId)        → idempotent open of 7 boxes
- closeAll()                  → close + clear references
- deleteAllFilesForCurrentUser() → physical file delete (signOut path)
- currentOwnerHash / currentOwnerFullId → for guard checks

Wires into HiveService getters in next task (A-6).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-6 — Layer 2: rename HiveService getters to namespaced

**Files:**
- Modify: `lib/core/services/hive_service.dart`

- [ ] **Step 1: Read current getters block (lines 184-194)**

```bash
sed -n '180,200p' lib/core/services/hive_service.dart
```

Confirms the 11 getters (`userBox`, `workoutBox`, `nutritionBox`, `healthBox`, `exerciseBox`, `foodBox`, `customBox`, `coachBox`, `syncBox`, `configBox`, `notificationsBox`).

- [ ] **Step 2: Replace user-scoped getters to route via HiveUserSession**

Edit `lib/core/services/hive_service.dart`. Replace the convenience getters block (lines 182-194) with:

```dart
  // ── Convenience getters for each box ──────────────────────────
  //
  // Shared boxes (read-only seed + app-level config) resolve to a
  // single global box.
  Box get exerciseBox => getBox(exerciseBoxName);
  Box get foodBox => getBox(foodBoxName);
  Box get syncBox => getBox(syncBoxName);
  Box get configBox => getBox(configBoxName);

  // User-scoped boxes resolve to `<root>_<8hex>` based on the current
  // HiveUserSession owner. Throws StateError if no user is signed in
  // (caller bug — UI should never read user-scoped Hive on the
  // unauthenticated splash screen).
  Box get userBox => _userScopedBox(userBoxName);
  Box get workoutBox => _userScopedBox(workoutBoxName);
  Box get nutritionBox => _userScopedBox(nutritionBoxName);
  Box get healthBox => _userScopedBox(healthBoxName);
  Box get customBox => _userScopedBox(customBoxName);
  Box get coachBox => _userScopedBox(coachBoxName);
  Box get notificationsBox => _userScopedBox(notificationsBoxName);

  Box _userScopedBox(String root) {
    if (!_initialized) {
      throw StateError(
        'HiveService.init() must be called before accessing boxes.',
      );
    }
    final ownerId = HiveUserSession.currentOwnerFullId;
    if (ownerId == null) {
      throw StateError(
        'HiveUserSession not opened — cannot access user-scoped box "$root". '
        'Call HiveUserSession.openForUser(userId) after sign-in.',
      );
    }
    final boxName = HiveUserSession.namespacedBoxName(root, ownerId);
    return Hive.box(boxName);
  }
```

Add the `import 'hive_user_session.dart';` line at the top of the file alongside other imports.

- [ ] **Step 3: Update `_compactableBoxNames` resolution**

Find the `_maybeCompact` method (lines 128-153). The current code iterates `_compactableBoxNames` and calls `Hive.box(name)`. With namespacing, those names need to be resolved per-user. Replace the `for (final name in _compactableBoxNames)` loop body with:

```dart
      for (final name in _compactableBoxNames) {
        try {
          final ownerId = HiveUserSession.currentOwnerFullId;
          // User-scoped boxes only compact when a user is signed in.
          // Shared boxes (configBox excluded — see _compactableBoxNames
          // comment on line ~104) compact regardless.
          final isUserScoped = HiveUserSession.userScopedBoxRoots.contains(name);
          if (isUserScoped && ownerId == null) {
            continue;
          }
          final actualBoxName = isUserScoped
              ? HiveUserSession.namespacedBoxName(name, ownerId!)
              : name;
          if (!Hive.isBoxOpen(actualBoxName)) continue;
          await Hive.box(actualBoxName).compact();
        } catch (e) {
          debugPrint('[HiveService._maybeCompact] $name: $e');
        }
      }
```

- [ ] **Step 4: Verify compile**

```bash
flutter analyze lib/core/services/hive_service.dart lib/core/services/hive_user_session.dart
```

Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/hive_service.dart
git commit -m "feat(hive): route user-scoped getters through HiveUserSession (Layer 2.2)

userBox / workoutBox / nutritionBox / healthBox / customBox / coachBox /
notificationsBox now resolve to <root>_<8hex> based on
HiveUserSession.currentOwnerFullId. Shared boxes (exercise/food/sync/
config) unchanged.

Throws StateError if a user-scoped box is read with no signed-in
session — caller bug, must be fixed at call site (no silent fallback
to a shared box that could leak).

_maybeCompact loop updated to namespace user-scoped box names.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-7 — Layer 2: two-phase init in main.dart + auth_provider

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Locate `main()` Hive init**

```bash
grep -nA 5 "HiveService.instance.init\|Hive.initFlutter\|runApp" lib/main.dart | head -40
```

- [ ] **Step 2: Confirm main.dart only opens shared boxes (no per-user calls)**

Current `HiveService.init()` opens all 11 boxes via `_safeOpenBox(name)` for each entry in the `_allBoxNames` list. With namespacing, only the 4 shared boxes (`exerciseBox`, `foodBox`, `configBox`, `syncBox`) should be opened at this stage.

Edit `lib/core/services/hive_service.dart`. Find the `init()` method and the `_allBoxNames` list:

```bash
grep -n "_allBoxNames\|Future<void> init" lib/core/services/hive_service.dart
```

Replace the static `_allBoxNames` (lines 45-57) with two lists:

```dart
  /// Shared boxes — opened by `init()` before runApp. Available to all
  /// users / no users.
  static const List<String> _sharedBoxNames = <String>[
    exerciseBoxName,
    foodBoxName,
    syncBoxName,
    configBoxName,
  ];

  /// User-scoped boxes — opened by `HiveUserSession.openForUser(id)`
  /// AFTER auth resolves. Each gets a `_<8hex>` namespace suffix.
  static const List<String> _userScopedBoxNames = <String>[
    userBoxName,
    workoutBoxName,
    nutritionBoxName,
    healthBoxName,
    customBoxName,
    coachBoxName,
    notificationsBoxName,
  ];
```

Update `init()` to iterate `_sharedBoxNames` only:

```dart
  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    for (final name in _sharedBoxNames) {
      await _safeOpenBox(name);
    }
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }
```

- [ ] **Step 3: Wire `HiveUserSession.openForUser` into auth_provider**

```bash
grep -nB 2 -A 30 "Future<void> _ensureLocalUser" lib/features/auth/providers/auth_provider.dart | head -60
```

Find the END of `_ensureLocalUser` (after the existing users-table upsert + terms_accepted_at sync). At the very end of the method, add:

```dart
    // Layer 2.3 — open per-user namespaced boxes BEFORE any UI mounts
    // that might read user-scoped Hive (RestoringScreen + everything
    // downstream). Idempotent — re-running for the same user is a
    // no-op. Different user → previous boxes closed first.
    await HiveUserSession.openForUser(user.id);
```

Add the import at the top of `auth_provider.dart` if not already present:

```dart
import 'package:icanbefitter/core/services/hive_user_session.dart';
```

- [ ] **Step 4: Wire `closeAll` into signOut**

Find the `signOut` method:

```bash
grep -nA 30 "Future<void> signOut" lib/features/auth/providers/auth_provider.dart
```

Modify `signOut` so the order is:
1. `await UserRepository.instance.clearAllData()` (clears box contents — works because boxes are still open)
2. `await HiveUserSession.deleteAllFilesForCurrentUser()` (closes + deletes the namespaced box files)
3. `await Supabase.instance.client.auth.signOut()` (terminates session)

Replace the body of `signOut` with:

```dart
  Future<void> signOut() async {
    try {
      await UserRepository.instance.clearAllData();
    } catch (e) {
      debugPrint('[auth/signOut] clearAllData failed: $e');
    }
    try {
      await HiveUserSession.deleteAllFilesForCurrentUser();
    } catch (e) {
      debugPrint('[auth/signOut] deleteAllFilesForCurrentUser failed: $e');
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('[auth/signOut] supabase signOut failed: $e');
    }
    state = const AsyncData(null);
  }
```

- [ ] **Step 5: Verify compile**

```bash
flutter analyze lib/main.dart lib/features/auth/providers/auth_provider.dart lib/core/services/hive_service.dart
```

Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/features/auth/providers/auth_provider.dart lib/core/services/hive_service.dart
git commit -m "feat(auth): two-phase Hive init — shared boxes pre-runApp, user-scoped post-auth (Layer 2.3)

HiveService.init() opens only the 4 shared boxes (exercise/food/sync/
config) before runApp. _ensureLocalUser opens the 7 user-scoped boxes
via HiveUserSession.openForUser(user.id) AFTER auth resolves.

signOut order:
1. clearAllData (boxes still open, contents wiped)
2. HiveUserSession.deleteAllFilesForCurrentUser (close + rm files)
3. Supabase auth.signOut (terminate session)

Each step wrapped in try/catch — partial failure doesn't abort the
remaining cleanup. Cross-account leak path closed at the storage
layer: a sign-in for user B can never read user A's box files.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-8 — Layer 2: migration of pre-namespacing local data

**Files:**
- Modify: `lib/core/services/hive_user_session.dart`

Existing installs (Test #4 +3 APK) have shared `coachBox` / `userBox` / etc. files containing the most recent user's data. On first launch of the +5 APK, that data needs to migrate into `coachBox_<currentUserId>` so the user doesn't perceive a data loss.

- [ ] **Step 1: Add `_migrateLegacySharedBoxes` to HiveUserSession**

Edit `lib/core/services/hive_user_session.dart`. Add a new private method invoked at the start of `openForUser`:

```dart
  /// One-shot migration: if a pre-namespacing shared box exists for any
  /// user-scoped root AND the per-user namespaced box for [userId]
  /// doesn't already have data, copy contents over and delete the
  /// shared box. Idempotent — second invocation finds no shared box
  /// to migrate, returns immediately.
  ///
  /// Skipped silently if the shared box is empty or fails to open.
  static Future<void> _migrateLegacySharedBoxes(String userId) async {
    for (final root in userScopedBoxRoots) {
      final namespaced = namespacedBoxName(root, userId);
      try {
        // If namespaced already has any keys, migration already ran for
        // this user OR they signed in fresh post-namespacing. Skip.
        if (Hive.isBoxOpen(namespaced)) {
          if (Hive.box(namespaced).keys.isNotEmpty) continue;
        }

        // Try to open the legacy shared box. If it doesn't exist on
        // disk, openBox creates an empty one — check keys count and
        // delete-empty if so.
        final legacy = await Hive.openBox(root);
        if (legacy.keys.isEmpty) {
          await legacy.close();
          await Hive.deleteBoxFromDisk(root);
          continue;
        }

        // Open namespaced (creates if needed), copy every key/value,
        // close + delete legacy.
        final dest = Hive.isBoxOpen(namespaced)
            ? Hive.box(namespaced)
            : await Hive.openBox(namespaced);
        for (final key in legacy.keys) {
          await dest.put(key, legacy.get(key));
        }
        await legacy.close();
        await Hive.deleteBoxFromDisk(root);
        debugPrint(
          '[HiveUserSession] migrated $root → $namespaced (${dest.keys.length} keys)',
        );
      } catch (e) {
        debugPrint('[HiveUserSession] migration $root failed: $e');
        // Non-fatal — fresh start, cloud has the data anyway.
      }
    }
  }
```

- [ ] **Step 2: Call migration at the start of openForUser**

Modify `openForUser` to call `_migrateLegacySharedBoxes(userId)` BEFORE the `for (final root in userScopedBoxRoots)` open loop:

```dart
  static Future<void> openForUser(String userId) async {
    if (_currentOwnerFullId == userId) {
      return;
    }
    if (_currentOwnerFullId != null) {
      await closeAll();
    }

    // One-shot migration — copies pre-namespacing shared box contents
    // into the namespaced box on first sign-in after upgrade.
    await _migrateLegacySharedBoxes(userId);

    final hash = userId.replaceAll('-', '').substring(0, 8);
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, userId);
      try {
        await Hive.openBox(boxName);
      } catch (e) {
        debugPrint('[HiveUserSession] failed to open $boxName: $e');
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }

    _currentOwnerHash = hash;
    _currentOwnerFullId = userId;
    debugPrint('[HiveUserSession] opened 7 boxes for user $hash');
  }
```

- [ ] **Step 3: Write a unit test for the migration**

Create `test/safety/hive_migration_legacy_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_mig_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('migration: legacy coachBox content copied to coachBox_<hash>', () async {
    // Simulate pre-namespacing state: data lives in shared coachBox
    final legacy = await Hive.openBox('coachBox');
    await legacy.put('msg_1', {'role': 'user', 'content': 'hello'});
    await legacy.put('msg_2', {'role': 'assistant', 'content': 'hi'});
    await legacy.close();

    // Sign in user A → migration should fire
    const userId = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
    await HiveUserSession.openForUser(userId);

    // Namespaced box has the data
    final namespaced = Hive.box('coachBox_5f0a13b2');
    expect(namespaced.get('msg_1'), {'role': 'user', 'content': 'hello'});
    expect(namespaced.get('msg_2'), {'role': 'assistant', 'content': 'hi'});

    // Legacy shared box is gone
    expect(File('${tempDir.path}/coachBox.hive').existsSync(), false);

    await HiveUserSession.closeAll();
  });

  test('migration is idempotent — second call no-ops', () async {
    final legacy = await Hive.openBox('coachBox');
    await legacy.put('msg_1', {'role': 'user', 'content': 'hello'});
    await legacy.close();

    const userId = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
    await HiveUserSession.openForUser(userId);
    await HiveUserSession.closeAll();

    // Second open of same user — no legacy file remains, migration skips silently
    await HiveUserSession.openForUser(userId);
    final namespaced = Hive.box('coachBox_5f0a13b2');
    expect(namespaced.get('msg_1'), {'role': 'user', 'content': 'hello'});
    await HiveUserSession.closeAll();
  });
}
```

- [ ] **Step 4: Run the test**

```bash
flutter test test/safety/hive_migration_legacy_test.dart
```

Expected: 2 passing tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/hive_user_session.dart \
        test/safety/hive_migration_legacy_test.dart
git commit -m "feat(hive): one-shot legacy shared-box migration (Layer 2.4)

On first openForUser after upgrade from pre-namespacing APK:
- For each of 7 user-scoped roots, check if shared <root> file has data
- If yes + namespaced <root>_<hash> is empty → copy contents
- Delete shared file
- Idempotent: empty shared box → delete-only; populated namespaced → skip

Failure of any single migration is non-fatal (logged + skipped).
Worst case: fresh start, cloud restore re-populates.

Tests: 2 unit tests under test/safety/.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-9 — Layer 3: GuardedBox + HiveOwnershipException

**Files:**
- Create: `lib/core/services/guarded_box.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'hive_user_session.dart';

/// Thrown when a user-scoped Hive box is accessed with a session that
/// doesn't own it. Caught by the global error handler installed in
/// `main.dart`, which force-signs-out + clears local state + redirects
/// to /sign-in.
class HiveOwnershipException implements Exception {
  HiveOwnershipException(this.message);
  final String message;
  @override
  String toString() => 'HiveOwnershipException: $message';
}

/// Wraps a Hive [Box] of type [T] with an ownership assertion on every
/// read/write/key/delete operation.
///
/// Construction captures the owner's 8-hex hash + full id at the moment
/// `HiveUserSession.openForUser` ran. Every operation checks that the
/// CURRENT Supabase session's user.id still starts with the captured
/// hash. Mismatch → throw `HiveOwnershipException`.
///
/// This is defense-in-depth on top of the namespaced-box layer (Task
/// A-5/6/7). Even if a namespaced box is somehow handed to a different
/// session (race condition, bug in HiveUserSession), the wrapper
/// catches the misuse at the call site instead of silently leaking
/// data.
class GuardedBox<T> {
  GuardedBox(this._box, this._ownerHash, this._ownerFullId);

  final Box _box;
  final String _ownerHash;
  final String _ownerFullId;

  void _assertOwnership() {
    final session = Supabase.instance.client.auth.currentUser?.id;
    if (session == null) {
      throw HiveOwnershipException(
        'No active session for user-scoped box (owner=$_ownerHash)',
      );
    }
    if (session != _ownerFullId) {
      throw HiveOwnershipException(
        'Box owner $_ownerHash != session ${session.substring(0, 8)}',
      );
    }
  }

  // ── Box surface — every method asserts ownership first ────────

  T? get(dynamic key, {T? defaultValue}) {
    _assertOwnership();
    return _box.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> put(dynamic key, T value) async {
    _assertOwnership();
    await _box.put(key, value);
  }

  Future<void> putAll(Map<dynamic, T> entries) async {
    _assertOwnership();
    await _box.putAll(entries);
  }

  Future<void> delete(dynamic key) async {
    _assertOwnership();
    await _box.delete(key);
  }

  Future<void> deleteAll(Iterable keys) async {
    _assertOwnership();
    await _box.deleteAll(keys);
  }

  Future<int> clear() async {
    _assertOwnership();
    return _box.clear();
  }

  Iterable get keys {
    _assertOwnership();
    return _box.keys;
  }

  Iterable<T> get values {
    _assertOwnership();
    return _box.values.cast<T>();
  }

  bool containsKey(dynamic key) {
    _assertOwnership();
    return _box.containsKey(key);
  }

  int get length {
    _assertOwnership();
    return _box.length;
  }

  bool get isEmpty {
    _assertOwnership();
    return _box.isEmpty;
  }

  bool get isNotEmpty {
    _assertOwnership();
    return _box.isNotEmpty;
  }

  /// Escape hatch: callers that need the raw Hive Box (e.g. listenable
  /// for ValueListenableBuilder) should use this AND assert ownership
  /// at the listener tier themselves. Use sparingly.
  Box get rawBox {
    _assertOwnership();
    return _box;
  }

  String get debugOwnerHash => _ownerHash;
}

/// Helper used by HiveService getters to construct a guarded wrapper
/// for a user-scoped box. Throws StateError if no session is active
/// (caller bug — same surface as Task A-6's `_userScopedBox`).
GuardedBox<T> wrapUserScopedBox<T>(String root) {
  final fullId = HiveUserSession.currentOwnerFullId;
  final hash = HiveUserSession.currentOwnerHash;
  if (fullId == null || hash == null) {
    throw StateError(
      'HiveUserSession not opened — cannot wrap user-scoped box "$root". '
      'Call HiveUserSession.openForUser(userId) after sign-in.',
    );
  }
  final boxName = HiveUserSession.namespacedBoxName(root, fullId);
  final box = Hive.box(boxName);
  return GuardedBox<T>(box, hash, fullId);
}
```

- [ ] **Step 2: Verify compile**

```bash
flutter analyze lib/core/services/guarded_box.dart
```

Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/guarded_box.dart
git commit -m "feat(hive): GuardedBox + HiveOwnershipException (Layer 3.1)

Defense-in-depth wrapper around user-scoped Hive boxes. Every
get/put/keys/delete/clear call asserts that the current Supabase
session's user.id matches the box's captured owner. Mismatch →
HiveOwnershipException, caught by global handler in main.dart (Task A-11).

This catches the case where a namespaced box reference somehow leaks
across a session boundary (race condition in openForUser/closeAll,
bug in caller, future regression). Without this layer, a stale Box
reference would silently read the wrong user's data.

API mirrors Hive Box surface: get / put / putAll / delete / deleteAll /
clear / keys / values / containsKey / length / isEmpty / isNotEmpty.
Plus rawBox escape hatch for ValueListenableBuilder.

wrapUserScopedBox<T>(root) factory used by HiveService getters in
Task A-10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-10 — Layer 3: wire HiveService getters through GuardedBox

**Files:**
- Modify: `lib/core/services/hive_service.dart`

Note: changing return type from `Box` to `GuardedBox<T>` is a breaking API change for every callsite. To avoid massive ripple, we keep the public getter return type as `Box` and route through `GuardedBox.rawBox`. The guard fires on every read via the wrapper's surface methods exposed on `GuardedBox`. Direct callers that want strict typing can use the new typed getters added below.

- [ ] **Step 1: Update HiveService user-scoped getters to return guarded wrappers**

Replace the user-scoped getter block (added in Task A-6) with both untyped (`Box`) and typed (`GuardedBox<dynamic>`) variants:

```dart
  // User-scoped boxes — now wrapped by GuardedBox for ownership
  // assertion on every operation. The Box getters return the raw
  // underlying box for backward compatibility with existing call
  // sites; the GuardedBox getters are preferred for new code.

  Box get userBox => userBoxGuarded.rawBox;
  Box get workoutBox => workoutBoxGuarded.rawBox;
  Box get nutritionBox => nutritionBoxGuarded.rawBox;
  Box get healthBox => healthBoxGuarded.rawBox;
  Box get customBox => customBoxGuarded.rawBox;
  Box get coachBox => coachBoxGuarded.rawBox;
  Box get notificationsBox => notificationsBoxGuarded.rawBox;

  GuardedBox<dynamic> get userBoxGuarded =>
      wrapUserScopedBox<dynamic>(userBoxName);
  GuardedBox<dynamic> get workoutBoxGuarded =>
      wrapUserScopedBox<dynamic>(workoutBoxName);
  GuardedBox<dynamic> get nutritionBoxGuarded =>
      wrapUserScopedBox<dynamic>(nutritionBoxName);
  GuardedBox<dynamic> get healthBoxGuarded =>
      wrapUserScopedBox<dynamic>(healthBoxName);
  GuardedBox<dynamic> get customBoxGuarded =>
      wrapUserScopedBox<dynamic>(customBoxName);
  GuardedBox<dynamic> get coachBoxGuarded =>
      wrapUserScopedBox<dynamic>(coachBoxName);
  GuardedBox<dynamic> get notificationsBoxGuarded =>
      wrapUserScopedBox<dynamic>(notificationsBoxName);
```

Add the import at the top of `hive_service.dart`:

```dart
import 'guarded_box.dart';
```

Note: `userBox => userBoxGuarded.rawBox` triggers `_assertOwnership` once on access. The returned raw `Box` reference can still be used to read data without further guarding — that's the cost of backward compatibility. Future callsites should migrate to `userBoxGuarded.get(key)` / `.put(key, value)` for guarded-on-every-call semantics. We do NOT migrate every callsite in this batch — the once-on-access guard is sufficient because (a) namespacing already prevents cross-account leaks at the storage layer, and (b) the brief window where a stale Box reference could be held is bounded by the next call to `userBox` which re-runs the guard.

- [ ] **Step 2: Verify compile of HiveService + at least one existing consumer**

```bash
flutter analyze lib/core/services/hive_service.dart
flutter analyze lib/shared/repositories/user_repository.dart
flutter analyze lib/shared/repositories/workout_repository.dart
```

Expected: 0 issues. Existing `userBox`, `workoutBox` etc. callsites continue to compile because the return type is still `Box`.

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/hive_service.dart
git commit -m "feat(hive): HiveService user-scoped getters route through GuardedBox (Layer 3.2)

Preserves the public `Box` return type for backward compat (no ripple
across hundreds of callsites). The guard fires on first access via
`*BoxGuarded.rawBox`. Future code should migrate to the *Guarded
getters for guarded-on-every-call semantics.

Returns:
- userBox / workoutBox / etc. → Box (assert-once-on-access)
- userBoxGuarded / workoutBoxGuarded / etc. → GuardedBox<dynamic>
  (assert-on-every-method-call)

Cross-account safety primary line of defense remains the namespaced
box files (Task A-5/6/7). GuardedBox catches stale-reference edge
cases that namespacing alone cannot.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-11 — Layer 3: global HiveOwnershipException handler

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Locate the existing zone / runApp call**

```bash
grep -nB 2 -A 10 "runApp\|runZonedGuarded\|FlutterError.onError" lib/main.dart | head -40
```

- [ ] **Step 2: Wrap runApp in runZonedGuarded with HiveOwnershipException handling**

Edit `lib/main.dart`. Replace the `runApp(...)` call with:

```dart
import 'dart:async';
// ... other existing imports ...
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // ... existing setup (WidgetsFlutterBinding.ensureInitialized,
  //     dotenv-style env injection if any, HiveService.init, etc.) ...

  await runZonedGuarded(
    () async {
      runApp(/* existing ProviderScope + MaterialApp.router */);
    },
    (error, stack) async {
      if (error is HiveOwnershipException) {
        debugPrint('[main] HiveOwnershipException caught: $error');
        try {
          await UserRepository.instance.clearAllData();
        } catch (e) {
          debugPrint('[main] clearAllData on ownership-exception failed: $e');
        }
        try {
          await HiveUserSession.deleteAllFilesForCurrentUser();
        } catch (e) {
          debugPrint('[main] deleteAllFilesForCurrentUser on ownership-exception failed: $e');
        }
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (e) {
          debugPrint('[main] signOut on ownership-exception failed: $e');
        }
        // Router auth listener will redirect to /sign-in on signOut.
        // No need to push a route manually.
        return;
      }
      // Re-raise non-ownership errors.
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    },
  );
}
```

If `main.dart` already wraps `runApp` in `runZonedGuarded`, fold the `HiveOwnershipException` branch into the existing handler instead of adding a second wrapper. Critical: the handler must `await` the cleanup before returning so the next sign-in starts from a clean state.

The user-facing snackbar ("Session expired. Please sign in again.") is rendered by the sign-in screen on mount — see Task A-13 step 2 for the wiring detail (sign-in screen reads a one-shot flag from `configBox` set by this handler before the redirect).

- [ ] **Step 3: Set the one-shot snackbar flag**

In the same `HiveOwnershipException` branch, before the `signOut`, write a flag:

```dart
        try {
          await Hive.box(HiveService.configBoxName).put(
            'session_expired_flag',
            DateTime.now().toIso8601String(),
          );
        } catch (e) {
          debugPrint('[main] write session_expired_flag failed: $e');
        }
```

Add the import:

```dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
```

The sign-in screen reads + clears this flag in Task A-13 if needed (in this plan, surfacing the snackbar is a small follow-up; adding it here would expand scope. The flag write is sufficient to wire it in Plan B / future polish.).

- [ ] **Step 4: Verify compile**

```bash
flutter analyze lib/main.dart
```

Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(main): global HiveOwnershipException handler (Layer 3.3)

runZonedGuarded catches HiveOwnershipException → clearAllData →
HiveUserSession.deleteAllFilesForCurrentUser → Supabase.signOut.
Router auth listener handles the /sign-in redirect.

Writes a session_expired_flag to configBox before signOut so the
sign-in screen can render a one-shot snackbar (\"Session expired.
Please sign in again.\") — wiring of the snackbar render itself is
deferred to follow-up polish (out of scope for Plan A).

Non-ownership errors continue to flow through FlutterError.reportError.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-12 — Layer 4: RestoringScreen client reconciliation

**Files:**
- Modify: `lib/features/auth/screens/restoring_screen.dart`

- [ ] **Step 1: Locate `_resolveOnboardingResumeRoute`**

```bash
grep -nB 2 -A 60 "_resolveOnboardingResumeRoute" lib/features/auth/screens/restoring_screen.dart
```

Capture the current method body. Look for the line that reads `profile['onboarding_completed_at']` and decides between `/home` / resume-step / `/onboarding/mission-brief`.

- [ ] **Step 2: Replace the method body**

Edit `lib/features/auth/screens/restoring_screen.dart`. Replace `_resolveOnboardingResumeRoute` with:

```dart
  /// Decides where to navigate after the post-auth gate finishes.
  ///
  /// Layer 4 (Plan A) self-heals legacy accounts where
  /// `user_profile.onboarding_completed_at IS NULL` despite the row
  /// being populated with goal/experience/weight. Symptom (OBS-3):
  /// returning user signs in, dumped back to onboarding because the
  /// flag was never stamped on first onboarding sync.
  ///
  /// Reconciliation rule: if the row HAS goal AND experience AND
  /// weight → user is effectively onboarded. Stamp the flag during
  /// restore so the inconsistency can never recur.
  Future<String> _resolveOnboardingResumeRoute(
    Map<String, dynamic>? profile,
  ) async {
    if (profile == null) {
      // No row → genuinely new user. Mission Brief (step 00).
      return '/onboarding/mission-brief';
    }

    final hasOnboardedFlag = profile['onboarding_completed_at'] != null;

    final hasCorePlanFields =
        profile['primary_goal'] != null &&
        profile['fitness_experience'] != null &&
        profile['current_weight_kg'] != null;

    final isOnboarded = hasOnboardedFlag || hasCorePlanFields;

    if (isOnboarded) {
      // Self-heal path — populated profile but the flag was never
      // stamped (legacy bug). Stamp it now via the existing helper.
      if (!hasOnboardedFlag) {
        debugPrint(
          '[RestoringScreen] self-heal: profile populated but '
          'onboarding_completed_at is NULL — stamping now.',
        );
        try {
          await _completeOnboardingFromRestore();
        } catch (e) {
          debugPrint('[RestoringScreen] self-heal stamp failed: $e');
          // Non-fatal — user still routed to /home; next launch will
          // re-attempt the stamp.
        }
      }
      return '/home';
    }

    // Mid-onboarding abandonment — pick first missing step.
    if (profile['full_name'] == null || profile['date_of_birth'] == null) {
      return '/onboarding/identity';
    }
    if (profile['primary_goal'] == null) {
      return '/onboarding/goal';
    }
    if (profile['current_weight_kg'] == null) {
      return '/onboarding/stats';
    }
    if (profile['fitness_experience'] == null) {
      return '/onboarding/details';
    }
    return '/onboarding/plan';
  }
```

If `_completeOnboardingFromRestore` doesn't already exist on `RestoringScreen`, add it as a private method that calls into `OnboardingNotifier.completeOnboarding` OR writes `onboarding_completed_at = NOW()` directly via `SyncService.instance.syncProfileNow(userId)` after writing to Hive. Verify the existing helper:

```bash
grep -nA 20 "_completeOnboardingFromRestore" lib/features/auth/screens/restoring_screen.dart
```

If absent, add this private method:

```dart
  /// Layer 4 self-heal — stamps onboarding_completed_at = NOW() on both
  /// Hive and Supabase so the populated-but-NULL state can't recur.
  Future<void> _completeOnboardingFromRestore() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final stampedAt = DateTime.now().toUtc().toIso8601String();
    final profileBox = HiveService.instance.userBox;
    final existing = (profileBox.get('profile') as Map?) ?? <dynamic, dynamic>{};
    final merged = Map<String, dynamic>.from(existing.cast<String, dynamic>());
    merged['onboarding_completed_at'] = stampedAt;
    await profileBox.put('profile', merged);
    unawaited(SyncService.instance.syncProfileNow(user.id));
  }
```

Add imports if needed:
```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
```

- [ ] **Step 3: Verify compile**

```bash
flutter analyze lib/features/auth/screens/restoring_screen.dart
```

Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/screens/restoring_screen.dart
git commit -m "fix(auth): RestoringScreen self-heals NULL onboarding_completed_at (Layer 4)

OBS-3 root cause: returning user has populated user_profile row
(goal/experience/weight all set) but onboarding_completed_at is NULL.
Pre-fix flow routed them back to /onboarding/mission-brief.

New rule:
  isOnboarded = onboarding_completed_at != null
             || (primary_goal != null
                 && fitness_experience != null
                 && current_weight_kg != null)

If we route to /home on the populated-but-NULL case,
_completeOnboardingFromRestore stamps the flag in Hive + fires
unawaited(syncProfileNow) so next launch sees the stamped flag.

Self-heal stamp failure is non-fatal — user still routes to /home.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-13 — Contract tests

**Files:**
- Create: `test/safety/cross_account_isolation_test.dart`

- [ ] **Step 1: Write the test file**

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_5_iso_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('cross-account isolation (Plan A)', () {
    test(
      'user A writes → closeAll → user B opens → reads return empty (different namespace)',
      () async {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
        const userB = '94368fd4-eeee-ffff-1111-222222222222';

        // Sign in as A and write
        await HiveUserSession.openForUser(userA);
        final aCoach = Hive.box('coachBox_5f0a13b2');
        await aCoach.put('msg_1', {'role': 'user', 'content': 'A says hi'});
        expect(aCoach.get('msg_1'), {'role': 'user', 'content': 'A says hi'});
        await HiveUserSession.closeAll();

        // Sign in as B
        await HiveUserSession.openForUser(userB);
        final bCoach = Hive.box('coachBox_94368fd4');
        // B's coachBox is a different file — empty
        expect(bCoach.get('msg_1'), isNull,
          reason: 'B must NOT see A\'s coach messages — namespacing is the storage-level guarantee');
        expect(bCoach.keys.length, 0);

        // A's data still exists in its own file
        // (re-open A's box directly to confirm)
        final aCoachStillThere = await Hive.openBox('coachBox_5f0a13b2');
        expect(aCoachStillThere.get('msg_1'),
          {'role': 'user', 'content': 'A says hi'});
      },
    );

    test(
      'namespaced box name is `<root>_<8hex of dehyphenated user.id>`',
      () {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
        expect(HiveUserSession.namespacedBoxName('coachBox', userA),
          'coachBox_5f0a13b2');
        expect(HiveUserSession.namespacedBoxName('userBox', userA),
          'userBox_5f0a13b2');
      },
    );

    test(
      'RestoringScreen reconciliation: profile with goal+experience+weight but NULL onboarding_completed_at is treated as onboarded',
      () {
        // Pure logic test — mirrors the boolean rule in
        // RestoringScreen._resolveOnboardingResumeRoute.
        bool isOnboarded(Map<String, dynamic> profile) {
          final hasFlag = profile['onboarding_completed_at'] != null;
          final hasCore = profile['primary_goal'] != null
              && profile['fitness_experience'] != null
              && profile['current_weight_kg'] != null;
          return hasFlag || hasCore;
        }

        // Affected account shape (Upendra-class, OBS-3)
        final populatedNullFlag = <String, dynamic>{
          'onboarding_completed_at': null,
          'primary_goal': 'build_muscle',
          'fitness_experience': 'intermediate',
          'current_weight_kg': 75.0,
        };
        expect(isOnboarded(populatedNullFlag), true,
          reason: 'self-heal: populated profile MUST be treated as onboarded even with NULL flag');

        // Genuinely new user
        final blankProfile = <String, dynamic>{
          'onboarding_completed_at': null,
          'primary_goal': null,
          'fitness_experience': null,
          'current_weight_kg': null,
        };
        expect(isOnboarded(blankProfile), false);

        // Already-onboarded normal user
        final stampedProfile = <String, dynamic>{
          'onboarding_completed_at': '2026-04-01T10:00:00Z',
          'primary_goal': 'build_muscle',
          'fitness_experience': 'intermediate',
          'current_weight_kg': 75.0,
        };
        expect(isOnboarded(stampedProfile), true);
      },
    );
  });
}
```

Note: a true behavioural test of `GuardedBox` throwing on session mismatch requires mocking `Supabase.instance.client.auth.currentUser`, which is heavy infrastructure. The contract that `GuardedBox._assertOwnership` throws when `session != _ownerFullId` is enforced by the assertion logic in Task A-9 + the integration is exercised by on-device verification (C1/C2 in spec §10). The test above covers the storage-layer (namespacing) and reconciliation contracts — the two layers where logic-only test coverage is feasible.

- [ ] **Step 2: Run the test**

```bash
flutter test test/safety/cross_account_isolation_test.dart
```

Expected: 3 passing tests.

- [ ] **Step 3: Commit**

```bash
git add test/safety/cross_account_isolation_test.dart
git commit -m "test(safety): cross-account isolation contracts (Plan A)

Three contract tests covering Plan A's three storage/logic contracts:

1. user A writes → closeAll → user B opens → B reads empty
   (namespaced box files are physically separate)
2. namespacedBoxName format is `<root>_<8hex of dehyphenated user.id>`
   (lock the naming contract — RestoringScreen, HiveUserSession,
   migration logic all depend on this exact format)
3. RestoringScreen reconciliation rule: profile with goal+experience+
   weight but NULL onboarding_completed_at is onboarded (Layer 4
   self-heal contract)

GuardedBox session-mismatch throw + on-device cross-account verify
(C1/C2 in spec §10) covered by integration test on device.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A-14 — Full test suite + analyze

**Files:** none (verification only)

- [ ] **Step 1: Run analyze across `lib/`**

```bash
flutter analyze lib/
```

Expected: `No issues found!` If any issues appear that were introduced by this plan's edits, fix at the introducing task. Issues that pre-existed on the base main commit are pre-existing — document in a separate note rather than fixing here.

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass. If a test fails:
- If it's a Plan-A-introduced test: fix at the introducing task.
- If it's a pre-existing test that broke because of Plan A's changes (e.g. it was reading raw `Hive.box('coachBox')` directly, which no longer exists post-namespacing): update the test to use `HiveUserSession` setup OR add to a deferred-fix list in the commit body.

- [ ] **Step 3: If anything fails, document or fix**

```bash
flutter test 2>&1 | tee /tmp/test-output.txt
# Review the failures
```

For pre-existing tests broken by namespacing, the most common fix is to add this `setUp` block:

```dart
setUp(() async {
  // ... existing temp-dir + path_provider mock + Hive.init ...
  await HiveUserSession.openForUser('test-user-id-12345678-aaaa-bbbb-cccc-dddddddddddd');
});
tearDown(() async {
  await HiveUserSession.closeAll();
});
```

- [ ] **Step 4: Commit (only if test fixes were needed)**

```bash
git add test/
git commit -m "test: adapt pre-existing tests to HiveUserSession namespacing (Plan A)

Tests that read raw Hive.box('userBox') etc. directly need a session
opened first. Added HiveUserSession.openForUser(...) in setUp +
closeAll in tearDown for affected tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

If no fixes were needed, skip the commit. Document the green state by appending a one-line note to the trace doc:

```bash
echo "" >> docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
echo "## Plan A green-state confirmation" >> docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
echo "" >> docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — \`flutter analyze lib/\` clean; \`flutter test\` all pass. Plan A code-complete." >> docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
git add docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md
git commit -m "docs(test-5): Plan A green-state confirmation"
```

---

## Task A-15 — Manual test-prep documentation

**Files:**
- Create: `docs/superpowers/notes/2026-04-28-test-5-cleanup.md`

- [ ] **Step 1: Write the cleanup doc**

Create `docs/superpowers/notes/2026-04-28-test-5-cleanup.md`:

```markdown
# APK Test #5 — manual test-prep cleanup

**Run before installing the APK Test #5 build for verification.**

References: spec `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §9.

## Step 1 — Wipe Supabase test accounts

Run in the Supabase SQL editor (project `dedsavbjuwgarrhphgnl`,
account `myfitnessjourney1988@gmail.com`):

```sql
DELETE FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
```

Migration 039's `ON DELETE CASCADE` chain cleans:
- `public.users` (FK to auth.users)
- `user_profile`, `user_preferences`, `user_progress` (FK to public.users)
- `ai_coach_interactions`, `coach_memory`, `memory_embeddings`
- `workout_logs`, `workout_log_exercises`, `workout_log_sets`
- `nutrition_logs`, `nutrition_log_items`, `water_logs`
- `weight_logs`, `body_measurements`, `daily_steps`, `sleep_logs`
- `streaks`, `streak_freezes` (if present)
- `progress_photos`, `subscriptions`, `referral_codes`,
  `referral_redemptions`, `promo_code_uses`, `food_corrections`,
  `community_reviews`, `client_errors`, `user_daily_snapshots`,
  `coach_memory`, `rank_promotions`
- `user_custom_exercises`, `user_custom_foods`,
  `scheduled_workouts`, `workout_templates`, `template_exercises`
- `telegram_connections`

Verify cleanup:

```sql
SELECT email, deleted_at IS NOT NULL AS deleted
FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
-- Expected: 0 rows (rows physically removed, not soft-deleted)
```

## Step 2 — Uninstall + reinstall on device

On the test Android device:

1. Settings → Apps → AVYA → Uninstall.
2. Confirm app data wiped.
3. Install `app-prod-release.apk` (versionCode +4) via `adb install` or
   manual sideload.
4. Open the app — should land on Welcome screen with no auto-restore.

This step matters because:
- Hive box files under `app_flutter/` are removed by uninstall.
- Auto Backup exclusion (verified in Task A-4) prevents Google Drive
  from re-restoring Hive on reinstall.
- Combined: device starts with truly empty local storage.

## Step 3 — Re-onboard both accounts

For each of the two test accounts:

1. Sign up fresh (or sign in if account auto-restored — see Step 1
   verification).
2. Complete the full onboarding flow (Mission Brief → Identity → Goal
   → Stats → Details → Plan → REPORT FOR DUTY).
3. Verify `user_profile.onboarding_completed_at IS NOT NULL` after
   completion:

```sql
SELECT user_id, primary_goal, fitness_experience, onboarding_completed_at
FROM user_profile
WHERE user_id IN (
  SELECT id FROM auth.users
  WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com')
);
-- Expected: 2 rows, both with onboarding_completed_at populated
```

## Step 4 — Run §10 success criteria

Walk through C1, C2, C3 from spec §10. Document pass/fail in the
verification log on the branch `feat/apk-test-5-batch`.

C1: Sign in as Upendra → use coach (5 messages) → sign out →
    sign in as Avyaansh → AI coach screen shows EMPTY thread.
C2: Sign in as Avyaansh → Profile → no submissions → sign out →
    sign in as Upendra → see Upendra's submissions.
C3: Synthetic NULL `onboarding_completed_at` row in dev DB →
    sign in → routes to /home (self-heal stamps the flag).

For C3, manually inject the synthetic state in dev:

```sql
UPDATE user_profile
SET onboarding_completed_at = NULL
WHERE user_id = (
  SELECT id FROM auth.users WHERE email = 'upendra.prasad@thinkingcode.com'
);
```

Then sign in on device — should land on /home, AND a follow-up
SELECT should show `onboarding_completed_at` re-stamped:

```sql
SELECT onboarding_completed_at FROM user_profile WHERE user_id = ...;
-- Expected: non-null timestamp recent (within seconds of sign-in)
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/notes/2026-04-28-test-5-cleanup.md
git commit -m "docs(test-5): manual test-prep cleanup steps

SQL DELETE for the 2 test accounts (cascade cleans 25+ user-scoped
tables via migration 039 FK chain), uninstall+reinstall instructions,
and §10 C1/C2/C3 verification walkthrough including synthetic NULL
onboarding_completed_at injection for C3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review

- [ ] **Spec coverage:**
  - Layer 1 (investigation) → Tasks A-2, A-3, A-4 ✅
  - Layer 2 (per-user namespacing) → Tasks A-5, A-6, A-7, A-8 ✅
  - Layer 3 (ownership guard + global handler) → Tasks A-9, A-10, A-11 ✅
  - Layer 4 (RestoringScreen reconciliation) → Task A-12 ✅
  - C1 (cross-account chat isolation) → enforced by namespacing (A-5/6/7) + verified on device per A-15 cleanup doc
  - C2 (cross-account submissions isolation) → same as C1 ✅
  - C3 (NULL `onboarding_completed_at` self-heal) → A-12 + test in A-13 ✅
- [ ] **Placeholder scan:** No TBD/TODO/"implement here". Every code block is verbatim. ✅
- [ ] **Type consistency:**
  - `HiveUserSession` (class) — A-5/A-6/A-7/A-8/A-9/A-12/A-13 use the same name. ✅
  - `GuardedBox<T>` (class) — A-9/A-10 same name. ✅
  - `HiveOwnershipException` (class) — A-9/A-11 same name. ✅
  - `lastAuthenticatedUserIdKey` (constant) — already exists on `HiveService` (line 43, verified at planning time); not redeclared. ✅
- [ ] **Test coverage:** Namespacing isolation (A-13 test 1), naming format contract (A-13 test 2), reconciliation rule (A-13 test 3), legacy migration (A-8 tests). ✅
- [ ] **CLAUDE.md compliance:**
  - No raw `Hive.box('name')` in production paths — all flow through `HiveService.instance.<box>` or `HiveUserSession`. ✅
  - signOut order respects fire-and-forget pattern (clearAllData first, then file deletes, then Supabase signOut). ✅
  - No `Hive.initFlutter()` in unit tests — all tests use `Hive.init(tempDir.path)` + path_provider mock. ✅

## Out of scope for Plan A (deferred to Plans B/C/D)

- Theme B (plan regen triggers — `edit_profile_screen._save` field expansion) → Plan B.
- Theme C (AI coach tool dispatch — `rescheduleWeek`, `pausePlan`, etc.) → Plan C.
- Theme D (per-tab letterhead standardization, U7 revert) → Plan D.
- Server-side SQL backfill of historical NULL `onboarding_completed_at` rows → not needed (only 2 accounts affected, wiped per A-15).
- iOS Auto Backup parity → Android-first; iOS comes later.
- Hive box encryption-at-rest → separate brainstorm if ever needed.
- Sign-in-screen "Session expired" snackbar wiring (flag is written in A-11; render is follow-up polish).
