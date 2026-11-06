---
bug_id: ea1059
date: 2026-05-23
batch: APK Test #16.2 +30 obs 5-12 batch — post-mockup additions (commit 14 / Theme J)
status: shipped
symptom: |
  Founder reviewed the Theme H-followup mockup 2026-05-23 and spotted
  that the graduation screen's Phase 2 preview card hardcodes
  `5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY` and a static 5-day
  template (`Day 1: Upper Power`, `Day 2: Lower Power`, `Day 3: Rest
  & Mobility`, `Day 4: Upper Hypertrophy`, `Day 5: Lower Hypertrophy`).

  Root cause: `_buildPhase2Preview` at `graduation_screen.dart:294`
  rendered a static template independent of the user's actual profile.
  Meanwhile the GENERATE NEXT PHASE CTA at the same screen (line 533)
  passes `profile['days_per_week']` dynamically to `generateAndSchedule`
  — so a 4-day user sees a 5-day preview but actually unlocks a 4-day
  plan. Misleading preview; the unlock surface itself was correct.
concept: graduation_phase2_preview
sot_registry_entry: workout_plan_preview
writers: []
readers:
  - { file: lib/features/train/screens/graduation_screen.dart, method_or_widget: _buildPhase2Preview — dry-runs PlanGenerator.generateV4 with the user's actual profile + next phase number, renders phase.weekPlans[0].workoutDays as the day-row strip + dynamic meta line, line: 294 }
hive_key_prefix: "n/a — preview-only render path; no Hive writes"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: test/contracts/graduation_phase2_preview_dynamic_test.dart
ist_handling:
  - { file: lib/features/train/screens/graduation_screen.dart, line: 294, source: "no date-key math — preview render only" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [graduation_phase2_preview_failed]
cross_account_guard: reads via UserRepository.instance.getProfile / getProgress which route through wrapUserScopedBox.
forbidden_patterns_checked:
  - "Hardcoded `5 DAYS/WEEK` literal — misleads non-5-day users."
  - "Hardcoded day-label list — different days_per_week + goal combos produce different splits."
  - "Calling generateV4 with side effects — must remain a pure dry-run; no Hive writes from this preview path."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "graduation_screen.dart:294-450 — _buildPhase2Preview rewritten + new _PreviewDay/phaseDisplayName/_phaseFocus helpers at end of file" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/graduation_phase2_preview_dynamic_test.dart — 8 assertions covering UserRepository read, generateV4 call, banned literals removal, dynamic meta line, dynamic phase title, telemetry on failure path" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/graduation_screen.dart (only consumer)
  callers_updated_in_this_batch:
    - lib/features/train/screens/graduation_screen.dart (rewrite + helpers + PlanGenerator import)
  callers_unchanged:
    - lib/shared/repositories/plan_generator.dart (PlanGenerator.generateV4 already pure; no change needed)
    - lib/features/train/providers/preview_plan_provider.dart (already uses generateV4 the same way; no change needed)
proposed_fix: |
  Rewrite _buildPhase2Preview (graduation_screen.dart:294-450):

  1. Read profile + progress via UserRepository at top of method.
  2. Derive nextPhase from progress.current_phase (matches the CTA logic
     including the 9-12 cycling for users who completed all 12).
  3. Pull daysPerWeek, goal, equipment, experienceLevel, injuries from
     profile (same defaults as previewPlanProvider).
  4. Call `PlanGenerator.instance.generateV4(...)` inside a try/catch.
     On success: take phase.weekPlans[0].workoutDays.take(5) and map to
     `_PreviewDay` records (title=name, exercises=first 3 names joined).
     On failure: telemetry `graduation_phase2_preview_failed` + fall
     back to a single descriptive line.
  5. Compute meta line dynamically:
     `'$daysPerWeek DAYS/WEEK · WEEKS ${(nextPhase-1)*4+1}-${nextPhase*4} · ${focusUppercased}'`.
  6. Chip label = `'PHASE $nextPhase'`. Phase title from `_phaseDisplayName(nextPhase)`.
  7. Day rows iterate via `previewDays.asMap().entries` (Dart flow
     analysis can't promote nullable across `List.generate` closure
     boundary; the for-in pattern with non-null entries works).
  8. Add helpers at end of file: `_PreviewDay` data class +
     `_phaseDisplayName` 1→12 map + `_phaseFocus` 1→12 map.
  9. Add `import 'package:icanbefitter/shared/repositories/plan_generator.dart'`.
regression_test_planned:
  - test/contracts/graduation_phase2_preview_dynamic_test.dart — 8 assertions: _buildPhase2Preview reads UserRepository; calls PlanGenerator.generateV4; banned "5 DAYS/WEEK" literal absent; 5 banned day-label literals absent; reads .workoutDays + name field; meta line interpolates daysPerWeek + week range from nextPhase; phase chip + title come from nextPhase; failure path emits graduation_phase2_preview_failed telemetry + fallback copy.
related_bugs:
  - 7b3eaf  # Theme F2 — same screen's CTA gate hardening (sibling fix)
  - ec4d27  # Theme F + F-NEW — same screen's unlock flow
  - b0baa5  # Theme H — same flow's startDate computation
---
# Body

## Why dry-run generateV4 (not a fixed Phase 2 sample)

`PlanGenerator.generateV4` is pure — zero Hive writes, zero network,
zero telemetry. Same call `previewPlanProvider` already uses for the
locked-week preview at /train/preview. Reusing it means the founder's
preview reflects EXACTLY what the unlock CTA will generate when tapped
— not a contrived sample that drifts from the canonical plan engine.

## Why all helpers stay private

`_PreviewDay`, `_phaseDisplayName`, `_phaseFocus` are leading-
underscore private to graduation_screen.dart. They don't need to be
exported — only this screen renders the preview. If a future screen
needs the phase metadata, lift them to `lib/shared/repositories/
plan_engine/phase_metadata.dart` at that time; premature extraction
without a second caller would be over-engineering.

## Why for-in over List.generate

`previewDays` is nullable (`List<_PreviewDay>?`) because the
generator call lives inside try/catch and the fallback path leaves
it null. Inside the `if (previewDays != null && previewDays.isNotEmpty)`
guard, Dart promotes the local variable to non-null — BUT not across
closure boundaries (the closure passed to `List.generate` re-reads
`previewDays` from the captured scope, where it's still nullable).
The for-in over `previewDays.asMap().entries` keeps the iteration
inline so flow analysis can promote correctly.

## Failure path telemetry

`graduation_phase2_preview_failed` op_type. Carries the phase number
+ first 200 chars of the error message. Lets us answer "did the
founder's plan generator throw at preview time?" from one SQL query
against client_errors. The fallback copy ("`$daysPerWeek workout
days personalised to your goal + equipment`") keeps the surface
useful — never a blank card.
