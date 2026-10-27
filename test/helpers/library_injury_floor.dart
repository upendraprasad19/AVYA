// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, R5): an INDEPENDENT Dart recomputation of the injury
// floor the JS builder (scripts/build_library_injury_additions_v15.js) applies to the new rows.
//
// It deliberately re-derives everything from the ORIGINAL library rows (E-ids) so a bug in the builder cannot hide
// behind a copy of the builder's own logic. Used by library_batch_c_injury_coverage_test.dart and, in Task 5, by the
// generator assertions that restrict themselves to the new ids.

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

import 'injury_safe_pool.dart';

/// Two new rows share a picture with a library row (the library rows' picture ids exist only in the scratch merged.json,
/// so these pairs are a constant, not a recomputation): the new row carries at least the library row's tags.
const Map<String, String> kTwinLibraryRow = {
  'G0814': 'E075', // Tricep Dip ~ Dip (Parallel Bars): elbow + shoulder
  'G1428': 'E210', // ~ Wrist Rotations: wrist
};

List<String> _strs(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();

List<String> sortedUnique(Iterable<String> v) => v.toSet().toList()..sort();

/// The `injury_contraindications` of [row], sorted and de-duplicated.
List<String> injuryTagsOf(Map<String, dynamic> row) => sortedUnique(_strs(row['injury_contraindications']));

/// The ORIGINAL library rows of [family]: E-ids only, never a new row (a later library already contains the G rows).
List<Map<String, dynamic>> familyOriginals(String? family, List<Map<String, dynamic>> lib) => family == null
    ? const []
    : lib.where((l) => '${l['id']}'.startsWith('E') && l['variant_family'] == family).toList();

/// Tokens on EVERY same-family original (the floor), empty when the family has no original.
List<String> floorOf(String? family, List<Map<String, dynamic>> lib) {
  final sibs = familyOriginals(family, lib);
  if (sibs.isEmpty) return const [];
  final count = <String, int>{};
  for (final s in sibs) {
    for (final t in injuryTagsOf(s)) {
      count.update(t, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return sortedUnique(count.entries.where((e) => e.value == sibs.length).map((e) => e.key));
}

/// Tokens on more than half, but not all, of the same-family originals.
List<String> majorityOf(String? family, List<Map<String, dynamic>> lib) {
  final sibs = familyOriginals(family, lib);
  if (sibs.isEmpty) return const [];
  final count = <String, int>{};
  for (final s in sibs) {
    for (final t in injuryTagsOf(s)) {
      count.update(t, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return sortedUnique(count.entries.where((e) => e.value > sibs.length / 2 && e.value < sibs.length).map((e) => e.key));
}

final RegExp _pushUp = RegExp(r'push[- ]?up', caseSensitive: false);
final RegExp _lowerBackNames = RegExp(r'russian twist|v[- ]?up|crunch|sit[- ]?up', caseSensitive: false);
final RegExp _hipNames = RegExp(r'\bhip (abduction|adduction)\b', caseSensitive: false);

/// The name- and pattern-rule tokens: push-up names carry shoulder; elbow_flexion / elbow_extension rows carry elbow;
/// Russian twist / V-up / crunch / sit-up names carry lower_back; hip abduction / adduction names carry hip.
List<String> familyRuleTokens(Map<String, dynamic> row) {
  final name = '${row['name']}';
  return sortedUnique([
    if (_pushUp.hasMatch(name)) 'shoulder',
    if (_strs(row['movement_pattern']).any((p) => p == 'elbow_flexion' || p == 'elbow_extension')) 'elbow',
    if (_lowerBackNames.hasMatch(name)) 'lower_back',
    if (_hipNames.hasMatch(name)) 'hip',
  ]);
}

/// The twin tokens of [row] (the library row's tags), or empty when the row has no twin.
List<String> twinTokens(Map<String, dynamic> row, List<Map<String, dynamic>> lib) {
  final from = kTwinLibraryRow[row['id']];
  if (from == null) return const [];
  return injuryTagsOf(lib.firstWhere((l) => l['id'] == from));
}

/// The tokens a new row MUST end with: floor, family rules and twin (the majority is a founder call, not a floor).
List<String> requiredTokens(Map<String, dynamic> row, List<Map<String, dynamic>> lib) =>
    sortedUnique([...floorOf(row['variant_family'] as String?, lib), ...familyRuleTokens(row), ...twinTokens(row, lib)]);

final RegExp _newRowId = RegExp(r'^[GN]\d');

/// True for an id of a Batch C1 row (G####, N##); the original library rows are E-ids.
bool isNewRowId(String id) => _newRowId.hasMatch(id);

/// Every main-lift id the phase actually serves, both variants, every week.
Iterable<String> builtIds(Phase p) => [
      for (final w in p.weekPlans)
        for (final d in w.workoutDays)
          for (final e in d.exercises) e.exerciseId
    ];

/// Disciplines a flag-OFF plan must never serve from the new rows (R6 (i)): the OFF cascade has no structural discipline
/// exclusion, so the new rows are kept out by data (priority_tier 3) and this loop proves it on the golden personas.
const Set<String> kNeverPickedDisciplines = {'calisthenics_skill', 'olympic', 'plyometric'};

/// R6 (i) and (ii) for ONE persona's built ids, scoped to the NEW ids: a picked new row is not a skill, olympic,
/// plyometric, high_impact or requires_coaching row (i); it carries its original-sibling floor, family-rule and twin
/// tokens, and one with no tags at all is a `kV14SafePool` name (ii). Returns one line per violation.
List<String> newRowPickViolations({
  required String personaKey,
  required Iterable<String> builtIds,
  required Map<String, Map<String, dynamic>> byId,
  required List<Map<String, dynamic>> library,
}) {
  final safe = {for (final n in kV14SafePool) n.toLowerCase()};
  final out = <String>[];
  for (final id in builtIds) {
    if (!isNewRowId(id)) continue;
    final row = byId[id];
    if (row == null) {
      out.add('$personaKey picked $id, which is not in the library');
      continue;
    }
    if (kNeverPickedDisciplines.contains(row['discipline']) || row['high_impact'] == true || row['requires_coaching'] == true) {
      out.add('$personaKey (i) picked $id ${row['name']}: ${row['discipline']}, high_impact ${row['high_impact']}, '
          'requires_coaching ${row['requires_coaching']}');
    }
    final have = injuryTagsOf(row);
    for (final t in requiredTokens(row, library)) {
      if (!have.contains(t)) out.add('$personaKey (ii) picked $id ${row['name']} without floor token $t (has $have)');
    }
    if (have.isEmpty && !safe.contains('${row['name']}'.toLowerCase())) {
      out.add('$personaKey (ii) picked $id ${row['name']}: untagged and not a safe-pool name');
    }
  }
  return out;
}
