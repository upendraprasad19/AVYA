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

// ── Directive-driven variant (2026-08-10) ────────────────────────────────
//
// [readScreenSource] above resolves parts from a HARDCODED folder map, which
// is the same static-list trap it exists to solve: split a new screen, or move
// a head file, and every source-grep test silently reads less than it thinks.
// That is not theoretical — extracting ONE function out of
// `restoring_screen.dart` reddened 3 tests here, and a stale count of "4
// affected tests" (the real number is 17) came from exactly this blind spot.
//
// [readLibrarySource] instead parses the head file's own `part '...';`
// directives, so it is correct for ANY layout — including the head file
// sitting OUTSIDE its parts folder, which is what `restoring_screen.dart`
// does so it keeps matching Gate 43's `*_screen.dart` filename regex.

/// Strips comments so a commented-out `part 'x';` line cannot be mistaken for
/// a real directive. The `(?<!:)` guard keeps `https://` inside string
/// literals intact — same expression the contract tests use.
String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

/// Reads a Dart library as ONE string: the head file at [headPath] plus every
/// file it pulls in with a `part '...';` directive, resolved relative to the
/// head file's own directory.
///
/// Throws if the head file or any declared part is missing — a source-grep
/// test that silently reads a subset of its subject is worse than one that
/// fails, because it keeps reporting green.
String readLibrarySource(String headPath) {
  final head = File(headPath);
  if (!head.existsSync()) {
    throw StateError('readLibrarySource: head file $headPath does not exist');
  }
  final headSource = head.readAsStringSync();
  final dir = head.parent.path;

  final partPaths = RegExp(r"""^\s*part\s+['"]([^'"]+)['"]\s*;""",
          multiLine: true)
      .allMatches(_stripComments(headSource))
      .map((m) => m.group(1)!)
      .toList()
    ..sort();

  final buffer = StringBuffer(headSource);
  for (final rel in partPaths) {
    final part = File('$dir/$rel');
    if (!part.existsSync()) {
      throw StateError(
          'readLibrarySource: $headPath declares part "$rel" but '
          '${part.path} does not exist');
    }
    buffer
      ..write('\n')
      ..write(part.readAsStringSync());
  }
  return buffer.toString();
}

/// The `restoring_screen.dart` library — head file + its part files.
///
/// Use this in place of `File('lib/features/auth/screens/restoring_screen.dart')
/// .readAsStringSync()` in any source-grep test, so a future extraction (OI-88
/// moves `_AnimatedDots` next) cannot silently narrow what the test reads.
String readRestoringScreenSource() =>
    readLibrarySource('lib/features/auth/screens/restoring_screen.dart');
