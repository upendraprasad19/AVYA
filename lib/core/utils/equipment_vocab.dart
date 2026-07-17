/// Canonical equipment vocabulary for the plan engine's equipment matching (⑥ slice A).
///
/// These are the controlled tokens the exercise library's `equipment_needed`
/// field is normalized to. The live V4 selector filters on the separate CLEAN
/// `equipment_tier` field, NOT `equipment_needed` (`exercise_repository.dart`
/// queryV4 `:270`), so this vocabulary is the data-quality PREREQUISITE for
/// slice B's item-level exclusion filter — and pins the field to a closed set
/// the contract test (`test/contracts/equipment_vocab_library_contract_test.dart`)
/// enforces against the live library so it can never silently drift.
///
/// Mirrors `InjuryVocab`, with ONE deliberate difference: [normalize] does NOT
/// inherit InjuryVocab's `\s+`/`\band\b` free-text split. Equipment tokens are
/// multi-word ("cable machine", "pull-up bar") and use an explicit " or "
/// OR-compound form ("Barbell or Dumbbells" = EITHER). A whitespace split would
/// (a) explode "cable machine" → cable + machine and (b) flip "X or Y" from OR to
/// AND. So each list element is treated as ONE whole-string token, and a " or "
/// compound is collapsed to its single MOST-ACCESSIBLE alternative (founder
/// decision 2026-07-14) via [_precedence].
class EquipmentVocab {
  EquipmentVocab._();

  /// The 12 canonical tokens. The contract test pins the live library as a
  /// SUBSET of this set (NOT equality — `smith machine` is canonical but 0
  /// library rows use it, so an equality assert would fail). The 11 non-`cardio
  /// machine` tokens are exactly `_getEquipmentList`'s full_gym item tokens
  /// (minus the `none` sentinel), so the vocab is pre-aligned for slice B's
  /// tier→items filter.
  static const canonicalTokens = <String>{
    'bodyweight',
    'dumbbells',
    'barbell',
    'bench',
    'pull-up bar',
    'cables',
    'machines',
    'smith machine',
    'resistance band',
    'kettlebell',
    'ez-bar',
    'cardio machine',
  };

  /// Accessibility order, most → least accessible. An OR-compound ("X or Y")
  /// collapses to whichever alternative ranks FIRST here — the conservative
  /// choice (the exercise survives under the easier equipment, so slice B's
  /// exclusion filter never over-excludes).
  static const _precedence = <String>[
    'bodyweight',
    'resistance band',
    'dumbbells',
    'kettlebell',
    'pull-up bar',
    'bench',
    'barbell',
    'ez-bar',
    'cables',
    'machines',
    'smith machine',
    'cardio machine',
  ];

  /// Every raw library / free-text token (lowercased) → canonical. Canonical
  /// tokens themselves are NOT listed (handled by the [canonicalTokens] check in
  /// [_mapPart]). Includes the OR sub-alternatives (`band`, `rack`, `pole`, …)
  /// that appear ONLY inside " or " compounds, so the split maps each part.
  static const _aliases = <String, String>{
    // plural / casing / hyphen drift
    'dumbbell': 'dumbbells',
    'cable machine': 'cables',
    'rope': 'cables', // cable-rope attachment: all 3 rows co-occur w/ Cable Machine
    'ez bar': 'ez-bar',
    'kettlebells': 'kettlebell',
    // machine family
    'machine': 'machines',
    'ghd machine': 'machines',
    'hack squat machine': 'machines',
    'hip abduction machine': 'machines',
    'hip adduction machine': 'machines',
    'leg curl machine': 'machines',
    'leg extension machine': 'machines',
    'leg press machine': 'machines',
    'pec deck machine': 'machines',
    'seated calf raise machine': 'machines',
    'reverse hyper machine': 'machines',
    // bench variants
    'incline bench': 'bench',
    'decline bench': 'bench',
    'flat bench': 'bench',
    'elevated bench': 'bench',
    'preacher bench': 'bench',
    'hyperextension bench': 'bench',
    'sissy squat bench': 'bench',
    // cardio machines
    'treadmill': 'cardio machine',
    'stationary bike': 'cardio machine',
    'rowing machine': 'cardio machine',
    'assault bike': 'cardio machine',
    'battle ropes': 'cardio machine',
    // barbell-family loaded implements
    'landmine': 'barbell',
    'landmine attachment': 'barbell',
    'squat rack': 'barbell',
    'power rack': 'barbell',
    'rack': 'barbell',
    'barbell on rack': 'barbell',
    'light barbell': 'barbell',
    't-bar': 'barbell',
    'trap bar': 'barbell',
    // machine-family heavy frames
    'prowler sled': 'machines',
    'sled': 'machines',
    'yoke frame': 'machines',
    'tire (100-200kg)': 'machines',
    // dumbbell-family free weights
    'weight plate': 'dumbbells',
    'plate': 'dumbbells',
    'weight': 'dumbbells',
    'sandbag': 'dumbbells',
    // resistance band
    'band': 'resistance band',
    // bodyweight: positional / household / accessory / suspension
    'box': 'bodyweight',
    'box (30-45cm)': 'bodyweight',
    'box (30-60cm)': 'bodyweight',
    'medicine ball': 'bodyweight',
    'wall': 'bodyweight',
    'doorway': 'bodyweight',
    'chair': 'bodyweight',
    'lying': 'bodyweight',
    'elevated surface': 'bodyweight',
    'bodyweight (bent over position)': 'bodyweight',
    'yoga mat': 'bodyweight',
    'foam roller': 'bodyweight',
    'ab wheel': 'bodyweight',
    'jump rope': 'bodyweight',
    'parallel bars': 'bodyweight',
    'trx suspension trainer': 'bodyweight',
    'trx': 'bodyweight',
    'ankle strap': 'bodyweight',
    'floor': 'bodyweight',
    'freestanding': 'bodyweight',
    'pole': 'bodyweight',
    'broomstick': 'bodyweight',
    'partner': 'bodyweight',
    'nordic attachment': 'bodyweight',
  };

  /// Map a single already-lowercased whole token (NOT an OR-compound) to a
  /// canonical, or null if unmappable.
  static String? _mapPart(String lower) {
    if (canonicalTokens.contains(lower)) return lower;
    return _aliases[lower];
  }

  /// Normalize ONE raw equipment token → a canonical token, or null if it maps
  /// to nothing. An OR-compound ("X or Y") is split on " or ", each alternative
  /// mapped, and the MOST-ACCESSIBLE (lowest [_precedence] index) returned.
  /// Whole-string only — never split on whitespace (so "cable machine" stays one
  /// token, and "X or Y" never becomes an AND of both).
  static String? normalizeToken(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return null;
    if (lower.contains(' or ')) {
      String? best;
      var bestRank = 1 << 30;
      for (final part in lower.split(' or ')) {
        final c = _mapPart(part.trim());
        if (c == null) continue;
        final rank = _precedence.indexOf(c);
        if (rank >= 0 && rank < bestRank) {
          bestRank = rank;
          best = c;
        }
      }
      return best;
    }
    return _mapPart(lower);
  }

  /// Normalize a raw equipment list → canonical tokens. Maps each element via
  /// [normalizeToken], DROPS unmappable elements (so an all-unmappable list → []
  /// = most-permissive, which every reader treats as "no equipment requirement":
  /// the dead V3 filter's `.every` is vacuously true on `[]`, and slice B's
  /// filter must treat `[]` as no-requirement), and de-duplicates preserving
  /// first-seen order.
  static List<String> normalize(Iterable<String>? raw) {
    if (raw == null) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final c = normalizeToken(item);
      if (c != null && seen.add(c)) out.add(c);
    }
    return out;
  }

  /// Crash-safe extract of a raw equipment value (from a map / profile / row)
  /// before normalization. Never throws — unlike `value as List?`, which
  /// `_CastError`s on a bare String (the ⑥ crash-fix class, diagnose e9d1c7).
  /// Returns the NORMALIZED canonical list.
  static List<String> fromProfile(Object? raw) {
    if (raw is List) return normalize(raw.map((e) => e.toString()));
    if (raw is String && raw.trim().isNotEmpty) return normalize([raw]);
    return const [];
  }

  /// The user's equipment EXCLUSIONS as a floor-sanitized canonical Set (⑥ B1):
  /// normalize to canonical tokens, then STRIP `none`/`bodyweight` so a user can
  /// never exclude the bodyweight floor — a pure-bodyweight exercise is thus
  /// never droppable and the universal-pool floor always survives an
  /// exclude-everything. This is the single derivation of the exclusion set (the
  /// plan engine flag-gates the CALL); unit-pinned so the flag-read seam has a
  /// cheap direct test.
  static Set<String> floorSanitizedExclusions(Iterable<String>? raw) {
    return normalize(raw).toSet()..removeAll(const {'none', 'bodyweight'});
  }

  /// Normalizes [map]'s `equipment_needed` to canonical vocab at the
  /// community-download write seam (⑥ slice B2 — the WRITE-side completion of
  /// slice A's owned-custom normalize, so STORED community rows are canonical
  /// like the seed, not the RAW cloud text). Mutates and returns the SAME map
  /// for call-site chaining. Crash-safe (delegates to [fromProfile]) and
  /// idempotent (canonical in → canonical out). When [enabled] is false
  /// (kill-switch `disable_community_equipment_normalize`), returns the map
  /// UNCHANGED — a verbatim raw store, today's exact behavior.
  ///
  /// Public + static so the seam is behaviorally testable without a live
  /// SyncService (rule 21 — a private helper in a `part of` file would force a
  /// source-grep-only test). Consistency/defense-in-depth: the sole live
  /// selection reader (queryV4) already `fromProfile`-normalizes on read, so
  /// this changes only the stored representation, never plan selection.
  static Map<String, dynamic> normalizedEquipmentRow(
    Map<String, dynamic> map, {
    bool enabled = true,
  }) {
    if (enabled) {
      map['equipment_needed'] = fromProfile(map['equipment_needed']);
    }
    return map;
  }

  /// ⑥ slice C1 — the equipment TIER → its canonical item list. The SINGLE source
  /// `_getEquipmentList` (plan_generator) delegates to, so the tier→items map can
  /// never drift from the generator. Each list begins with `none` (the
  /// no-requirement sentinel, NOT a canonical token) then the tier's canonical
  /// items. Invariant (pinned by equipment_chip_vocab_contract_test):
  /// `tierItems[t] ⊆ canonicalTokens ∪ {'none'}`.
  static const Map<String, List<String>> tierItems = <String, List<String>>{
    'bodyweight': ['none', 'bodyweight'],
    'home_dumbbells': ['none', 'bodyweight', 'dumbbells', 'resistance band'],
    'basic_gym': [
      'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
      'pull-up bar', 'cables', 'resistance band',
    ],
    'full_gym': [
      'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
      'pull-up bar', 'cables', 'machines', 'smith machine',
      'resistance band', 'kettlebell', 'ez-bar',
    ],
  };

  /// The items a user of [tier] can EXCLUDE in the Customize UI — the tier's items
  /// minus the bodyweight floor (`none`/`bodyweight` are never excludable, so the
  /// floor always survives — mirrors [floorSanitizedExclusions]). A `bodyweight`
  /// tier → `[]` (nothing to customize → the UI hides the section). Invariant
  /// (pinned): the result ⊆ [canonicalTokens].
  static List<String> tierExcludableItems(String tier) {
    return (tierItems[tier] ?? const ['none', 'bodyweight'])
        .where((t) => t != 'none' && t != 'bodyweight')
        .toList();
  }

  static const Map<String, String> _chipLabels = <String, String>{
    'dumbbells': 'Dumbbells',
    'barbell': 'Barbell',
    'bench': 'Bench',
    'pull-up bar': 'Pull-up Bar',
    'cables': 'Cables',
    'machines': 'Machines',
    'smith machine': 'Smith Machine',
    'resistance band': 'Resistance Band',
    'kettlebell': 'Kettlebell',
    'ez-bar': 'EZ-Bar',
    'cardio machine': 'Cardio Machine',
  };

  /// Display label for an equipment chip token (e.g. `pull-up bar` → "Pull-up Bar").
  static String chipLabel(String token) => _chipLabels[token] ?? token;

  /// Pure add/remove toggle for the equipment-exclusion multi-select — NO `none`
  /// sentinel (an empty list = "exclude nothing", the default). Returns a fresh
  /// GROWABLE list.
  static List<String> toggleExclusion(Iterable<String> current, String token) {
    final next = current.toList();
    if (next.contains(token)) {
      next.remove(token);
    } else {
      next.add(token);
    }
    return next;
  }

  /// Drop any exclusion not valid for [tier] — a tier DOWNGRADE (full_gym →
  /// basic_gym) must not leave a stale `machines` exclusion. Returns a growable,
  /// order-preserving subset of the CURRENT tier's excludable items.
  static List<String> pruneToTier(Iterable<String> current, String tier) {
    final valid = tierExcludableItems(tier).toSet();
    return current.where(valid.contains).toList();
  }
}
