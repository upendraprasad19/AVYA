// lib/shared/widgets/exercise_plate/plate_resolver.dart
//
// Name -> plate. No Flutter imports, so the logic is separable from any widget
// harness — but note resolvePlate DOES read Hive, so its tests still need the
// binding and the path_provider mock. Only monogramFor is genuinely pure.
//
// Plate SHAPE comes from the library's `demo_pair` field, NOT a constant here.
// It used to be a logging_type rule plus a hand-curated exception list, so the
// asset pipeline (Python) and the renderer (Dart) each held half of one
// decision with nothing keeping them in sync.
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

const Set<String> _monogramStopWords = {'the', 'a', 'of', 'with', 'to', 'and'};

/// Trailing possessive, straight or curly. Removed BEFORE punctuation becomes
/// whitespace, so it never survives as a bare "s" token.
final RegExp _possessive = RegExp(r"['’]s\b", caseSensitive: false);

class ExercisePlate {
  final String? slug;
  final List<String> assetPaths;
  final bool isPair;
  final String monogram;

  const ExercisePlate({
    required this.slug,
    required this.assetPaths,
    required this.isPair,
    required this.monogram,
  });

  bool get hasArtwork => assetPaths.isNotEmpty;
}

/// Up to three initials from the significant words of [name]. Never empty.
///
/// It does NOT identify — three letters collide across the library ('SS' is
/// shared by five exercises). Its only job is to make an artwork-less slot look
/// deliberate; the exercise name renders beside it.
String monogramFor(String name) {
  // Strip the possessive FIRST. Doing it by word length instead — which is the
  // obvious-looking fix — silently breaks every genuine one-letter word:
  // V-Up -> U, Z Press -> P, T-Bar Row -> BR, and Prone Y/T/W Raise all
  // collapsing to the same PR. Measured over all 292 names: the length filter
  // changes 12 — the 3 possessives it gets right, and 9 one-letter words it
  // gets wrong. The possessive regex changes exactly those 3.
  final words = name
      .replaceAll(_possessive, '')
      .replaceAll(RegExp(r"[^A-Za-z0-9\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_monogramStopWords.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) return '?';
  return words.take(3).map((w) => w[0].toUpperCase()).join();
}

ExercisePlate resolvePlate(String exerciseName) {
  final mono = monogramFor(exerciseName);
  // EXACT name, never search() — that is substring, and "Push Up" would
  // resolve to "Pike Push Up".
  final row = ExerciseRepository.instance.getByExactName(exerciseName);

  // `is String`, never `as String?` — this box also holds community rows
  // written from Postgres (lib/core/services/sync/sync_community.dart:502),
  // where any field can be any JSON type. A hard cast red-screens the sheet.
  final rawSlug = row?['demo_slug'];
  final slug = rawSlug is String ? rawSlug.trim() : '';

  if (slug.isEmpty) {
    return ExercisePlate(
        slug: null, assetPaths: const [], isPair: false, monogram: mono);
  }

  final isPair = row?['demo_pair'] == true;
  final paths = isPair
      ? <String>[
          'assets/exercise_plates/$slug-1.svg',
          'assets/exercise_plates/$slug-3.svg',
        ]
      : <String>['assets/exercise_plates/$slug-1.svg'];

  return ExercisePlate(
      slug: slug, assetPaths: paths, isPair: isPair, monogram: mono);
}
