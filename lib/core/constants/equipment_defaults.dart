// lib/core/constants/equipment_defaults.dart
//
// ⑦ OI-89: the ONE fallback for a profile missing `equipment_access`.
//
// Before this constant, 14 production sites disagreed across FOUR values —
// `basic_gym` ×6, `full_gym` ×3, `home_dumbbells` ×1, `bodyweight` ×3, plus one
// bare `''`. A bodyweight user whose profile lost the key was therefore
// generated a full gym plan by most of them, routing around the capability
// floor entirely: `resolveCapability` scopes the hard floor to the bodyweight
// tier, so a wrong tier does not merely pick wrong exercises, it turns the
// floor OFF.
//
// `bodyweight` is the fail-safe direction. A bodyweight plan is performable by a
// gym user; a gym plan is not performable by a bodyweight user. When we do not
// know, the honest default is the one that cannot hurt.
library;

/// The tier assumed when a profile carries no `equipment_access`.
const String kDefaultEquipmentAccess = 'bodyweight';

/// The user's equipment tier from a profile map, or [kDefaultEquipmentAccess].
///
/// Treats an empty or whitespace-only string as absent — `ai_snapshot_builder`
/// used to default to `''`, which reached the AI coach as a tier claim of
/// nothing at all.
String equipmentAccessOf(Map<dynamic, dynamic> profile) {
  final v = profile['equipment_access'];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return kDefaultEquipmentAccess;
}
