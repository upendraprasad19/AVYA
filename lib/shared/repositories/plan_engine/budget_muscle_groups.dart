/// Batch B2 (docs/plans/2026-10-22-session-set-budget.md), Task 2: the muscle
/// normaliser the session set budget counts in.
///
/// The library's `primary_muscles` is free text ("Lateral Delts", "Calves
/// (Gastrocnemius)", "Hip Flexors (Psoas)"), and the engine's own
/// `muscleGroupOf` is frozen (titration evidence keeps it, Ruling 10). Budget
/// accounting needs ten stable groups, so it normalises here instead. Pure Dart.
///
/// The map is a keyword table over the lowercased token with parentheticals
/// stripped. It was checked against every distinct token in the shipped library:
/// none maps to two groups, and the tokens that map to none are the ones that
/// train no budgeted group ("Full Body", "Forearms", "Hip Flexors", ...).
class BudgetMuscleGroups {
  BudgetMuscleGroups._();

  /// The ten budget groups, in the order reports list them.
  static const List<String> groups = [
    'Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps',
    'Quads', 'Hamstrings', 'Glutes', 'Core', 'Calves',
  ];

  static final RegExp _parenthetical = RegExp(r'\([^)]*\)');

  /// Ruling 12: `lower back`, `erector` and `spinal` name the erectors, not the
  /// lats and upper back, so they map to NO group. Deadlift therefore stops
  /// spending the Back allowance. (A bare "thoracic" / "spine" is not matched
  /// by the Back keywords either.)
  static final RegExp _erectors = RegExp(r'lower back|erector|spinal');

  /// Keyword -> group, checked in this order on a token that is not an erector.
  /// `lat` matches only as a whole word (M6): "Lateral Delts" is Shoulders.
  static final List<(String, RegExp)> _rules = [
    ('Chest', RegExp(r'chest|pec')),
    ('Back', RegExp(r'\blats?\b|back|trap|rhomboid')),
    ('Shoulders', RegExp(r'delt|shoulder')),
    ('Biceps', RegExp(r'bicep|brachialis')),
    ('Triceps', RegExp(r'tricep')),
    ('Quads', RegExp(r'quad')),
    ('Hamstrings', RegExp(r'hamstring')),
    ('Glutes', RegExp(r'glute')),
    ('Core', RegExp(r'abs|oblique|core|transverse')),
    ('Calves', RegExp(r'calf|calves|gastrocnemius|soleus')),
  ];

  /// The budget groups [tokens] credit. Each token has its parentheticals
  /// stripped and is lowercased first; a token that matches no rule contributes
  /// nothing, and an empty or unknown input is an empty set (never a throw).
  static Set<String> of(List<String> tokens) {
    final out = <String>{};
    for (final raw in tokens) {
      final token = raw.replaceAll(_parenthetical, '').trim().toLowerCase();
      if (token.isEmpty || _erectors.hasMatch(token)) continue;
      for (final (group, pattern) in _rules) {
        if (pattern.hasMatch(token)) out.add(group);
      }
    }
    return out;
  }
}
