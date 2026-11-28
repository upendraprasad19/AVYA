---
bug_id: e5a9c3
date: 2026-11-20
batch: android-play-billing-fallback (ADR-0022, U4a)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  The Profile PRO card's MANAGE SUBSCRIPTION sheet said \"Your PRO subscription is handled by Razorpay and auto-renews by default\". That is false in every store build (no Razorpay) and a renewal promise nobody verified for the web checkout.
concept: subscription_manage_sheet_copy
sot_registry_entry: not_applicable
writers:
  - { file: lib/core/copy/purchase_copy.dart, method_or_widget: "PurchaseCopy.manageSubscription", line: 36 }
readers:
  - { file: lib/features/profile/screens/profile/screen.dart, method_or_widget: "_onManageSubscription sheet body", line: 281 }
hive_key_prefix: none
hive_key_formula: "not applicable: display text / a URL string, nothing is stored"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/profile_subscription_sheet_copy_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: static text."
forbidden_patterns_checked:
  - { pattern: "a payment provider named in a sentence shown to every user", absent: true }
proposed_fix: |
  The sentence moved to `PurchaseCopy.manageSubscription` and names no provider and no renewal: it is true for a web purchase, a free-days code and a later store purchase.
regression_test_planned: |
  test/contracts/profile_subscription_sheet_copy_test.dart
mutation_proof: |
  Rule 21, backup/mutate/run/restore. M1 the copy file's sentence set back to 'handled by Razorpay': 1 test RED (the behavioural one). The source pin (screen.dart renders the constant and holds no Razorpay literal) is presence only.
impact_analysis: |
  Display text / a link only. No stored value changes meaning.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "manageSubscription added, sheet reads it; the new test passes." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No stored value changes." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Static text only; no store or payment provider is called." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract touched." }
recurrence: "Not a recurrence: grepped docs/diagnoses for the sentence and for the wrong package id; no earlier diagnose names either."
related_bugs: []
---

# e5a9c3 - manage-subscription-sheet-names-razorpay

## What happened
The sheet text was an inline literal written for the Razorpay-only era. ADR-0022 puts a store build in front of testers who have no Razorpay, so the literal would be read as a statement about their purchase. It is rewritten once, in the shared copy file, for every mode.
