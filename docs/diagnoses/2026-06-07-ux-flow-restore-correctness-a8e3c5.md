---
bug_id: a8e3c5
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 5, UX/flow/restore correctness)
status: fixed
blast_radius: account
symptom: >
  Twelve client UX/flow/restore defects from the 2026-06-07 audit. F3: the streak
  explainer claimed "+1 each week you complete at least 80% of scheduled workouts",
  but the real algorithm is +1 per completed scheduled DAY. F14: home rendered TWO
  profile-completeness nudges at once (the top CompletenessNudge and the mid
  ProfileNudgeCard both fire below 80%). F20: the Stats BACK button wrote the
  route-extras key current_weight_kg while the flow reads weight_kg, losing the
  typed weight on return (reset to 75.0). F25: the plan-expired upgrade passed the
  gate KEY phases_2_to_12 to showPaywallSheet, which switches on the display token,
  so the tailored subtitle was lost. F28/F29: the nutrition "remaining today" usage
  chips were invalidated only at midnight (stale after an increment) and
  cart_auditor showed REMAINING while its siblings showed USED. F34: AI-cost
  features trust local isPro() with no documented note of the server-side cap. F37:
  sleep-log restore had no pagination (truncated at the PostgREST 1000-row cap).
  F38: the every-launch lightweight restore omitted the workout plan, so
  cross-device plan_start drift was never re-anchored. F40: progress-photo capture
  had no try/catch — a PhotoQuotaException stuck the upload spinner forever with no
  paywall / snackbar. F41: the reports header had a gold/bold "SHARE" label that
  looked tappable but had no handler. F42: the plan-expired copy drifted to
  generic-wellness tone.
concept: client_ux_flow_and_restore_correctness
sot_registry_entry: "n/a — UX/flow/restore correctness; the restore contracts touched (sleep_logs pagination, workout_plan re-anchor) are governed by docs/architecture/sync.md restore-completeness"
writers:
  - "{ file: lib/core/services/sync/sync_health.dart, line: 356 } — F37 sleep restore now paginates via _fetchAllRows"
  - "{ file: lib/core/services/sync_service.dart, line: 905 } — F38 restoreLightweightAlways re-anchors the workout plan"
  - "{ file: lib/features/profile/screens/progress_photos_screen.dart, line: 60 } — F40 capture wrapped in try/catch (quota → paywall/snackbar)"
readers:
  - "{ file: lib/features/home/widgets/profile_nudge_card.dart, line: 24 } — F14 hides below 80% so only one nudge shows"
  - "{ file: lib/features/train/widgets/plan_expired_card.dart, line: 98 } — F25 passes the display token 'Phases 2-12'"
  - "{ file: lib/features/home/widgets/streak_explainer_sheet.dart, line: 84 } — F3 honest per-day rule"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: "_restoreSleepLogs (F37 pagination via _fetchAllRows); restoreLightweightAlways adds _restoreWorkoutPlan (F38)"
cloud_table: sleep_logs
cloud_columns: "n/a — F37 is a pagination fix on the existing select, no column change"
contract_test_path: test/contracts/audit_2026_06_07_batch5_regression_test.dart
ist_handling: n/a
provider_invalidations: "F28 — after each AI-cost increment the matching remaining provider is invalidated (aiTextLogRemainingProvider / scanMealRemainingProvider / cartAuditorRemainingProvider) so the chip refreshes immediately, not only at midnight"
telemetry_op_types: "restore_sleep_logs (F37 path)"
cross_account_guard: n/a
forbidden_patterns_checked: >
  streak_explainer no longer says "80%"; profile_nudge_card carries the
  "percentage < 80" guard; plan_expired passes 'Phases 2-12' (not the gate key) and
  carries no generic-wellness emoji; cart_auditor shows USED; progress_photos
  catches PhotoQuotaException + calls showPaywallSheet; sync_health restore uses
  _fetchAllRows('sleep_logs'); restoreLightweightAlways calls _restoreWorkoutPlan —
  all asserted by the Batch 5 regression guard.
proposed_fix: >
  F3 rewrite to the real per-day rule. F14 ProfileNudgeCard returns shrink below
  80% (CompletenessNudge owns that band). F20 BACK writes weight_kg. F25 pass the
  display token. F28 invalidate the remaining provider after each increment; F29
  standardise cart_auditor to USED. F34 document the server-side cap. F37 route
  sleep restore through _fetchAllRows. F38 add _restoreWorkoutPlan to
  restoreLightweightAlways. F40 try/catch with paywall (free) / come-back-later
  snackbar (PRO) + always clear the spinner. F41 remove the dead SHARE label. F42
  re-voice in the Wardroom lexicon.
regression_test_planned: test/contracts/audit_2026_06_07_batch5_regression_test.dart groups 'Restore completeness' + 'UX flow correctness' — GREEN
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: 12 UX/flow/restore sites fixed; analyze clean; regression guard green }"
  - "{ layer: client_server_contract, status: fixed_in_this_batch, evidence: F37 sleep restore paginates to the 50k ceiling; F38 plan re-anchored every launch }"
  - "{ layer: edge_function, status: verified, evidence: F34 — confirmed trg_food_text_rate_limit (migration 026) enforces the AI-cost daily cap server-side regardless of client isPro }"
impact_analysis: >
  These are the day-to-day correctness + trust paths: an honest streak rule, one
  (not two) nudge, a weight value that survives BACK, the right paywall subtitle,
  live usage chips, complete sleep + plan restore on every device, a progress-photo
  flow that recovers from a quota hit, no dead affordances, and on-brand copy. None
  changes a money / auth path; all are account-tier client correctness.
closes-diagnose: a8e3c5
---

# Client UX / flow / restore correctness (12 findings)

The broad client-correctness sweep from the 2026-06-07 audit.

## Fixes
- **F3** streak explainer → real per-day algorithm (was a fabricated weekly-80%).
- **F14** `ProfileNudgeCard` hides below 80% so only one completeness nudge shows.
- **F20** Stats BACK writes `weight_kg` (was `current_weight_kg`) — typed weight survives return.
- **F25** plan-expired paywall passes the display token `'Phases 2-12'` (was the gate key).
- **F28/F29** usage chips invalidate after each increment + cart_auditor uses the USED convention.
- **F34** documented that AI-cost caps are server-enforced by `trg_food_text_rate_limit` (migration 026).
- **F37** sleep restore paginates via `_fetchAllRows` (no 1000-row truncation).
- **F38** `restoreLightweightAlways` re-anchors the workout plan every launch.
- **F40** progress-photo capture try/catch → paywall (free) / snackbar (PRO); spinner always clears.
- **F41** removed the dead "SHARE" header affordance in reports.
- **F42** re-voiced the plan-expired copy in the Wardroom lexicon.

## Guard
`audit_2026_06_07_batch5_regression_test.dart` (Restore completeness + UX flow groups).
