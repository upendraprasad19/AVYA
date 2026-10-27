---
bug_id: b5e8d2
date: 2026-10-24
batch: payment-hardening (unit U1; OI-350, OI-359)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  verify-payment (any signed-in caller, the account's Razorpay credentials) fetched the payment named in the
  request and, BEFORE checking that it belonged to the caller, captured it when it was `authorized` and answered
  `Payment status is '<status>', not 'captured'` with a 200 when it was not captured. So any signed-in user who
  knew another user's `pay_` id could make the server capture that user's authorized payment (money taken from
  them on the caller's say-so) or read its status; the 403 "Payment does not belong to this user" came only once
  the payment was captured. A payment with no `notes.user_id` was likewise captured or echoed before its 400.
  Found by the OI-341 hermes pass (seat 2, L23) on 2026-10-17 (OI-350) and again on 2026-10-20 (OI-359, the same
  defect). OI-359 is a duplicate of OI-350.
concept: verify_payment_owner_before_capture — verify-payment proves the caller owns the payment before it captures it or says anything about it.
sot_registry_entry: verify_payment_owner_before_capture
writers:
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the 400 (no notes.user_id) and 403 (notes.user_id !== caller) guards, now directly after the Razorpay GET", line: 399 }
readers:
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the capture POST of an authorized payment, reachable only past the guards", line: 441 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the status echo (payment.status !== \"captured\" -> 200 verified:false), reachable only past the guards", line: 476 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: "verify fallback: trusts only status 200 && verified == true; every other reply is a soft failure and the next timer retries", line: 911 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, razorpay_payment_id]
contract_test_path: supabase/functions/verify-payment/index_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none new"]
  failure: ["none new: the 400 and 403 bodies are byte-identical to before; they are only reached earlier"]
cross_account_guard: "this IS the cross-account guard: payment.notes.user_id must equal the JWT caller before the capture or the status answer. The app always writes notes.user_id at order time (create-razorpay-order), so a real user's own payment is unaffected."
forbidden_patterns_checked:
  - "a kill switch for the move — REJECTED with the founder's approval (F-2, 2026-10-24): an old path behind a switch would keep the cross-account capture reachable, and the change only reorders two existing guards whose bodies are unchanged."
  - "checking ownership from the order instead of the payment notes — REJECTED: the notes are what the order path writes and what both writers already trust; a second source would be a new drift."
  - "dropping the auto-capture — REJECTED: the caller's own authorized payment (UPI test VPAs, wallet delays) still needs it; the capture just moves behind the guards."
proposed_fix: >-
  Move the two guards (text, order and messages unchanged: absent notes.user_id -> 400 "Missing user_id in payment
  notes"; mismatch -> 403 "Payment does not belong to this user") to directly after `let payment = await
  razorpayResponse.json();`, before the capture block and the status echo. Nothing before them now touches
  anything that is not the caller's (the rate-limit counter is the caller's own, the idempotency pre-check is
  `.eq("user_id", userId)`, the GET is a read). A non-null primitive body (unreachable from Razorpay) now answers
  400 instead of a 200 echo; a null body still throws into the existing 500.
regression_test_planned:
  - "supabase/functions/verify-payment/index_test.ts, the 'U1:' tests (Scenario.intercept answers the Razorpay GET and capture): another user's AUTHORIZED payment -> 403 and no capture request recorded; another user's CREATED payment -> 403 and the body names no status; an AUTHORIZED payment with no user_id key, and with Razorpay's empty-notes array [] -> 400 and no capture; control: the caller's own authorized payment -> one capture POST {amount, currency} and 200 verified:true with one subscriptions insert."
  - "test/contracts/verify_payment_owner_before_capture_writer_to_reader_test.dart (the Gate 9 name for the concept): both guards precede the first /capture URL, the authorized branch and the status echo in comment-stripped code (the stripper keeps `https://`); the client trusts only 200 + verified:true. test/contracts/verify_payment_notes_user_id_required_test.dart (the c8f229 pins) is unchanged."
mutation_proof: >-
  Scratchpad ph/mutate_u1.py (each mutant computed from the file before any write, restored and sha256-compared in
  `finally`). M1, the guards moved back to their origin/main position below the echo: 4 Deno tests red (both 403
  tests, both 400 tests) + 1 Dart pin red. M1b, the guards between the capture and the echo: 3 Deno tests red
  (the AUTHORIZED 403 and both 400 tests) + 1 Dart pin red. Correction to the plan, which predicted M1b would
  redden the CREATED test: with the guards ahead of the echo a created payment is already refused 403, so M1b is
  caught by the capture-recording tests instead; both mutants are caught. The commit's B-pass
  (docs/reviews/, staged hash in the commit) found two survivors and both are now killed by tests added in the
  same commit: M5, the 403 compare loosened to `!=` (a notes.user_id of `[caller]` then passes), 0 red before,
  1 red after (the array-type test); M12, the 403 also refusing the caller's OWN created payment, 0 red before,
  1 red after (the own-CREATED control). Self-attested.
impact_analysis: >-
  The caller's own payment, in every status, takes the same requests and gets the same body as before. Only a
  payment whose notes do not name the caller changes: it now gets the 400/403 without a capture and without its
  status. The client trusts only 200 + verified:true, so its handling is unchanged.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "razorpay_service.dart:911-915 accepts only status 200 && verified == true; :1011-1019 retries on anything else; no client branch reads the 400/403 bodies differently" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live verify-payment v30 is byte-identical to origin/main 3af16319 (bundle compared 2026-10-24); the deploy of this change is a founder-gated live step after the merge (plan section 6)" }
  - { tier: 11, name: "External services", status: verified, evidence: "Razorpay GET /v1/payments/<id> returns notes as an object, or [] when empty; both are covered (the [] case answers 400 via the missing-key branch)" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "create-razorpay-order writes notes.user_id = the JWT caller on every order (the app's only order path), so the app's own payments always pass the guards" }
recurrence: >-
  Recurrence of the c8f229 concept (verify_payment_notes_user_id_guard, 2026-05-17, OI-29): that fix made the
  ownership check fail closed on an absent notes.user_id but left it AFTER the side effects. Same class in a new
  shape: a side effect on a service-role path performed before the authorization check that should gate it. The
  known-good fix (the two-step guard) is kept verbatim and moved ahead of every side effect; the new Dart pin
  pins the ORDER against the capture and the echo, which the c8f229 pins did not.
related_bugs:
  - c8f229
---

# verify-payment captured and described a payment before checking whose it was

## What was wrong

The handler's order was GET -> capture if authorized -> echo the status if not captured -> require
`notes.user_id` -> require it to equal the caller. The two ownership guards came last, so the capture (a side
effect on another user's money) and the status (information about another user's payment) were both reachable
by any signed-in caller with a payment id.

## Writer and reader

Writer: the two guards, now at `verify-payment/index.ts:399-433`. Readers that must stay behind them: the capture
POST (`:441`) and the status echo (`:476`). Client reader: `razorpay_service.dart:911`.

## The fix

See `proposed_fix`. Plan: `docs/plans/2026-10-24-payment-hardening.md` section 3 U1. Rollback: a forward deploy
of the prepared verify-payment payload built from the rollback SHA `6bfbd402` (plan section 6), which is the code
live v30 runs; there is no kill switch for this unit (plan F-2).
