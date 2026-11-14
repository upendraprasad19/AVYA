// Batch C2a (OI-460): the library DEPTH RULE as one reusable computation.
//
// A cell is (injury set of 1 or 2 tags) x (slot pattern) x (equipment tier). The pool that fills a cell is every
// strength / prehab / mobility row that does not carry an injury of the set, has the pattern and has the tier.
// Removing a row must leave `min(depth_before, 3)` rows in every cell that row occupies.
//
// The pattern is read under BOTH semantics the plan engine uses:
//  - movementPattern: `movement_pattern`;
//  - slotPattern: `slot_pattern ?? movement_pattern` (the core-list reader until seed v27). Unit 1B-F2 copied every
//    slot_pattern into movement_pattern and removed the key, so on the shipped library both semantics now agree; the
//    slot semantics stays because the frozen C2 `depth_before` cells were measured under it.
// The keep set is the UNION of the two. The cell key matches scripts/library_batch_c2_removals_gen.js
// ("mp|" / "slot|" + injuries joined with + + "/" + pattern + "/" + tier), so a frozen `depth_before` can be compared.
library;

enum DepthSemantics { movementPattern, slotPattern }

const kDepthEligibleDisciplines = {'strength', 'prehab', 'mobility'};
const kDepthSkipPatterns = {'warmup', 'cooldown', 'flexibility', 'cardio'};

String depthSemanticsPrefix(DepthSemantics s) => s == DepthSemantics.movementPattern ? 'mp' : 'slot';

List<String> _strings(Object? v) => v is List ? [for (final e in v) '$e'] : const <String>[];

/// Every single injury tag and every pair, over the tags that appear in [rows] (sorted, pairs in sorted order).
List<List<String>> depthInjurySets(List<Map<String, dynamic>> rows) {
  final tags = <String>{for (final r in rows) ..._strings(r['injury_contraindications'])}.toList()..sort();
  final out = <List<String>>[];
  for (var i = 0; i < tags.length; i++) {
    out.add([tags[i]]);
    for (var j = i + 1; j < tags.length; j++) {
      out.add([tags[i], tags[j]]);
    }
  }
  return out;
}

List<String> depthPatterns(Map<String, dynamic> row, DepthSemantics sem) {
  if (sem == DepthSemantics.slotPattern) {
    final slot = _strings(row['slot_pattern']);
    if (slot.isNotEmpty) return slot;
  }
  return _strings(row['movement_pattern']);
}

/// How many rows of [lib] (minus [without]) fill the cell.
int depthCount(
  List<Map<String, dynamic>> lib, {
  required Set<String> without,
  required DepthSemantics sem,
  required List<String> injuries,
  required String pattern,
  required String tier,
}) {
  var n = 0;
  for (final r in lib) {
    if (without.contains(r['id'])) continue;
    if (!kDepthEligibleDisciplines.contains(r['discipline'])) continue;
    final inj = _strings(r['injury_contraindications']);
    if (injuries.any(inj.contains)) continue;
    if (!depthPatterns(r, sem).contains(pattern)) continue;
    if (!_strings(r['equipment_tier']).contains(tier)) continue;
    n++;
  }
  return n;
}

/// The cells of ONE row ([row] need not be in [lib]) with their depth in [lib] minus [without].
/// Cells where the row's own injury tags rule it out are not its cells.
Map<String, int> depthCells(
  List<Map<String, dynamic>> lib,
  Map<String, dynamic> row, {
  Set<String> without = const {},
  required DepthSemantics sem,
  required List<List<String>> sets,
}) {
  final out = <String, int>{};
  final own = _strings(row['injury_contraindications']);
  for (final s in sets) {
    if (s.any(own.contains)) continue;
    for (final p in depthPatterns(row, sem).where((x) => !kDepthSkipPatterns.contains(x))) {
      for (final t in _strings(row['equipment_tier'])) {
        out['${depthSemanticsPrefix(sem)}|${s.join('+')}/$p/$t'] =
            depthCount(lib, without: without, sem: sem, injuries: s, pattern: p, tier: t);
      }
    }
  }
  return out;
}

/// The greedy fixed point the generator runs: rows of [dropIds] (ascending id) that cannot go without breaking a cell,
/// starting from [forced]. An ineligible row (conditioning and the like) is in no pool, so it is never kept.
Set<String> computeDepthKeeps(
  List<Map<String, dynamic>> lib,
  List<String> dropIds, {
  required Set<String> forced,
  required DepthSemantics sem,
  required List<List<String>> sets,
}) {
  final byId = {for (final r in lib) r['id'] as String: r};
  final ids = [...dropIds]..sort();
  final keep = {...forced};
  var changed = true;
  while (changed) {
    changed = false;
    final removed = {for (final i in ids) if (!keep.contains(i)) i};
    for (final id in ids) {
      if (keep.contains(id)) continue;
      final row = byId[id]!;
      if (!kDepthEligibleDisciplines.contains(row['discipline'])) continue;
      final before = depthCells(lib, row, sem: sem, sets: sets);
      final after = depthCells(lib, row, without: removed, sem: sem, sets: sets);
      final broken = before.entries.any((c) => after[c.key]! < (c.value < 3 ? c.value : 3));
      if (broken) {
        keep.add(id);
        changed = true;
      }
    }
  }
  return keep;
}

/// The cells of [rowIds] that fall below `min(need, 3)` when [removeIds] are taken out of [lib].
/// [frozenBefore] maps a cell key to its frozen depth when below 3 (a missing key means "3 or more", so need 3).
List<String> depthViolations(
  List<Map<String, dynamic>> lib,
  Iterable<Map<String, dynamic>> rowsToCheck, {
  required Set<String> removeIds,
  required List<List<String>> sets,
  Map<String, Map<String, int>> frozenBefore = const {},
}) {
  final out = <String>[];
  for (final row in rowsToCheck) {
    final id = row['id'] as String;
    for (final sem in DepthSemantics.values) {
      final after = depthCells(lib, row, without: removeIds, sem: sem, sets: sets);
      for (final c in after.entries) {
        final need = frozenBefore[id]?[c.key] ?? 3;
        if (c.value < need) out.add('$id ${c.key} ${c.value}<$need');
      }
    }
  }
  return out;
}
