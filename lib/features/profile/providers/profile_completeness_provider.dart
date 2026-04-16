import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Tier 2 profile fields ordered by plan impact (highest first).
const kTier2Fields = <({String key, String label, String benefit})>[
  (key: 'session_duration_minutes', label: 'Session Duration', benefit: 'Get plans sized for your schedule'),
  (key: 'physique_focus', label: 'Physique Focus', benefit: 'Bias workouts toward your goals'),
  (key: 'injuries', label: 'Injuries', benefit: 'Avoid exercises that could hurt you'),
  (key: 'target_weight_kg', label: 'Target Weight', benefit: 'Unlock weight projection'),
  (key: 'body_fat_percent', label: 'Body Fat %', benefit: 'Get more accurate calorie targets'),
  (key: 'pace_preference', label: 'Pace Preference', benefit: 'Control how fast you cut or bulk'),
];

/// Tier 1 fields (collected at onboarding — should already be filled).
const kTier1Fields = <String>[
  'full_name', 'date_of_birth', 'gender', 'height_cm', 'current_weight_kg',
  'primary_goal', 'equipment_access', 'days_per_week', 'fitness_experience',
  'lifestyle_activity',
];

class ProfileCompletenessData {
  final int percentage;
  final ({String key, String label, String benefit})? highestImpactMissing;
  final List<({String key, String label, String benefit})> allMissing;

  const ProfileCompletenessData({
    required this.percentage,
    this.highestImpactMissing,
    this.allMissing = const [],
  });

  bool get isComplete => percentage >= 100 || allMissing.isEmpty;
}

final profileCompletenessProvider = Provider<ProfileCompletenessData>((ref) {
  final profile = UserRepository.instance.getProfile() ?? {};

  // Count Tier 1 filled
  int tier1Filled = 0;
  for (final key in kTier1Fields) {
    final val = profile[key];
    if (val != null && val.toString().isNotEmpty) tier1Filled++;
  }

  // Count Tier 2 filled + collect missing
  int tier2Filled = 0;
  final missing = <({String key, String label, String benefit})>[];
  for (final field in kTier2Fields) {
    final val = profile[field.key];
    bool isFilled = false;
    if (val == null) {
      isFilled = false;
    } else if (field.key == 'injuries') {
      // injuries = ['none'] counts as not filled (default)
      final list = val is List ? val : [];
      isFilled = list.isNotEmpty && !(list.length == 1 && list.first.toString() == 'none');
    } else if (val is String) {
      isFilled = val.isNotEmpty;
    } else if (val is num) {
      isFilled = val > 0;
    } else {
      isFilled = true;
    }

    if (isFilled) {
      tier2Filled++;
    } else {
      missing.add(field);
    }
  }

  // Weighted percentage: Tier 1 = 60%, Tier 2 = 40%
  final tier1Pct = kTier1Fields.isEmpty ? 60.0 : (tier1Filled / kTier1Fields.length) * 60;
  final tier2Pct = kTier2Fields.isEmpty ? 40.0 : (tier2Filled / kTier2Fields.length) * 40;
  final pct = (tier1Pct + tier2Pct).round().clamp(0, 100);

  return ProfileCompletenessData(
    percentage: pct,
    highestImpactMissing: missing.isNotEmpty ? missing.first : null,
    allMissing: missing,
  );
});
