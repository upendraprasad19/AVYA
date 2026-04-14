import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Format exercise display text based on user's experience level.
///
/// - Beginner: "Back: Lat Pulldown" (category only)
/// - Intermediate: "Lats: Lat Pulldown" (muscle group)
/// - Advanced: "Lats (Width): Lat Pulldown" (muscle + focus)
class ExerciseDisplay {
  static String formatMuscleLabel(Map<String, dynamic> exercise) {
    final experience = UserRepository.instance.getProfile()?['fitness_experience'] as String? ?? 'intermediate';
    final targetFocus = exercise['target_focus'] as String? ?? '';
    final category = exercise['category'] as String? ?? '';

    switch (experience) {
      case 'beginner':
        return _categoryLabel(category);
      case 'advanced':
        return targetFocus.isNotEmpty ? targetFocus : _categoryLabel(category);
      default: // intermediate
        // Extract just the muscle name from target_focus (e.g., "Lats (Width)" → "Lats")
        if (targetFocus.isEmpty) return _categoryLabel(category);
        final parenIdx = targetFocus.indexOf('(');
        return parenIdx > 0 ? targetFocus.substring(0, parenIdx).trim() : targetFocus;
    }
  }

  static String _categoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'push': return 'Push';
      case 'pull': return 'Back';
      case 'legs': return 'Legs';
      case 'core': return 'Core';
      default: return category.isNotEmpty ? category[0].toUpperCase() + category.substring(1) : 'Exercise';
    }
  }
}
