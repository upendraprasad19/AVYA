// lib/shared/widgets/exercise_plate/exercise_media_resolver.dart
//
// Name -> animation (Batch M2a). The READER of the library's `media_slug` / `media_version` fields (SoT concept
// `exercise_media_fields`). It reads Hive through the repository, like `resolvePlate`, and imports no widget code.
//
// The row's fields are UNTRUSTED. The exerciseBox also holds community rows written from Postgres
// (lib/core/services/sync/sync_community.dart:502), where any field can be any JSON type, and the slug becomes a URL path
// segment, a file name and an asset path, so it is checked here, once:
//   - `is String`, never `as String?` (a hard cast red-screens the sheet);
//   - trimmed, then matched against `^[a-z0-9][a-z0-9-]*$` (no separator, no "..", no space, no uppercase);
//   - the version must be an `int >= 1` (a double 1.0 or the string '1' is not a version).
// Anything else resolves to null and the caller keeps the plate.
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

final RegExp _slugPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// The animation of the library exercise named [exerciseName] (exact name, or an alias of the surviving row), or null.
ExerciseMedia? resolveMedia(String exerciseName) {
  final row = ExerciseRepository.instance.getByExactName(exerciseName);
  if (row == null) return null;

  final rawSlug = row['media_slug'];
  if (rawSlug is! String) return null;
  final slug = rawSlug.trim();
  if (!_slugPattern.hasMatch(slug)) return null;

  final rawVersion = row['media_version'];
  if (rawVersion is! int || rawVersion < 1) return null;

  return ExerciseMedia(slug: slug, version: rawVersion);
}
