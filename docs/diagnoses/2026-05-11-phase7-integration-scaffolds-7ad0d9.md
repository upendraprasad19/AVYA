---
bug_id: 7ad0d9
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 10+ critical end-to-end flows had no integration test coverage at all — Razorpay purchase (the entire payment stack), sign-up + onboarding traverse, delete-account (DPDP §17 irreversible), cross-account isolation, cross-device restore, workout completion → receipt → share, streak freeze refill ↔ consume, plan generator → first workout, custom exercise submission flow, promo code apply, AI coach tool-calling. Audit recommended building out the scaffolding even if the bodies are skipped pending device-CI infrastructure.
concept: phase7_integration_scaffolds
sot_registry_entry: integration_test_coverage
writers: []
readers: []
hive_key_prefix: "n/a — integration test scaffolds"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/contracts/phase7_integration_scaffolds_present_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["scaffold_file_missing"]
proposed_fix: Create 10 integration test scaffold files under integration_test/flows/, one per critical end-to-end flow. Each scaffold has top-level docstring + group() + named test() entries with `skip: 'Phase 7 scaffold — ...'`. The skip reason explains the pre-condition (Razorpay test mode / Supabase test mode / device harness / fixture user). Add a guardrail contract test asserting every scaffold file exists + carries the skip marker + initializes IntegrationTestWidgetsFlutterBinding. The bodies themselves are Phase 8 / future-batch implementation work that needs device-CI infrastructure.
regression_test_planned:
  - test/contracts/phase7_integration_scaffolds_present_test.dart (11 individual checks — one per scaffold)
---
# Audit Phase 7: integration test scaffolding

## Why

The audit recommended "Build out the 10 missing critical flows
(incl. Razorpay purchase E2E + sign-up onboarding traverse +
delete-account E2E)." These are the highest-risk surfaces with
zero E2E coverage. Manual smoke testing has been the only signal.

Implementing the bodies requires device-CI infrastructure (Razorpay
test-mode credentials, Supabase test users, monotonic-clock harness
for streak freeze tests, etc.). The scaffolding work — file
existence + structure + documented test list + clearly-marked skip
state — is what this batch delivers.

## Scaffolds shipped (10 files + 1 guardrail)

| # | File | Coverage |
|---|---|---|
| 1 | `integration_test/flows/razorpay_purchase_flow_test.dart` | paywall → Razorpay → poll-and-activate → PRO unlock; H-19/H-20/H-41 in particular |
| 2 | `integration_test/flows/signup_onboarding_traverse_test.dart` | Welcome → 6-screen onboarding → home; H-3 self-heal verification |
| 3 | `integration_test/flows/delete_account_e2e_test.dart` | DPDP §17 — confirmation + Razorpay cancel + auth.users delete + audit row |
| 4 | `integration_test/flows/cross_account_isolation_e2e_test.dart` | Test #5 namespacing + C-6 guard + C-10 signOut routing |
| 5 | `integration_test/flows/cross_device_restore_e2e_test.dart` | Theme A restore completeness (workouts + nutrition + meals + freezes + diet plan + ranks + inbox + PRO) |
| 6 | `integration_test/flows/workout_completion_receipt_share_test.dart` | C-8 + C-14 + receipt scoping + WardSetChips primitive |
| 7 | `integration_test/flows/streak_freeze_concurrency_test.dart` | C-14 + C-15 + StreakProgressService + optimistic-lock RPC |
| 8 | `integration_test/flows/plan_generator_to_first_workout_test.dart` | targetCount + cascade depth + logging type resolver |
| 9 | `integration_test/flows/custom_exercise_submission_test.dart` | H-13 per-key restore + H-14 pagination + 7ad0c5 admin gate |
| 10 | `integration_test/flows/promo_code_apply_test.dart` | T-3 idempotency + UNIQUE(code, user_id) per CLAUDE.md §16 #7 |
| 11 | `integration_test/flows/ai_coach_tools_e2e_test.dart` | 20-tool dispatch + H-21/H-22 input caps + Test #11 L1 snackbar |

## Guardrail

`test/contracts/phase7_integration_scaffolds_present_test.dart`
asserts every scaffold file exists, initializes
`IntegrationTestWidgetsFlutterBinding`, and carries the
`'Phase 7 scaffold — ...'` skip marker. If a scaffold vanishes
from disk OR loses its skip marker (i.e., is run unintentionally
in CI without infrastructure), the guardrail fails.

## Status

All 11 guardrail tests pass on commit. Bodies are SKIPPED until
Phase 8 (or a future batch) wires up:
- Razorpay test-mode credentials in CI secrets.
- Per-run Supabase test user provisioning + teardown.
- Connected-device CI runner (e.g., Firebase Test Lab integration).
- Admin JWT for the promote-community-item flow.

## Related

- T-1..T-11 contract tests (Phase 6 — these scaffolds reference the
  same invariants from the integration side)
- CLAUDE.md §11 (AI tool-calling architecture)
- CLAUDE.md §16 (payment flow)
- CLAUDE.md §13a (onboarding 6-screen flow)
