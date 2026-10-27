/// The "EST" seal date on the PRO subscription card: when the user became a
/// member. `SubscriptionInfoData` carries no start date, so it is
/// back-computed from the expiry and the plan length (yearly/annual 365,
/// otherwise 30). DD/MM/YY matches the Wardroom handoff motif.
///
/// OI-341 Piece B2b: never later than [now]. A stacked purchase ends at
/// trial end + plan days, so the back-computed start is the trial end, in the
/// future until the trial is over; the seal shows today until then. A
/// `referral_trial` plan still back-computes 30 days (approximate, unchanged).
/// Display only, in the device's local zone (not an IST date key).
library;

String estSealDate({
  required DateTime? expiresAt,
  required String? plan,
  required DateTime now,
}) {
  if (expiresAt == null) return ddMmYy(now);
  final lower = plan?.toLowerCase();
  final planDays = (lower == 'yearly' || lower == 'annual') ? 365 : 30;
  final startedAt = expiresAt.subtract(Duration(days: planDays));
  // Both branches print the LOCAL calendar date: the stored expiry is often
  // UTC (refreshFromSupabase), and a UTC date would show the previous day
  // for a purchase between 00:00 and 05:30 IST (B-pass P3-5).
  return ddMmYy((startedAt.isAfter(now) ? now : startedAt).toLocal());
}

String ddMmYy(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = (d.year % 100).toString().padLeft(2, '0');
  return '$dd/$mm/$yy';
}
