# Web Razorpay Checkout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sell AVYA PRO in the webapp — replace the "payments are mobile-only" dead end with a working Razorpay Standard Checkout on web (test keys), reusing the existing order/verification pipeline unchanged.

**Architecture:** A thin `dart:js_interop` bridge (modeled on `pwa_install_interop_web.dart`) opens `checkout.js` with the same options map the native path already builds; the web success payload feeds one shared, extracted `handlePaymentConfirmed` so native and web run byte-identical verification. Kill-switch `disable_web_checkout` preserves the old paywall behavior verbatim (§4.6).

**Tech Stack:** Flutter web, `dart:js_interop` (conditional import keyed `dart.library.js_interop`), Razorpay Standard Checkout.js, existing Supabase EF pipeline (untouched).

**Spec:** `docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md`

**Worktree:** `.claude/worktrees/web-razorpay-checkout` (branch `web-razorpay-checkout`, base `c4eee5e0`). ALL work happens there. `.env` is copied.

**Discipline notes for the executor:**
- Commits via `sh scripts/safe_commit.sh "<msg>"` (raw `git commit` is hook-blocked). Push later via `scripts/safe_push.sh` when founder asks.
- Pre-commit runs gates only (lean path); analyze + full suite run at pre-push — run targeted tests during dev, not the full suite (ADR-0018 split).
- `dart:js_interop` is a platform library — the `_web.dart` file is analyzed on every platform; type errors inside it surface at **web compile**, so Task 6's `flutter build web` verification is load-bearing, not optional.
- Two spec deviations, deliberate, to be visible to reviewers: (1) the callback keys (`handler`/`modal.ondismiss`) are injected by the web impl directly — `jsify` does NOT convert Dart functions, so a pure-map injection helper would be wrong; the pure parity pin is instead `buildRazorpayCheckoutOptions` (Task 2). (2) checkout.js has **no failure callback** — failures surface inside Razorpay's own modal and reach us as `ondismiss` (mapped to the existing `PAYMENT_CANCELLED` no-snackbar path), so the spec's "error-snackbar equivalent" exists only for the SDK-unavailable case (`onUnavailable`).

---

### Task 1: Barrel + pure functions + web bridge + stub (all three Dart files — the barrel's conditional import needs all of them to compile)

**Files:**
- Create: `lib/core/services/razorpay_web_checkout.dart` (barrel + pure functions)
- Create: `lib/core/services/razorpay_web_checkout_web.dart` (web bridge — created here, first USED in Task 4)
- Create: `lib/core/services/razorpay_web_checkout_stub.dart`
- Test: `test/contracts/razorpay_web_success_payload_test.dart`
- Test: `test/contracts/razorpay_web_kill_switch_test.dart`

- [ ] **Step 1: Write the failing payload test**

```dart
// test/contracts/razorpay_web_success_payload_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/razorpay_web_checkout.dart';

void main() {
  group('parseWebSuccessPayload — web success → shared-pipeline fields', () {
    test('full payload maps all three fields', () {
      final r = parseWebSuccessPayload({
        'razorpay_payment_id': 'pay_Q123',
        'razorpay_order_id': 'order_Q456',
        'razorpay_signature': 'sig789',
      });
      expect(r.paymentId, 'pay_Q123');
      expect(r.orderId, 'order_Q456');
      expect(r.signature, 'sig789');
    });

    test('missing fields are null, never thrown', () {
      final r = parseWebSuccessPayload({});
      expect(r.paymentId, isNull);
      expect(r.orderId, isNull);
      expect(r.signature, isNull);
    });

    test('null values are null-safe', () {
      final r = parseWebSuccessPayload({
        'razorpay_payment_id': null,
        'razorpay_order_id': 12345,
      });
      expect(r.paymentId, isNull);
      expect(r.orderId, '12345'); // non-string coerced via toString
      expect(r.signature, isNull);
    });

    test('field names are EXACTLY the checkout.js contract (writer/reader pin)',
        () {
      // Guards against renaming to payment_id/order_id — the JS side of this
      // contract is Razorpay's, not ours; drift here silently nulls the id
      // that verify-payment polls by.
      final r = parseWebSuccessPayload({'payment_id': 'x'});
      expect(r.paymentId, isNull); // wrong key name must NOT be read
    });
  });
}
```

- [ ] **Step 2: Write the failing kill-switch test**

```dart
// test/contracts/razorpay_web_kill_switch_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/razorpay_web_checkout.dart';

void main() {
  group('isWebCheckoutDisabledByConfig — §4.6 kill-switch convention', () {
    test('absent (null) ⇒ ACTIVE (checkout enabled)', () {
      expect(isWebCheckoutDisabledByConfig(null), isFalse);
    });
    test('true ⇒ disabled (old mobile-only behavior)', () {
      expect(isWebCheckoutDisabledByConfig(true), isTrue);
    });
    test('false ⇒ ACTIVE', () {
      expect(isWebCheckoutDisabledByConfig(false), isFalse);
    });
    test("string 'true' ⇒ ACTIVE (type-strict, matches isSyncAutoDrainDisabled)",
        () {
      expect(isWebCheckoutDisabledByConfig('true'), isFalse);
    });
  });
}
```

- [ ] **Step 3: Run both — expect FAIL (file/barrel doesn't exist)**

Run: `flutter test test/contracts/razorpay_web_success_payload_test.dart test/contracts/razorpay_web_kill_switch_test.dart`
Expected: compile errors (`razorpay_web_checkout.dart` not found).

- [ ] **Step 4: Implement the barrel + pure functions + web bridge + stub**

First the barrel:

```dart
// lib/core/services/razorpay_web_checkout.dart
/// Web Razorpay checkout — selection barrel + pure mappings.
///
/// The JS-interop implementation (`razorpay_web_checkout_web.dart`) is
/// selected ONLY on web via the conditional import below, keyed on
/// `dart.library.js_interop` (modern web interop — NOT the deprecated
/// dart:html used by lib/features/dev/xls_saver_web.dart). Pattern
/// precedent: lib/shared/widgets/pwa_install/pwa_install_interop_*.dart.
/// The stub guarantees the Android/iOS build never references web libs.
///
/// Spec: docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md
library;

import 'razorpay_web_checkout_stub.dart'
    if (dart.library.js_interop) 'razorpay_web_checkout_web.dart' as impl;

/// Pure mapping of Razorpay Standard Checkout's web success payload onto
/// the three fields the native SDK's PaymentSuccessResponse carries —
/// the shared verification pipeline consumes identical values on both
/// platforms. Field names are Razorpay's checkout.js contract; a rename
/// here silently nulls the id verify-payment polls by.
({String? paymentId, String? orderId, String? signature})
    parseWebSuccessPayload(Map<String, dynamic> raw) {
  String? ns(Object? v) => v == null ? null : v.toString();
  return (
    paymentId: ns(raw['razorpay_payment_id']),
    orderId: ns(raw['razorpay_order_id']),
    signature: ns(raw['razorpay_signature']),
  );
}

/// §4.6 kill-switch predicate — pure, testable form (mirrors
/// `isSyncAutoDrainDisabled`, sync_state_provider.dart:43). configBox key
/// `disable_web_checkout`: absent or anything but `true` ⇒ web checkout
/// ACTIVE, so a missing/unopened configBox can never silently disable
/// payments. The defensive configBox wrapper is
/// `RazorpayService.webCheckoutDisabled`.
bool isWebCheckoutDisabledByConfig(Object? rawConfigValue) =>
    rawConfigValue == true;

/// Barrel entry — delegates to the selected implementation.
void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function() onDismissed,
  required void Function(String message) onUnavailable,
}) =>
    impl.openWebCheckout(
      options: options,
      onSuccess: onSuccess,
      onDismissed: onDismissed,
      onUnavailable: onUnavailable,
    );
```

Then the web bridge:

```dart
// lib/core/services/razorpay_web_checkout_web.dart
// Web implementation of the Razorpay checkout bridge (spec 2026-09-17).
// Selected by the conditional import in razorpay_web_checkout.dart keyed
// `dart.library.js_interop`. MUST NOT be imported directly by native-facing
// code — the barrel is the only entry point.
//
// ⚠ checkout.js has NO failure callback: card failures/retries happen
// inside Razorpay's own modal; the only close signal is modal.ondismiss.
// onUnavailable covers the SDK-unavailable case (script blocked/offline).
//
// Spec: docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md

import 'dart:js_interop';

extension type RazorpayCheckoutInstance._(JSObject _) implements JSObject {
  external void open();
}

@JS('Razorpay')
external JSFunction get _razorpayCtor;

void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function() onDismissed,
  required void Function(String message) onUnavailable,
}) {
  try {
    final jsOptions = options.jsify();
    if (jsOptions is! JSObject) {
      onUnavailable("Couldn't start payment. Check your connection and try again.");
      return;
    }
    jsOptions['handler'] = ((JSObject resp) {
      final raw = resp.dartify();
      onSuccess(raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{});
    }).toJS;
    final modal = JSObject();
    modal['ondismiss'] = (() => onDismissed()).toJS;
    jsOptions['modal'] = modal;

    final instance = _razorpayCtor
        .callAsConstructor<RazorpayCheckoutInstance>(jsOptions);
    instance.open();
  } catch (_) {
    // SDK missing (checkout.js blocked/offline) or construction failure —
    // actionable failure, never a silent swallow (rule 17: release error
    // handling must surface something to the user).
    onUnavailable("Couldn't start payment. Check your connection and try again.");
  }
}
```

Then the stub:

```dart
// lib/core/services/razorpay_web_checkout_stub.dart
// Non-web stub for the Razorpay checkout bridge (spec 2026-09-17).
// razorpay_service only calls openWebCheckout behind kIsWeb, but the stub
// guarantees the Android/iOS build never references dart:js_interop (same
// rule as lib/shared/widgets/pwa_install/pwa_install_interop_stub.dart:6).
// The parsed-payload + kill-switch PURE functions live in the barrel and
// are importable on every platform.

/// No-op off-web. onUnavailable fires on native callers, but there are
/// none — the kIsWeb branch is the only caller.
void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function() onDismissed,
  required void Function(String message) onUnavailable,
}) {
  onUnavailable('Payments are only available on web or the mobile app.');
}
```

- [ ] **Step 5: Run both — expect PASS (4 + 4 tests)**

Run: `flutter test test/contracts/razorpay_web_success_payload_test.dart test/contracts/razorpay_web_kill_switch_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/razorpay_web_checkout.dart lib/core/services/razorpay_web_checkout_web.dart lib/core/services/razorpay_web_checkout_stub.dart test/contracts/razorpay_web_success_payload_test.dart test/contracts/razorpay_web_kill_switch_test.dart
sh scripts/safe_commit.sh "feat(web): razorpay checkout barrel — pure web-success mapping, kill-switch predicate, checkout.js bridge + native stub"
```

---

### Task 2: Extract `buildRazorpayCheckoutOptions` (parity pin, no behavior change)

**Files:**
- Modify: `lib/core/services/razorpay_service.dart` (`openCheckout`, options map currently built inline at `:225-239`)
- Test: `test/contracts/razorpay_checkout_options_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/razorpay_checkout_options_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';

void main() {
  group('buildRazorpayCheckoutOptions — order/amount parity pin', () {
    test('carries SERVER order_id and amount — never client-computed', () {
      final o = RazorpayService.buildRazorpayCheckoutOptions(
        keyId: 'rzp_test_x',
        orderId: 'order_server_made',
        amountPaise: 34900,
        plan: 'monthly',
        email: 'u@x.com',
        notes: {'user_id': 'uid', 'plan': 'monthly'},
      );
      expect(o['order_id'], 'order_server_made');
      expect(o['amount'], 34900);
      expect(o['currency'], 'INR');
    });

    test('notes flow through (user_id + promo reach the webhook)', () {
      final o = RazorpayService.buildRazorpayCheckoutOptions(
        keyId: 'k', orderId: 'o', amountPaise: 1, plan: 'yearly',
        email: '', notes: {'user_id': 'u', 'plan': 'yearly', 'promo_code': 'X'},
      );
      expect((o['notes'] as Map)['promo_code'], 'X');
      expect((o['prefill'] as Map)['email'], '');
    });

    test('plan label switches Yearly/Monthly', () {
      final y = RazorpayService.buildRazorpayCheckoutOptions(
        keyId: 'k', orderId: 'o', amountPaise: 1, plan: 'yearly',
        email: '', notes: const {},
      );
      expect(y['description'], 'PRO Yearly Plan');
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL (static method doesn't exist)**

Run: `flutter test test/contracts/razorpay_checkout_options_test.dart`
Expected: compile error (`buildRazorpayCheckoutOptions` not defined).

- [ ] **Step 3: Extract the static + wire `openCheckout` to use it**

In `razorpay_service.dart`, add (near the top of the class, after the fields):

```dart
  /// The single source of the checkout options map — built from the
  /// SERVER-derived order_id + amount (plan-derived-from-amount security
  /// rule, docs/architecture/payment.md §1). Consumed by BOTH the native
  /// open and the web open. @visibleForTesting so the web contract test can
  /// pin order_id/amount parity without a network round-trip.
  @visibleForTesting
  static Map<String, dynamic> buildRazorpayCheckoutOptions({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String plan,
    required String email,
    required Map<String, String> notes,
  }) {
    return {
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'name': AppConstants.appName,
      'description': 'PRO ${plan == 'yearly' ? 'Yearly' : 'Monthly'} Plan',
      'currency': 'INR',
      'prefill': {
        'email': email,
      },
      'notes': notes,
      'theme': {
        'color': '#D4B270',
      },
    };
  }
```

Then in `openCheckout`, replace the inline map at `:225-239` with:

```dart
    final options = buildRazorpayCheckoutOptions(
      keyId: keyId,
      orderId: orderId,
      amountPaise: amountPaise,
      plan: plan,
      email: user.email ?? '',
      notes: notes,
    );
```

(`import 'package:flutter/foundation.dart'` already present for `kIsWeb`; add `show visibleForTesting` if needed.)

- [ ] **Step 4: Run — expect PASS (3 tests)**

Run: `flutter test test/contracts/razorpay_checkout_options_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/razorpay_service.dart test/contracts/razorpay_checkout_options_test.dart
sh scripts/safe_commit.sh "refactor(payments): extract buildRazorpayCheckoutOptions — platform-neutral parity pin for web checkout"
```

---

### Task 3: Extract shared `handlePaymentConfirmed` (one verification pipeline)

**Files:**
- Modify: `lib/core/services/razorpay_service.dart` (`_handlePaymentSuccess` at `:346-457`)
- Test: `test/contracts/razorpay_web_shared_success_handler_test.dart` (source-grep wiring)

- [ ] **Step 1: Write the failing wiring test**

```dart
// test/contracts/razorpay_web_shared_success_handler_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const srcPath = 'lib/core/services/razorpay_service.dart';
  late String src;

  setUpAll(() {
    src = File(srcPath).readAsStringSync();
  });

  group('shared success handler wiring — native and web feed ONE pipeline', () {
    test('extracted handlePaymentConfirmed exists with the shared signature', () {
      expect(src, contains('Future<void> handlePaymentConfirmed({'));
      expect(src, contains('required String paymentId'));
      expect(src, contains('String? orderId'));
      expect(src, contains('String? signature'));
    });

    test('native _handlePaymentSuccess DELEGATES (body extracted, not duplicated)', () {
      expect(src, contains('void _handlePaymentSuccess(PaymentSuccessResponse'));
      expect(src, contains('handlePaymentConfirmed('));
    });

    test('poll + in-flight mark reachable through the shared method', () {
      expect(src, contains('markPaymentInFlight'));
      expect(src, contains('_pollAndActivate('));
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/contracts/razorpay_web_shared_success_handler_test.dart`
Expected: FAIL — `handlePaymentConfirmed(` not in source yet.

- [ ] **Step 3: Extract the body**

In `razorpay_service.dart`:

1. Rename `void _handlePaymentSuccess(PaymentSuccessResponse response) async {` (line `:346`) to a thin delegator and move the ENTIRE body into the new shared method. The only changes inside the body are the three `response.*` reads:

```dart
  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    unawaited(handlePaymentConfirmed(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId,
      signature: response.signature,
    ));
  }

  /// Platform-neutral confirmation path — the ONE verification pipeline
  /// (native SDK event AND web checkout.js success callback both land
  /// here). Body extracted verbatim from the pre-web-branch
  /// _handlePaymentSuccess; only the response.* plumbing changed.
  /// @visibleForTesting so the wiring test can pin the delegation.
  @visibleForTesting
  Future<void> handlePaymentConfirmed({
    required String paymentId,
    String? orderId,
    String? signature,
  }) async {
    debugPrint('RazorpayService: payment success — '
        'paymentId=$paymentId, orderId=$orderId');
    // ... body continues VERBATIM from the old _handlePaymentSuccess
    // (JWT refresh → optimistic activation block → _showProActivatedFeedback
    // → _onSuccess?.call() → try { await _pollAndActivate(
    //     paymentId: paymentId, orderId: orderId ?? '', signature: signature ?? '')
    //   } → messenger?.clearSnackBars()) ...
  }
```

⚠ The extracted body must be VERBATIM from `:349-456` with exactly these substitutions: `response.paymentId ?? ''` → `paymentId` (top debugPrint keeps the plain value); `markPaymentInFlight(orderId: response.orderId)` → `markPaymentInFlight(orderId: orderId)`; `_pollAndActivate(paymentId: response.paymentId ?? '', orderId: response.orderId ?? '', signature: response.signature ?? '')` → `_pollAndActivate(paymentId: paymentId, orderId: orderId ?? '', signature: signature ?? '')`. Everything else — comment blocks included — untouched.

- [ ] **Step 4: Run — expect PASS (3 tests) + no analyzer regressions**

Run: `flutter test test/contracts/razorpay_web_shared_success_handler_test.dart && flutter analyze --no-fatal-infos lib/core/services/razorpay_service.dart`
Expected: PASS; analyze clean for the file (⚠ per-file analyze is a DIFFERENT input set if `part` files exist here — none do; still run full analyze in Task 6).

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/razorpay_service.dart test/contracts/razorpay_web_shared_success_handler_test.dart
sh scripts/safe_commit.sh "refactor(payments): extract handlePaymentConfirmed — one verification pipeline for native + web"
```

---

### Task 4: Service web branch + index.html script tag

**Files:**
- Modify: `web/index.html` (add checkout.js script tag)
- Modify: `lib/core/services/razorpay_service.dart` (`:241` web branch + `webCheckoutDisabled` getter; the barrel + bridge from Task 1 are first USED here)

- [ ] **Step 1: Add the script tag to `web/index.html`**

In `<head>`, immediately after the `<base href="$FLUTTER_BASE_HREF">` line (`:15`):

```html
  <!-- Razorpay Standard Checkout (web payments, spec 2026-09-17). Loaded
       synchronously in head per Razorpay docs; guarded at call time in
       razorpay_web_checkout_web.dart if blocked/offline. -->
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
```

- [ ] **Step 2: Add `webCheckoutDisabled` + the web branch to `razorpay_service.dart`**

Add imports (top of file):

```dart
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/razorpay_web_checkout.dart';
```

Add the public getter (next to `navigatorKey`):

```dart
  /// §4.6 kill-switch read for the paywall + web branch. Defensive — a
  /// missing/unopened configBox defaults to checkout-ACTIVE (same pattern
  /// as sync_state_provider._autoDrainDisabled).
  bool get webCheckoutDisabled {
    try {
      return isWebCheckoutDisabledByConfig(
          HiveService.instance.configBox.get('disable_web_checkout'));
    } catch (_) {
      return false;
    }
  }
```

Replace `if (kIsWeb) return;` (`:241`) with:

```dart
    if (kIsWeb) {
      if (webCheckoutDisabled) {
        debugPrint('RazorpayService: web checkout disabled by kill-switch');
        onFailure?.call();
        return;
      }
      debugPrint('RazorpayService: opening web checkout — plan=$plan, '
          'order_id=$orderId, amount=$amountPaise paise');
      openWebCheckout(
        options: options,
        onSuccess: (raw) {
          final parsed = parseWebSuccessPayload(raw);
          unawaited(handlePaymentConfirmed(
            paymentId: parsed.paymentId ?? '',
            orderId: parsed.orderId,
            signature: parsed.signature,
          ));
        },
        onDismissed: () {
          // Mirrors the native PAYMENT_CANCELLED path (:466): user closed
          // the modal — call the failure callback WITHOUT the error
          // snackbar. Failures inside the modal surface there, not here.
          debugPrint('RazorpayService: web checkout dismissed');
          onFailure?.call();
        },
        onUnavailable: (message) {
          _showOrderCreationFailure(serverError: message);
          onFailure?.call();
        },
      );
      return;
    }
```

(The native `_razorpay?.open(options);` line below stays exactly as-is.)

- [ ] **Step 3: Verify compile safety + wire-up**

Run: `flutter analyze --no-fatal-infos lib/core/services/` then `flutter build web --dart-define-from-file=.env`
Expected: analyze clean; **web build completes** — this is the ONLY check that type-checks the `dart:js_interop` file (⚠ per-file analyze is a different input set from a web compile; the web file is analyzed everywhere but its JS-constructor typing is only exercised here).

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/razorpay_service.dart web/index.html
sh scripts/safe_commit.sh "feat(web): open Razorpay checkout on web — checkout.js script tag, kill-switch branch, shared success path"
```

---

### Task 5: Paywall web branch — kill-switch preserves the old dead-end verbatim

**Files:**
- Modify: `lib/shared/widgets/paywall_sheet.dart` (`:279-292`)

- [ ] **Step 1: Rewrite the web branch**

Replace `:279-292`:

```dart
    if (kIsWeb) {
      // §4.6 kill-switch — old pre-web-checkout behavior preserved verbatim
      // so rollback needs no redeploy (disable_web_checkout in configBox).
      if (ref.read(razorpayServiceProvider).webCheckoutDisabled) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payments are only available in the mobile app. Download ICANBEFITTER to upgrade.',
              style: AppTypography.bodySm,
            ),
            backgroundColor: AppColors.card,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      // Web checkout active — flow exactly like mobile: sheet pops,
      // openCheckout opens the browser checkout (razorpay_service web branch).
    }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze --no-fatal-infos lib/shared/widgets/paywall_sheet.dart`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/shared/widgets/paywall_sheet.dart
sh scripts/safe_commit.sh "feat(web): paywall opens checkout on web — old mobile-only snackbar preserved behind disable_web_checkout"
```

---

### Task 6: Mutation proofs + full verification (before push)

**Files:**
- Modify: `test/contracts/razorpay_web_success_payload_test.dart` (mutation run only)
- Modify: `test/contracts/razorpay_web_kill_switch_test.dart` (mutation run only)
- Modify: `lib/core/services/razorpay_service.dart` (mutation run only)

- [ ] **Step 1: Mutation 1 — payload field rename.** In `razorpay_web_checkout.dart`, change `raw['razorpay_payment_id']` → `raw['payment_id']`. Run the payload test: expect **exactly the exact-contract test + full-payload test redden** (2 of 4). Confirm the mutation applied first: `git grep -c "raw\['payment_id'\]" -- lib/core/services/razorpay_web_checkout.dart` returns ≥1. Restore.

- [ ] **Step 2: Mutation 2 — kill-switch inversion.** Change `=> rawConfigValue == true;` → `=> rawConfigValue != true;`. Run the kill-switch test: expect **all 4 redden**. Confirm via `git grep -c "rawConfigValue != true"`. Restore.

- [ ] **Step 3: Mutation 3 — options parity.** In `buildRazorpayCheckoutOptions`, change `'amount': amountPaise` → `'amount': 0`. Run the options test: expect the server-amount test to redden. Confirm via `git grep -c "'amount': 0" -- lib/core/services/razorpay_service.dart`. Restore.

- [ ] **Step 4: Record the three mutations (what was mutated, how many reddened) — they go into the plan-review record + commit message of the final test commit.**

- [ ] **Step 5: Full local verification**

```bash
flutter analyze --no-fatal-infos
flutter test test/contracts/razorpay_web_success_payload_test.dart test/contracts/razorpay_web_kill_switch_test.dart test/contracts/razorpay_checkout_options_test.dart test/contracts/razorpay_web_shared_success_handler_test.dart
flutter build web --dart-define-from-file=.env
```

Expected: analyze 0 warnings; 11 tests pass; web build completes.

- [ ] **Step 6: Pre-push runs the full suite (≥platform tier) — let it. Do NOT `--no-verify`.**

---

## Post-implementation (discipline, in order)

1. **×2 plan review FIRST (§4.12):** before ANY of the above tasks execute, dispatch two context-blind reviewers on THIS plan + spec (with `docs/agent_brief_preamble.md` prefix). Fix every material finding. Write `docs/plan-reviews/web-razorpay-checkout.md` (`review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`).
2. Classify the real diff with `scripts/blast_radius_from_diff.dart` after the first implementation commit; platform tier ⇒ `bpass: accepted` in the record; run `/code-review` (B-pass) BEFORE the `--no-ff` merge to `main` (self-initiated, §4.3).
3. Founder E2E on the deployed webapp: test-card success / failure / dismissal → PRO unlocks, expiry correct, webhook grant visible in `subscriptions`.
4. Clean the founder's test subscription rows from prod after verification.
5. Batch close (§5): file auto-renew OI via `scripts/mint_oi.sh`; ADR amending ADR-0005; SoT registry check (`check_sot_registry_parity.dart` will catch stale line ranges — re-run after any edit above the cited lines); memory transition (billing brainstorm → web shipped); §5 checklist; skill self-evolution entries.
