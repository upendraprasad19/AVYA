---
bug_id: a9e2f7
date: 2026-10-24
batch: payment-hardening (unit U2; OI-351)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  On a payment.authorized delivery the webhook captures the payment BEFORE it records the row. If that delivery
  then failed to record (a non-23505 insert failure, or with stacking ON a failed record_paid_subscription), it
  answered 500, and every Razorpay replay of the SAME authorized event met Razorpay's "already captured" refusal
  and answered 502 "Capture failed, will retry" until the 300 s authorized window closed (then 400 too old). The
  money was taken and only the separate payment.captured event could record the row. This is the normal flow,
  not an edge: create-razorpay-order sets payment_capture: 1, so Razorpay itself may have captured the payment
  before the authorized event arrives, and the webhook's own capture is then refused. Found by the OI-341 hermes
  pass (seats 1 and 4, OI-351).
concept: webhook_already_captured_recovery — a refused capture of an already-captured payment records the row from the signed event.
sot_registry_entry: webhook_already_captured_recovery
writers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "rereadIsCaptured: one GET of the payment, bounded at 1500 ms (race, body read inside), never throws, strict id/amount/captured/status check", line: 269 }
readers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "handler: the captureRefused branch (recover and continue to the unchanged notes/plan/insert path, or today's 502)", line: 538 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, razorpay_payment_id, plan, start_date, end_date]
contract_test_path: test/contracts/webhook_already_captured_recovery_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["log line '[razorpay-webhook] capture refused, payment already captured; continuing payment_id=<id>' (warn)"]
  failure: ["unchanged: '[razorpay-webhook] capture failed for <id>: <razorpayErrorSummary>' or 'capture threw for <id>: <errorName>' then the 502"]
cross_account_guard: "the event is HMAC-verified and the re-read must answer the SAME payment id and the SAME amount as the signed event; the row is still written from the signed event's notes (user_id UUID-checked) and the amount-derived plan, exactly as on the payment.captured path."
forbidden_patterns_checked:
  - "trusting the re-read's notes or amount for the row — REJECTED: the signed event stays the source of amount, notes and plan; the re-read only answers 'is it captured, for this amount'."
  - "an unbounded re-read — REJECTED: Razorpay times a delivery out at about 5 s; the GET is raced against 1500 ms with the body read inside the race (a hang after the headers is bounded too, test U2 (11b)); when the timeout wins the GET is aborted, and its signal is live when the GET starts (U2 (16)); when the GET wins, with a true or a false answer, no timer stays pending (U2 (17), op sanitizer on). Only the GET is bounded: the capture POST before it has no timeout, unchanged from origin/main and outside this fix."
  - "a loose check (captured OR status) — REJECTED: every clause is required and has its own negative test (compound-boolean connective rule)."
proposed_fix: >-
  Hoist the credentials; on a non-OK capture or a throw set captureRefused and keep the summary; after the try,
  if refused and the switch is not exactly "true", call rereadIsCaptured(id, event amount, credentials): true ->
  warn and fall through to the unchanged notes/plan/insert path; false -> log the summary and return today's 502.
  Kill switch DISABLE_WEBHOOK_CAPTURE_RECOVERY (exactly "true") = today's behaviour (golden against the frozen
  origin/main handler). Replays after a recovery meet the H-19 pre-SELECT and skip.
regression_test_planned:
  - "supabase/functions/razorpay-webhook/index_test.ts 'U2 (1)' to 'U2 (15c)': recovery records (refused or thrown capture, GET captured for the amount); GET authorized / 500 / other amount -> 502 and no row; happy path makes no GET; three replays after a recovery skip via H-19 with no capture, no GET and one promo redemption; stacking ON -> exactly one RPC call and promo only when inserted; a 23505 race -> no promo; switch 'true' -> a TRUE golden of origin/main (status, body, request list); any other switch value -> recovery on; a hung GET and a hung BODY -> 502 within about 2 s; one negative per clause (id, captured, status, null, array, string amount)."
  - "test/contracts/webhook_already_captured_recovery_writer_to_reader_test.dart: one call, behind the switch, inside the captureRefused branch; the race and the body read inside it; a Razorpay fetch, not a supabase call; the switch documented in SECRET_INVENTORY.md."
  - "test/contracts/payment_log_safety_writer_to_reader_test.dart rule 3 (added here, because U2 holds the capture refusal in `refusal` until the recovery is decided): a console call may interpolate a declared message variable only because EVERY assignment to it (plain or compound) is checked like a console argument, built from literals with each `${...}` classified for the file, AND every other mention of the name is one of those assignments or a console use (so a destructuring, a loop variable or a second use cannot fill it); an undeclared or unused message variable, or one listed as a value, fails. Rule 4 (same file, B-pass 6759fb19989f finding 2): `console` appears only as `console.<method>(` and no dynamic-global door (globalThis, Reflect, window, self, eval, Function) appears in a scanned file, and `Deno` appears only as `Deno.<name>` and never as `Deno.stderr`, `.stdout` or `.core`; names are matched with literal text blanked, regex literals are recognised, a spread `...name` counts as a mention, and each file's raw count of console calls must equal the calls the scan sees (a desynchronised scan cannot hide one)."
  - "supabase/functions/razorpay-webhook/index_test.ts 'U2 (16)' and 'U2 (17)' (B-pass finding 6): rereadIsCaptured called directly with fetch swapped; the timeout aborts the hung GET's signal; a winning GET leaves no pending timer (Deno op sanitizer on)."
mutation_proof: >-
  Scratchpad ph/mutate_u2.py and mutate_u2_j.py, every mutant computed before the write and the file restored and
  sha256-compared: M3 the recovery call removed -> 8 red; M3b the race dropped -> 2 red (both hang tests); M3d id,
  M3e number type, M3f amount, M3g captured, M3h status, each clause removed -> 1 red each (its own negative test);
  M3i switch ignored -> the golden red; M3j the body read moved after the race -> U2 (11b) red. M3c (the
  plain-object check dropped) stays green and is EQUIVALENT: a null body is still refused by the remaining check,
  and an array or a string has no `id` equal to the payment id, so the id clause refuses it. The log contract's
  rule 3 (ph/mutate_u2_msgvar.py, 6 mutants, all red): a raw body in the capture-failed assignment (contract and
  the U0 log Deno test), a raw error in the capture-threw one, an appended `refusal += ${body}`, a concatenated
  body, the variable dropped from _messageVariables, and the variable listed as a value. After the B-pass
  (review 6759fb19989f), 8 more leak mutants, all red: a destructured raw body replacing the assignment and added
  after it, an object destructuring, a loop variable, `console["error"](...)`, a method alias, an object alias and a
  globalThis lookup. Each rule is NECESSARY: with the rule-4 check neutered the method-alias leak passes, and with the
  mention count neutered the added destructuring passes. ph/mutate_u2_f6.py: `controller.abort()` removed -> U2 (16)
  red; `clearTimeout(timer)` removed -> U2 (17) red. After the delta B-pass (review a5048de70f02), all red: an abort
  at construction (U2 (16)), a timer cleared only on a true answer (U2 (17) false cases), a regex-quote pair hiding a
  console call, a rest-destructuring fill, a `Deno.stderr` write and a `(Deno as any)[...]` lookup; with regex
  awareness neutered the hidden call is still caught by the raw cross-check (2 red, the scanner self-test and the
  cross-check), with both neutered only the self-test stays red. Self-attested.
impact_analysis: >-
  Only a refused or thrown capture changes: when Razorpay says the payment is captured for this exact amount the
  row is recorded instead of a 502. One extra Razorpay GET (at most 1.5 s) on that path only; the happy path makes
  no GET. No real payment has run since the live keys went in, so no stranded payment exists to backfill.
touched_layers_checked:
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live razorpay-webhook v34 is byte-identical to origin/main 3af16319; the deploy is the last founder-gated live step" }
  - { tier: 11, name: "External services", status: verified, evidence: "Razorpay refuses a capture of a captured payment (400 BAD_REQUEST_ERROR) and GET /v1/payments/<id> answers {id, amount, captured, status}; the replay window for payment.authorized is 300 s in this handler" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "the recovered path writes through the unchanged insert / record_paid_subscription branch; unique_razorpay_payment_id keeps a replay idempotent (H-19 and the 23505 branch)" }
recurrence: >-
  Not a recurrence of a prior diagnose: searched INDEX for 'already captured', 'payment.authorized', '502' and
  'capture'; the nearest are 9a7c14 (a TDZ crash in the same handler) and 7ad0d5 (the 23505 race in
  verify-payment), different defects. Same family as OI-351's own description only.
related_bugs:
  - 7ad0d5
---

# A refused capture of an already-captured payment looped on 502

## What was wrong

The webhook treated every capture refusal as "try again later", including Razorpay's "already captured", which
is the answer every replay gets once a first delivery (or Razorpay's own auto-capture) has captured the payment.

## The fix

See `proposed_fix`. Plan: `docs/plans/2026-10-24-payment-hardening.md` section 3 U2.

## Review (B-pass 6759fb19989f, 6 findings, all fixed in this commit)

1. Rule 3 missed a destructuring / loop assignment of `refusal`: every mention of the name is now counted.
2. The console was reachable by bracket lookup or alias: rule 4.
3. `SECRET_INVENTORY.md` cited OI-407 before the board had it: the OI-407 entry (this switch only) lands in this
   commit; the order-abuse switch joins it with U3.
4. The recovery contract's header named diagnose e7b3c5: corrected to a9e2f7.
5. Four registry entries named the subscription insert but pointed elsewhere (stale before this batch, in both
   writers): repointed from code anchors (webhook 759-771 and 759-782 with the 23505 arm, verify-payment 660-672
   and 657-734 with the canonical end date).
6. Nothing pinned the abort and the timer clear: U2 (16) and U2 (17).

## Review (delta B-pass a5048de70f02 on those fixes, 6 findings)

1. A regex literal with a quote hid a console call from every rule: regex literals are recognised, plus a per-file
   raw cross-check and a per-file "sees at least one call" floor.
2. U2 (16) passed with an abort at construction: it also asserts the signal is live when the GET starts.
3. A rest-destructuring `[...refusal] = [body]` was not a mention: a spread now counts.
4. The timer clear was pinned on a true answer only: U2 (17) also runs on a 500 and on captured:false.
5. `Deno.stderr` / `Deno.stdout` / `Deno.core` were open: `Deno` is allowed only as `Deno.<name>`, without those.
6. The OI-407 title names both switches while only this one exists at this commit: kept, the minted title; the
   body says the order-abuse switch joins with U3.

The contract is a source scan, and a source scan does not converge (code-review skill, lens 6): the behavioural
"U0 log:" Deno tests with origin controls remain the backstop for a raw value in a log line; the rounds stop here
because both reviews' remaining doors need deliberate obfuscation, not a plausible regression.
