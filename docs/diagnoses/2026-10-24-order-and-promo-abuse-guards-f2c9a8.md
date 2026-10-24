---
bug_id: f2c9a8
date: 2026-10-24
batch: payment-hardening (unit U3; OI-366)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  create-razorpay-order had no per-user limit, so a signed-in caller could create Razorpay orders without bound,
  and it priced an order with ANY active code even when the code had expired or run out ("tolerant at order
  time"); an unknown or inactive code silently gave a full-price order, and a failed promo read was treated as
  "no promo". validate-promo had no limit either, compared expiry with the server's UTC day (setHours) instead of
  the IST day the code is meant for, and folded a read error into "Invalid promo code". OI-366's own text was
  partly wrong: validate-promo did enforce expiry and max_uses; the real gap was the order door
  (create-razorpay-order, the promo block) and the missing limits.
concept: create_order_rate_limit, promo_validate_rate_limit, promo_usable_rule — bounded attempts and one strict rule where a code is accepted for a new purchase.
sot_registry_entry: promo_usable_rule
writers:
  - { file: supabase/functions/_shared/promo_rules.ts, method_or_widget: "promoUsableAt: inactive, expired (IST day; non-date valid_until = expired), exhausted", line: 24 }
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "handler: consume_quota('create_order', 1-hour bucket, 30) before any other read", line: 140 }
  - { file: supabase/functions/validate-promo/index.ts, method_or_widget: "handler: consume_quota('promo_validate', 1-hour bucket, 20) before the body", line: 79 }
readers:
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "handler: strict promo (read error -> 500 promo_check_unavailable; unknown/unusable -> 400 promo_invalid; no order)", line: 251 }
  - { file: supabase/functions/validate-promo/index.ts, method_or_widget: "handler: the four answers through promoUsableAt; read error -> 200 'Couldn't check the code right now'", line: 121 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: "createOrder: a non-409 non-2xx shows the server `error` text (_extractServerError)", line: 488 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: "_validatePromoCode: shows data['reason'] when valid is not true; any thrown call -> 'Network error'", line: 228 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/promo_usable_rule_writer_to_reader_test.dart
ist_handling:
  - { file: supabase/functions/_shared/promo_rules.ts, line: 32, fn: "promoUsableAt (istDateStr(now) > valid_until date)" }
provider_invalidations: []
telemetry_op_types:
  success: ["usage_counters rows create_order / promo_validate (founder digest, subday totals); log 'order_abuse_guards=<on|off>' once per request in both functions"]
  failure: ["429 rate_limited / rate_limit_unavailable (order); 500 promo_check_unavailable; 400 promo_invalid; validate-promo 200 valid:false with the rate or 'couldn't check' reason"]
cross_account_guard: "the counter's user id is the JWT caller's (supabase.auth.getUser), so a caller can only spend their own allowance."
forbidden_patterns_checked:
  - "making the payment WRITERS strict too — REJECTED: a payment already made at the discount must stay recordable if the code lapses before capture (payment.md rule 2; c3e7a1 pages the no-match case); strict-at-order cannot strand money."
  - "a 429 from validate-promo — REJECTED: the paywall shows ANY non-2xx as 'Network error'; installed builds read {valid:false, reason}, so every refusal is a 200 with a reason."
  - "failing OPEN on a counter error — REJECTED: the order limit fails CLOSED like verify_payment_rate_limit (an order outage costs a retry, not money)."
  - "a bare string compare of valid_until — REJECTED: letters sort after digits, so 'infinity' or garbage would never expire; a non-date is expired."
proposed_fix: >-
  `_shared/promo_rules.ts` promoUsableAt. create-razorpay-order: the limit right after the JWT check (fixed 1-hour
  UTC bucket, the delete-account precedent: a sub-day bucket whose only observable is its duration); the strict
  promo block. validate-promo: exported handler, env read inside it, the same limit (20) and rule, maybeSingle
  with the error read. Kill switch DISABLE_ORDER_ABUSE_GUARDS (exactly "true", both functions together) restores
  the old paths verbatim; each request logs order_abuse_guards. DIGEST_KEYS gains create_order and promo_validate
  (subday, no cap). OI-407 tracks deleting the old paths after the live checks.
regression_test_planned:
  - "supabase/functions/_shared/promo_rules_test.ts: the rule table, the IST boundary pair (23:59 IST ok, 00:01 IST next day expired, while the UTC date is still the same day), both date formats, 'infinity'/'abc'/''/null/number, is_active null/'true'/1, used_count null with max_uses 0 and 5, the check order."
  - "supabase/functions/create-razorpay-order/index_test.ts 'U3:' tests: one counter call before the guard read with key/limit/bucket; -1 -> 429 + Retry-After and no order; RPC error -> 429 fail closed; expired/exhausted/inactive/null-active/unknown -> 400 promo_invalid and no order; usable codes in both formats and 'today' -> discounted order; promo read error -> 500 and no order; switch 'true' -> origin/main's answers (status, body, order body) and no counter; other switch values keep the guards."
  - "supabase/functions/validate-promo/index_test.ts (new; frozen fixture validate_promo_origin_main.ts.txt): the four answers and the IST expiry; one counter call; 21st check -> rate reason and no lookup; RPC error and read error -> the distinct reason; switch 'true' -> origin/main on 10 scenarios; no JWT -> 401 before the counter; importing reads no env, fetches nothing, binds no server; the switch name equals create-razorpay-order's."
  - "test/contracts/create_order_rate_limit_, promo_validate_rate_limit_ and promo_usable_rule_writer_to_reader_test.dart (wiring, client readers, digest, inventory; the writers stay tolerant); founder_digest_caps_mirror_test.dart and usage_quota_ledger_writer_to_reader_test.dart updated (allowlist)."
  - "test/contracts/payment_log_safety_writer_to_reader_test.dart: validate-promo joins the scan (this unit gave it new log lines); its interpolations are classified for that file (JWT user.id, constants, pgErrorCode) and its catch-all is listed; create-razorpay-order's new lines are classified the same way."
mutation_proof: >-
  Scratchpad ph/mutate_u3.py (13 mutants, each computed before the write, every file restored and sha256-compared):
  M5 the -1 branch dropped -> 2 red; M5b the RPC error ignored -> 1; M5c the promo read error ignored -> 1; M5d the
  old tolerant rule -> 2; M6 the UTC day instead of IST -> 3; M6b no date regex -> 1; M6c >= to > -> 4; M6d a truthy
  is_active -> 1; M7 validate-promo's limit dropped -> 2; M7b its read error folded into Invalid -> 1; M7c and M7d
  each switch ignored -> the golden red. M6e (`!==` instead of `!=` on max_uses) stays green and is EQUIVALENT: an
  undefined max_uses gives Number(undefined) = NaN and every comparison with NaN is false, so the code is still
  not exhausted. Log safety (ph/mutate_u3_log.py, 6 mutants, all red in the contract): validate-promo's raw read
  error, a raw rate error, a second argument; create-razorpay-order's raw promo code in the refusal line and its raw
  promo error; validate-promo dropped from the scan. After the B-pass (review beee28f0d9f2, ph/mutate_u3_bpass.py,
  all red): the expired case removed (V1), the strict switch skipped so the tolerant path answers (V4: red only
  after the two any-time-zone inputs were added, a malformed valid_until and is_active "true"), a UTC-shifted clock
  in each door (V5, V6: the frozen 00:01 IST tests), a wrong Retry-After (C8), the fixed "a few minutes" copy, a
  floor in retryMinutes, the non-number counter check removed in each of the three functions, and the integer
  clause dropped. Self-attested.
impact_analysis: >-
  A normal buyer makes one or two order attempts and one promo check, far under 30 and 20. Stated and accepted:
  a 409 already-PRO, a 400 bad plan and a bad JSON body each spend an order unit; callFunction retries a 502, 503
  or 504 up to 3 times (not the 500s), so one tap during a Razorpay outage can spend 4 units, and the bucket is a
  fixed UTC hour, so the 429 names the real wait in minutes ("Try again in 37 minutes"). A code that expired or ran out between the
  paywall check and the order is now refused with a clear message instead of honoured; the paywall has closed by
  then, so reopening it starts clean. The writers are unchanged, so any payment made is recordable.
touched_layers_checked:
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live create-razorpay-order v18 equals origin/main; live validate-promo v21 differs only by std@0.177.0 vs 0.224.0 (ec01b469); both deploys are founder-gated after the merge" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "consume_quota has no key allowlist (migrations 128/130), so the new keys need no migration; promo_codes.valid_until is date NOT NULL" }
  - { tier: 1, name: "Client code", status: verified, evidence: "razorpay_service.dart:488 shows the server error text for a non-409 failure; paywall_sheet.dart:228-237 shows data['reason'] when valid is not true" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "validate-promo keeps HTTP 200 {valid, reason, discount_pct}; create-razorpay-order's new errors carry `error` text the client shows verbatim" }
recurrence: >-
  Same shape as f2c8d5 (2026-09-11: windowed rate limits that never functioned; the consume_quota fixed-bucket
  pattern this unit reuses, fail-closed for a payment path like verify_payment_rate_limit). The promo half is not
  a recurrence: c3e7a1 is the writers' no-match alert, which stays tolerant on purpose.
related_bugs:
  - f2c8d5
  - c3e7a1
---

# Unbounded order attempts and a tolerant promo rule at the order door

## What was wrong

The order door priced orders with codes that had expired or run out and had no attempt limit; validate-promo had
no limit and judged expiry by the server's UTC day.

## The fix

See `proposed_fix`. Plan: `docs/plans/2026-10-24-payment-hardening.md` section 3 U3.

## Review (B-pass beee28f0d9f2, 7 findings)

1. Neither door's handler pinned the IST day (the unit rule did), and validate-promo's switch could fall through
   into the tolerant path: an exhaustive `default` refuses, and frozen-clock tests at 00:01 / 23:59 IST run in both
   doors; two inputs where the tolerant path differs in any time zone pin the switch itself.
2. The 429 said "a few minutes" for a wait of up to an hour: it now names the minutes (`retryMinutes`).
3. Retry-After was asserted only to lie in [1, 3600]: now the rest of the current hour.
4. payment.md and supabase/functions/CLAUDE.md did not describe U3 in this commit: they land in the branch's docs
   commit (the plan's commit 5, same pull request), which describes all three concepts and the switch.
5. Two founder-digest registry ranges pointed at the weekly-keys read (stale before this batch): repointed from
   code anchors.
6. A counter answer that is neither -1 nor a count (null, 0, a fraction) passed: all three limits (the two new ones
   and verify-payment's, the same shape) now refuse it like an RPC error, each with tests.
7. The new digest comment lacked the hourly-bucket day-boundary note, and a test evaluated today's IST date at
   load time: both fixed.

## Review (delta B-pass 657e30b88cac on those fixes, 2 findings, no P0-P2)

1. The exhaustive `default` was unpinned at runtime (unreachable: four members, four cases): a source pin in
   `promo_usable_rule_writer_to_reader_test.dart` requires its `never` check and its refusal; CI's `deno check`
   fails on a fifth member.
2. The `typeof usedCount !== "number"` clause was redundant (`Number.isInteger` is false for every non-number):
   removed in the three functions; "the non-number counter check removed" in the mutation proof means the whole
   check.
