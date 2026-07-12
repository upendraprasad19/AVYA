/// Canonical injury vocabulary for the plan engine's contraindication filter.
///
/// These are the EXACT tokens the exercise library's `injury_contraindications`
/// field uses (verified against `assets/data/exercise_library.json`: 9 distinct
/// tokens across 115 of 258 rows — ankle 13, elbow 12, hamstring 2, hip 26,
/// knee 30, lower_back 24, neck 1, shoulder 33, wrist 15).
///
/// The engine matches injuries by **exact lowercase equality**
/// (`exercise_repository.dart` queryV4 `:290`; `exercise_selector.dart` the
/// universal-pool filter). So every injury value that reaches the engine — from
/// the Edit-Profile chips, a stored profile map, a restored cloud row, or the
/// AI-coach muster/induction free-text — MUST be normalized to one of these
/// tokens first. Otherwise the filter silently no-ops: the whole reason this
/// class exists is the vocabulary-drift bug where the UI stored `back` but the
/// library tags `lower_back`, so a back-injured user's plan excluded ZERO
/// exercises (writer/reader field drift — the house default suspect class).
///
/// Read-side alias, NOT a boot normalizer: `normalize()` is applied at every
/// READ seam (chip render, generation, muster write) so it heals local, legacy,
/// restored, and free-text values uniformly with no cloud migration and no
/// restore-fragility.
class InjuryVocab {
  InjuryVocab._();

  /// The 9 canonical library tokens. This set IS the contract pinned by
  /// `test/contracts/injury_vocab_library_contract_test.dart` against the live
  /// library so it can never silently drift again.
  static const canonicalTokens = <String>{
    'ankle',
    'elbow',
    'hamstring',
    'hip',
    'knee',
    'lower_back',
    'neck',
    'shoulder',
    'wrist',
  };

  /// Legacy / free-text synonyms → canonical token. Matched after lowercasing +
  /// trimming. Covers the legacy Edit-Profile chip value (`back`), plurals, and
  /// the common muster/induction free-text phrasings ("lower back", "bad knee").
  static const _aliases = <String, String>{
    'back': 'lower_back',
    'lower back': 'lower_back',
    'lowerback': 'lower_back',
    'low back': 'lower_back',
    'lumbar': 'lower_back',
    'spine': 'lower_back',
    'knees': 'knee',
    'bad knee': 'knee',
    'shoulders': 'shoulder',
    'rotator cuff': 'shoulder',
    'wrists': 'wrist',
    'elbows': 'elbow',
    'ankles': 'ankle',
    'hips': 'hip',
    'hamstrings': 'hamstring',
    'hammy': 'hamstring',
    'necks': 'neck',
  };

  /// Normalize a raw injury list to the canonical library vocabulary.
  ///
  /// - Lowercases + trims each entry.
  /// - Maps legacy/free-text synonyms (`back` → `lower_back`).
  /// - Splits multi-token free text (`"lower back, bad knee"`) into its tokens.
  /// - Drops `none`, empty strings, and anything that cannot be mapped to a
  ///   canonical token (so unrecognised free-text never reaches the engine as a
  ///   phantom exclusion that matches nothing).
  /// - De-duplicates, preserving first-seen order.
  static List<String> normalize(Iterable<String>? raw) {
    if (raw == null) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      for (final tok in _tokenize(item)) {
        if (seen.add(tok)) out.add(tok);
      }
    }
    return out;
  }

  /// Safely extract a raw injury list from a profile-map value before it is
  /// threaded into the generator. The value is normally a `List`, but may be
  /// null or — for a legacy pre-migration-033 local install — a bare `String`;
  /// this NEVER throws (unlike `value as List?`, which `_CastError`s on a
  /// String). The result is canonicalized downstream by [normalize] at the
  /// central generateV4 seam, so this only has to extract, not normalize.
  static List<String> fromProfile(Object? raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) {
      final s = raw.trim();
      if (s.isNotEmpty && s.toLowerCase() != 'none') return [s];
    }
    return const [];
  }

  static Iterable<String> _tokenize(String item) {
    final lower = item.toLowerCase().trim();
    if (lower.isEmpty || lower == 'none') return const [];
    // Try the whole phrase first ("lower back" → lower_back).
    final whole = _canonical(lower);
    if (whole != null) return [whole];
    // Otherwise split free text and map each fragment.
    final parts =
        lower.split(RegExp(r'[,/;&]|\band\b|\s+')).where((p) => p.isNotEmpty);
    final out = <String>[];
    for (final p in parts) {
      final c = _canonical(p);
      if (c != null) out.add(c);
    }
    return out;
  }

  /// Map a single already-lowercased fragment to a canonical token, or null.
  static String? _canonical(String s) {
    final collapsed = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    if (canonicalTokens.contains(collapsed)) return collapsed;
    final underscored = collapsed.replaceAll(' ', '_');
    if (canonicalTokens.contains(underscored)) return underscored;
    final alias = _aliases[collapsed];
    if (alias != null) return alias;
    // Strip a laterality qualifier — the exercise library does not distinguish
    // sides, so "left shoulder" / "right_knee" map to the base token
    // (shoulder / knee) rather than being dropped as unmappable.
    final delateralized =
        collapsed.replaceFirst(RegExp(r'^(left|right)[\s_-]+'), '');
    if (delateralized != collapsed && delateralized.isNotEmpty) {
      return _canonical(delateralized);
    }
    return null;
  }
}
