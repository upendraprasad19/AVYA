import 'package:icanbefitter/core/copy/wardroom_copy.dart';

/// Pure formatters for the chat workout card's notes
/// (docs/plans/train-coach-log-refresh.md, B').

/// Names joined `, `, de-duplicated in first-seen order, at most five, then
/// [WardroomCopy.activeFinishMoreTemplate] for the rest.
String joinDraftNames(List<String> names) {
  final unique = <String>[];
  for (final n in names) {
    if (!unique.contains(n)) unique.add(n);
  }
  if (unique.length <= 5) return unique.join(', ');
  final more = WardroomCopy.activeFinishMoreTemplate
      .replaceAll('{n}', '${unique.length - 5}');
  return '${unique.take(5).join(', ')}$more';
}

/// The note on a card that kept failed exercises: the partial line when
/// anything from this card was ever saved, else the none-saved line.
String formatDraftNote({
  required List<String> savedNames,
  required List<String> failedNames,
}) {
  if (savedNames.isEmpty) return WardroomCopy.coachWorkoutLogFailed;
  return WardroomCopy.coachWorkoutLogPartialTemplate
      .replaceAll('{saved}', joinDraftNames(savedNames))
      .replaceAll('{names}', joinDraftNames(failedNames));
}

/// The confirm-row line shown when DISCARD is tapped after a save.
String formatDiscardRest(List<String> savedNames) {
  final unique = savedNames.toSet();
  final template = unique.length >= 2
      ? WardroomCopy.coachWorkoutDiscardRestManyTemplate
      : WardroomCopy.coachWorkoutDiscardRestTemplate;
  return template.replaceAll('{saved}', joinDraftNames(savedNames));
}

/// The line naming exercises that had no usable set.
String formatSkipped(List<String> skippedNames) => WardroomCopy
    .coachWorkoutSkippedTemplate
    .replaceAll('{names}', joinDraftNames(skippedNames));
