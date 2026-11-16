import '../../../core/utils/injury_vocab.dart';
import '../../../shared/repositories/user_repository.dart';

/// Unit 3C (OI-396, d77): the profile patch that adds a coach-reported injury [token] (a canonical token), or null
/// (no write) when there is no profile yet or the stored injuries already hold it (compared after
/// [InjuryVocab.normalize], so a stored legacy `back` holds `lower_back`). The new list is the stored one
/// ([InjuryVocab.fromProfile], a legacy bare String included) minus `none`, plus [token]. Pure.
Map<String, dynamic>? coachInjuryProfilePatch(Map<String, dynamic> current, String token) {
  if (current.isEmpty) return null;
  final stored = InjuryVocab.fromProfile(current['injuries']);
  if (InjuryVocab.normalize(stored).contains(token)) return null;
  return {
    'injuries': [
      ...stored.where((t) => t.trim().toLowerCase() != 'none'),
      token,
    ],
  };
}

/// Unit 3C (OI-396, d77 / d78): the token the injury diff preview says it will add (`Adds Knee to your injuries`),
/// or null (no line): the [bodyPart]'s token when the current profile exists and does not hold it yet. Read through
/// the repository (the preview computes its swap plan the same way, in its `initState`); never throws.
String? coachInjuryTokenToAdd(String? bodyPart) {
  final token = InjuryVocab.coachPartToken(bodyPart);
  if (token == null) return null;
  try {
    final profile = UserRepository.instance.getProfile();
    if (profile == null) return null;
    return coachInjuryProfilePatch(profile, token) == null ? null : token;
  } catch (_) {
    return null;
  }
}

/// The preview line for [token] (d77): `Adds Knee to your injuries (change it in Edit Profile)`.
String coachInjuryAddsLine(String token) =>
    'Adds ${InjuryVocab.chipLabel(token)} to your injuries (change it in Edit Profile)';
