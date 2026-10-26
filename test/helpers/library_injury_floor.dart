// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, R5): an INDEPENDENT Dart recomputation of the injury
// floor the JS builder (scripts/build_library_injury_additions_v15.js) applies to the new rows.
//
// It deliberately re-derives everything from the ORIGINAL library rows (E-ids) so a bug in the builder cannot hide
// behind a copy of the builder's own logic. Used by library_batch_c_injury_coverage_test.dart and, in Task 5, by the
// generator assertions that restrict themselves to the new ids.

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
