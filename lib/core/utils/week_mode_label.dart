// Train/Home hero label: the WEEK's character as a display word.
//
// Pure token -> word mapper (train-header-b2). The raw token is the
// periodization `week_character` stamped on every schedule row
// (baseline | overreach | peak | deload, plus `working` once a deload is lifted
// by `deload_evaluator.dart`). The service-aware resolver that picks WHICH token
// to map lives in `WorkoutScheduleReadService.weekModeForRow`; both cards call
// that, so Train and Home cannot disagree.

/// Display word for one raw `week_character`, normalised ONCE
/// (`toString().toLowerCase().trim()`). Empty / null -> null (no word is
/// invented, the caller omits the label). An unknown token is capitalised so a
/// future vocabulary still renders something sensible.
String? weekModeLabel(Object? rawWeekCharacter) {
  final t = rawWeekCharacter?.toString().toLowerCase().trim() ?? '';
  if (t.isEmpty) return null;
  const known = <String, String>{
    'baseline': 'Baseline',
    'overreach': 'Overreach',
    'peak': 'Peak',
    'deload': 'Deload',
    'working': 'Working',
  };
  return known[t] ?? '${t[0].toUpperCase()}${t.substring(1)}';
}
