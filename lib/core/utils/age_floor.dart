/// The minimum age to use AVYA Fit, in whole years.
///
/// 13 since 2026-10-16 (founder decision, OI-305). It matches the published
/// privacy policy ("You must be 13 or older to use AVYA Fit",
/// icanbefitter.com/privacy, October 2026). One constant for every date-of-birth
/// picker: the onboarding identity step, the conversational onboarding step and
/// Edit Profile used to carry three different floors (10, 16 and 13).
const int kMinAgeYears = 13;

/// The latest date of birth a picker may offer on [now]: someone who turns
/// [kMinAgeYears] today may pick today's day and month [kMinAgeYears] years ago.
///
/// On 29 February, when that year has no 29 February, the day clamps to 28
/// February (Dart's `DateTime` would roll it to 1 March, which admits someone
/// who turns 13 the next day).
DateTime latestAllowedDob(DateTime now) {
  final year = now.year - kMinAgeYears;
  final day = DateTime(year, now.month, now.day);
  return day.month == now.month ? day : DateTime(year, now.month, 28);
}
