# sync_service.dart Part-File Split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `lib/core/services/sync_service.dart` (5,104 lines, single class, ~95 methods) into per-domain part files using Dart `part`/`part of` + extensions, with zero behavior change and zero public-API change.

**Architecture:** `sync_service.dart` keeps the `SyncService` class declaration, singleton, instance fields, static helpers, and cross-domain orchestrators. Domain-specific instance methods move to part files in `lib/core/services/sync/sync_<domain>.dart`. Each part file declares `part of '../sync_service.dart';` and wraps its methods in `extension SyncService<Domain> on SyncService { ... }`. Extensions in the same library can access library-private members (`_hive`, `_supabase`, `_realtimeSubscription`, etc.), so no state or visibility changes are needed.

**Tech Stack:** Dart 3.x + Flutter, supabase_flutter, Hive, Riverpod (state only, not touched).

**Spec:** `docs/superpowers/specs/2026-05-13-sync-service-part-split-design.md`

**Branch:** `refactor/sync-service-part-split` (off `main` tip after `e541d95`).

**Worktree:** `C:/Upendra/Claude Code/Fitness App/.claude/worktrees/confident-cartwright-5a65bd` (current working directory).

---

## Key mechanical contract (read first)

**Why extensions, not class-body splits:** Dart `part`/`part of` does NOT allow splitting a single class body across files. Each part file must contain top-level declarations. The clean pattern is `extension SyncService<Domain> on SyncService { ... }` in each part file. Inside the same library, extension methods can access library-private (`_underscore`) fields and methods of `SyncService`.

**What stays in `sync_service.dart`:**
- Top-level `_coerceInt` function (library-private, used by multiple parts).
- `RestoreResult` class.
- `class SyncService` declaration with constructor, singleton (`_instance`, `instance`), ALL instance fields (`_hive`, `_supabase`, `_restoreCancelled`, `_queueInitialized`, `_realtimeSubscription`, `_healthSyncCompleter`, `_restoreCompleteController`).
- All `static` helpers (`_deterministicId`, `_looksLikeUuid`, `_nlogKeyForRestore`, `_customEntityId`, `_currentPlatform`, `_currentClientVersion`, `_hasValue`, `_hasNumber`, `_uuidGen`, `_syncNamespace`, `_customEntityNamespace`, `_lastSnapshotKey`, `_lastFullSyncKey`, `_lastCustomSyncKey`, `_fullSyncInterval`).
- `cancelInflightRestore()` (tiny, on the class).
- `onRestoreComplete` getter + `healthSyncDone` getter (tiny, on the class).
- Cross-domain orchestrators: `checkAndSync`, `pushSnapshot`, `weeklyFullSync`, `restoreFromCloud`, `restoreFromCloudForUser`, `restoreLightweightAlways`, `_restoreIfNeeded`, `_replayPendingOnboardingSync`, `_syncFitnessSummary`, `pullRecentCrossChannelLogs`, `_pullWeightLogs`, `_pullNutritionLogs`, `_pullMeasurements`.
- All `part 'sync/sync_<domain>.dart';` directives.

**What moves to part files:** All other instance methods (`_syncXxx`, `_restoreXxx`, public `syncXxxNow`, `syncFreezes`, etc.) grouped by domain. Methods become extension methods on `SyncService`. Static helpers stay on the main class — DO NOT move statics into extensions (call sites would change from `SyncService._foo()` to `SyncServiceX._foo()`).

**Verifying after each commit:**
```bash
flutter analyze              # expect: 0 errors, 0 warnings
flutter test                 # expect: 1707/0/2 (was 1706/0/2 before commit 0)
```
If either fails: revert the commit, investigate, do not proceed.

**No `--no-verify` shortcuts.** Pre-commit hook runs the same `analyze` + `test` gate.

---

## Task 1: Commit 0 — Create branch, add API snapshot test, update existing contract tests for cross-file scanning

**Why this first:** Locks the public API surface in a test BEFORE any extraction. Updates the two existing contract tests so they scan `sync_service.dart` + all files in `lib/core/services/sync/` — without this, the moment `syncWorkoutData` moves to `sync_workout.dart` (Task 9), `sync_fanout_contract_test.dart` will fail because it only reads `sync_service.dart`.

**Files:**
- Create: `test/contracts/sync_service_public_api_snapshot_test.dart`
- Modify: `test/contracts/sync_fanout_contract_test.dart` (broaden source scan)
- Modify: `test/contracts/restore_completeness_writes_test.dart` (broaden source scan)

- [ ] **Step 1.1: Create the branch off main tip and confirm baseline**

```bash
cd "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/confident-cartwright-5a65bd"
git checkout -b refactor/sync-service-part-split
flutter analyze
flutter test
```

Expected: `flutter analyze` exits 0 with no issues. `flutter test` shows `1706 passed, 0 failed, 2 skipped` (or whatever the current baseline is — record the exact number for comparison throughout).

- [ ] **Step 1.2: Write the API snapshot test (failing initially because the file doesn't exist yet)**

Create `test/contracts/sync_service_public_api_snapshot_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Locks the public API surface of `SyncService` during the part-file
/// refactor (refactor/sync-service-part-split, 2026-05-13).
///
/// Scans `lib/core/services/sync_service.dart` AND every file under
/// `lib/core/services/sync/` for `Future<...>` / `Stream<...>` / `void`
/// methods on either `class SyncService` or `extension X on SyncService`
/// that DO NOT start with an underscore. The sorted set of names must
/// exactly match `expectedPublicApi`.
///
/// If a method is renamed or accidentally privatised during the refactor,
/// this test fails. If a new public method is added (e.g. by a parallel
/// bug-fix batch landing mid-refactor), update `expectedPublicApi` after
/// confirming the addition is intentional.
void main() {
  group('SyncService public API snapshot (refactor lock)', () {
    test('public method list is unchanged', () {
      const expectedPublicApi = <String>{
        'cancelInflightRestore',
        'checkAndSync',
        'drainTelemetryQueue',
        'initQueue',
        'pullRecentCrossChannelLogs',
        'pushSnapshot',
        'reportSyncFailure',
        'restoreFromCloud',
        'restoreFromCloudForUser',
        'restoreLightweightAlways',
        'subscribeToRealtimeSync',
        'syncCoachMemoryNow',
        'syncCommunityItems',
        'syncCustomItemsNow',
        'syncFreezes',
        'syncMeasurementsNow',
        'syncNotificationsInboxEntry',
        'syncNutritionData',
        'syncProfileNow',
        'syncProgressNow',
        'syncSavedDietPlan',
        'syncSavedMealsNow',
        'syncSleepNow',
        'syncWeightNow',
        'syncWorkoutData',
        'unsubscribeRealtime',
        'weeklyFullSync',
        // Getters that look like methods (counted as public API surface):
        'healthSyncDone',
        'onRestoreComplete',
      };

      final files = <File>[
        File('lib/core/services/sync_service.dart'),
        ...Directory('lib/core/services/sync')
            .let((dir) => dir.existsSync() ? dir.listSync() : <FileSystemEntity>[])
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      ];

      // Match instance method signatures: indent + (Future<...>|Stream<...>|void)
      // + space + name + ( ... ). Excludes static (no `static ` prefix) so
      // statics like `_deterministicId` aren't counted as instance API.
      // Also matches getters: `Stream<void> get onRestoreComplete`,
      // `Future<void> get healthSyncDone`.
      final methodPattern = RegExp(
        r'^\s+(?:Future<[^>]*>|Stream<[^>]*>|void)\s+(?:get\s+)?([a-zA-Z]\w*)\s*[\(\=]',
        multiLine: true,
      );

      final found = <String>{};
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final m in methodPattern.allMatches(src)) {
          final name = m.group(1)!;
          if (name.startsWith('_')) continue;
          // Skip helper methods that aren't on SyncService (e.g. the
          // `methodBody` helper inside test files won't be scanned, but
          // ANY top-level free function in sync part files would be —
          // we don't have any, so this regex is sufficient).
          found.add(name);
        }
      }

      expect(found, equals(expectedPublicApi),
          reason:
              'SyncService public API surface changed. If this is '
              'intentional (new public method added), update '
              'expectedPublicApi in this test after confirming the '
              'change is reviewed. If this is unintentional (method '
              'accidentally renamed/privatised during refactor), '
              'revert the rename.');
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
```

- [ ] **Step 1.3: Run the new test — expect PASS (sync directory doesn't exist yet, scans only the root file, finds exact set)**

```bash
flutter test test/contracts/sync_service_public_api_snapshot_test.dart
```

Expected: PASS. If FAIL with "expected set ... got ...", inspect the diff and either: (a) add the missing/extra method to `expectedPublicApi` if the difference is correct, or (b) check that the regex catches the method shape correctly.

- [ ] **Step 1.4: Update `sync_fanout_contract_test.dart` to scan across `sync_service.dart` AND `lib/core/services/sync/*.dart`**

Open `test/contracts/sync_fanout_contract_test.dart` and replace the `setUpAll` block at lines 18-23 with:

```dart
  setUpAll(() {
    final root = File('lib/core/services/sync_service.dart');
    expect(root.existsSync(), isTrue,
        reason: 'Run from project root');
    final partsDir = Directory('lib/core/services/sync');
    final parts = partsDir.existsSync()
        ? partsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
        : <File>[];
    syncServiceSrc = [
      root.readAsStringSync(),
      ...parts.map((f) => f.readAsStringSync()),
    ].join('\n\n');
  });
```

This concatenates `sync_service.dart` + all sync part files into a single string. The existing `methodBody` regex helper now finds methods regardless of which file they live in. No other change needed to the test.

- [ ] **Step 1.5: Update `restore_completeness_writes_test.dart` to scan across files too**

Open `test/contracts/restore_completeness_writes_test.dart`. The first test (lines 19-29) reads `sync_service.dart` directly. Replace lines 20-21 with:

```dart
      final rootSrc =
          File('lib/core/services/sync_service.dart').readAsStringSync();
      final partsDir = Directory('lib/core/services/sync');
      final partsSrc = partsDir.existsSync()
          ? partsDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map((f) => f.readAsStringSync())
              .join('\n\n')
          : '';
      final src = '$rootSrc\n\n$partsSrc';
```

Leave the three `expect(src.contains(...))` assertions unchanged.

- [ ] **Step 1.6: Run the full test suite to confirm zero regression**

```bash
flutter analyze
flutter test
```

Expected: `analyze` → 0/0. `test` → `1707 passed, 0 failed, 2 skipped` (one more than baseline because of the new snapshot test).

- [ ] **Step 1.7: Commit**

```bash
git add test/contracts/sync_service_public_api_snapshot_test.dart \
        test/contracts/sync_fanout_contract_test.dart \
        test/contracts/restore_completeness_writes_test.dart
git commit -m "$(cat <<'EOF'
refactor(sync): commit 0 — lock public API + broaden contract test scans

Adds test/contracts/sync_service_public_api_snapshot_test.dart locking
the 28-method public surface of SyncService (instance methods +
getters) by sorted set equality.

Updates sync_fanout_contract_test.dart + restore_completeness_writes_test.dart
to scan lib/core/services/sync_service.dart AND every file under
lib/core/services/sync/. Without this, every contract test that
reads sync_service.dart directly will fail the moment a method
moves to a part file in commits 1-10 of this refactor.

Pre-extraction baseline lock for refactor/sync-service-part-split.
See docs/superpowers/specs/2026-05-13-sync-service-part-split-design.md.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Commit 1 — Pilot: Extract `sync_restore_completeness.dart` (smallest, most isolated)

**Why this domain first:** Smallest of all (~280 lines, 7 methods), pinned by a dedicated contract test, no shared mutable state with other domains. If the `part` + `extension` mechanism has any unforeseen issue with library-private access or analyzer behavior, we discover it here at low blast radius.

**Methods to extract** (line ranges approximate, verify in current file):
- `syncFreezes()` (around L4822)
- `syncNotificationsInboxEntry()` (around L4863)
- `syncSavedDietPlan()` (around L4904)
- `_restoreFreezes()` (around L4933)
- `_restoreNotificationsInbox()` (around L4990)
- `_restoreSavedDietPlan()` (around L5044)
- `_restoreRankPromotions()` (around L5072)

**Files:**
- Create: `lib/core/services/sync/sync_restore_completeness.dart`
- Modify: `lib/core/services/sync_service.dart` (remove the 7 methods + add `part` directive)

- [ ] **Step 2.1: Verify the current line ranges of the 7 target methods**

```bash
grep -n "Future<void> syncFreezes\|Future<void> syncNotificationsInboxEntry\|Future<void> syncSavedDietPlan\|Future<void> _restoreFreezes\|Future<void> _restoreNotificationsInbox\|Future<void> _restoreSavedDietPlan\|Future<void> _restoreRankPromotions" lib/core/services/sync_service.dart
```

Record the line number of each. Note the line number of the method ENDING brace by reading each method top-to-bottom or jumping to the next method's signature.

- [ ] **Step 2.2: Create the part file with extension**

Create `lib/core/services/sync/sync_restore_completeness.dart`. Contents skeleton — fill the body of each method by copy-pasting from `sync_service.dart`:

```dart
part of '../sync_service.dart';

/// APK Test #11 — Theme A push + restore for the 4 Hive-only surfaces
/// that previously vanished on reinstall: streak freezes, notifications
/// inbox, saved diet plan, rank promotions. See CLAUDE.md §15
/// "Restore-completeness sync" for the canonical contract.
extension SyncServiceRestoreCompleteness on SyncService {
  // ── PUSH (sync) ─────────────────────────────────────────────

  Future<void> syncFreezes() async {
    // ... paste exact body from sync_service.dart syncFreezes() ...
  }

  Future<void> syncNotificationsInboxEntry(Map<String, dynamic> entry) async {
    // ... paste exact body ...
  }

  Future<void> syncSavedDietPlan(Map<String, dynamic> planJson) async {
    // ... paste exact body ...
  }

  // ── PULL (restore) ──────────────────────────────────────────

  Future<void> _restoreFreezes(String userId) async {
    // ... paste exact body ...
  }

  Future<void> _restoreNotificationsInbox(String userId) async {
    // ... paste exact body ...
  }

  Future<void> _restoreSavedDietPlan(String userId) async {
    // ... paste exact body ...
  }

  Future<void> _restoreRankPromotions(String userId) async {
    // ... paste exact body ...
  }
}
```

The bodies are copy-pasted byte-for-byte. Imports are inherited from `sync_service.dart` — DO NOT add any `import` statements in the part file (Dart will reject them).

- [ ] **Step 2.3: Add the `part` directive to `sync_service.dart`**

Find the line immediately after the existing `import` block (around line 19, after `import 'package:icanbefitter/shared/repositories/user_repository.dart';`). Add:

```dart
part 'sync/sync_restore_completeness.dart';
```

- [ ] **Step 2.4: Remove the 7 methods from `sync_service.dart`**

Delete the exact line ranges for the 7 method bodies. Be careful with the leading method-level doc comments — they should move WITH the method if they describe the method, but NOT move if they describe a section (rare in this domain).

- [ ] **Step 2.5: Run analyze + test**

```bash
flutter analyze
flutter test
```

Expected: `analyze` → 0/0. `test` → 1707/0/2 unchanged. Specifically `sync_service_public_api_snapshot_test.dart`, `restore_completeness_writes_test.dart`, and `sync_fanout_contract_test.dart` should all PASS.

If `analyze` reports "method `_restoreFreezes` not defined" inside `restoreFromCloudForUser` (which calls it), the most likely cause is the `part` directive is missing or the extension wrapper is malformed. Re-check that:
- `sync_service.dart` has `part 'sync/sync_restore_completeness.dart';` near the top.
- `sync/sync_restore_completeness.dart` has `part of '../sync_service.dart';` as its first non-comment line.
- The extension block opens with `extension SyncServiceRestoreCompleteness on SyncService {` and closes correctly.

- [ ] **Step 2.6: Commit**

```bash
git add lib/core/services/sync/sync_restore_completeness.dart \
        lib/core/services/sync_service.dart
git commit -m "$(cat <<'EOF'
refactor(sync): extract restore-completeness to part file (1/10)

Pilots the part-file split mechanism. Moves 7 methods (syncFreezes,
syncNotificationsInboxEntry, syncSavedDietPlan, _restoreFreezes,
_restoreNotificationsInbox, _restoreSavedDietPlan,
_restoreRankPromotions) from sync_service.dart into a new
SyncServiceRestoreCompleteness extension in
lib/core/services/sync/sync_restore_completeness.dart.

Library-private state on SyncService remains accessible via Dart's
part/part-of same-library semantics. Zero behavior change. Public API
snapshot test (commit 0) + restore_completeness_writes_test +
sync_fanout_contract_test all green.

LOC: sync_service.dart 5104 → 4824 (-280).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Commit 2 — Extract `sync_realtime.dart`

**Methods to extract:**
- `subscribeToRealtimeSync()` (around L1211)
- `_attachRealtimeStream()` (around L1238)
- `_reconnectRealtimeWithRefreshedJwt()` (around L1294)
- `unsubscribeRealtime()` (around L1315)

**Library-private field consumed:** `_realtimeSubscription` (stays on `SyncService` class declaration in main file).

**Files:**
- Create: `lib/core/services/sync/sync_realtime.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 3.1: Verify line ranges**

```bash
grep -n "Future<void> subscribeToRealtimeSync\|void _attachRealtimeStream\|Future<void> _reconnectRealtimeWithRefreshedJwt\|void unsubscribeRealtime" lib/core/services/sync_service.dart
```

- [ ] **Step 3.2: Create part file**

Create `lib/core/services/sync/sync_realtime.dart`:

```dart
part of '../sync_service.dart';

/// Realtime cross-channel sync (PRO Telegram bot relay).
/// Manages Supabase realtime subscription lifecycle for the active user.
extension SyncServiceRealtime on SyncService {
  Future<void> subscribeToRealtimeSync() async {
    // ... paste exact body ...
  }

  void _attachRealtimeStream(String userId, {required int attempt}) {
    // ... paste exact body ...
  }

  Future<void> _reconnectRealtimeWithRefreshedJwt(
    // ... paste signature + body ...
  ) async {
    // ...
  }

  void unsubscribeRealtime() {
    // ... paste exact body ...
  }
}
```

- [ ] **Step 3.3: Add `part 'sync/sync_realtime.dart';` to `sync_service.dart` (right after the previous part directive)**

- [ ] **Step 3.4: Remove the 4 methods from `sync_service.dart`**

- [ ] **Step 3.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 3.6: Commit**

```bash
git add lib/core/services/sync/sync_realtime.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract realtime to part file (2/10)

Moves 4 methods (subscribeToRealtimeSync, _attachRealtimeStream,
_reconnectRealtimeWithRefreshedJwt, unsubscribeRealtime) into
SyncServiceRealtime extension. Validates that part files can mutate
library-private stateful fields (_realtimeSubscription stays on the
SyncService class declaration in the root file).

LOC: sync_service.dart 4824 → 4674 (-150).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Commit 3 — Extract `sync_coach.dart`

**Methods to extract:**
- `syncCoachMemoryNow()` (around L2463)
- `_syncCoachInteractions()` (around L4665)
- `_restoreCoachInteractions()` (around L4708)
- `_restoreCoachMemory()` (around L4764)

**Files:**
- Create: `lib/core/services/sync/sync_coach.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 4.1: Verify line ranges**

```bash
grep -n "Future<void> syncCoachMemoryNow\|Future<void> _syncCoachInteractions\|Future<void> _restoreCoachInteractions\|Future<void> _restoreCoachMemory" lib/core/services/sync_service.dart
```

- [ ] **Step 4.2: Create `lib/core/services/sync/sync_coach.dart`**

```dart
part of '../sync_service.dart';

/// Sync + restore for AI coach interactions and coach memory
/// (coaching_notes, daily summaries). See CLAUDE.md §11.
extension SyncServiceCoach on SyncService {
  Future<void> syncCoachMemoryNow(String userId) async {
    // ... paste body ...
  }

  Future<void> _syncCoachInteractions(String userId) async {
    // ... paste body ...
  }

  Future<void> _restoreCoachInteractions(String userId, String since) async {
    // ... paste body ...
  }

  Future<void> _restoreCoachMemory(String userId) async {
    // ... paste body ...
  }
}
```

- [ ] **Step 4.3: Add `part 'sync/sync_coach.dart';` to `sync_service.dart`**

- [ ] **Step 4.4: Remove the 4 methods**

- [ ] **Step 4.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 4.6: Commit**

```bash
git add lib/core/services/sync/sync_coach.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract coach to part file (3/10)

Moves 4 methods (syncCoachMemoryNow, _syncCoachInteractions,
_restoreCoachInteractions, _restoreCoachMemory) into
SyncServiceCoach extension.

LOC: sync_service.dart 4674 → 4274 (-400).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Commit 4 — Extract `sync_community.dart`

**Methods to extract:**
- `_backfillCustomEntityIds()` (around L199) — even though it's near the top, it's a custom-entity helper that belongs with community sync.
- `_syncCustomItems()` (around L2515)
- `syncCustomItemsNow()` (around L2456) — one-line delegator to `_syncCustomItems`.
- `syncCommunityItems()` (around L3681)
- `_restoreCustomExercises()` (around L2996)
- `_restoreCustomFoods()` (around L3053)

**DO NOT move:** `_customEntityId` (static — stays in `sync_service.dart`).

**Files:**
- Create: `lib/core/services/sync/sync_community.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 5.1: Verify line ranges**

```bash
grep -n "Future<void> _backfillCustomEntityIds\|Future<void> _syncCustomItems\|Future<void> syncCustomItemsNow\|Future<void> syncCommunityItems\|Future<void> _restoreCustomExercises\|Future<void> _restoreCustomFoods" lib/core/services/sync_service.dart
```

- [ ] **Step 5.2: Create `lib/core/services/sync/sync_community.dart`**

```dart
part of '../sync_service.dart';

/// Community sync — user-contributed custom exercises and foods.
/// Sync direction: local custom items pushed to cloud immediately;
/// approved community items pulled periodically to user's Hive.
extension SyncServiceCommunity on SyncService {
  Future<void> _backfillCustomEntityIds() async {
    // ... paste body ...
  }

  Future<void> syncCustomItemsNow() => _syncCustomItems();

  Future<void> _syncCustomItems() async {
    // ... paste body ...
  }

  Future<void> syncCommunityItems() async {
    // ... paste body ...
  }

  Future<void> _restoreCustomExercises(String userId) async {
    // ... paste body ...
  }

  Future<void> _restoreCustomFoods(String userId) async {
    // ... paste body ...
  }
}
```

- [ ] **Step 5.3: Add `part 'sync/sync_community.dart';` to `sync_service.dart`**

- [ ] **Step 5.4: Remove the 6 methods from `sync_service.dart`**

- [ ] **Step 5.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 5.6: Commit**

```bash
git add lib/core/services/sync/sync_community.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract community to part file (4/10)

Moves 6 methods (_backfillCustomEntityIds, _syncCustomItems,
syncCustomItemsNow, syncCommunityItems, _restoreCustomExercises,
_restoreCustomFoods) into SyncServiceCommunity extension.
Static _customEntityId helper stays on the SyncService class.

LOC: sync_service.dart 4274 → 3774 (-500).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Commit 5 — Extract `sync_health.dart`

**Methods to extract:**
- `syncWeightNow()` (around L1808)
- `syncSleepNow()` (around L1828)
- `syncMeasurementsNow()` (around L1881)
- `_syncWeightLogs()` (around L1897)
- `_syncMeasurements()` (around L1927)
- `_syncSleepLogs()` (around L1959)
- `_syncStepsLogs()` (around L1992)
- `_syncUrineColorLogs()` (around L2025)
- `_restoreWeightLogs()` (around L3100)
- `_restoreMeasurements()` (around L3214)
- `_restoreSleepLogs()` (around L3396)
- `_restoreStepsLogs()` (around L3430)

**Files:**
- Create: `lib/core/services/sync/sync_health.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 6.1: Verify line ranges**

```bash
grep -n "Future<void> syncWeightNow\|Future<void> syncSleepNow\|Future<void> syncMeasurementsNow\|Future<void> _syncWeightLogs\|Future<void> _syncMeasurements\|Future<void> _syncSleepLogs\|Future<void> _syncStepsLogs\|Future<void> _syncUrineColorLogs\|Future<void> _restoreWeightLogs\|Future<void> _restoreMeasurements\|Future<void> _restoreSleepLogs\|Future<void> _restoreStepsLogs" lib/core/services/sync_service.dart
```

- [ ] **Step 6.2: Create `lib/core/services/sync/sync_health.dart`**

```dart
part of '../sync_service.dart';

/// Sync + restore for health-domain Hive surfaces: weight, body
/// measurements, sleep, steps, urine color.
extension SyncServiceHealth on SyncService {
  // ── Public entry points (called from biometric provider) ────

  Future<void> syncWeightNow() async {
    // ... paste body ...
  }

  Future<void> syncSleepNow() async {
    // ... paste body ...
  }

  Future<void> syncMeasurementsNow() async {
    // ... paste body ...
  }

  // ── Push helpers ────────────────────────────────────────────

  Future<void> _syncWeightLogs(String userId) async { /* ... */ }
  Future<void> _syncMeasurements(String userId) async { /* ... */ }
  Future<void> _syncSleepLogs(String userId) async { /* ... */ }
  Future<void> _syncStepsLogs(String userId) async { /* ... */ }
  Future<void> _syncUrineColorLogs(String userId) async { /* ... */ }

  // ── Pull helpers ────────────────────────────────────────────

  Future<void> _restoreWeightLogs(String userId, String since) async { /* ... */ }
  Future<void> _restoreMeasurements(String userId, String since) async { /* ... */ }
  Future<void> _restoreSleepLogs(String userId, String since) async { /* ... */ }
  Future<void> _restoreStepsLogs(String userId, String since) async { /* ... */ }
}
```

Each `/* ... */` is replaced with the exact body from `sync_service.dart`.

- [ ] **Step 6.3: Add `part 'sync/sync_health.dart';` to `sync_service.dart`**

- [ ] **Step 6.4: Remove the 12 methods**

- [ ] **Step 6.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 6.6: Commit**

```bash
git add lib/core/services/sync/sync_health.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract health to part file (5/10)

Moves 12 methods (weight, measurements, sleep, steps, urine — both
push and pull) into SyncServiceHealth extension.

LOC: sync_service.dart 3774 → 3274 (-500).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Commit 6 — Extract `sync_profile.dart`

**Methods to extract:**
- `syncProfileNow()` (around L2139)
- `_syncUserProfile()` (around L2335)
- `_syncUserPreferences()` (around L4588)
- `_syncUserProgress()` (around L3572)
- `syncProgressNow()` (around L2319)
- `_restoreUserProfile()` (around L3242)
- `_restoreUserProgress()` (around L3314)
- `_restoreUserPreferences()` (around L4613)

**Files:**
- Create: `lib/core/services/sync/sync_profile.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 7.1: Verify line ranges**

```bash
grep -n "Future<void> syncProfileNow\|Future<void> _syncUserProfile\|Future<void> _syncUserPreferences\|Future<void> _syncUserProgress\|Future<void> syncProgressNow\|Future<void> _restoreUserProfile\|Future<void> _restoreUserProgress\|Future<void> _restoreUserPreferences" lib/core/services/sync_service.dart
```

- [ ] **Step 7.2: Create `lib/core/services/sync/sync_profile.dart`**

```dart
part of '../sync_service.dart';

/// Sync + restore for user-identity surfaces: user_profile,
/// user_preferences, user_progress.
extension SyncServiceProfile on SyncService {
  Future<void> syncProfileNow(String userId) async { /* ... */ }
  Future<void> syncProgressNow() async { /* ... */ }
  Future<void> _syncUserProfile(String userId) async { /* ... */ }
  Future<void> _syncUserPreferences(String userId) async { /* ... */ }
  Future<void> _syncUserProgress(String userId) async { /* ... */ }
  Future<void> _restoreUserProfile(String userId) async { /* ... */ }
  Future<void> _restoreUserProgress(String userId) async { /* ... */ }
  Future<void> _restoreUserPreferences(String userId) async { /* ... */ }
}
```

- [ ] **Step 7.3: Add `part 'sync/sync_profile.dart';` to `sync_service.dart`**

- [ ] **Step 7.4: Remove the 8 methods**

- [ ] **Step 7.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2. Note: `_restoreUserProfile` uses `_hasValue` / `_hasNumber` static helpers — those stay on the main class and remain accessible (`SyncService._hasValue(...)` or just `_hasValue(...)` inside an instance method scope works because static calls within the class are unambiguous; from an extension, prefer `SyncService._hasValue(...)`). If analyze fails with "_hasValue not defined," prefix the calls with `SyncService.`.

- [ ] **Step 7.6: Commit**

```bash
git add lib/core/services/sync/sync_profile.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract profile + prefs + progress to part file (6/10)

Moves 8 methods (syncProfileNow, syncProgressNow, _syncUserProfile,
_syncUserPreferences, _syncUserProgress, _restoreUserProfile,
_restoreUserProgress, _restoreUserPreferences) into
SyncServiceProfile extension.

LOC: sync_service.dart 3274 → 2874 (-400).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Commit 7 — Extract `sync_nutrition.dart`

**Methods to extract:**
- `_syncNutritionLogs()` (around L1692)
- `_syncWaterLogs()` (around L2056)
- `_syncSavedMeals()` (around L4498)
- `syncSavedMealsNow()` (around L2301)
- `syncNutritionData()` (around L678)
- `_restoreNutritionLogs()` (around L3131)
- `_restoreWaterLogs()` (around L3350)
- `_restoreSavedMeals()` (around L4536)

**DO NOT move:** `_nlogKeyForRestore` (static — stays on `SyncService` in main file).

**Files:**
- Create: `lib/core/services/sync/sync_nutrition.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 8.1: Verify line ranges**

```bash
grep -n "Future<void> _syncNutritionLogs\|Future<void> _syncWaterLogs\|Future<void> _syncSavedMeals\|Future<void> syncSavedMealsNow\|Future<void> syncNutritionData\|Future<void> _restoreNutritionLogs\|Future<void> _restoreWaterLogs\|Future<void> _restoreSavedMeals" lib/core/services/sync_service.dart
```

- [ ] **Step 8.2: Create `lib/core/services/sync/sync_nutrition.dart`**

```dart
part of '../sync_service.dart';

/// Sync + restore for nutrition domain: nutrition_logs (+ items),
/// water_logs, user_saved_meals.
///
/// `syncNutritionData()` is the SoT fan-out entry point pinned by
/// `test/contracts/sync_fanout_contract_test.dart` — its body must
/// continue to call `_syncNutritionLogs`, `_syncWaterLogs`,
/// `_syncSavedMeals`.
extension SyncServiceNutrition on SyncService {
  Future<void> syncNutritionData() async { /* ... */ }
  Future<void> syncSavedMealsNow() async { /* ... */ }
  Future<void> _syncNutritionLogs(String userId) async { /* ... */ }
  Future<void> _syncWaterLogs(String userId) async { /* ... */ }
  Future<void> _syncSavedMeals(String userId) async { /* ... */ }
  Future<void> _restoreNutritionLogs(String userId, String since) async { /* ... */ }
  Future<void> _restoreWaterLogs(String userId, String since) async { /* ... */ }
  Future<void> _restoreSavedMeals(String userId) async { /* ... */ }
}
```

- [ ] **Step 8.3: Add `part 'sync/sync_nutrition.dart';` to `sync_service.dart`**

- [ ] **Step 8.4: Remove the 8 methods**

- [ ] **Step 8.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2. Specifically verify `sync_fanout_contract_test.dart` still passes — its broadened scan from Task 1 should locate `syncNutritionData` in the new part file.

- [ ] **Step 8.6: Commit**

```bash
git add lib/core/services/sync/sync_nutrition.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract nutrition to part file (7/10)

Moves 8 methods (syncNutritionData, syncSavedMealsNow, plus per-prefix
push + pull helpers) into SyncServiceNutrition extension. Static
_nlogKeyForRestore helper stays on SyncService class.

LOC: sync_service.dart 2874 → 2274 (-600).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Commit 8 — Extract `sync_workout.dart` (BIGGEST)

**Methods to extract:**
- `syncWorkoutData()` (around L630)
- `_syncWorkoutLogs()` (around L1323)
- `_syncExerciseLogs()` (around L1387)
- `_resolveCompletedAt()` (around L1546)
- `_dateFromKey()` (around L1596)
- `_syncScheduleCompletions()` (around L1657)
- `_syncStreaks()` (around L2084)
- `_restoreWorkoutLogs()` (around L2762)
- `_restoreExerciseLogs()` (around L2805)
- `_restoreScheduleCompletions()` (around L2955)
- `_restoreStreaks()` (around L3468)
- `_syncWorkoutPlan()` (around L3527)
- `_restoreWorkoutPlan()` (around L3604)
- `_syncWorkoutTemplates()` (around L3762)
- `_restoreWorkoutTemplates()` (around L3943)
- `_syncScheduledWorkouts()` (around L4089)
- `_restoreScheduledWorkouts()` (around L4307)

Note: `_resolveCompletedAt` and `_dateFromKey` are workout-specific helpers; they move with the domain.

**Files:**
- Create: `lib/core/services/sync/sync_workout.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 9.1: Verify line ranges**

```bash
grep -n "Future<void> syncWorkoutData\|Future<void> _syncWorkoutLogs\|Future<void> _syncExerciseLogs\|String _resolveCompletedAt\|String? _dateFromKey\|Future<void> _syncScheduleCompletions\|Future<void> _syncStreaks\|Future<void> _restoreWorkoutLogs\|Future<void> _restoreExerciseLogs\|Future<void> _restoreScheduleCompletions\|Future<void> _restoreStreaks\|Future<void> _syncWorkoutPlan\|Future<void> _restoreWorkoutPlan\|Future<void> _syncWorkoutTemplates\|Future<void> _restoreWorkoutTemplates\|Future<void> _syncScheduledWorkouts\|Future<void> _restoreScheduledWorkouts" lib/core/services/sync_service.dart
```

- [ ] **Step 9.2: Create `lib/core/services/sync/sync_workout.dart`**

```dart
part of '../sync_service.dart';

/// Sync + restore for workout domain: workout_logs,
/// workout_log_exercises, workout_log_sets, scheduled_workouts,
/// workout_schedule_completions, workout_templates, streaks,
/// workout_plan.
///
/// `syncWorkoutData()` is the SoT fan-out entry point pinned by
/// `test/contracts/sync_fanout_contract_test.dart` — its body must
/// continue to call all 6 listed helpers.
extension SyncServiceWorkout on SyncService {
  Future<void> syncWorkoutData() async { /* ... */ }

  // ── Push helpers ────────────────────────────────────────────

  Future<void> _syncWorkoutLogs(String userId) async { /* ... */ }
  Future<void> _syncExerciseLogs(String userId) async { /* ... */ }
  Future<void> _syncScheduleCompletions(String userId) async { /* ... */ }
  Future<void> _syncStreaks(String userId) async { /* ... */ }
  Future<void> _syncWorkoutPlan(String userId) async { /* ... */ }
  Future<void> _syncWorkoutTemplates(String userId) async { /* ... */ }
  Future<void> _syncScheduledWorkouts(String userId) async { /* ... */ }

  // ── Pull helpers ────────────────────────────────────────────

  Future<void> _restoreWorkoutLogs(String userId, String since) async { /* ... */ }
  Future<void> _restoreExerciseLogs(String userId, String since) async { /* ... */ }
  Future<void> _restoreScheduleCompletions(String userId, String since) async { /* ... */ }
  Future<void> _restoreStreaks(String userId) async { /* ... */ }
  Future<void> _restoreWorkoutPlan(String userId) async { /* ... */ }
  Future<void> _restoreWorkoutTemplates(String userId) async { /* ... */ }
  Future<void> _restoreScheduledWorkouts(String userId, String since) async { /* ... */ }

  // ── Domain helpers ──────────────────────────────────────────

  String _resolveCompletedAt(/* ... */) { /* ... */ }
  String? _dateFromKey(String? key) { /* ... */ }
}
```

- [ ] **Step 9.3: Add `part 'sync/sync_workout.dart';` to `sync_service.dart`**

- [ ] **Step 9.4: Remove the 17 methods**

- [ ] **Step 9.5: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2. Special focus: `sync_fanout_contract_test.dart` is now the most-stressed test — it checks `syncWorkoutData`'s body contains 6 specific helper call strings. All 6 helpers AND `syncWorkoutData` are now in the same part file, so the broadened scan from Task 1 should locate them.

- [ ] **Step 9.6: Commit**

```bash
git add lib/core/services/sync/sync_workout.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract workout to part file (8/10)

Moves 17 methods (syncWorkoutData + 7 push helpers + 7 pull helpers
+ _resolveCompletedAt + _dateFromKey) into SyncServiceWorkout
extension. Biggest single extraction at ~1200 LOC.

LOC: sync_service.dart 2274 → 1074 (-1200).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Commit 9 — Extract `sync_infrastructure.dart`

**Methods to extract** (queue + telemetry + dead-letter + session + timestamps):
- `initQueue()` (around L284)
- `_executeUserProfileUpsert()` (around L299)
- `_sendDeadLetterTelemetry()` (around L317)
- `reportSyncFailure()` (around L2158)
- `_safeRestoreOp()` (around L2175)
- `_enqueueTelemetryFailure()` (around L2199)
- `drainTelemetryQueue()` (around L2225)
- `_reportSyncFailure()` (around L2255)
- `_setTimestamp()` (around L5101)
- `_getTimestamp()` (around L5095)
- `_ensureSessionOpen()` (around L89) — small instance method tied to HiveUserSession.

**DO NOT move:**
- `_currentPlatform()` + `_currentClientVersion()` (static — stay on main class).
- `cancelInflightRestore()` (5-line setter, stays inline on main class with the `_restoreCancelled` field for cohesion).

**Files:**
- Create: `lib/core/services/sync/sync_infrastructure.dart`
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 10.1: Verify line ranges**

```bash
grep -n "void initQueue\|Future<Result<void, SyncError>> _executeUserProfileUpsert\|Future<void> _sendDeadLetterTelemetry\|Future<void> reportSyncFailure\|Future<void> _safeRestoreOp\|Future<void> _enqueueTelemetryFailure\|Future<void> drainTelemetryQueue\|Future<void> _reportSyncFailure\|Future<void> _setTimestamp\|DateTime? _getTimestamp\|Future<String?> _ensureSessionOpen" lib/core/services/sync_service.dart
```

- [ ] **Step 10.2: Create `lib/core/services/sync/sync_infrastructure.dart`**

```dart
part of '../sync_service.dart';

/// Infrastructure for SyncService: pending-op queue, dead-letter
/// telemetry, session bootstrap, and last-sync-timestamp tracking.
extension SyncServiceInfrastructure on SyncService {
  Future<String?> _ensureSessionOpen() =>
      HiveUserSession.ensureOpenedForCurrentSession();

  void initQueue() { /* ... */ }

  Future<Result<void, SyncError>> _executeUserProfileUpsert(
    Map<String, dynamic> payload,
  ) async { /* ... */ }

  Future<void> _sendDeadLetterTelemetry(PendingSyncOp op) async { /* ... */ }

  Future<void> reportSyncFailure({ /* ... */ }) async { /* ... */ }

  Future<void> _safeRestoreOp(String label, Future<void> task) async { /* ... */ }

  Future<void> _enqueueTelemetryFailure(String opType, Object error) async { /* ... */ }

  Future<void> drainTelemetryQueue() async { /* ... */ }

  Future<void> _reportSyncFailure({ /* ... */ }) async { /* ... */ }

  Future<void> _setTimestamp(String key) async { /* ... */ }

  DateTime? _getTimestamp(String key) { /* ... */ }
}
```

- [ ] **Step 10.3: Remove the `_ensureSessionOpen` definition from `sync_service.dart` (lines around L89)**

Be careful: `_ensureSessionOpen` is referenced from MANY orchestrator methods that still live in `sync_service.dart` (`checkAndSync`, `pushSnapshot`, `weeklyFullSync`, `restoreFromCloudForUser`, etc.). After moving the method to the extension, callsites continue to work because they call `this._ensureSessionOpen()` which resolves via extension lookup.

- [ ] **Step 10.4: Add `part 'sync/sync_infrastructure.dart';` to `sync_service.dart`**

- [ ] **Step 10.5: Remove the 11 methods**

- [ ] **Step 10.6: Run gate**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 10.7: Commit**

```bash
git add lib/core/services/sync/sync_infrastructure.dart \
        lib/core/services/sync_service.dart
git commit -m "refactor(sync): extract infrastructure to part file (9/10)

Moves 11 methods (initQueue, _executeUserProfileUpsert,
_sendDeadLetterTelemetry, reportSyncFailure, _safeRestoreOp,
_enqueueTelemetryFailure, drainTelemetryQueue, _reportSyncFailure,
_setTimestamp, _getTimestamp, _ensureSessionOpen) into
SyncServiceInfrastructure extension. Statics (_currentPlatform,
_currentClientVersion) stay on SyncService class.

LOC: sync_service.dart 1074 → 474 (-600).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 11: Commit 10 — Final cleanup + CLAUDE.md update

**This commit:**
1. Verifies the final shape of `sync_service.dart` (~500-700 lines).
2. Updates CLAUDE.md §5 "Single-source-of-truth files" entry to mention the part-file structure.
3. Marks audit item B-5 closed in `docs/audit/2026-05-11/cleanup-batch-triage.md`.

**No new part file** is created in this commit. The "extract `sync_helpers.dart`" idea from the spec turned out unnecessary because all helpers are `static` — splitting statics into a part file changes their callsite (`SyncService._foo` → `SyncServiceHelpers._foo`), which would violate the no-API-change rule. Statics stay where they are.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/audit/2026-05-11/cleanup-batch-triage.md`
- Verify (no edit): `lib/core/services/sync_service.dart` is now ~474-700 lines.

- [ ] **Step 11.1: Verify final shape of sync_service.dart**

```bash
wc -l lib/core/services/sync_service.dart
ls -la lib/core/services/sync/
```

Expected:
- `sync_service.dart` between 400 and 700 lines.
- Nine files in `lib/core/services/sync/`: `sync_restore_completeness.dart`, `sync_realtime.dart`, `sync_coach.dart`, `sync_community.dart`, `sync_health.dart`, `sync_profile.dart`, `sync_nutrition.dart`, `sync_workout.dart`, `sync_infrastructure.dart`.

- [ ] **Step 11.2: Update CLAUDE.md §5 — find the bullet for `sync_service.dart`**

Search CLAUDE.md for the existing entry. Find: there is no explicit `sync_service.dart` entry in the "Single-source-of-truth files" list as of 2026-05-13, but several entries refer to it (e.g. "`SyncService.instance.syncWorkoutData()`"). Add a new bullet to the SoT files list under §5:

```markdown
- `lib/core/services/sync_service.dart` — `SyncService` singleton. Split into 9 part files under `lib/core/services/sync/` via Dart `part`/`part of` + extensions (refactor 2026-05-13, commit `<HEAD>`). Root file contains the class declaration, singleton, instance fields, static helpers, cross-domain orchestrators (`checkAndSync`, `pushSnapshot`, `weeklyFullSync`, `restoreFromCloud*`, `pullRecentCrossChannelLogs`). Domain parts: `sync_workout.dart`, `sync_nutrition.dart`, `sync_health.dart`, `sync_profile.dart`, `sync_community.dart`, `sync_coach.dart`, `sync_restore_completeness.dart`, `sync_realtime.dart`, `sync_infrastructure.dart`. Public API surface pinned by `test/contracts/sync_service_public_api_snapshot_test.dart`. Fan-out + restore-completeness contracts pinned by `sync_fanout_contract_test.dart` + `restore_completeness_writes_test.dart` (both updated to scan across the root file + all part files).
```

- [ ] **Step 11.3: Update `docs/audit/2026-05-11/cleanup-batch-triage.md`**

Find the section "B-5. `sync_service.dart` 4572-line file split" (around line 130). Add a status line at the top of that section:

```markdown
**Status:** CLOSED 2026-05-13 — split into 9 part files via `refactor/sync-service-part-split` branch, merged in commit `<MERGE-SHA>`. See `docs/superpowers/specs/2026-05-13-sync-service-part-split-design.md` + `docs/superpowers/plans/2026-05-13-sync-service-part-split-plan.md`.
```

- [ ] **Step 11.4: Run the full test suite one last time on the branch**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 11.5: Commit**

```bash
git add CLAUDE.md docs/audit/2026-05-11/cleanup-batch-triage.md
git commit -m "refactor(sync): finalize part-file split (10/10) + doc updates

Updates CLAUDE.md §5 to document the 9-part SyncService structure.
Marks docs/audit/2026-05-11/cleanup-batch-triage.md item B-5 as
CLOSED.

No code changes in this commit — final verification:
- sync_service.dart: $(wc -l < lib/core/services/sync_service.dart) lines
- 9 part files under lib/core/services/sync/
- 1707 tests pass (was 1706 + new api-snapshot test from commit 0)
- 0 analyze issues

Closes refactor/sync-service-part-split.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 12: Merge + APK ship cycle

**Files:** none (git + build commands only).

- [ ] **Step 12.1: Verify the branch is ready**

```bash
git log --oneline main..HEAD
```

Expected: 11 commits (commit 0 + 10 refactor commits). No fix:/bug:/regression: commits mixed in.

- [ ] **Step 12.2: Final analyze + test on the branch tip**

```bash
flutter analyze
flutter test
```

Expected: 0/0 + 1707/0/2.

- [ ] **Step 12.3: STOP and wait for founder approval before merging.**

Per CLAUDE.md global rules: "Never commit or push unless the user explicitly asks." The merge to `main` is a push-equivalent — wait for explicit "merge" or "ship" instruction from the founder.

When approved:

```bash
git checkout main
git pull
git merge --no-ff refactor/sync-service-part-split -m "Merge refactor: sync_service.dart part-file split

Splits the 5,104-line sync_service.dart into 9 per-domain part files
under lib/core/services/sync/ using Dart part/part-of + extensions.
Zero behavior change, zero public-API change. Public API pinned by
new sync_service_public_api_snapshot_test.dart contract test.

See docs/superpowers/specs/2026-05-13-sync-service-part-split-design.md
and docs/superpowers/plans/2026-05-13-sync-service-part-split-plan.md.

Closes audit item B-5 (docs/audit/2026-05-11/cleanup-batch-triage.md).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

- [ ] **Step 12.4: STOP and wait for explicit APK build approval.**

Per founder rule `feedback_apk_build_explicit_approval.md`: APK build needs explicit approval EVERY time. Wait for "build apk" / "ship" / equivalent.

When approved, invoke the `/build-apk` skill (NEVER raw `flutter build apk`, per `feedback_use_build_apk_skill.md`).

- [ ] **Step 12.5: Manual smoke on installed APK**

On the device with the new APK installed:
1. Cold start the app.
2. Sign in (or restore from cloud if reinstalled).
3. Log a single set on an active workout → verify it appears in Hive + reaches cloud via `workout_log_exercises` / `workout_log_sets` within 30s.
4. Log a single meal via food search → verify `nutrition_logs` + `nutrition_log_items` rows in cloud.
5. Trigger restore round-trip: log out → sign in → confirm all surfaces restore (workout history, nutrition logs, freezes, notifications inbox, saved diet plan, rank promotions).
6. Query `client_errors` table for any new rows in the last hour. Expected: zero new error rows from this APK build.

If any smoke check fails: file a diagnose-doc, revert the merge from main, fix on the branch, re-merge.

---

## Self-review

**Spec coverage check:**
- Spec §3 (8 locked decisions) — all reflected in tasks. ✅
- Spec §4 (target file layout) — Tasks 2-10 each create one of the 9 part files. The spec lists 10 part files but `sync_helpers.dart` is dropped because static helpers stay on the class (callsite preservation). Task 11 documents this revision. ✅
- Spec §5 (execution sequence) — 11 tasks (commit 0 + 1-10) plus merge task. ✅
- Spec §6 (test strategy) — API snapshot test in Task 1, existing contract tests broadened in Task 1. ✅
- Spec §7 (risks + mitigations) — pilot validates mechanism (Task 2), rollback per commit available (each commit standalone), API snapshot test catches accidental renames. ✅
- Spec §8 (completion criteria) — all 11 line items reachable from the tasks. ✅
- Spec §9 (effort) — 11 tasks at 30min-2h each fits the 12h estimate. ✅

**Placeholder scan:** No "TBD", "implement later", "add appropriate error handling," or undefined types. Bodies of moved methods are referenced as `/* ... */` placeholders in the plan EXCEPT in Task 2 (the pilot), which has the full skeleton — this is intentional: the pilot establishes the template, and each subsequent task is mechanical copy-paste of method bodies. The plan does not need to reproduce 5,000 lines of code that already exist in the source file.

**Type consistency check:** All method names listed in the plan match the actual signatures from the grep results performed during planning. Extension names follow consistent pattern (`SyncService<Domain>`). The locked public API set in Task 1.2 matches the methods that should remain accessible after the refactor.

**One adjustment from spec:** Spec §4 lists `sync_helpers.dart` as the 10th part file. The plan drops it (no part file created in Task 11) because all helpers are `static` and moving them into an extension would change callsites. Documented in Task 11.

---

**Plan complete and saved to `docs/superpowers/plans/2026-05-13-sync-service-part-split-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Each task is well-bounded and a fresh agent can pick up Task N with just the spec + plan + access to the worktree.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

**Which approach?**