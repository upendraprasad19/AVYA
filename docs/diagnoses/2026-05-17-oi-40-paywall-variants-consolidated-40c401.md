---
bug_id: 40c401
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  `paywall_sheet_phase_variant.dart` rendered a phase-unlock pitch
  bottom sheet, but its UPGRADE TO PRO CTA called `Navigator.pop()`
  with a deferred-checkout note — never actually invoked any purchase
  flow. A free user who tapped a locked Phase II card got the pitch
  then was returned to the locked screen with no path forward.

  Two-paywall risk: separate analytics, separate copy, separate
  restore flow. The phase variant claimed to share but didn't.
concept: paywall_single_purchase_path
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: lib/shared/widgets/paywall_sheet_phase_variant.dart, method: CTA escalates to showPaywallSheet, line: 124 }
readers:
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: canonical purchase pipeline, line: 1 }
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-40 group (2 cases), line: 174 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: []
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — UI sheet"
forbidden_patterns_checked:
  - { pattern: "phase variant CTA without showPaywallSheet escalation", absent: true }
proposed_fix: |
  Phase variant's UPGRADE TO PRO CTA now pops the soft-pitch sheet
  then calls `showPaywallSheet(context, feature: 'Phases 2-12')` —
  the canonical sheet with promo code, plan toggle, Razorpay
  invocation, restore flow, analytics. Two surfaces (context-
  appropriate pitch + canonical purchase) but one pipeline.

  Considered + rejected: merging into a single component with a
  variant parameter. The phase variant's value-prop framing differs
  meaningfully — keeping it as a separate soft-pitch surface is the
  cleaner UX.
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug 40c401 — paywall phase variant CTA was a dead-end

closes-oi: OI-40

Soft-pitch sheet now correctly escalates to the canonical paywall on tap. Two surfaces, one purchase pipeline.
