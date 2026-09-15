// scripts/check_restore_round_trip_coverage.dart
//
// Gate: 21
//
// Gate 21: every `syncX()` method in `lib/core/services/sync/` must
// have a paired `_restoreX()` (or `restoreX()`) method. Catches the
// OI-09 / Test #12.8 class — "6 of 16 _restoreXxx methods keyed wrong
// fields" — by surfacing missing pairs before they ship.
//
// Closes OI-42 lens L39 (restore round-trip coverage). Companion to
// `test/contracts/restore_round_trip_field_coverage_test.dart` which
// validates PROJECTION coverage; this gate validates PAIRING.
//
// Exit 0 — every public syncX has a matching restoreX (or is allowlisted)
// Exit 1 — at least one orphan

import 'dart:io';

const _syncDir = 'lib/core/services/sync';

// syncX methods that intentionally have NO restoreX counterpart.
// Each entry needs a why-document reason.
const _syncOnlyAllowlist = <String, String>{
  'syncCustomItemsNow':
      'community-shared exercises restore via custom_exercises pull, not method name match',
  'syncProfileNow':
      'profile restore is part of restoreFromCloudForUser orchestrator, not per-method',
  'syncWorkoutData':
      'cross-domain orchestrator; restore happens via _restore<Domain> per-prefix',
  'syncWorkoutDataNow':
      'H1a (Unit H) non-coalesced fan-out variant of syncWorkoutData; same restore-via-_restore<Domain> pairing',
  'syncNutritionData':
      'cross-domain orchestrator; restore happens via _restoreNutritionLogs / _restoreWaterLogs / etc.',
  'syncNutritionDataNow':
      'H1a (Unit H) non-coalesced fan-out variant of syncNutritionData; same restore-via-_restoreNutritionLogs pairing',
  'syncFreezes':
      'restore lives in _restoreFreezes (private); shape verified by '
      'restore_completeness_writes_test',
  'syncSavedDietPlan':
      'restore lives in _restoreSavedDietPlan (private); shape verified by '
      'restore_completeness_writes_test',
  'syncNotificationsInboxEntry':
      'restore lives in _restoreNotificationsInbox (private); shape verified by '
      'restore_completeness_writes_test',
  'syncCoachMemoryNow':
      'restore lives in _restoreCoachMemory (private); shape verified by '
      'restore_completeness_writes_test',
  'syncWorkoutTemplatesNow':
      'subset of syncWorkoutData; restore via _restoreWorkoutTemplates',
  'syncUrineColorLogs':
      'subset of health domain; restored via _restoreHealth orchestrator covering nutritionBox urine entries',
  'syncProgressNow':
      'user_progress restored as part of restoreFromCloudForUser (single SELECT then UserRepository.saveProgress)',
  'syncFitnessSummary':
      'fitness summary is derived/computed; not a primary surface — restored implicitly via coach_memory + workout/nutrition restores',
  'syncSleepNow':
      'sleep restore covered by _restoreSleepLogs under sync_health; method name suffix differs',
  'syncCustomItems':
      'restore covered by _restoreCustomExercises + _restoreCustomFoods (per-type, not unified)',
  'syncCommunityItems':
      'community items are READ-ONLY from client perspective — restore not applicable (cloud is the SoT)',
  'syncWeightNow':
      'weight restore covered by _restoreWeightLogs under sync_health; method name suffix differs',
};

void main() {
  final dir = Directory(_syncDir);
  if (!dir.existsSync()) {
    stderr.writeln('[Gate 21] WARN — $_syncDir not found. Exit 0.');
    exit(0);
  }

  final syncMethods = <String>{};
  final restoreMethods = <String>{};

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final src = entity.readAsStringSync();

    // Public/private syncX method declarations. Match `Future<...> syncX(`
    // or `Future<...> _syncX(`. Skip when prefix is `Future` itself.
    final syncRegex = RegExp(r'Future<[^>]+>\s+_?(sync[A-Z]\w*)\s*\(');
    for (final m in syncRegex.allMatches(src)) {
      syncMethods.add(m.group(1)!);
    }
    final restoreRegex = RegExp(r'Future<[^>]+>\s+_?(restore[A-Z]\w*)\s*\(');
    for (final m in restoreRegex.allMatches(src)) {
      restoreMethods.add(m.group(1)!);
    }
  }

  // Also scan sync_service.dart root file.
  final root = File('lib/core/services/sync_service.dart');
  if (root.existsSync()) {
    final src = root.readAsStringSync();
    final syncRegex = RegExp(r'Future<[^>]+>\s+_?(sync[A-Z]\w*)\s*\(');
    for (final m in syncRegex.allMatches(src)) {
      syncMethods.add(m.group(1)!);
    }
    final restoreRegex = RegExp(r'Future<[^>]+>\s+_?(restore[A-Z]\w*)\s*\(');
    for (final m in restoreRegex.allMatches(src)) {
      restoreMethods.add(m.group(1)!);
    }
  }

  // For each syncX, expect restoreX (matching the X part).
  final orphans = <String>[];
  for (final sync in syncMethods) {
    final suffix = sync.substring(4); // sync → suffix is everything after
    final hasRestore = restoreMethods
        .any((r) => r.substring(7).startsWith(suffix.substring(0, suffix.length.clamp(0, 8))));
    if (!hasRestore && !_syncOnlyAllowlist.containsKey(sync)) {
      orphans.add('$sync (no matching restore$suffix*)');
    }
  }

  stdout.writeln(
      '[Gate 21] sync methods: ${syncMethods.length}, restore methods: ${restoreMethods.length}, allowlist: ${_syncOnlyAllowlist.length}');

  if (orphans.isEmpty) {
    stdout.writeln('[Gate 21] PASS — every syncX has a paired restoreX (or allowlisted).');
    exit(0);
  } else {
    stderr.writeln('[Gate 21] ${orphans.length} orphan syncX without restore:');
    for (final o in orphans) {
      stderr.writeln('  $o');
    }
    stderr.writeln(
        '\n  Fix: add the matching restoreX method to sync_service.dart, '
        'OR add the syncX name to _syncOnlyAllowlist with a clear reason.');
    exit(1);
  }
}
