---
bug_id: b9e4c3
date: 2026-11-26
batch: oi348-walk-rest (found by plan review round 2)
status: fixed
tier: m_fix
blast_radius: platform
symptom: |
  Edit Profile, AI body-fat assessment: every refusal from assess-body-composition reads
  "Assessment failed. Please try again." A second try within 30 days never says when the next one
  is allowed, an unsuitable photo never says why, and `pro_required` never opens the paywall.
  The repository read `response.status != 200`, but `client.functions.invoke` (functions_client
  2.7.1, lib/src/functions_client.dart:255-269) THROWS FunctionsHttpException on any non-2xx, and
  `SupabaseService.retryColdStart` rethrows a 4xx. So the branch that built
  BodyCompositionAssessmentException never ran and the screen's `on` clause for it was dead.
  Found by reading the code; older than this batch. Since d7a2e4 these expected refusals were also
  recorded as non-fatals.
concept: body_fat_assessment_persist
sot_registry_entry: not_applicable
writers:
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "assessBodyComposition (catch of FunctionException) and bodyCompositionRefusalOf", line: 1466 }
readers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_runBfAssessment: on BodyCompositionAssessmentException (paywall, next allowed date, photo message)", line: 1929 }
hive_key_prefix: none
hive_key_formula: "not applicable: a refusal writes nothing"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/body_composition_refusal_behavioral_test.dart
ist_handling:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, line: 1847, fn: _formatDate }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [body_fat_assessment]
cross_account_guard: "not applicable: no write."
forbidden_patterns_checked:
  - { pattern: "a user-visible branch on a non-2xx response.status after callFunction in assessBodyComposition", absent: true }
proposed_fix: |
  Catch FunctionException around the call. When its details carry one of the three codes the
  function sends (pro_required, rate_limited, unsuitable_image), throw
  BodyCompositionAssessmentException with the status, message and next_allowed_at; anything else
  (5xx, gateway body, no network) is rethrown unchanged, so no raw server text reaches the user and
  it is still recorded. The Edge Function is unchanged and not redeployed.
regression_test_planned: |
  test/contracts/body_composition_refusal_behavioral_test.dart: the real repository method over
  real HTTP against a loopback server (429, 422, 403 map; 500 and an unknown code stay
  FunctionException; 200 returns the data). test/profile/edit_profile_save_closed_screen_test.dart
  "the monthly limit says when the next one is allowed": the real AI Assess button, the snackbar
  text and no non-fatal.
mutation_proof: |
  See "Mutation results" below.
impact_analysis: |
  One repository method and the screen's existing branches, which were already written for these
  codes. No stored value, no server change. Other `status != 200` checks after callFunction exist
  in lib/ and are not part of this fix.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "assessBodyComposition + bodyCompositionRefusalOf; new behavioral tests." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "A refusal writes nothing." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "Read supabase/functions/assess-body-composition/index.ts: 403 pro_required, 429 rate_limited + next_allowed_at, 422 unsuitable_image, all as application/json. The deployed version was not re-read; no change, no deploy." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "The client now reads the refusal where invoke delivers it. A live refusal was not triggered (it needs a PRO user token and spends the month's assessment)." }
recurrence: "Recurrence of the class recorded in memory feedback_function_exception_class (APK Test #12.5, create-razorpay-order 409 handled in dead code)."
related_bugs: [d7a2e4]
---

# b9e4c3 - Body-fat assessment refusals never reached the user

## What happened
The client handled the function's refusals as a response status, which `functions.invoke` never
returns for them. They arrive as a thrown exception, so the screen showed its general failure line.

## Fix
Read the refusal from the thrown `FunctionException`; leave every other failure as it was.

## Mutation results
Rule 21, mutate/run/restore from a saved byte copy (restore verified by bytes). The `throw` of the
refusal removed: 3 RED in the repository test; the same change run against the closed-screen file:
the "monthly limit" screen test went red (one other test of that file also went red once in that
run, see d7a2e4). Any code read as a refusal: 1 RED.

## Code review (B-pass, 2026-11-27): the next-allowed date was shown in UTC

Making the message reachable exposed an older helper: `_formatDate` read day and month from the
parsed UTC instant, so any time from 18:30 to 23:59 UTC showed the day before the real India date,
and a try on the shown day was refused. It now converts with `istDateOf`. The screen test's
fixture moved from 10:00Z (same day in both zones) to 20:00Z and expects the next day. Mutation:
the conversion removed, 1 RED.
