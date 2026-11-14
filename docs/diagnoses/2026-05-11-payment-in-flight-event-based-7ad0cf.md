---
bug_id: 7ad0cf
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `SubscriptionService` payment grace window was a pure time-based `paymentInFlightUntil` ISO timestamp. Two pathologies — (a) a slow webhook past 10 min flips grace to false even though we're still legitimately awaiting verdict, so refreshFromSupabase / verifyFromServer can downgrade a paying user; (b) a fast confirmation in 5s leaves the window open for another 9:55, masking unrelated downgrade events during that window (e.g. server returns is_pro=false for a different reason and the grace check suppresses it).
concept: payment_in_flight_event_based
sot_registry_entry: subscription_payment_grace
writers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: markPaymentInFlight + clearPaymentInFlight, line: 116 }
readers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: isPaymentInFlight + paymentInFlightOrderId, line: 96 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: _handlePaymentSuccess + verify / webhook paths, line: 308 }
hive_key_prefix: "userBox: paymentInFlightOrder (new), paymentInFlightUntil (legacy)"
hive_key_formula: "paymentInFlightOrder = { order_id, started_at_iso }"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: []
contract_test_path: test/subscription/payment_grace_window_test.dart
ist_handling: []
provider_invalidations: [subscriptionInfoProvider]
telemetry_op_types:
  success: [subscription_state_written]
  failure: [subscription_write_failure]
cross_account_guard: n/a
forbidden_patterns_checked: ["payment_grace_purely_time_based"]
proposed_fix: Replace `_paymentInFlightUntilKey` (ISO timestamp) with `_paymentInFlightOrderKey` storing `{ order_id, started_at }`. `markPaymentInFlight(orderId: response.orderId)` records the Razorpay order_id from `_handlePaymentSuccess`. `isPaymentInFlight` evaluates as `(order record exists AND now - started_at < 10min ceiling)`. Clear is event-based — webhook lands OR verify-payment returns final verdict OR explicit `clearPaymentInFlight()`. The 10-min ceiling preserved ONLY as fallback safety cap. Legacy `paymentInFlightUntil` key is read once for back-compat and superseded on the next event-based write.
regression_test_planned:
  - test/subscription/payment_grace_window_test.dart (5 cases — absent / set / clear / expired event-based / legacy back-compat)
---
# Audit H-41: payment grace window was purely time-based

## Bug

`SubscriptionService.markPaymentInFlight()` stamped `now + 10min` to
`MigratedKey('paymentInFlightUntil')`. `isPaymentInFlight` returned
`now < until`. Two pathologies:

1. **Slow webhook >10 min.** Razorpay typically fires the webhook
   within 30s, but retry storms / production webhook delays can push
   it past 10 min. The grace window flips to `false`. Next
   `refreshFromSupabase` or `verifyFromServer` query returns
   `is_pro: false` (subscription row not yet written), triggers
   `_downgradeLocally()`, and the paying user sees the upgrade pill
   stuck on GO PRO. APK Test #12 / C-4 closed a similar class but the
   underlying time-only design persisted.
2. **Fast confirm <10 min leaves the window open.** Webhook fires in
   5s, `clearPaymentInFlight()` runs, BUT the 9:55 grace window is
   already past. During that residual window, an unrelated downgrade
   event (legitimate cancellation, subscription expired) would be
   suppressed by `isPaymentInFlight=true`. UI keeps showing PRO until
   the next cold start.

## Cause

Time windows are a fragile proxy for the actual signal — "did the
server confirm this specific payment yet?". The event-based handle
exists (Razorpay's `order_id` + the webhook + verify-payment
response) but was never used.

## Fix

Replace the ISO timestamp key with an event-based record:

```dart
static const String _paymentInFlightOrderKey = 'paymentInFlightOrder';

Future<void> markPaymentInFlight({String? orderId}) async {
  final startedAt = DateTime.now().toIso8601String();
  await MigratedKey.write(_paymentInFlightOrderKey, {
    'order_id': orderId ?? '',
    'started_at': startedAt,
  });
  // Clear the legacy key so the two shapes don't co-exist.
  await MigratedKey.delete(_paymentInFlightUntilKey);
}

bool get isPaymentInFlight {
  final rec = MigratedKey.read<dynamic>(_paymentInFlightOrderKey);
  if (rec is Map) {
    final startedAt = DateTime.tryParse((rec['started_at'] ?? '').toString());
    if (startedAt != null) {
      return DateTime.now().difference(startedAt) < _paymentGraceWindow;
    }
  }
  // Legacy fallback for one-time post-upgrade read.
  ...
}
```

Plus a new public getter `paymentInFlightOrderId` so webhook /
verify-payment handlers can correlate.

The 10-min ceiling is preserved ONLY as a fallback safety cap (if the
clear path is missed somehow — network drop after webhook, app killed
mid-verify), not as the primary signal. The canonical clear path is
event-based:

- `RazorpayService` webhook-confirmed branch → `clearPaymentInFlight()`.
- `RazorpayService.verifyPayment` final-verdict branch (success OR
  explicit final failure) → `clearPaymentInFlight()`.
- Subscription-state writes after server confirms → `clearPaymentInFlight()`.

`RazorpayService._handlePaymentSuccess` now passes
`markPaymentInFlight(orderId: response.orderId)`.

## Back-compat

Legacy `paymentInFlightUntil` is read once at the bottom of
`isPaymentInFlight` for installs that upgraded across this refactor.
The first event-based `markPaymentInFlight()` write deletes the
legacy key.

## Regression test

`test/subscription/payment_grace_window_test.dart` — 5 cases:

1. `isPaymentInFlight` is `false` when key absent.
2. `markPaymentInFlight(orderId)` records the event-based shape;
   `paymentInFlightOrderId` exposes the order_id; legacy key cleared.
3. `clearPaymentInFlight` removes the event-based marker AND any
   legacy key.
4. An event-based record with `started_at` older than 10 min is
   treated as not-in-flight (fallback ceiling).
5. Legacy `paymentInFlightUntil` key is honoured for back-compat.

Suite: 1560 pass / 0 fail / 2 skip.

## Related

- APK Test #12 / Task C-1 (introduced the time-based grace window)
- 7ad0c1 / 7ad0c4 (Phase 1 — payment-stack hardening)
