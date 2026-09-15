import 'dart:convert';
import 'dart:io';

/// Loads the bundled exercise library JSON directly from disk.
///
/// Used by the V4 diagnostic harness. Avoids the production HiveService
/// so the harness can run as a pure-Dart unit test without Flutter bindings.
class LibraryLoader {
  static const _defaultPath = 'assets/data/exercise_library.json';

  /// Reads the JSON file from disk and returns the parsed list.
  /// Throws if the file is missing or malformed.
  static List<Map<String, dynamic>> loadFromAssets({String? path}) {
    final filePath = path ?? _defaultPath;
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError(
        'exercise_library.json not found at "$filePath" '
        '(cwd=${Directory.current.path})',
      );
    }
    final raw = file.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw StateError('Expected JSON array, got ${decoded.runtimeType}');
    }
    return decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
