// scripts/check_mutation_invalidation_set.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable):
// Mutation methods must invalidate the canonical provider set per
// docs/architecture/sync.md "Provider invalidation after mutation".
//
// Heuristic source-grep — for each scanned file, look for methods whose
// body contains BOTH a Hive write (`workoutBox.put`, `nutritionBox.put`,
// etc. — direct or via WriteService) AND any `ref.invalidate(...)` call.
// For such methods, count how many of the canonical providers are
// invalidated. Methods invalidating < 50% of the canonical set are
// flagged as WARNINGS (not hard failures — granular mutations may not
// need every provider refreshed).
//
// Files scanned:
//   - lib/features/train/providers/train_provider.dart
//   - lib/features/nutrition/providers/nutrition_provider.dart
//   - lib/features/home/providers/home_provider.dart
//   - lib/features/train/widgets/edit_workout_log_sheet.dart
//
// Canonical provider sets:
//   workout = {currentPlanProvider, workoutStatsProvider,
//              calendarWeekProvider, streakProvider,
//              todayWorkoutProvider, allExercisePRsProvider,
//              aiInsightProvider}
//   nutrition = {nutritionSummaryProvider, weeklyNutritionProvider,
//                aiInsightProvider}
//
// Exit 0 = pass (no missing-invalidation hotspots).
// Exit 1 = fail (large gap detected — likely a docs/architecture/sync.md violation).
//
// Usage: dart run scripts/check_mutation_invalidation_set.dart

import 'dart:io';

const workoutCanonical = <String>{
  'currentPlanProvider',
  'workoutStatsProvider',
  'calendarWeekProvider',
  'streakProvider',
  'todayWorkoutProvider',
  'allExercisePRsProvider',
  'aiInsightProvider',
};

const nutritionCanonical = <String>{
  'nutritionSummaryProvider',
  'weeklyNutritionProvider',
  'aiInsightProvider',
};

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final warnings = <String>[];
  final missing = <String>[];

  final filesAndDomains = <_FileSpec>[
    _FileSpec(
      path: 'lib/features/train/providers/train_provider.dart',
      domain: 'workout',
      canonical: workoutCanonical,
    ),
    _FileSpec(
      path: 'lib/features/nutrition/providers/nutrition_provider.dart',
      domain: 'nutrition',
      canonical: nutritionCanonical,
    ),
    _FileSpec(
      path: 'lib/features/home/providers/home_provider.dart',
      domain: 'mixed',
      canonical: {...workoutCanonical, ...nutritionCanonical},
    ),
    _FileSpec(
      path: 'lib/features/train/widgets/edit_workout_log_sheet.dart',
      domain: 'workout',
      canonical: workoutCanonical,
    ),
  ];

  for (final spec in filesAndDomains) {
    final f = File('$projectRoot/${spec.path}');
    if (!f.existsSync()) {
      missing.add(spec.path);
      continue;
    }

    final content = f.readAsStringSync();

    // Find all invalidated providers in the WHOLE file (cheap aggregate
    // check). A method body-level walker would be more precise but
    // dramatically more code; aggregate is enough to flag gaps.
    final invalidatedHere = <String>{};
    final invalidateRegex = RegExp(r'ref\.invalidate\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\b');
    for (final m in invalidateRegex.allMatches(content)) {
      invalidatedHere.add(m.group(1)!);
    }

    final intersection = spec.canonical.intersection(invalidatedHere);
    final missingFromFile = spec.canonical.difference(invalidatedHere);

    if (intersection.isEmpty) {
      // File never invalidates ANY canonical provider. Only a bug if
      // it does DIRECT box.put (not through a WriteService — those
      // handle invalidation internally via the `onInvalidate` hook).
      final hasDirectMutation = RegExp(
        r'\b(workoutBox|nutritionBox|healthBox)\s*\.\s*(put|delete)\s*\(',
      ).hasMatch(content);
      // Files that ONLY invoke WriteService.* are fine — invalidation
      // is the service's responsibility via onInvalidate hooks.
      if (hasDirectMutation) {
        warnings.add(
          '${spec.path} — does direct box.put/delete but invalidates NO canonical '
          '${spec.domain} provider (expected: ${spec.canonical.join(", ")})',
        );
      }
    } else if (missingFromFile.length > spec.canonical.length / 2) {
      // More than half of the canonical set is never invalidated.
      warnings.add(
        '${spec.path} — invalidates only ${intersection.length}/${spec.canonical.length} '
        'canonical ${spec.domain} providers; missing: ${missingFromFile.join(", ")}',
      );
    }
  }

  if (missing.isNotEmpty) {
    stderr.writeln('[check_mutation_invalidation_set] ERROR — scanned files missing:');
    for (final p in missing) {
      stderr.writeln('  $p');
    }
    exit(1);
  }

  if (warnings.isEmpty) {
    stdout.writeln('[check_mutation_invalidation_set] PASS — '
        'mutation files invalidate the canonical provider sets.');
    exit(0);
  } else {
    // Warnings are informational; print and exit 0 unless any file has
    // a TOTAL miss (0 / N). Total misses come back as warnings starting
    // with "mutates Hive but invalidates NO". Hard-fail on those.
    var totalMisses = warnings.where((w) => w.contains('NO canonical')).length;
    stderr.writeln('\n[check_mutation_invalidation_set] '
        '${totalMisses > 0 ? "FAIL" : "WARN"} — ${warnings.length} files with '
        'mutation/invalidation gaps:');
    for (final w in warnings) {
      stderr.writeln('  $w');
    }
    if (totalMisses > 0) {
      stderr.writeln('\n  Fix: ensure every mutation invalidates the '
          'docs/architecture/sync.md canonical provider set for its domain.');
      exit(1);
    }
    stdout.writeln('\n[check_mutation_invalidation_set] PASS (with warnings).');
    exit(0);
  }
}

class _FileSpec {
  final String path;
  final String domain;
  final Set<String> canonical;
  const _FileSpec({
    required this.path,
    required this.domain,
    required this.canonical,
  });
}
