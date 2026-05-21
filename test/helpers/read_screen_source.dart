// test/helpers/read_screen_source.dart
//
// Helper for source-grep tests that previously read a single god-screen
// file. After tech-debt audit 2026-05-20 / C3 + C4, the 4 god screens
// (train, profile, ai_coach, active_workout) were split into a sibling
// folder with `screen.dart` + N part files. Source-grep tests no longer
// have a single file to read; they need the concatenated contents.
//
// Usage:
//   final src = readScreenSource('train');     // train/screen.dart + parts
//   final src = readScreenSource('profile');
//   final src = readScreenSource('ai_coach');
//   final src = readScreenSource('active_workout');
//
// The helper resolves the screen folder, reads every `*.dart` file in it,
// and returns the concatenated content. Order is alphabetical so output is
// stable across machines.

import 'dart:io';

/// Folder mapping for the 4 split screens.
const _folders = <String, String>{
  'train': 'lib/features/train/screens/train',
  'profile': 'lib/features/profile/screens/profile',
  'ai_coach': 'lib/features/ai_coach/screens/ai_coach',
  'active_workout': 'lib/features/train/screens/active_workout',
};

/// Reads `screen.dart` + every sibling `*.dart` file in the named screen
/// folder and returns their contents concatenated (alphabetical order).
String readScreenSource(String screenName) {
  final folder = _folders[screenName];
  if (folder == null) {
    throw ArgumentError(
        'readScreenSource: unknown screen "$screenName". Known: '
        '${_folders.keys.join(", ")}');
  }
  final dir = Directory(folder);
  if (!dir.existsSync()) {
    throw StateError('readScreenSource: folder $folder does not exist');
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => f.readAsStringSync()).join('\n');
}
