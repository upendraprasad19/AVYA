// lib/features/profile/services/target_impact.dart
//
// goal-change-targets B3 (founder decision 2): Edit Profile tells the user, with exact numbers,
// when a Save moved the calorie / protein targets. Pure: the screen hands in the profile snapshot
// taken when the form OPENED and the profile after the Save's recompute.
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

/// The calorie and protein targets before and after a Save.
class TargetImpact {
  const TargetImpact({
    required this.caloriesFrom,
    required this.caloriesTo,
    required this.proteinFrom,
    required this.proteinTo,
  });

  final num? caloriesFrom;
  final num caloriesTo;
  final num? proteinFrom;
  final num proteinTo;
}

/// True when [after] differs from [before] on a derivation input in a way the user MADE, not one a
/// re-save re-derives: onboarding stores `date_of_birth` as an ISO timestamp while Edit Profile
/// re-saves `YYYY-MM-DD` (compared by the first 10 characters), and the height field shows whole
/// cm, so a stored 177.8 re-saves as 178 (compared within 0.5). Other numbers compare within 0.05,
/// text after trim. This is NOT `derivedTargetInputsChanged`, whose raw `!=` fires on an unchanged
/// form.
bool derivationInputsChangedForDialog(
  Map<dynamic, dynamic> before,
  Map<dynamic, dynamic> after,
) {
  for (final k in derivedTargetInputKeys) {
    if (_differs(k, before[k], after[k])) return true;
  }
  return false;
}

bool _differs(String key, Object? a, Object? b) {
  if (a == null && b == null) return false;
  if (a == null || b == null) return true;
  if (key == 'date_of_birth') {
    final x = a.toString();
    final y = b.toString();
    String day(String s) => s.length >= 10 ? s.substring(0, 10) : s;
    return day(x).trim() != day(y).trim();
  }
  if (a is num && b is num) {
    final tol = key == 'height_cm' ? 0.5 : 0.05;
    return (a - b).abs() > tol;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
  if (a is String && b is String) return a.trim() != b.trim();
  return a != b;
}

/// The impact of a Save, or null when there is nothing to say: no derivation input really changed,
/// the targets did not move (either the calories OR the protein number), or the profile has no
/// calorie target after the Save.
TargetImpact? targetImpactFor(
  Map<dynamic, dynamic> before,
  Map<dynamic, dynamic> after,
) {
  if (!derivationInputsChangedForDialog(before, after)) return null;
  num? n(Object? v) => v is num ? v : null;
  final cTo = n(after['daily_calories']);
  final pTo = n(after['protein_grams']);
  if (cTo == null || pTo == null) return null;
  final cFrom = n(before['daily_calories']);
  final pFrom = n(before['protein_grams']);
  final moved = cFrom != cTo || pFrom != pTo;
  if (!moved) return null;
  return TargetImpact(
      caloriesFrom: cFrom, caloriesTo: cTo, proteinFrom: pFrom, proteinTo: pTo);
}
