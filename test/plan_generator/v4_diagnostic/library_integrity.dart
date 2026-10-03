import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

class TripletRow {
  final String movementPattern;
  final String equipmentTier;
  final String suitableFor;
  final bool foundationalOnly;
  final int count;

  const TripletRow(
    this.movementPattern,
    this.equipmentTier,
    this.suitableFor,
    this.foundationalOnly,
    this.count,
  );
}

class LibraryIntegrity {
  static const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
  static const _levels = ['beginner', 'intermediate', 'advanced'];

  /// Returns true if [field] (String or List<String>) contains [value] (case-insensitive exact).
  static bool _fieldContains(dynamic field, String value) {
    final v = value.toLowerCase();
    if (field is List) return field.any((e) => e.toString().toLowerCase() == v);
    return (field as String?)?.toLowerCase() == v;
  }

  /// Unique raw values seen in any exercise's `equipment_tier` list.
  /// Flags string-mismatch bugs (e.g. "full gym" space vs "full_gym" underscore).
  static List<String> uniqueEquipmentTiers(List<Map<String, dynamic>> lib) {
    final seen = <String>{};
    for (final ex in lib) {
      final tiers = ex['equipment_tier'];
      if (tiers is List) {
        for (final t in tiers) {
          seen.add(t.toString());
        }
      }
    }
    final sorted = seen.toList()..sort();
    return sorted;
  }

  /// Count exercises for every (movement_pattern × tier × suitable_for ×
  /// is_foundational) production-plausible triplet.
  static List<TripletRow> tripletCounts(List<Map<String, dynamic>> lib) {
    final rows = <TripletRow>[];
    for (final pattern in kMovementPatterns) {
      for (final tier in _tiers) {
        for (final level in _levels) {
          for (final foundational in [true, false]) {
            final count = lib.where((e) {
              if (!_fieldContains(e['movement_pattern'], pattern)) return false;
              final tiers = e['equipment_tier'];
              if (tiers is! List ||
                  !tiers.any((t) => t.toString().toLowerCase() == tier)) {
                return false;
              }
              final suitable = e['suitable_for'];
              if (suitable is List) {
                final hasLevel = suitable.any(
                  (s) => s.toString().toLowerCase() == level,
                );
                if (!hasLevel) return false;
              }
              if (foundational && e['is_foundational'] != true) return false;
              return true;
            }).length;
            rows.add(TripletRow(
              pattern,
              tier,
              level,
              foundational,
              count,
            ));
          }
        }
      }
    }
    return rows;
  }

  /// Render a Markdown section combining the triplet table + tier audit.
  static String renderMarkdown(List<Map<String, dynamic>> lib) {
    final buf = StringBuffer();
    buf.writeln('## Library integrity pre-check');
    buf.writeln();
    buf.writeln('**Triplet counts** (movement_pattern × equipment_tier × suitable_for × foundational-only)');
    buf.writeln();
    buf.writeln('| movement_pattern | equipment_tier | suitable_for | foundational | count |');
    buf.writeln('|---|---|---|---|---|');
    for (final row in tripletCounts(lib)) {
      final flag = row.count == 0 ? ' ⚠️' : '';
      buf.writeln(
        '| ${row.movementPattern} | ${row.equipmentTier} | ${row.suitableFor} '
        '| ${row.foundationalOnly} | ${row.count}$flag |',
      );
    }
    buf.writeln();
    final tiers = uniqueEquipmentTiers(lib);
    final suspicious = tiers.where((t) => t.contains(' ')).toList();
    buf.writeln('**Equipment tier unique values:** `${tiers.join("`, `")}`');
    if (suspicious.isNotEmpty) {
      buf.writeln();
      buf.writeln('⚠️ **Suspicious tiers with spaces:** `${suspicious.join("`, `")}`');
    }
    buf.writeln();
    return buf.toString();
  }
}
