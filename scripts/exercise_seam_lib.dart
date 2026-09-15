// scripts/exercise_seam_lib.dart
//
// ⑦ OI-89 Gate A — enumerate every place an exercise can reach a user.
//
// WHY THIS EXISTS. Across four review rounds the count of "exercise-emitting
// seams" went 5 → 7 → 10 → 11, and every round found one the previous round had
// missed. That is not a counting failure, it is a METHOD failure: the set is
// mechanically enumerable and was being enumerated by hand.
//
// The seams found late were not obscure. `exercise_swap_sheet.dart` had declared
// an `equipment` field and read it nowhere; `cardio_finisher.dart`'s `jump_rope`
// case was the only one of five that ignored `hasGymEquipment`; and
// `warmup_cooldown.dart` prescribes Dead Hang (pull-up bar) and Band Pull Apart
// (resistance band) into every generated day. They were missed because nobody
// grepped.
//
// This gate pins the inventory by FILE with an expected COUNT. Line numbers rot,
// so keying on them would produce a gate that fails on every unrelated edit; a
// count changes exactly when a seam is added or removed, which is the event worth
// blocking on.
//
// WHAT THIS GATE CANNOT SEE, stated so a green run is not mistaken for total
// coverage:
//
//   - The community download WRITE seam (`sync_community.dart`) puts rows into
//     `exerciseBox` through an API matching none of these patterns. It is the
//     live population for `canPerform`'s fail-closed branch, and it is invisible
//     here.
//   - A seam reached through a variable rather than a literal call
//     (`final r = repo; r.getAll();`) is invisible to any source scan.
//   - Block comments are not stripped (see `stripLineComment`).
//
// All three are real. A source-pattern gate BOUNDS the class it can see; it does
// not prove the class is empty. It replaces "did I remember them all?" with "has
// the inventory moved?", which is a different and answerable question.
//
// Pure (no dart:io) so the gate's own test can drive it with synthetic input.

/// Source patterns that can put an exercise in front of a user or into a plan.
const seamPatterns = <String>[
  'PlannedExercise(',
  '.getAll()',
  'repo.search(',
  '.queryV4(',
  'getCustomExercises(',
];

/// Every file allowed to contain seam sites, with the count expected and WHY.
///
/// A count that no longer matches means a seam was added or removed. Update this
/// map in the same commit, stating what the new site does about capability —
/// that decision is the whole point of the gate.
const seamAllowlist = <String, SeamEntry>{
  'lib/shared/repositories/plan_engine/exercise_selector.dart': SeamEntry(16,
      'The cascade itself. Attempts 1-5, buildPinnedDays and '
      '_applyHistoryAdjustments all take the capability set as a REQUIRED '
      'parameter, so a missed call site fails to compile.'),
  'lib/features/train/screens/template_builder_screen.dart': SeamEntry(3,
      'Seam 7. :518 customs, :524 the default empty-query getAll().take(30), '
      ':528 search. Filtered BEFORE .take(30) or a bodyweight user sees a '
      'near-empty list.'),
  'lib/features/nutrition/services/diet_plan_generator.dart': SeamEntry(2,
      'NOT an exercise seam - nutrition. Listed rather than excluded by a '
      'narrower regex, because a narrower regex is a blind spot nobody reviews.'),
  'lib/shared/repositories/plan_engine/warmup_cooldown.dart': SeamEntry(2,
      'Seam 11. Prescribes into EVERY day via plan_generator and '
      'template_service. equipmentNeeded must be POPULATED on these '
      'constructions before any filter runs - it is null today, so the oracle '
      'is blind and a fail-closed predicate would delete every warm-up.'),
  'lib/shared/repositories/plan_engine/training_history_analyzer.dart':
      SeamEntry(2,
          'Reads history to shape selection; does not emit to the user directly.'),
  'lib/shared/repositories/plan_engine/models.dart': SeamEntry(2,
      'The PlannedExercise type itself plus its fromMap - definition, not '
      'emission.'),
  'lib/features/train/widgets/exercise_swap_sheet.dart': SeamEntry(2,
      'Seam 6. Takes an explicit capability set. NOTE its `equipment` field '
      'holds the OUTGOING exercise requirement, not the user capability - '
      'filtering by it inverts the check.'),
  'lib/features/train/screens/active_workout/exercise_picker_sheet.dart':
      SeamEntry(2,
          'Seam 8. getAll() + customs, filtered on category and name only until '
          'this batch. Takes an explicit capability set.'),
  'lib/shared/repositories/plan_engine/cardio_finisher.dart': SeamEntry(1,
      'Seam 10. equipmentNeeded is null on this construction - same problem as '
      'warmup_cooldown.'),
  'lib/shared/repositories/exercise_repository.dart': SeamEntry(1,
      'The repository itself - the source the other seams read from.'),
};

class SeamEntry {
  final int count;
  final String reason;
  const SeamEntry(this.count, this.reason);
}

/// One source line matching a seam pattern.
class SeamSite {
  final String file;
  final int line;
  final String pattern;
  const SeamSite(this.file, this.line, this.pattern);
  @override
  String toString() => '$file:$line ($pattern)';
}

/// Strips `//` line comments so a pattern mentioned in prose is not counted.
/// Block comments are left alone: no seam pattern appears inside one today, and
/// a naive block stripper is worse than none.
String stripLineComment(String line) {
  final at = line.indexOf('//');
  return at < 0 ? line : line.substring(0, at);
}

/// Every seam site in [filesByPath] (path → source).
List<SeamSite> findSeamSites(Map<String, String> filesByPath) {
  final sites = <SeamSite>[];
  for (final entry in filesByPath.entries) {
    final lines = entry.value.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final code = stripLineComment(lines[i]);
      for (final p in seamPatterns) {
        if (code.contains(p)) {
          sites.add(SeamSite(entry.key, i + 1, p));
        }
      }
    }
  }
  return sites;
}

/// Violations: a file not on the allowlist, or one whose count has moved.
List<String> seamViolations(
  List<SeamSite> sites, {
  Map<String, SeamEntry> allowlist = seamAllowlist,
}) {
  final violations = <String>[];
  final counted = <String, int>{};
  for (final s in sites) {
    counted[s.file] = (counted[s.file] ?? 0) + 1;
  }

  for (final entry in counted.entries) {
    final allowed = allowlist[entry.key];
    if (allowed == null) {
      final where =
          sites.where((s) => s.file == entry.key).map((s) => s.line).join(', ');
      violations.add(
        'NEW exercise-emitting seam: ${entry.key} (${entry.value} site(s) at '
        'line(s) $where). Decide what it does about equipment capability, then '
        'add it to seamAllowlist with a reason. Seams went 5->7->10->11 across '
        'four review rounds precisely because this was done by eye.',
      );
      continue;
    }
    if (allowed.count != entry.value) {
      violations.add(
        '${entry.key}: expected ${allowed.count} seam site(s), found '
        '${entry.value}. A seam was added or removed — update seamAllowlist in '
        'this commit and say what the new site does about capability.',
      );
    }
  }

  for (final path in allowlist.keys) {
    if (!counted.containsKey(path)) {
      violations.add(
        '$path is on seamAllowlist but has no seam sites — the file moved or '
        'the seam was removed. Drop the entry.',
      );
    }
  }

  return violations;
}
