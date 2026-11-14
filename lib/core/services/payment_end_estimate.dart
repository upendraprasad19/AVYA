/// Pure decisions behind a stacked trial purchase (OI-341 Piece B2b,
/// `docs/plans/oi341-piece-b2b-client.md` 2.2). No Flutter, no Hive, no
/// network, so every row is testable (`test/core/payment_end_estimate_test.dart`).
///
/// The server's `stacks_after` (the latest trial end, from
/// `create-razorpay-order` when its door is open) only shapes a local
/// ESTIMATE: the writers compute the real stacked end and their stored
/// `end_date` overwrites this on every path.
library;

import 'package:icanbefitter/core/constants/subscription_plans.dart';
import 'package:icanbefitter/core/copy/payment_copy.dart';

/// A value further out than this (10 years) is refused: it would sit in the local
/// expiry until the server overwrites it.
const Duration kStacksAfterMaxAhead = Duration(days: 3650);

/// A time part (`T` or a space) followed, at the very end, by `Z` or a
/// `+hh:mm` / `-hh:mm` offset. A date-only string has no time part, so its
/// `-29` can never read as an offset.
final RegExp _offsetAfterTime =
    RegExp(r'[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$');

/// The server's `stacks_after`, or null for anything that is not an
/// offset-carrying timestamp within [kStacksAfterMaxAhead] of [now]. Total:
/// never throws (it runs inside the order call's `try`).
DateTime? parseStacksAfter(Object? raw, {required DateTime now}) {
  if (raw is! String) return null;
  final s = raw.trim();
  if (!_offsetAfterTime.hasMatch(s)) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  if (parsed.isAfter(now.add(kStacksAfterMaxAhead))) return null;
  return parsed;
}

/// The local end-date estimate after a payment: plan days from the later of
/// [now] and [stacksAfter]. Local ISO string (no `Z`), the shape the old
/// `_computeEndDate` wrote, whatever zone the inputs carry.
String estimatePaidEndDate({
  required String plan,
  DateTime? stacksAfter,
  required DateTime now,
}) {
  final base =
      (stacksAfter != null && stacksAfter.isAfter(now)) ? stacksAfter : now;
  final days = plan == 'yearly' ? 365 : 30;
  return base.toLocal().add(Duration(days: days)).toIso8601String();
}

/// What `openCheckout` recorded for one order.
class PendingCheckout {
  final String plan;
  final DateTime? stacksAfter;
  const PendingCheckout({required this.plan, this.stacksAfter});
}

/// Recorded checkouts keyed by order id, so a payment confirmed after a LATER
/// checkout started still reads its own plan and stacks-after. Bounded; the
/// oldest record is evicted first.
class PendingCheckouts {
  static const int maxEntries = 4;
  final Map<String, PendingCheckout> _byOrderId = {};

  bool get isEmpty => _byOrderId.isEmpty;

  void record(String orderId, PendingCheckout checkout) {
    _byOrderId.remove(orderId);
    _byOrderId[orderId] = checkout;
    while (_byOrderId.length > maxEntries) {
      _byOrderId.remove(_byOrderId.keys.first);
    }
  }

  PendingCheckout? lookup(String? orderId) =>
      (orderId == null || orderId.isEmpty) ? null : _byOrderId[orderId];

  void clear() => _byOrderId.clear();
}

/// The plan and stacks-after for a confirmed payment. A recorded order gives
/// its own record (`matched: true`); anything else gives today's behaviour:
/// `pendingPlan ?? 'monthly'` and no stacked estimate.
({String plan, DateTime? stacksAfter, bool matched}) resolveConfirmedCheckout({
  required PendingCheckouts store,
  String? confirmedOrderId,
  String? pendingPlan,
}) {
  final record = store.lookup(confirmedOrderId);
  if (record != null) {
    return (plan: record.plan, stacksAfter: record.stacksAfter, matched: true);
  }
  return (plan: pendingPlan ?? 'monthly', stacksAfter: null, matched: false);
}

enum OrderConflict { alreadyPro, trialUpgradeUnavailable, other }

/// A 409 body from `create-razorpay-order`. With the door shut a trial user's
/// latest row is the trial, so `current_plan` is `referral_trial`.
OrderConflict classifyOrderConflict(Map<String, dynamic> body) {
  if (body['error_code'] != 'already_pro') return OrderConflict.other;
  return body['current_plan'] == kReferralTrialPlan
      ? OrderConflict.trialUpgradeUnavailable
      : OrderConflict.alreadyPro;
}

/// True when a failed order call is a trial row's 409 (door shut). Used where
/// the heal threw, so the fall-through toast keeps the trial copy instead of
/// the server's "You're already a PRO member." text.
bool isTrialRefusal({required int? status, required Object? details}) =>
    status == 409 &&
    details is Map &&
    classifyOrderConflict(Map<String, dynamic>.from(details)) ==
        OrderConflict.trialUpgradeUnavailable;

/// The snackbar text after a 409: the trial copy for a trial row, else
/// today's "already PRO" line, byte-for-byte.
String orderConflictMessage({
  required bool trialUpgradeUnavailable,
  required String endLabel,
}) =>
    trialUpgradeUnavailable
        ? PaymentCopy.trialUpgradeUnavailable
        : 'You\'re already PRO — active until $endLabel';

/// The Razorpay checkout description. Any `stacksAfter` (past or future)
/// means the server said this order stacks, so the notice is appended.
String checkoutDescription({required String plan, DateTime? stacksAfter}) {
  final base = 'PRO ${plan == 'yearly' ? 'Yearly' : 'Monthly'} Plan';
  return stacksAfter == null
      ? base
      : '$base. ${PaymentCopy.trialStackingNotice}';
}
