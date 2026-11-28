import '../../core/services/auto_appended_custom.dart' show isLibraryRow;
import '../../core/utils/exercise_name_identity.dart';
import 'plan_engine/equipment_capability.dart';

typedef _Row = Map<String, dynamic>;

/// The rows a hand-pick exercise list shows (founder 2026-11-28): a user adding
/// or swapping by hand can pick ANY exercise, so equipment only ORDERS the list
/// and never removes a row. One name is listed once.
///
/// Used by the mid-workout picker, the swap sheet, the template builder and the
/// coach's swap list. A NEW hand-pick list goes through here. Plans the app
/// builds still filter by equipment (`EquipmentCapability`).
class PickerRows {
  const PickerRows._(
    this.matchingLibrary,
    this.matchingCustom,
    this.otherLibrary,
    this.otherCustom,
  );

  /// Built-in and community rows the user's equipment covers.
  final List<_Row> matchingLibrary;

  /// The user's own rows their equipment covers.
  final List<_Row> matchingCustom;

  /// The remaining built-in and community rows.
  final List<_Row> otherLibrary;

  /// The user's remaining own rows.
  final List<_Row> otherCustom;

  List<_Row> get custom => [...matchingCustom, ...otherCustom];

  List<_Row> get merged => [
        ...matchingLibrary,
        ...matchingCustom,
        ...otherLibrary,
        ...otherCustom,
      ];

  /// Arranges the WHOLE of `ExerciseRepository.getAll()` and ALL of
  /// `getCustomExercises()`; a list searches or filters the result, so which
  /// row stands for a name never depends on what was typed.
  ///
  /// One row per name: the user's own row wins, then a built-in, then a
  /// community row (the first the equipment covers, else the first). A row is
  /// the same name when [exerciseDuplicateKey] agrees. A community row that
  /// shares an id with an own row is that row's copy. A built-in is never
  /// dropped by id, because the swap write lets a built-in win an id clash.
  /// Two built-ins, or two own rows, never drop each other.
  ///
  /// [capability] is `resolveCapabilityFromProfile()`; null means every row
  /// matches. Input maps are not changed.
  static PickerRows arrange({
    required List<_Row> library,
    required List<_Row> custom,
    required Set<String>? capability,
  }) {
    bool libraryMatches(_Row row) =>
        capability == null ||
        EquipmentCapability.canPerform(row['equipment_needed'], capability);
    bool customMatches(_Row row) =>
        capability == null ||
        EquipmentCapability.canOfferInPicker(
            row['equipment_needed'], capability,
            isCustom: true);

    final customByName = <String, int>{};
    final customById = <String, int>{};
    for (var i = 0; i < custom.length; i++) {
      final name = _nameKey(custom[i]);
      if (name != null) customByName.putIfAbsent(name, () => i);
      final id = _id(custom[i]);
      if (id != null) customById.putIfAbsent(id, () => i);
    }

    final replacedByCustom = <int, List<_Row>>{};
    final replacedByLibrary = <int, List<_Row>>{};
    final kept = <int>{};

    // 1. Rows an own exercise stands for.
    for (var i = 0; i < library.length; i++) {
      final row = library[i];
      final name = _nameKey(row);
      final id = isLibraryRow(row) ? null : _id(row);
      final owner = (name == null ? null : customByName[name]) ??
          (id == null ? null : customById[id]);
      if (owner == null) {
        kept.add(i);
      } else {
        (replacedByCustom[owner] ??= []).add(row);
      }
    }

    // 2. A community row beside a built-in of the same name.
    final builtInByName = <String, int>{};
    for (final i in kept) {
      final name = _nameKey(library[i]);
      if (name != null && isLibraryRow(library[i])) {
        builtInByName.putIfAbsent(name, () => i);
      }
    }
    for (final i in kept.toList()) {
      if (isLibraryRow(library[i])) continue;
      final name = _nameKey(library[i]);
      final builtIn = name == null ? null : builtInByName[name];
      if (builtIn == null) continue;
      kept.remove(i);
      (replacedByLibrary[builtIn] ??= []).add(library[i]);
    }

    // 3. Community rows sharing a name.
    final communityByName = <String, List<int>>{};
    for (final i in kept) {
      final name = _nameKey(library[i]);
      if (name != null && !isLibraryRow(library[i])) {
        (communityByName[name] ??= []).add(i);
      }
    }
    for (final group in communityByName.values) {
      if (group.length < 2) continue;
      final winner = group.firstWhere((i) => libraryMatches(library[i]),
          orElse: () => group.first);
      for (final i in group) {
        if (i == winner) continue;
        kept.remove(i);
        (replacedByLibrary[winner] ??= []).add(library[i]);
      }
    }

    final matchingLibrary = <_Row>[];
    final otherLibrary = <_Row>[];
    for (var i = 0; i < library.length; i++) {
      if (!kept.contains(i)) continue;
      (libraryMatches(library[i]) ? matchingLibrary : otherLibrary)
          .add(_standingFor(library[i], replacedByLibrary[i]));
    }
    final matchingCustom = <_Row>[];
    final otherCustom = <_Row>[];
    for (var i = 0; i < custom.length; i++) {
      (customMatches(custom[i]) ? matchingCustom : otherCustom)
          .add(_standingFor(custom[i], replacedByCustom[i]));
    }
    return PickerRows._(
        matchingLibrary, matchingCustom, otherLibrary, otherCustom);
  }

  /// Whether [row] belongs under a category chip: its own category, or the
  /// category of a row it stands for.
  static bool inCategory(Map row, String category) {
    final wanted = category.toLowerCase();
    bool matches(Object? value) => value?.toString().toLowerCase() == wanted;
    final others = row['picker_categories'];
    return matches(row['category']) || (others is List && others.any(matches));
  }

  /// Whether [name] is already among [takenNames], so its row is greyed. Wider
  /// than the day's own rule (`exerciseNameKey`): a curly apostrophe or a
  /// double space does not make a second tappable row. The writers are
  /// unchanged.
  static bool isTaken(String name, Set<String> takenNames) {
    final key = exerciseDuplicateKey(name);
    return key.isNotEmpty &&
        takenNames.any((taken) => exerciseDuplicateKey(taken) == key);
  }

  /// [row], or a copy that is also found by the names and categories of the
  /// rows it replaced. `category` itself is never changed: a picker writes it
  /// into the workout.
  static _Row _standingFor(_Row row, List<_Row>? replaced) {
    if (replaced == null) return row;
    final names = <String>{..._aliases(row)};
    final categories = <String>{};
    final ownName = _nameKey(row);
    final ownCategory = row['category']?.toString().toLowerCase();
    for (final other in replaced) {
      final name = other['name']?.toString() ?? '';
      final key = _nameKey(other);
      if (key != null && key != ownName) names.add(name);
      names.addAll(_aliases(other));
      final category = other['category']?.toString() ?? '';
      if (category.isNotEmpty && category.toLowerCase() != ownCategory) {
        categories.add(category);
      }
    }
    if (categories.isEmpty && names.length == _aliases(row).toSet().length) {
      return row;
    }
    return <String, dynamic>{
      ...row,
      if (names.isNotEmpty) 'name_aliases': names.toList(),
      if (categories.isNotEmpty) 'picker_categories': categories.toList(),
    };
  }

  static List<String> _aliases(_Row row) {
    final aliases = row['name_aliases'];
    return aliases is List ? [for (final a in aliases) a.toString()] : const [];
  }

  static String? _nameKey(_Row row) {
    final key = exerciseDuplicateKey(row['name']?.toString() ?? '');
    return key.isEmpty ? null : key;
  }

  static String? _id(_Row row) {
    final id = row['id']?.toString() ?? '';
    return id.isEmpty ? null : id;
  }
}
