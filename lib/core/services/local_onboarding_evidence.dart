/// Pure predicate: does LOCAL state prove this device's user already
/// finished onboarding?
///
/// closes-diagnose: c2e9f4
///
/// ## Why this exists as its own file
///
/// The logic lived inline inside `RestoringScreen._kickoffRestore`'s
/// `ResumeOnboarding` branch, where exactly one of the three
/// "not onboarded" branches consulted it. The `StartMissionBrief` branch —
/// the branch every FAILED cloud read lands on — consulted nothing and went
/// straight to `/onboarding/mission-brief`. Extracting the predicate makes it
/// reusable across all three branches and testable without a widget, a
/// router, or a live Supabase session.
///
/// ## What counts as evidence
///
/// Either signal alone is sufficient, and they fail in opposite directions:
///
///   * [flagOnboarded] — the top-level `onboarding_completed` boolean that
///     `app_router._authRedirect` itself gates on. Present for a user who
///     completed onboarding on this device or reached `/home` through
///     `_goHome`'s stamp (a3f6d9).
///   * a profile map carrying all 9 fields migration 112 gates server-side —
///     present for a user whose cloud profile has been restored into Hive but
///     whose boolean flag was never stamped (the a3f6d9 gap).
///
/// ## What it must NOT do
///
/// Return true for a genuinely new user. A fresh install has no profile map
/// and no flag, so both legs are false — [StartMissionBrief] routing for real
/// new users is unchanged. This is the property the behavioral test pins.
library;

/// True when local state alone establishes that this user has completed
/// onboarding.
///
/// [hiveProfile] is `userBox['profile']` (raw, may be null or a
/// `Map<dynamic, dynamic>` straight out of Hive). [flagOnboarded] is
/// `MigratedKey.readWithDefault<bool>('onboarding_completed', false)`.
///
/// ⚠ CALLER PRECONDITION: read both inputs only AFTER the user-scoped Hive
/// session is open. Under authenticated-but-owner-null, `wrapUserScopedBox`
/// serves `GuardedBox.empty` (guarded_box.dart:333) — every read returns
/// null, so this predicate returns false and the caller silently concludes
/// "no evidence" when the evidence exists on disk. That is precisely how the
/// pre-c2e9f4 `ResumeOnboarding` self-heal managed to be intermittently inert
/// on cold start. `HiveUserSession.ensureOpenedForCurrentSession()` is the
/// call that makes this safe; it is NOT enough to rely on the parallel
/// `restoreFromCloudForUser` having opened the session, because that call
/// site (sync_service.dart:454) is fire-and-forget and therefore racy.
bool hasLocalOnboardedEvidence({
  required Object? hiveProfile,
  required bool flagOnboarded,
}) {
  if (flagOnboarded) return true;
  return hasAllRequiredProfileFields(hiveProfile);
}

/// The 9 columns migration 112 gates `onboarding_completed_at` on
/// server-side. Kept as a named list so the client predicate and the server
/// trigger can be diffed by eye rather than by memory.
const List<String> requiredOnboardingProfileFields = <String>[
  'primary_goal',
  'fitness_experience',
  'current_weight_kg',
  'date_of_birth',
  'gender',
  'height_cm',
  'target_weight_kg',
  'days_per_week',
  'equipment_access',
];

/// True when [hiveProfile] is a map carrying a non-null value for every one
/// of [requiredOnboardingProfileFields].
///
/// Named separately from [hasLocalOnboardedEvidence] because the stamp
/// ATTEMPT in `RestoringScreen` needs this stricter signal on its own: a
/// legacy `flagOnboarded == true` user missing one of the 9 fields must still
/// go home, but must NOT retry a write migration 112 will reject forever
/// (OI-46, 2026-07-29).
bool hasAllRequiredProfileFields(Object? hiveProfile) {
  if (hiveProfile is! Map) return false;
  for (final field in requiredOnboardingProfileFields) {
    if (hiveProfile[field] == null) return false;
  }
  return true;
}
