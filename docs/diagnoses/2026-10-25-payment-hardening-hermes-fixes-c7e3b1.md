---
bug_id: c7e3b1
date: 2026-10-25
batch: payment-hardening (commit 6, the hermes-pass fixes; report docs/audit/2026-10-25-hermes-payment-hardening.md)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  The end-of-batch hermes pass (four Sonnet seats, lenses L1 L2 L21 L22 L23 L29 L40) found, in the five
  payment-hardening commits and the code they sit in: (H12, P2) razorpay-webhook CAPTURED an authorized payment
  and only then answered 400 for a missing or malformed notes.user_id, so the money was taken with no row it could
  ever write; (H1, P2) a refused Razorpay order answered 502, which the client's callFunction retries up to three
  times, so one tap spent up to four of the 30 hourly order units; (H10, P3) the four outer catch-alls logged the
  whole error as a second console argument, and a req.json() SyntaxError quotes the request body in its message;
  (H11) create-razorpay-order logged an unknown, client-supplied promo code (bounded) on refusal; (H8) the two
  "does not match any plan" lines named no payment id; (H9) a repeat use of a code by the same user (23505 on
  UNIQUE(code, user_id)) logged as an error; (H2) the founder digest read "none" for create_order and
  promo_validate while DISABLE_ORDER_ABUSE_GUARDS was on; (H6) the abuse-limit counters inflated "Top users";
  (H3) the switch name was spelled in two functions and validate-promo said "Try again in an hour" for a fixed
  UTC bucket that can end in a minute; (H7) the payment_log_safety registry entry missed two scanned files and
  carried an unread key.
concept: payment_log_safety, create_order_rate_limit, webhook_already_captured_recovery — the hermes-pass corrections to the batch's three new contracts.
sot_registry_entry: payment_log_safety
writers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "handler: the notes.user_id refusals (missing -> 400, not a UUID -> 400), now ahead of the payment.authorized capture block (H12)", line: 499 }
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "handler: the refused Razorpay order answers `guardsOn ? 500 : 502` (H1)", line: 378 }
  - { file: supabase/functions/_shared/payment_log_safe.ts, method_or_widget: "stackFrames(err, n = 3): frames only, never the message line (H10)", line: 43 }
  - { file: supabase/functions/_shared/order_abuse_guards.ts, method_or_widget: "ORDER_ABUSE_GUARDS_DISABLE_ENV, retryMinutes, secondsLeftInBucket (H3)", line: 8 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "NON_ACTIVITY_KEYS + QUOTA_KILL_SWITCHES (H6, H2)", line: 289 }
readers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "handler: the capture POST of an authorized payment, reachable only past the user_id refusals", line: 556 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "callFunction: retries a FunctionException with status 502/503/504 (not 500)", line: 528 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: "createOrder catch: any non-409 FunctionException shows _extractServerError(details), the same text for 500 and 502", line: 266 }
  - { file: supabase/functions/validate-promo/index.ts, method_or_widget: "the rate refusal names the wait (rateLimitedReason(retryAfterSeconds))", line: 106 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: "shows `reason` verbatim when valid is not true", line: 237 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/payment_log_safety_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["[verify-payment|razorpay-webhook] promo redemption: repeat use by this user, audit row already exists (info, was error)"]
  failure: ["[<fn>] request_id=<id> unhandled <ErrorName> at <frames> (the catch-alls; was the whole error)", "[create-razorpay-order] promo refused: <usability> code_length=<n> (was the bounded code)"]
cross_account_guard: "unchanged: the webhook's notes.user_id checks keep their text and bodies and only move ahead of the capture; the order and promo counters stay keyed by the JWT caller."
forbidden_patterns_checked:
  - "a kill switch for the H12 move: REJECTED, same reasoning as U1 (F-2): an old path would keep 'capture a payment with no usable user id' reachable, and the move reorders two existing refusals whose bodies are unchanged."
  - "moving the plan derivation ahead of the capture as well (B-pass bfaeb6fb79da finding 4): NOT in this commit; it changes the B2a amount_no_match alert's meaning in both writers and needs the shared-account question answered live, so it is filed as OI-409 with that question."
  - "refunding the order unit on a refused Razorpay order (H1): REJECTED, refund_quota takes an AI reservation id, not a counter key; changing the status the client retries on is the smaller fix."
  - "dropping the catch-all logs (H10): REJECTED, the name and frames are what an outage needs; only the message (which can carry the body) goes."
proposed_fix: >-
  H12: move the notes extraction and the two user_id refusals, unchanged, from after the capture block to directly
  after the H-19 idempotency pre-SELECT, so a payment.authorized event with no or a malformed notes.user_id is
  answered 400 while the payment is only authorized (Razorpay auto-refunds uncaptured payments). H1: `err(guardsOn
  ? 500 : 502, ...)`; the switch keeps the origin's 502. H10: `stackFrames()` in payment_log_safe.ts (the stack after the message only, each frame escaped and bounded); each catch-all
  logs `request_id=<id> unhandled ${errorName(e)} at ${stackFrames(e)}`; the log contract loses its two-argument
  exception list and pins the four lines inside their outer catch. H11: log `refused: <usability>
  code_length=<n>`. H8: `payment_id=` on both "does not match any plan" lines. H9: a 23505 on the promo_code_uses
  insert is an info line (UNIQUE(code, user_id), migration 025, verified live). H2/H6: QUOTA_KILL_SWITCHES maps
  create_order and promo_validate to DISABLE_ORDER_ABUSE_GUARDS; NON_ACTIVITY_KEYS adds delete_account,
  verify_payment, create_order, promo_validate. H3: _shared/order_abuse_guards.ts holds the switch name and the wait
  wording; create-razorpay-order re-exports them; validate-promo's refusal reads "Try again in N minutes". H7: the
  registry entry gains validate-promo and payment_alert.ts as readers and a `regression_test:` key in place of the
  unread `behavioral_test_path_writers:`.
regression_test_planned:
  - "razorpay-webhook/index_test.ts 'H12:' (missing and malformed user_id on payment.authorized: 400 and zero capture POSTs, with the frozen origin handler capturing once as the positive control; a valid user_id: one capture, one row) and 'H9:'; the 'U0 log' amount-no-match line now carries payment_id."
  - "verify-payment/index_test.ts 'H9:' and the amount-mismatch line with payment_id."
  - "create-razorpay-order/index_test.ts 'H1:' (500 guards on, 502 = origin with the switch set) and 'H11:'; the U0 refused-order test now asserts origin 502 vs new 500."
  - "validate-promo/index_test.ts 'hermes H3:' and the rate refusals checked against the rest of the current UTC hour."
  - "_shared/payment_log_safe_test.ts (stackFrames), _shared/order_abuse_guards_test.ts, _shared/founder_digest_content_test.ts (H2), founder-digest/index_test.ts (H6, one test per key)."
  - "test/contracts/payment_log_safety_writer_to_reader_test.dart (no two-argument exception; each catch-all line exactly once, inside the outer catch), test/contracts/webhook_already_captured_recovery_writer_to_reader_test.dart (the user_id refusals precede the authorized branch and the capture POST), promo_validate_rate_limit_writer_to_reader_test.dart (repointed to rateLimitedReason)."
mutation_proof: >-
  Scratchpad ph/mutate_c6.py: 21 mutants, each computed and anchor-asserted before any write, restored and sha256-
  compared in `finally`, `git diff --stat` identical after. All red: H12 unhoist (2 Deno), H1 always 502 (2), H1
  always 500 (1), H10 frames keep the message (2), H10 n ignored (1), H11 code back (1), H8 webhook id (1), H8
  verify-payment id (1), H9 code 23503 in each writer (1 each), H9 info line at error level in each writer (1
  each), H2 drop create_order (2), H2 drop promo_validate (2), H6 drop verify_payment (1), H6 drop delete_account
  (1), H3 validate-promo "an hour" (1), H3 validate-promo whole hour (2), H3 create-order whole hour (1), H3 bucket
  floor 0 (1), H3 switch name (3). One survivor on the first run: the H9 info line logged with console.error stayed
  green because the assertion looked for "promo_code_uses" in error lines and the info line does not contain it;
  the assertion now forbids any error line about "promo redemption", and both level mutants are red. Dart: a
  catch-all reverted to the two-argument form reddens 3 log-contract tests; the H12 unhoist reddens the new
  ordering pin (1). B-pass bfaeb6fb79da (20 reviewer mutants, all red but two) found that stackFrames kept a
  message line holding a newline and "at " as a frame, unescaped (finding 1, P2), and that no Deno test triggered a
  catch-all (finding 2: the reviewer's catch-all mutants stayed green in Deno). Fixed: stackFrames reads the stack
  only after the message (a message the stack lacks gives no_stack), escapes and bounds each frame; a 'catch-all:'
  Deno test per authenticated door posts an unparseable body with a newline and "at ". Mutants after the fix, all
  red: the old split (2), no escape (1), no bound (1), no fail-closed on a lost message (1), validate-promo
  catch-all back to two arguments (1), create-order catch-all printing the message (1), verify-payment catch-all
  back to two arguments (1). Delta B-pass aabb2b0dbdbb (18 mutants) left four green: the C1 and format-character
  escapes were unpinned (finding 2) and the webhook catch-all had no Deno test (finding 3); it also found that a
  throwing `stack`/`message` getter made stackFrames throw inside the catch-all, and that a non-string message
  scanned the whole stack (finding 5). Fixed: a C1 + Cf frame fixture, a signed-unparseable-body webhook test
  (harness `signedRawWebhookRequest`), stackFrames wrapped in try/catch and `no_stack` for a non-string message.
  Mutants after the fix, all red: no Cf (1), no C1 (1), no try/catch (1), non-string message read as empty (1,
  re-run in a form that compiles after the first attempt was a type error), webhook catch-all printing the message
  (1). Self-attested.
impact_analysis: >-
  A payment with a valid notes.user_id (every order the app creates) takes the same requests and gets the same
  answers as before; only a payment.authorized event with no or a malformed user_id changes, from capture-then-400
  to 400 without a capture. A refused Razorpay order shows the same text in the app (500 and 502 both reach
  _extractServerError) and is no longer retried, with the guards on. The rate-limit text in the paywall changes
  from "an hour" to the real minutes. Log lines change as listed in telemetry_op_types. The digest changes only
  while the switch is on (UNMETERED) and in the Top users totals.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "supabase_service.dart:528 retries 502/503/504 only (retryOn500 is not set for create-razorpay-order); razorpay_service.dart:266 shows the server text for any non-409; paywall_sheet.dart:237 shows `reason` verbatim" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "live pg_constraint on public.promo_code_uses (2026-10-25): promo_code_uses_code_user_unique UNIQUE (code, user_id), the pkey on id, two FKs; so a 23505 on that insert is a repeat use by the same user" }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "six functions change (verify-payment, razorpay-webhook, create-razorpay-order, validate-promo, founder-digest, telegram-admin-bot); each deploy is a founder-gated live step after the merge (closure PH-DEPLOYS)" }
  - { tier: 11, name: "External services", status: verified, evidence: "Razorpay auto-refunds a payment left authorized and not captured; the H12 400 leaves it uncaptured (the capture POST is never sent, tested)" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "create-razorpay-order writes notes.user_id = the JWT caller on every order, so the app's own payments pass the webhook's checks before the capture as before" }
recurrence: >-
  H12 is a recurrence of bug class 2.121 (a service-role path performs its side effect before the authorization
  check that should gate it): b5e8d2 fixed it in verify-payment in this very batch, and the twin writer
  (razorpay-webhook) kept the same "capture, then check notes.user_id" order. The known-good fix is applied as in
  b5e8d2: the checks move, unchanged, ahead of the side effect; the ORDER is pinned in source and the side effect's
  ABSENCE is tested. The other findings are not recurrences of a recorded class; H10 is the catch-all exception
  U0 kept deliberately and the hermes pass showed it reachable with body text.
related_bugs:
  - b5e8d2
  - c8f229
  - d1a4f6
  - f2c9a8
---

# Payment hardening: the hermes-pass fixes

## What was wrong

The batch fixed verify-payment's "capture before the ownership check" (b5e8d2) but its twin, the webhook, still
captured a `payment.authorized` payment before checking that the notes named a user it could record. The other
findings tighten what the batch's own new code logs, answers and counts: see `symptom`.

## Writer and reader

H12 writer: the two refusals at `razorpay-webhook/index.ts:499` and `:513`; reader that must stay behind them: the
capture POST at `:556`. H1 writer: `create-razorpay-order/index.ts:378`; reader: the client's retry set at
`supabase_service.dart:528`. The rest: `writers` / `readers` above.

## The fix

See `proposed_fix`. No kill switch for H12 (as U1). H1 and the H3 wording sit inside the existing
`DISABLE_ORDER_ABUSE_GUARDS` switch, whose OFF path keeps the origin's 502 (tested against the frozen origin
handler).
