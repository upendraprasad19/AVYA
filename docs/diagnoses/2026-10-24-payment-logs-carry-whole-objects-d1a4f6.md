---
bug_id: d1a4f6
date: 2026-10-24
batch: payment-hardening (unit U0 + R-6; OI-360)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  The payment functions logged whole objects. verify-payment and razorpay-webhook printed the PostgREST error of
  a failed non-23505 subscriptions insert as an object (its `details` echoes the failing row: in the webhook the
  real Razorpay signature, in verify-payment the ids), the full Razorpay body of a refused capture or order, the
  whole payment notes when user_id was missing, the raw malformed user_id, the raw client `plan` and promo code
  (a newline could forge a second log line, an unbounded string could grow it), the idempotency pre-SELECT's
  error message and the rate-limit RPC's error message. Function logs are kept by the platform and readable by
  every dashboard user. Separately (R-6), both redeemPromo twins ignored the RETURNED errors of
  increment_promo_used_count and the promo_code_uses insert (supabase-js does not throw them), so a failed
  increment was silent; U3 makes used_count decide exhaustion, which makes that silence a promo that never runs
  out. Found by the OI-341 hermes pass (OI-360).
concept: payment_log_safety — a payment-path log line carries a code, a type, a shape or a bounded value, never a whole object.
sot_registry_entry: payment_log_safety
writers:
  - { file: supabase/functions/_shared/payment_log_safe.ts, method_or_widget: "pgErrorCode / errorName / boundedText / razorpayErrorSummary / notesShape (pure, no imports)", line: 12 }
readers:
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "the non-23505 insert failure line (reconcile fields + code, own prefix)", line: 699 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "the refused capture line (razorpayErrorSummary)", line: 466 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "redeemPromo: the two returned errors, labelled, code only (R-6)", line: 139 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "the non-23505 insert failure line (reconcile fields + code, no request_id)", line: 730 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "missing user_id (notesShape), malformed user_id (type and length)", line: 512 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "redeemPromo: the two returned errors, labelled, code only (R-6)", line: 221 }
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "the Razorpay order refusal line (razorpayErrorSummary)", line: 277 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/payment_log_safety_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none new"]
  failure: ["log lines only: '[verify-payment] subscription insert failed (non-23505) request_id= payment_id= user_id= plan= amount_paise= code=', '[razorpay-webhook] subscription insert failed (non-23505) payment_id= user_id= plan= amount_paise= code=', '[<fn>] promo redemption: increment_promo_used_count failed code=' and '... promo_code_uses insert failed code='"]
cross_account_guard: "not_applicable: logging only; no response, row or count changes (R-6 adds lines, never a different answer)."
forbidden_patterns_checked:
  - "dropping the ids from the insert-failure lines — REJECTED: on that branch money is captured and no row exists; the ids are what an operator reconciles with, so they stay (the stacking-read line already carries them, OI-341 B1)."
  - "a second console argument of any kind — REJECTED and now pinned: every console call in the three payment functions takes one built string (test/contracts/payment_log_safety_writer_to_reader_test.dart), except the two outer catch-alls the plan keeps (their reachable throws carry no row data)."
  - "logging err.message for a Razorpay or fetch error — REJECTED: a fetch TypeError's message embeds the URL (f9d3b7), a Razorpay description can carry customer text; the name, status and code/reason are enough."
proposed_fix: >-
  New pure `_shared/payment_log_safe.ts`. Every payment-path log site uses it: the two insert-failure lines, the
  refused capture (both writers) and order, the missing/malformed user_id, notes.plan and the client plan, every
  logged promo code, the pre-SELECT and rate-limit errors. R-6: redeemPromo destructures both returned errors and
  logs a labelled code-only line; its outer catch logs errorName + code. Responses unchanged. Found while pinning:
  verify-payment's consume_quota failure line logged rateErr.message, a site the plan's list missed; it now logs
  the code.
regression_test_planned:
  - "supabase/functions/_shared/payment_log_safe_test.ts: each helper against hostile input (a 23503 with the signature in details and hint, non-string, nested, empty, 10 KB and newline-forged codes, a 10 KB body, notes as [], null, a string, an object with a secret value and an unknown key)."
  - "supabase/functions/verify-payment/index_test.ts and razorpay-webhook/index_test.ts, the 'U0 log:' tests: the same scenario first through the frozen origin/main handler, where the secret must be VISIBLE (positive control), then through the new handler, where it must be absent and the expected line present; and the 'U0 R-6:' tests per twin (response and row equal to a successful redemption, exactly one labelled code-only line)."
  - "test/contracts/payment_log_safety_writer_to_reader_test.dart: every console call in the three payment functions takes one argument (a bracket- and template-aware parser), every `${...}` inside a console call is on a classified allowlist (helper call, checked id, number/constant/derived value, server-generated short token) with a mirror check for stale entries, the two allowed catch-alls exist exactly as listed, each function imports the helpers, the insert-failure lines carry the reconcile fields."
  - "B-pass of this commit (docs/reviews/, staged hash in the commit): 'U0 log:' tests for the sites its mutants proved unpinned: the create-order Razorpay refusal (create-razorpay-order/index_test.ts, frozen-origin control), the checkout-supplied notes.promo_code at the webhook's not-found and no-plan lines and verify-payment's amount-mismatch line, and verify-payment's rate-limit counter failure (the message carried a secret; only the code may be logged); boundedText escaping DEL, the C1 range and U+2028/U+2029, which JSON.stringify leaves raw (payment_log_safe_test.ts, characters built from their codes)."
mutation_proof: >-
  Scratchpad ph/mutate_u0.py (each mutant computed before the write, restored and sha256-compared), measured
  2026-10-24: M2 in verify-payment (the insert error object passed again as a second console argument) -> 1 Deno
  test red (the 'U0 log:' insert test) + the Dart console-shape pin red; M2 in razorpay-webhook -> the same, 1 + 1;
  M2b in verify-payment (the increment check removed) -> 1 red ('U0 R-6: a failed increment_promo_used_count');
  M2b in razorpay-webhook (the promo_code_uses check removed) -> 1 red. Every positive control SHOWED the secret
  against origin/main before the new handler was asserted clean. The commit's B-pass ran 16 mutants and found 6
  survivors (all leaks kept INSIDE one template literal, which the one-argument rule cannot see), now each red:
  create-order raw `${body}` -> 1 Deno ('a refused Razorpay order') + the Dart interpolation allowlist; webhook raw
  promo code at the not-found line -> 1 Deno, at the no-plan line -> 1 Deno; verify-payment raw promo code at the
  amount-mismatch line -> 1 Deno; verify-payment `${rateErr.message}` -> 1 Deno (+ Dart); the redeemPromo catch
  logging `${e}` -> the Dart interpolation allowlist (presence-only: supabase-js returns database errors rather
  than throwing them, so no fake reaches that catch with a message). boundedText without the new separator
  escaping -> 1 Deno unit test red. A DELTA review of those fixes found the contract still blind to a message
  built in a variable, a `+`-concatenated value, console.info/debug, and a global allowlist that let create-order's
  raw `plan` through; plus three values called "short tokens" that were not filtered (Razorpay's statusText, the
  stacking read's `rec.code`, the create-order guard's code) and bidi/format characters passing boundedText. Now:
  the contract scans every console method, requires ONE argument built only from literals (or `(x ? lit : lit)`),
  checks every interpolation against a PER-FILE classified allowlist with a stale-entry mirror, strips comments
  with a quote-aware scanner, and scans _shared/payment_alert.ts too; captureConsole records info/debug; the three
  values go through boundedText / codeToken (new helper) / pgErrorCode; boundedText escapes \p{Cf} as well.
  Mutants (ph/mutate_u0_delta.py), each red: g flag dropped, format class dropped (1 Deno unit each); variable
  message, concatenated value (2 Dart each); console.info with a raw body, raw `plan` in create-order, raw
  rec.code, raw statusText, raw guard code (1 Dart each). Self-attested.
impact_analysis: >-
  Log text only. No response body, status, row or request changes; the R-6 checks add a log line on a failure that
  was silent. A dashboard search for the old insert-failure text ('Failed to insert subscription') finds the new
  prefixed line instead (payment.md rule 11 will document it: the batch's docs commit, plan section 5 commit 5).
  Rollback: a forward deploy of each function's payload built from the rollback SHA `6bfbd402` (plan section 6).
  No kill switch for this unit, by the founder's decision recorded as plan F-2 (log text only, no behaviour to
  switch).
touched_layers_checked:
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live verify-payment v30, razorpay-webhook v34, create-razorpay-order v18 are byte-identical to origin/main 3af16319 (compared 2026-10-24); the deploys are founder-gated live steps after the merge" }
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "no client reads a function log" }
  - { tier: 11, name: "External services", status: verified, evidence: "Razorpay error bodies are {error:{code,description,reason,field,...}}; only status, code and reason are kept" }
recurrence: >-
  Recurrence of the secret-in-a-log class: f9d3b7 (2026-09-21, a fetch TypeError's message carried the Gemini URL
  and key) and 82b018 (the Telegram bot token in a fetch error, the founder-digest telegramErrorSummary rule). The
  known-good fix (log a name, a code or a summary, never the object or its message) is applied, and this time it
  is pinned for the whole payment path by a shape test rather than per site.
related_bugs:
  - f9d3b7
  - 82b018
---

# Payment-path logs carried whole objects

## What was wrong

Seventeen log sites across the three payment functions printed an error object, a Razorpay body, the notes or a
raw client string. The worst was the webhook's insert failure: its PostgREST `details` echoes the row, signature
included. Separately, redeemPromo never looked at the errors supabase-js returns.

## The fix

See `proposed_fix`. Plan: `docs/plans/2026-10-24-payment-hardening.md` section 3 U0 and "U0 log sites".
