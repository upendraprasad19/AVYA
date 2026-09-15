import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

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
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  // b3c9d4 (round-1 review finding 1) — DERIVED from userProfileProvider, not
  // a fourth independent Hive read. `full_name` is one of the 10 kTier1Fields
  // above, each worth 6 points, so a profile map that has not yet merged the
  // `users` row renders 94% instead of 100% — which is exactly what the
  // founder's Profile screenshot showed. As a plain Provider this cached the
  // pre-restore read for the whole session and sat in NO tab's
  // invalidateOnRetry, so nothing could heal it. Watching the source fixes
  // that without adding it to any hand-maintained list.
  final profile = ref.watch(userProfileProvider);

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
      // Any non-empty selection counts — including `['none']`, which is
      // how the UI encodes "No injuries" (a valid, plan-relevant answer).
      //
      // Previously this treated `['none']` as "unfilled default" and left
      // the nudge card visible forever, which confused users who had
      // explicitly selected "No injuries". Observed 2026-04-17 on
      // icanbefitter@gmail.com — profile completeness stuck at 87% with
      // "Injuries" called out despite the user picking "No injuries".
      final list = val is List ? val : [];
      isFilled = list.isNotEmpty;
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
