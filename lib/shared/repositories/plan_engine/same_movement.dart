// Library Batch S1b-2 (plan docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md, Decision 2): the same-movement
// rule. A loaded version (N14 to N22) carries `same_movement_as: <original id>`; the founder's condition (2026-11-08) is
// that a version and its original never share a day. Generation dedups a day by NAME, so the rule is: wherever a name
// is checked, its partner's name is checked too. `expand` adds the partners to a name set; callers pass the result to
// the check they already run (queryV4 excludeNames, the universal-pool skip, the core-list `passes`, the soft-avoid
// sets). Per-exercise preferences (demoted, plateau) are NOT expanded (plan Decision 2's table).
//
// Pure: built from the full library rows (never a filtered view, or a partner a filter removed would be missed).
// Symmetric: E147 expands to N14 and N14 to E147. Not transitive: two versions of one original would not exclude each
// other (none exists). Names are exact library casing; `expandLower` serves the lowercase avoid sets.
library;

class SameMovement {
  SameMovement._(this._partners, this._partnersLower);

  /// Exact name -> partner names.
  final Map<String, Set<String>> _partners;

  /// Lowercase name -> lowercase partner names.
  final Map<String, Set<String>> _partnersLower;

  static final SameMovement empty = SameMovement._(const {}, const {});

  /// Builds the partner map from library rows (`id`, `name`, `same_movement_as`). A link to an id that is not in
  /// [rows] is ignored.
  factory SameMovement.fromRows(Iterable<Map<String, dynamic>> rows) {
    final nameById = <String, String>{};
    final links = <(String, String)>[];
    for (final r in rows) {
      final id = r['id'];
      final name = r['name'];
      if (id is! String || name is! String) continue;
      nameById[id] = name;
      final to = r['same_movement_as'];
      if (to is String && to.isNotEmpty) links.add((name, to));
    }
    if (links.isEmpty) return empty;
    final partners = <String, Set<String>>{};
    final lower = <String, Set<String>>{};
    for (final (name, toId) in links) {
      final other = nameById[toId];
      if (other == null || other == name) continue;
      (partners[name] ??= <String>{}).add(other);
      (partners[other] ??= <String>{}).add(name);
      (lower[name.toLowerCase()] ??= <String>{}).add(other.toLowerCase());
      (lower[other.toLowerCase()] ??= <String>{}).add(name.toLowerCase());
    }
    return SameMovement._(partners, lower);
  }

  bool get isEmpty => _partners.isEmpty;

  /// The partner names of [name] (exact casing); empty when it has none.
  Set<String> partnersOf(String name) => _partners[name] ?? const <String>{};

  /// [names] plus every partner of a member (exact casing). Returns [names] itself when nothing is added.
  Set<String> expand(Set<String> names) {
    if (_partners.isEmpty || names.isEmpty) return names;
    Set<String>? out;
    for (final n in names) {
      final p = _partners[n];
      if (p == null) continue;
      for (final q in p) {
        if (names.contains(q)) continue;
        (out ??= {...names}).add(q);
      }
    }
    return out ?? names;
  }

  /// [names] (lowercase) plus every partner of a member (lowercase). Returns [names] itself when nothing is added.
  Set<String> expandLower(Set<String> names) {
    if (_partnersLower.isEmpty || names.isEmpty) return names;
    Set<String>? out;
    for (final n in names) {
      final p = _partnersLower[n];
      if (p == null) continue;
      for (final q in p) {
        if (names.contains(q)) continue;
        (out ??= {...names}).add(q);
      }
    }
    return out ?? names;
  }
}
