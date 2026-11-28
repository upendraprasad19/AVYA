/// What `public.referrer_summary()` (migration 160) tells a referrer about the
/// friends who used their code. Aggregates only: no names, no payment time, no
/// plan class (founder decision 2026-10-16, unit C of
/// `docs/plans/referral-unit-c-client.md`).
///
/// `joined` = friends who used the code; `subscribed` = friends who
/// subscribed; `pending` = subscribed and not yet credited (the 7-day hold);
/// `credited` = friends whose reward was paid; `daysEarned` = PRO days
/// credited to the referrer.
class ReferrerSummary {
  final int joined;
  final int subscribed;
  final int pending;
  final int credited;
  final int daysEarned;

  const ReferrerSummary({
    required this.joined,
    required this.subscribed,
    required this.pending,
    required this.credited,
    required this.daysEarned,
  });

  /// Parses the RPC body. Accepts a `Map` and a one-row `List` of maps (the
  /// two shapes PostgREST has been seen to return for a scalar-returning
  /// function). A missing, non-int or negative field makes the WHOLE object
  /// unknown (`null`): the surface hides itself, it never shows a wrong number
  /// and never shows zeros that were not read.
  static ReferrerSummary? tryParse(Object? raw) {
    Object? body = raw;
    if (body is List) {
      if (body.length != 1) return null;
      body = body.first;
    }
    if (body is! Map) return null;
    int? field(String key) {
      final v = body is Map ? body[key] : null;
      return v is int && v >= 0 ? v : null;
    }

    final joined = field('joined');
    final subscribed = field('subscribed');
    final pending = field('pending');
    final credited = field('credited');
    final daysEarned = field('days_earned');
    if (joined == null ||
        subscribed == null ||
        pending == null ||
        credited == null ||
        daysEarned == null) {
      return null;
    }
    return ReferrerSummary(
      joined: joined,
      subscribed: subscribed,
      pending: pending,
      credited: credited,
      daysEarned: daysEarned,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReferrerSummary &&
      other.joined == joined &&
      other.subscribed == subscribed &&
      other.pending == pending &&
      other.credited == credited &&
      other.daysEarned == daysEarned;

  @override
  int get hashCode =>
      Object.hash(joined, subscribed, pending, credited, daysEarned);
}
