/// The pure decision behind the in-app referral credit notice (unit C,
/// `docs/plans/referral-unit-c-client.md` section 2.3).
///
/// [seen] is the Hive scalar `referral_credit_seen_days` (`null` = none stored:
/// the first evaluation on this device, a reinstall, a new phone, or a
/// sign-out/sign-in; a stored non-int counts as none and is mapped to `null`
/// by the caller). [daysEarned] is the server's lifetime total.
///
/// Founder decision 2026-10-16: the first run is SILENT. A lifetime total is
/// never announced as "new"; the invite sheet's counters block always shows
/// the running total.
class CreditNoticeDecision {
  /// Days to announce in ONE notice; 0 = show nothing.
  final int announceDays;

  /// A value to store now, silently; `null` = write nothing. Never set while a
  /// notice is announced: that scalar is written only when the user dismisses
  /// the notice or taps through.
  final int? storeSeenSilently;

  const CreditNoticeDecision({this.announceDays = 0, this.storeSeenSilently});

  static const none = CreditNoticeDecision();

  @override
  bool operator ==(Object other) =>
      other is CreditNoticeDecision &&
      other.announceDays == announceDays &&
      other.storeSeenSilently == storeSeenSilently;

  @override
  int get hashCode => Object.hash(announceDays, storeSeenSilently);

  @override
  String toString() =>
      'CreditNoticeDecision(announce=$announceDays, storeSilently=$storeSeenSilently)';
}

CreditNoticeDecision creditNoticeFor({
  required int daysEarned,
  required int? seen,
}) {
  // A negative total is a malformed read: treat it as unknown.
  if (daysEarned < 0) return CreditNoticeDecision.none;
  if (seen == null || seen < 0) {
    return CreditNoticeDecision(storeSeenSilently: daysEarned);
  }
  if (daysEarned > seen) {
    return CreditNoticeDecision(announceDays: daysEarned - seen);
  }
  if (daysEarned < seen) {
    // A lower total after a void or a repair: re-baseline silently.
    return CreditNoticeDecision(storeSeenSilently: daysEarned);
  }
  return CreditNoticeDecision.none;
}

/// Count-neutral, singular/plural-safe notice copy (also the Semantics label).
String creditNoticeText(int days) =>
    'You earned $days PRO ${days == 1 ? 'day' : 'days'} from friends who subscribed.';
