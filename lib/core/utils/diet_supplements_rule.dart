// lib/core/utils/diet_supplements_rule.dart
//
// Diet plan Unit 4a (2026-11-15, docs/plans/diet-supplements.md section 2):
// the ONE rule for "Supplements are active for this user", plus the age read
// it needs and the profile-push entry.
//
//   active = flag on  AND  PRO  AND  profile['diet_supplements'] == true
//            AND  an adult (18 or more) with a readable date of birth.
//
// Every reader (the Diet Plan screen, the plan provider, the snapshot
// builder) calls [dietSupplementsActive] or [dietSupplementsEligible]; the
// only raw reads of the key and the date are the inputs provider (it reads
// Hive) and the section's hint choice (unreadable date vs a minor). Pure: no
// Hive, no Riverpod.
//
// The age gate is SELF-ATTESTED: onboarding stores whatever date the user
// picked. The live stepped flow (identity_screen.dart) seeds its picker at
// 25 years ago and the legacy chat flow at 1 Jan 1998, so a minor who
// accepts the shown date reads as an adult (an existing hole in every age
// reader, OI-513; parked on the OI board for the store launch). The age is
// counted on the device's calendar day, not IST's: a one-day edge.
library;

/// The age from which Supplements are offered.
const int kSupplementsMinAgeYears = 18;

/// An age at or above this is treated as unreadable, not as a very old user.
const int kImplausibleAgeYears = 120;

final RegExp _dobPrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])');

/// Whole years of age on [now], or null when [dob] is missing, blank, not a
/// string, not a real calendar date, in the future, or older than
/// [kImplausibleAgeYears]. Null is NOT adult (fail safe for a minor). The
/// birthday comparison is by month and day, so a 29 February birthday counts
/// as 1 March in a year without one (the conservative choice for "under
/// 18"). A time part after the date is ignored (the app stores both
/// `YYYY-MM-DD` and `toIso8601String()`); no time zone conversion.
int? ageYearsOn(Object? dob, DateTime now) {
  if (dob is! String) return null;
  final m = _dobPrefix.firstMatch(dob.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final real = DateTime(y, mo, d);
  if (real.year != y || real.month != mo || real.day != d) return null;
  var age = now.year - y;
  if (now.month < mo || (now.month == mo && now.day < d)) age--;
  if (age < 0 || age >= kImplausibleAgeYears) return null;
  return age;
}

/// True when the Supplements section may be SHOWN: the flag is on and the
/// user is an adult with a readable date of birth. No PRO, no toggle.
bool dietSupplementsEligible({
  required Map<dynamic, dynamic>? profile,
  required bool enabled,
  required DateTime now,
}) {
  if (!enabled || profile == null) return false;
  final age = ageYearsOn(profile['date_of_birth'], now);
  return age != null && age >= kSupplementsMinAgeYears;
}

/// True when the user's Supplements are ON and effective: eligible, PRO, and
/// the stored switch is exactly `true`.
bool dietSupplementsActive({
  required Map<dynamic, dynamic>? profile,
  required bool pro,
  required bool enabled,
  required DateTime now,
}) {
  if (!pro) return false;
  if (!dietSupplementsEligible(profile: profile, enabled: enabled, now: now)) {
    return false;
  }
  return profile!['diet_supplements'] == true;
}

/// The `diet_supplements` entry of the profile push (`_syncUserProfile`). A
/// stored bool is pushed, `false` too (a restore merge ignores a cloud NULL,
/// so dropping the `false` would let a stale cloud `true` switch the feature
/// back on). Absent (never set), a non-bool, or the flag off: no entry, so a
/// user who never touched the switch pushes exactly what they pushed before.
Map<String, bool> dietSupplementsPushEntry(
  Map<dynamic, dynamic> profile, {
  required bool enabled,
}) {
  if (!enabled) return const {};
  final raw = profile['diet_supplements'];
  return raw is bool ? {'diet_supplements': raw} : const {};
}
