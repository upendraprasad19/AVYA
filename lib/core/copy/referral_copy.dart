/// Single source of truth for the referral surfaces' literal copy (unit C,
/// `docs/plans/referral-unit-c-client.md`). Count-neutral, singular/plural-safe
/// where a number is spliced in; never promises the referrer cannot tell who
/// paid (a referrer's client can still read an opaque friend id and the join
/// time, and for ONE friend the aggregates are that friend).
class ReferralCopy {
  ReferralCopy._();

  /// Invite sheet description: the real rule (migration 159).
  static const String inviteDescription =
      'Friends who use this code within 7 days of signing up get 7 days of PRO '
      'free. If they subscribe within 90 days, you get 7 days too, a week '
      'after their first payment (30 for the yearly plan), unless they cancel '
      'in that week.';

  /// The disclosure line next to EVERY code-entry surface (the friend side).
  static const String friendDisclosure =
      'The friend who shared this code can see how many of their friends '
      'joined and subscribed.';

  static const String countersEyebrow = 'YOUR INVITES';
  static const String labelJoined = 'FRIENDS JOINED';
  static const String labelSubscribed = 'SUBSCRIBED';
  static const String labelDaysEarned = 'PRO DAYS EARNED';
  static const String labelPending = 'PENDING';

  static String countersSemantics({
    required int joined,
    required int subscribed,
    required int daysEarned,
    int pending = 0,
  }) =>
      '$joined ${joined == 1 ? 'friend' : 'friends'} joined, $subscribed '
      'subscribed, $daysEarned ${daysEarned == 1 ? 'day' : 'days'} earned'
      '${pending > 0 ? ', $pending pending' : ''}';

  static const String codeApplyFailed =
      'Could not apply that code. Please try again.';

  static const String codeApplied = 'Code applied — +7 days PRO added!';
  static const String codeAlreadyApplied = 'Code already applied.';

  static const String noticeDismissLabel = 'Dismiss referral credit notice';
  static const String noticeOpenHint = 'Opens your invite code';
}
