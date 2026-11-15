// lib/shared/widgets/exercise_plate/exercise_cues.dart
//
// ONE parser for the four coaching fields of an exercise-library row, shared by
// the three places that show them: the active-workout FORM & CUES panel, the
// plate sheet and the logging viewer (SoT concept `exercise_coaching_content`).
//
// Each reader used to carry its own copy: the sheet split `coaching_cues` on ';'
// and the panel did not, and the numeric-breathing guard was written twice and
// kept in step by a source-grep test. The rules, once:
//   * `coaching_cues` is a list of cues. Since library v12 every row stores one
//     cue per item; before that 84 rows packed several into one string joined by
//     ';', so each item is split on ';' (a community row or an install still on
//     an older seed renders as lines too).
//   * `common_mistakes` is a list; its items are NOT split (no bundled item has
//     a ';', pinned by exercise_library_text_shape_contract_test).
//   * `breathing_cue` and `warmup_protocol` are strings and are NEVER split:
//     37 and 3 bundled rows contain a ';' inside the sentence.
//   * A bare NUMBER as `breathing_cue` is the fingerprint of a spreadsheet
//     column shift (136 rows had it until the OI-149 repair, 2026-10-22): it is
//     suppressed rather than printed as "BREATHING / 5". This regex is written
//     here and nowhere else.
//   * Community rows carry arbitrary JSON types: list items go through
//     `toString()`, string fields are read with `is String`. Never a hard cast.
class ExerciseCues {
  const ExerciseCues({
    this.cues = const [],
    this.mistakes = const [],
    this.breathing,
    this.warmup,
  });

  final List<String> cues;
  final List<String> mistakes;
  final String? breathing;
  final String? warmup;

  /// Nothing to show: the panel renders no heading at all.
  bool get isEmpty =>
      cues.isEmpty && mistakes.isEmpty && breathing == null && warmup == null;
}

final RegExp _numericOnly = RegExp(r'^\d+(\.\d+)?$');

/// The cues of [row] (an `ExerciseRepository.getByExactName` result), or an
/// empty [ExerciseCues] for a null row (no library match).
ExerciseCues exerciseCuesOf(Map<String, dynamic>? row) {
  if (row == null) return const ExerciseCues();
  final breathing = _cleanString(row['breathing_cue']);
  return ExerciseCues(
    cues: _stringList(row['coaching_cues'], splitOnSemicolon: true),
    mistakes: _stringList(row['common_mistakes']),
    breathing:
        (breathing != null && _numericOnly.hasMatch(breathing)) ? null : breathing,
    warmup: _cleanString(row['warmup_protocol']),
  );
}

/// An array field: each element via `toString()`, trimmed, blanks dropped.
List<String> _stringList(Object? v, {bool splitOnSemicolon = false}) {
  if (v is! List) return const [];
  return v
      .expand((e) => splitOnSemicolon ? e.toString().split(';') : [e.toString()])
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// A string field: null for anything that is not a non-blank String (113 of 285
/// `warmup_protocol` values were "" in library v12).
String? _cleanString(Object? v) {
  final s = v is String ? v.trim() : '';
  return s.isEmpty ? null : s;
}
