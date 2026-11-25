---
bug_id: a2f144
date: 2026-11-25
batch: oi348-landing3a (OI-348 walk, Landing 3a, P1)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk decision P1 (founder 2026-11-22): PRO phases keep coming after Phase XII and the copy must say "all phases". Investigation found the app still told users phases END at 12 ("phases 2-12", "Phases II-XII", "full 48-week journey", the paywall letterhead "Phases 2-12 is a PRO feature", the coach manual "Phases II-XII auto-generated"), and three display surfaces stop at 12: (1) every phase numeral map was 1-12 with an arabic fallback, so a PRO user in Phase XI saw "PHASE 13" for the phase two ahead in the week selector (week_selector.dart labels at current+1 / current+2); (2) the Profile journey card drew 12 dots, so from Phase 13 every dot read completed and none current; (3) its name line fell back to "Phase N", reading "Phase 13 — Phase 13". The preview route's 1-12 parse (preview_plan_provider.dart) also returned Phase I for anything past XII; that one is LATENT (only free users reach the preview, for II and III). The generator itself is uncapped (plan_engine/plan_generator.dart _getPhaseMeta names 13+ "Deployment N"; workout_schedule_read_service.dart removed the >= 12 dead end 2026-05-31).
concept: phase_roman_numeral
sot_registry_entry: phase_roman_numeral
writers:
  - { file: lib/core/utils/roman_numeral.dart, method_or_widget: "toRoman (1..3999, digits otherwise) / fromRoman (canonical only)", line: 32 }
  - { file: lib/core/utils/hold_week_labels.dart, method_or_widget: "phaseRoman => toRoman (the one phase-label entry point)", line: 157 }
  - { file: lib/features/profile/widgets/journey_phase_dots.dart, method_or_widget: "journeyDotBlockStart / journeyPhaseName / JourneyPhaseDots", line: 15 }
readers:
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: "_phaseRoman => phaseRoman (labels current, +1, +2, past phases)", line: 992 }
  - { file: lib/features/train/widgets/hold_roadmap_strip.dart, method_or_widget: "_roman => phaseRoman", line: 30 }
  - { file: lib/features/train/providers/preview_plan_provider.dart, method_or_widget: "_romanToInt => fromRoman ?? 1", line: 185 }
  - { file: lib/features/profile/screens/profile/journey_timeline.dart, method_or_widget: "journeyPhaseName + JourneyPhaseDots", line: 121 }
  - { file: lib/core/utils/hold_week_labels.dart, method_or_widget: "futurePhaseUnlockCopy 'Complete Phase X to unlock Phase Y' (phaseRoman)", line: 203 }
hive_key_prefix: "n/a (display only)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/core/roman_numeral_test.dart
ist_handling: ["none: no dates"]
provider_invalidations: ["none"]
telemetry_op_types:
  success: [paywall_shown]
  failure: []
cross_account_guard: "n/a (pure display)"
forbidden_patterns_checked:
  - { pattern: "a quoted 'XII' numeral table outside roman_numeral.dart", absent: true }
  - { pattern: "2-12 / II-XII / 48-week in any lib/ Dart string or captain_manual.ts", absent: true }
  - { pattern: "List.generate(12 in journey_timeline.dart", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-landing3a.md (2 review rounds, converged; founder 2026-11-25 "fix numbering too").
  1. One converter lib/core/utils/roman_numeral.dart (toRoman / fromRoman). phaseRoman delegates; week_selector._phaseRoman and hold_roadmap_strip._roman stay as one-line delegates (a gate, scripts/check_week_selector_phase_labels.dart, and two tests pin the name _phaseRoman(widget.currentPhase); review round 1). The preview parse uses fromRoman ?? 1.
  2. Journey card: JourneyPhaseDots draws the 12-phase block holding the current phase (13-24, 25-36 ...); the name cycles the card's own 12 names (Phase 13 = "Foundation"). Phases 1-12 render as before. The three phase-name lists (journey card, generator blob, WorkoutScheduleReadService.phaseNameFor) already differed before this batch; not widened, not unified here.
  3. Copy (Wardroom, terse): the paywall feature token 'Phases 2-12' -> PaywallSheet.phaseProgressionFeature = 'Phase Progression' at the five doors + the subtitle switch (letterhead "Phase Progression is a PRO feature"); benefit "Generate new plans after Week 4 (all phases, no end point)"; phase variant "Auto-generate all phases after Phase I ..." / "All phases after Phase I unlock automatically ..."; Phase 2 preview card "All phases unlock, with no end point"; coach manual "All phases after Phase I auto-generated, with no end point (free locks at Phase I after 4 weeks)" (the hold-week warning after it is unchanged; captain_manual_hold_test reads it). Comments and docs swept the same way.
  4. Telemetry: paywall_shown feature= changes from "Phases 2-12" to "Phase Progression" ON PURPOSE (paywall_sheet.dart protects funnel continuity, Hermes L1): pre-launch, testing accounts only (CLAUDE.md section 1); stated on the constant.
  5. Server copy reaches the coach only after ai-proxy and weekly-report are redeployed (founder go; closure ledger P1-EF-DEPLOY).
regression_test_planned: |
  test/core/roman_numeral_test.dart (5): known values incl. XIII/XIV/XIX/XL/XLIX/MCMXCIV/MMMCMXCIX, round trip 1..200, out-of-range digits, strict parse (IIII, VX, IC, lower case, spaces rejected), phaseRoman(13) = XIII.
  test/contracts/phase_roman_single_source_test.dart (4): no other numeral table under lib/, the three delegates, the preview parse.
  test/features/profile/journey_phase_dots_test.dart (10): wiring pin, block start, cycling names, phases 1/12/13/24/25 pumped (12 dots, exactly one current, completed count), free dimming.
  test/contracts/phase_copy_no_end_point_test.dart (3): ban on the old wording in lib/ strings and the manual; the five doors use the one constant.
  test/contracts/phase_13_generation_behavioral_test.dart (2): CHARACTERIZATION (the generator already did this): phases 13 and 14 generate "Deployment 1/2" with 4 weeks of non-empty days.
  Deno supabase/functions/_shared/captain_manual_limits_test.ts (+1): no II-XII / 2-12, the new line present.
  INVERTED: test/contracts/hold_week_labels_test.dart pinned phaseRoman(13) == '13'; now 'XIII' (0 still '0').
  Repointed (never loosened) to the constant: paywall_phase_variant_mode_none_test, paywall_generic_upgrade_title_behavioral_test, audit_2026_06_07_batch5_regression_test, phase_c_oi_closures_test.
mutation_proof: |
  Rule 21, scratchpad mut3a.sh (cp backup, applied-check, cp back, cmp clean): M8 toRoman capped at 12 -> 4 red; M9 a private 1-12 map back in week_selector -> 2 red; M10 the old token at plan_expired_card -> 3 red; M11 "Phases II-XII" back in the variant -> 1 red; M12 dot block pinned to 1 -> 5 red; M13 journey name back to "Phase N" past 12 -> 1 red; M14 preview parse back to a small map -> 1 red.
  The phase-13 characterization test was NOT mutated: its only mutation target is plan_generator.dart, which root CLAUDE.md rule 14 says never to modify without explicit instruction (not even temporarily). Stated, not claimed.
impact_analysis: |
  Display only; phases 1-12 render byte-identical except the changed copy. The phase variant and paywall show the new words in every build mode. The roadmap screen's own 12-week / DEPLOYMENT 01 limits (train CLAUDE.md "Compact top of screen") are a separate, pre-existing item not touched here. ward_phase_dots.dart (totalPhases = 12) is exported but unused in lib/; phase2_preview_card._phaseDisplayName falls back to "Phase n" past 12 but the card shows II/III only; sign_in_screen "Twelve months. We change the man." is brand time copy, not a phase cap (all recorded verified_clean on the ledger).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "roman_numeral.dart, hold_week_labels.dart, week_selector.dart, hold_roadmap_strip.dart, preview_plan_provider.dart, journey_phase_dots.dart, journey_timeline.dart, paywall_sheet(.dart, _phase_variant.dart), phase2_preview_card.dart, 3 paywall doors; 24 new tests + 5 repointed/inverted green." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive read or write changed." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "None." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "None." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "_shared/captain_manual.ts line changed (imported by ai-proxy and weekly-report only); deno test supabase/functions/ 1966 passed; deno check both; redeploy waits for the founder go." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The paywall token is client-only (git grep: no server reader); the gate key phases_2_to_12 is unchanged." }
recurrence: "Not a recurrence. Same family as the past-phase display fixes (5c8e2a) in that a display assumed a fixed 12-phase arc after the generator dropped the cap on 2026-05-31."
related_bugs: [5c8e2a]
---

# a2f144 - phase-numeral-past-xii

## What happened
The generator stopped capping phases at 12 in May, but the labels, the Profile journey card and the sales copy kept assuming twelve. Phase 13 showed as "13", the journey card showed no current phase, and the paywall promised "Phases 2-12".

## The fix
One numeral converter for every phase label (XIII, XIV, ...), a journey card that shows the 12-phase block you are in, and copy that says "all phases, no end point", including the coach's manual (live after the Edge Function redeploy).
