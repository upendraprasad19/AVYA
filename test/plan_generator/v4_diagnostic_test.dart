import 'package:flutter_test/flutter_test.dart';
import 'v4_diagnostic/library_loader.dart';

void main() {
  group('V4 Diagnostic Harness', () {
    test('library_loader loads all exercises from assets/data/exercise_library.json', () {
      final exercises = LibraryLoader.loadFromAssets();
      expect(exercises, isNotEmpty);
      expect(exercises.length, greaterThan(100),
          reason: 'Library should have at least 100 exercises');
      final first = exercises.first;
      expect(first['id'], isNotNull);
      expect(first['movement_pattern'], isNotNull);
      expect(first['equipment_tier'], isA<List>());
    });
  });
}
