// lib/core/services/exercise_media/exercise_media.dart
//
// The plain data class for one exercise animation (Batch M2a). No Flutter import: the client, the store and the repository import
// this file and never the widgets folder.
//
// A value is built only by `resolveMedia` (lib/shared/widgets/exercise_plate/exercise_media_resolver.dart), which has already
// checked the shape of `slug` (`^[a-z0-9][a-z0-9-]*$`) and `version` (an int >= 1), so [objectName] always matches the client's
// own pattern `^[a-z0-9][a-z0-9-]*_v[1-9][0-9]*\.webp$`. There is deliberately no `==` override: callers compare [objectName].
class ExerciseMedia {
  const ExerciseMedia({required this.slug, required this.version});

  /// The file's stem, `<gif number>-<name>` (library field `media_slug`).
  final String slug;

  /// 1 for every file in M1 (library field `media_version`); a re-recorded file ships as a higher version.
  final int version;

  /// The private Storage object in the `exercise-media` bucket, and the device cache key.
  String get objectName => '${slug}_v$version.webp';

  /// The bundled 192 x 192 still (`assets/exercise_stills/`, Task 2).
  String get stillAsset => 'assets/exercise_stills/$slug.webp';
}
