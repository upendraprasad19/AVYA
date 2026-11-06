// lib/shared/providers/exercise_media_provider.dart
//
// Hand-written providers for the exercise-animation delivery (Batch M2a, Task 7). Nothing here needs a `main.dart` change: the
// native byte store resolves its folder lazily on first use, and the web store opens its Hive box lazily too, so a blocked
// IndexedDB cannot delay boot.
//
// No subscription gate and no `isPro` anywhere (C7: animations are free to every tier); a source-grep test pins that.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_client.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_repository.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_store.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_flags.dart';
import 'package:path_provider/path_provider.dart';

final exerciseMediaClientProvider = Provider<ExerciseMediaClient>((ref) => ExerciseMediaClient());

/// Native: files under the application SUPPORT directory (not the cache directory, so the OS "clear cache" cannot delete files
/// the index lists), 150 MB. Web: a Hive LazyBox, 60 MB (below a typical browser per-origin quota, and also the size of the
/// in-memory fallback).
final exerciseMediaStoreProvider = Provider<ExerciseMediaStore>((ref) {
  final ExerciseMediaBytesStore bytes = kIsWeb
      ? HiveExerciseMediaBytesStore(HiveService.openMediaBlobBox)
      : FileExerciseMediaBytesStore(
          () async => Directory('${(await getApplicationSupportDirectory()).path}/exercise_media'),
        );
  return ExerciseMediaStore(bytes: bytes, capBytes: kIsWeb ? 60 * 1024 * 1024 : 150 * 1024 * 1024);
});

final exerciseMediaRepositoryProvider = Provider<ExerciseMediaRepository>((ref) {
  return ExerciseMediaRepository(
    client: ref.watch(exerciseMediaClientProvider),
    store: ref.watch(exerciseMediaStoreProvider),
    // The kill switch is read at the SINK on every `ensure`, so a flag flipped mid-session takes effect on the next open.
    enabled: () => PlateFlags.animationsEnabled,
  );
});

/// The compile-time platform switch (Task 1's verdicts): the view reads it and shows stills only when it is false.
final exerciseAnimationsPlatformEnabledProvider = Provider<bool>((ref) {
  return animationsPlatformEnabled(
    isWeb: kIsWeb,
    webSwitch: kWebAnimationsFetchEnabled,
    nativeSwitch: kNativeAnimationsFetchEnabled,
  );
});
