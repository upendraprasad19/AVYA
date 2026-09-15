---
bug_id: 5d2ff1
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: razorpay-webhook derived plan (monthly/yearly) from client-supplied body.plan instead of payment amount, allowing a monthly payment to grant yearly entitlement.
concept: subscription_state
sot_registry_entry: subscription_state
writers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: handler, line: 1 }
readers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: derivePlanFromAmount, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [plan, end_date, razorpay_payment_id]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Mirror derivePlanFromAmount from verify-payment into razorpay-webhook; ignore body.plan for entitlement; compute plan from payment.amount in paise.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 5d2ff1cb0e85d54f8913cbc14b571c88b5397e8e
Subject: fix(payment): razorpay-webhook derives plan from amount (Test #11 I1)
Files changed: supabase/functions/razorpay-webhook/index.ts
