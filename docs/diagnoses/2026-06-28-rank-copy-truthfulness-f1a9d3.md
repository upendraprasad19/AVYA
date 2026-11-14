---
bug_id: f1a9d3
date: 2026-06-28
batch: client-wins-hardening
status: fixed
blast_radius: platform
symptom: >
  OBS-1 (founder, live web signup): the induction "I COMMIT" screen promised
  "Make Sub Lieutenant rank — 104 workouts on this app" and "104 workouts is
  roughly six months of disciplined training". The promotion ceremony
  (ceremony_text.ts) echoed the same workout-count framing ("100 workouts on the
  books → officer track", "200 sessions — the Contract"). But the rank engine
  (rank_ladder_data.dart kRankGates) gates on TIME + CONSISTENCY only — minWeeks
  + streak (sailor) / completionRate (officer) + deployments (PO/CPO) — and
  IGNORES workout count entirely (the RankGate.totalWorkoutsAtLeast field is
  defined but NEVER set in any gate). Sub Lieutenant actually requires 104 WEEKS
  (2 years) + 80% completion, not 104 workouts. So a committed user who logs 104
  workouts in ~6 months ranks up to NOTHING — a broken-promise churn landmine at
  the point of peak investment. Pure copy↔engine drift.
concept: rank_gate_copy_truthfulness
sot_registry_entry: >
  rank_gate_copy_truthfulness — the source of truth for what a rank requires is
  rank_ladder_data.dart kRankGates (+ the human-readable rank_service._humanGateText).
  User-facing rank copy (induction_screen.dart, ceremony_text.ts) MUST describe
  that gate truthfully — time + consistency, never a workout count.
writers: >
  SOURCE OF TRUTH (unchanged this batch): rank_ladder_data.dart kRankGates +
  RankLadderEntry.minWeeks; rank_service.dart _humanGateText renders the honest
  per-rank line ("2 years of service · 80% completion (rolling 26 weeks)").
  CONSUMERS corrected this batch: induction_screen.dart _buildMsg2 (the "I COMMIT"
  pledge) + supabase/functions/_shared/ceremony_text.ts (officer-crossing + LtCdr
  ceremony lines + their comments).
readers: >
  induction_screen.dart _buildMsg2 — rendered on the onboarding "I COMMIT" screen.
  ceremony_text.ts formatPromotionCeremony — rendered by evaluate-rank-promotions
  into ai_coach_interactions rows (channel=promotion_ceremony) shown in the coach
  chat thread on promotion.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: ["ai_response"]
contract_test_path: test/ai_coach/induction_pledge_test.dart
ist_handling: >
  Not applicable — copy-only change. No timestamp/date semantics touched. The
  rank engine's IST-based week counting (phase_started_at) is unchanged.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "User-facing rank copy that states a numeric threshold (workout/session count) the rank engine does NOT gate on. The engine gates Sub Lieutenant on 104 WEEKS + 80% completion; the copy claimed '104 workouts ≈ six months'. A user hitting the stated count ranks up to nothing → broken-promise churn. FIXED: copy rewritten to the real gate (time + consistency) for both surfaces; tests now assert the false counts are ABSENT and the truthful framing PRESENT (the pre-fix induction_pledge_test actively PINNED the false '104 workouts' string)."
proposed_fix: >
  Engine UNCHANGED (founder directive: honor the engine, fix only the copy).
  (1) induction_screen.dart _buildMsg2 — replace the false "Make Sub Lieutenant —
  104 workouts / six months" pledge with framing B: anchor on the nearer fast
  ranks (first rank in opening weeks → Petty Officer by month three, threaded
  conditionally under "Hold the line") with Lieutenant named as the destination
  (no false timeline), and describe the real mechanism (80% completion,
  consistency). Ran the psychology-pass-fitness lens (caught the "PO by month
  three" over-promise → conditional framing; "guarantee" → "the contract").
  (2) ceremony_text.ts — officer-crossing + LtCdr lines now state weeksHeld (the
  real gate dimension) + totalWorkouts as a journey STAT, dropping the false
  "100 workouts on the books" / "200 sessions — the Contract" thresholds; comments
  corrected. (3) Rewrote induction_pledge_test.dart + ceremony_text_test.dart to
  GUARD the truth (assert false counts absent, truthful framing present) +
  source-grep ceremony_text.ts.
regression_test_planned: >
  test/ai_coach/induction_pledge_test.dart — asserts the induction source no
  longer contains '104 workouts' / 'Sub Lieutenant rank' / 'six months', and DOES
  reference the nearer ranks (Petty, month three) + Lieutenant + 'Eighty percent'
  + 'contract'. test/ai_coach/ceremony_text_test.dart — source-greps
  ceremony_text.ts: no 'workouts on the books' / '200 sessions'; has 'weeks on the
  line' + 'sessions logged'. Both fail on the pre-fix tree.
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — induction_screen.dart _buildMsg2 pledge rewritten truthful (framing B); both contract tests rewritten to guard the truth."
  - "edge_function_code_vs_deploy — status: fixed_in_this_batch — ceremony_text.ts copy + comments corrected in code. LIVE DEPLOY of evaluate-rank-promotions is PENDING founder per-action approval (deploy-gated) — the shared file change takes effect only on redeploy."
  - "client_code — status: verified — engine UNCHANGED: rank_ladder_data.dart kRankGates + minWeeks untouched (confirmed by reading the file); totalWorkoutsAtLeast remains unused; no promotion-logic edit."
impact_analysis: >
  Affects every user reading the onboarding pledge or a promotion ceremony. The
  false workout-count promise set an expectation the engine never honored (rank
  up on a count), which would betray the most-committed users around month 6 when
  they hit the count and ranked up to nothing — a retention landmine, not just an
  honesty gap. Copy-only; zero engine/data changes; no migration; no re-grade.
  The induction change is client (ships on the next web push / APK); the ceremony
  change ships when evaluate-rank-promotions is redeployed (founder-approved).
---

# f1a9d3 — rank copy promised a workout count the engine never gates on (OBS-1)

See YAML frontmatter for the full diagnosis. Founder OBS-1 from a live web
signup: "the sub lieutenant data is incorrect."

## Root cause (one line)
The induction pledge + promotion ceremony hardcoded a **workout-count** path to
rank ("104 workouts → Sub Lieutenant", "200 sessions — the Contract") while the
engine gates purely on **time + consistency** (`minWeeks` + streak/completionRate)
and never reads a workout count — a copy↔engine drift, with the pre-fix
`induction_pledge_test` actively pinning the false "104 workouts" string in place.

## Fix
Engine untouched (founder: honor the engine). Both copy surfaces rewritten to the
real gate — framing B (nearer fast ranks + Lieutenant as the destination) for the
pledge; weeks-held + sessions-as-stat for the ceremony — and the tests flipped to
guard the truth. Ran psychology-pass-fitness on the pledge. Ceremony EF redeploy
held for founder approval (deploy-gated).
