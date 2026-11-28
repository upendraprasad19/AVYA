---
bug_id: c3e7a1
date: 2026-10-21
batch: oi341-piece-b2-door (OI-341 Piece B2a)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  A CAPTURED Razorpay payment whose amount matches no plan price answered 400 in both payment writers and wrote no
  subscriptions row and no alert. The usual cause is a promo code deleted or its `discount_pct` edited between order
  creation and capture (the notes carry the code, the amount carries the old discount, and `derivePlanFromAmount`
  returns null); a stray amount does the same. `payment_record_failed` fired only on the stacking ON path's function
  failure, so the user paid, got no PRO, and nobody was told: Razorpay retried the 400 for a day and gave up. The
  webhook's second 400 (`amount_mismatch`, the computeExpectedAmount cross-check) had the same silence. Found by the
  OI-341 Piece B2a hermes pass (seat 4, finding 4); B2a's live steps use a dedicated 90% promo code, so this path is
  one operator edit away during them.
concept: payment_record_failed_alert — every captured payment that a writer cannot record pages the founder.
sot_registry_entry: payment_record_failed_alert
writers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "handler: the `!derived` 400 arm, now calling reportPaymentRecordFailure (code amount_no_match)", line: 533 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "handler: the cross-check 400 arm (code amount_cross_check)", line: 592 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the `!derived` 400 arm (code amount_no_match), after the payment-owner check", line: 489 }
readers:
  - { file: supabase/functions/_shared/payment_alert.ts, method_or_widget: "reportPaymentRecordFailure: dedup per payment id, critical first, warn after", line: 132 }
  - { file: supabase/migrations/133_alert_critical_notify_trigger.sql, method_or_widget: "private.dispatch_critical_alert_notify: pages Telegram on a critical alerts insert", line: 1 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: alerts
cloud_columns: [source, severity, summary, context_json, suggested_action]
contract_test_path: supabase/functions/razorpay-webhook/index_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none new"]
  failure: ["alerts row source payment_record_failed, context_json.code amount_no_match or amount_cross_check (critical for the first per payment id in 24 h, then warn); the existing console.error lines are unchanged"]
cross_account_guard: "the webhook's user id comes from the HMAC-verified payload (UUID-checked before this point); verify-payment's arm is reached only after `payment.notes.user_id === userId` (the JWT user), so a caller cannot make the writer page about another user's payment."
forbidden_patterns_checked:
  - "recording the row anyway at a guessed plan — REJECTED: rule 1 of docs/architecture/payment.md (the plan is derived from the amount, never guessed) exists to stop a cheap payment claiming a dearer plan; the operator decides from the alert."
  - "changing the 400 to a 500 — REJECTED: the response is unchanged on purpose (Razorpay already retries a 400, and a 500 would not make the amount match)."
  - "making the writers' promo read strict — REJECTED: their tolerant read is what keeps an in-flight 90% payment recordable when the code is deactivated mid-checkout (plan step 0 (c)); the strict rule belongs at order creation (OI-366)."
proposed_fix: >-
  In both writers' `!derived` arm, and in the webhook's cross-check arm, call `reportPaymentRecordFailure` before the
  unchanged 400, with code `amount_no_match` / `amount_cross_check`, plan `unknown` (or the derived plan for the
  cross-check), the amount and a fresh request id; the webhook passes `timeoutMs: 1000` like its other alert. The
  alert's suggested action now names these codes and the usual cause.
regression_test_planned:
  - "supabase/functions/razorpay-webhook/index_test.ts: a promo payment whose code row is gone -> the same 400 body, no row, one critical payment_record_failed alert with code amount_no_match, the ids, the amount and plan 'unknown'; a stray amount with a hung alerts table -> the 400 within about 2 s; the cross-check arm forced by a promo read that changes between the two reads -> the same 400 amount_mismatch and code amount_cross_check; a matching promo payment -> no alert."
  - "supabase/functions/verify-payment/index_test.ts: the deleted-promo case -> the same 400 body, no row, one alert (fn verify-payment, code amount_no_match); a matching promo payment -> no alert."
mutation_proof: >-
  NM1 (the webhook no-match alert skipped) reddens 2 tests, NM2 (the cross-check alert re-coded as amount_no_match) 1,
  NM3 (the verify-payment alert skipped) 1, NM4 (the webhook's no-match alert on the default 3 s bound) 1. Part of the
  B2a runner (scratchpad mutate_b2a.py), each an exact-one-match replace computed before any write, restored and
  byte-compared after the run. Self-attested.
impact_analysis: >-
  One extra alerts round trip (bounded, never changes the response) on two 400 arms that a correct payment never
  reaches. A deliberate garbage amount needs a captured payment, so it cannot be used to spam pages for free, and the
  dedup keeps one page per payment id per day.
touched_layers_checked:
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live verify-payment v26 and razorpay-webhook v30 are the b8385b6c code; the B2a deploy is plan section 4 step 2, its own founder go, NOT done" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "alerts columns source/severity/summary/context_json/suggested_action exist (backups/live_schema_columns.json, migration 076); there is no CHECK on source; severity critical/warn are allowed" }
  - { tier: 11, name: "External services", status: verified, evidence: "Razorpay retries a non-2xx webhook for 24 h after event creation (its webhook docs, plan section 1); the 400 is unchanged, so the retry pattern is unchanged" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "verify-payment's 400 body is unchanged; the client's handling of it (razorpay_service.dart verify fallback) is unchanged" }
recurrence: "Same class as the B1 payment_record_failed design (a captured payment no row records must page) and bug class 2.49's mirror: a failure path that is silent. Searched INDEX for 'amount_does_not_match', 'derivePlanFromAmount' and the concept (paid but not recorded): the prior entries (f2a6d1, the grace window; 519075) are different defects. No recurrence."
related_bugs:
  - b95d61
---

# A captured payment whose amount matched no plan was dropped silently

## What was wrong

Both writers derive the plan from the amount (payment.md rule 1). When the amount matches nothing, for example because
the promo row was deleted or its percentage edited after checkout opened, they answer 400 and write nothing. That is
the right refusal, but nothing recorded that money had been taken: no row, no alert, only a log line with the
platform's short retention.

## Writer and reader

Writers: the three 400 arms named above. Reader: the founder, through the `alerts` row (Telegram for critical,
the daily digest for warn).

## The fix

See `proposed_fix`. Plan: `docs/plans/oi341-piece-b2-door.md` section 13. Ledger: `docs/audit/oi341-piece-b2-door.closure.yaml`.
