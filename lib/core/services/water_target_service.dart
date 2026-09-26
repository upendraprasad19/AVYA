import 'hive_service.dart';

/// Single source of truth for the user's daily water target.
///
/// Read precedence:
///   1. User-set manual override (stored in userBox under [_overrideKey]).
///   2. Computed from profile: weight × 35 ml + training-day bonus + lifestyle bonus.
///   3. Floor: 2500 ml (no one should be told they only need 2 L).
///
/// Ceiling: 4000 ml. Range can be overridden via [setUserOverride] (clamped).
///
/// Formula additions per founder direction 2026-05-04:
///   +500 ml if training 4+ days/week.
///   +300 ml if lifestyle_activity == 'active' or 'very_active'.
class WaterTargetService {
  WaterTargetService._();
  static final instance = WaterTargetService._();

  static const _overrideKey = 'water_target_override_ml';

  /// Minimum daily water target in ml. No user should be told they only
  /// need less than 2.5 L.
  static const int floorMl = 2500;

  /// Maximum daily water target in ml. Above 4 L is rarely warranted and
  /// can be confusing / counterproductive.
  static const int ceilingMl = 4000;

  /// Returns the effective water target for the current user.
  ///
  /// Priority: override (validated) → computed from profile → floor.
  int currentTargetMl() {
    final userBox = HiveService.instance.userBox;
    final override = userBox.get(_overrideKey) as int?;
    if (override != null && override >= floorMl && override <= ceilingMl) {
      return override;
    }
    final profile = userBox.get('profile') as Map?;
    if (profile == null) return floorMl;
    return computeFromProfile(profile);
  }

  /// Pure computation from a profile map. Public so tests and onboarding
  /// can call it without needing Hive.
  ///
  /// Fields read: `current_weight_kg`, `lifestyle_activity`, `days_per_week`.
  /// All fall back to safe defaults when absent.
  static int computeFromProfile(Map profile) {
    final weightKg =
        (profile['current_weight_kg'] as num?)?.toDouble() ?? 70.0;
    final lifestyle =
        profile['lifestyle_activity']?.toString() ?? 'moderate';
    final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 0;

    // Base: ~35 ml per kg of body weight.
    var ml = (weightKg * 35).round();

    // Training-day bonus: 4+ sessions/week adds meaningful sweat loss.
    if (daysPerWeek >= 4) ml += 500;

    // Lifestyle bonus: active/very_active users burn more through movement.
    if (lifestyle == 'active' || lifestyle == 'very_active') ml += 300;

    if (ml < floorMl) return floorMl;
    if (ml > ceilingMl) return ceilingMl;
    return ml;
  }

  /// Persists a user-set override to Hive userBox. Device-local by design —
  /// overrides are NOT synced to Supabase. The onboarding-computed value
  /// `profile['water_target_ml']` is what restores from cloud; override is a
  /// per-device preference that resets when Hive is wiped (sign-out, reinstall).
  ///
  /// Pass `null` to clear the override and return to the formula-computed value.
  /// Values are clamped to [floorMl, ceilingMl] before saving.
  Future<void> setUserOverride(int? targetMl) async {
    final userBox = HiveService.instance.userBox;
    if (targetMl == null) {
      await userBox.delete(_overrideKey);
    } else {
      final clamped = targetMl.clamp(floorMl, ceilingMl);
      await userBox.put(_overrideKey, clamped);
    }
  }

  /// Returns `true` when the user has a valid manual override, so the UI
  /// can show a "Reset to recommended" affordance.
  ///
  /// Mirrors the range guard in [currentTargetMl] — an out-of-range value
  /// stored in Hive is treated as absent (no valid override).
  bool hasUserOverride() {
    final override = HiveService.instance.userBox.get(_overrideKey) as int?;
    return override != null && override >= floorMl && override <= ceilingMl;
  }
}
