---
bug_id: b4e9c7
date: 2026-08-03
batch: Unit B — post-batch residuals (closes OI-84)
status: fixed
blast_radius: platform
symptom: >
  `lib/features/train/screens/graduation_screen.dart` reached 909 lines against
  Gate 43's 800-line ceiling and passed only because it had been added to the
  gate's transitional allow-list — the FIRST entry that one-way ratchet ever
  took. No user-visible defect; the harm is structural. The file had already
  demonstrated the concrete cost: at 794 lines it sat SIX under the ceiling, so
  Unit 3c's phase-advance monotonic fix (`c8f3d1`) could not touch it at all
  without tripping the gate, and the allow-list entry was created to unblock
  that fix.
concept: phase_advance_write_path
sot_registry_entry: phase_progress_current_phase
writers: >
  `lib/shared/services/pro_phase_advance.dart` `runGraduationPhaseAdvance`
  (NEW — the relocated block; calls `commitPhaseAdvance`, which is the single
  writer of the advance delta) · `commitPhaseAdvance` (unchanged) ·
  `markPhaseRepeatNudgePending` (unchanged, still the shared nudge writer).
  BEFORE this unit the graduation half of that path lived inline at
  `graduation_screen.dart:637-757`. The set of writers is UNCHANGED by this
  unit — only their location moved.
readers: >
  `graduation_screen.dart:_onPro` reads the new `GraduationAdvanceResult`
  (outcome enum + `repeatNudgeFlagged`) and maps it to UI: the busy snackbar,
  the success/already-advanced snackbar copy, `phase_unlock_completed` vs
  `phase_unlock_counter_already_advanced`, and the provider-invalidation set.
  Downstream readers of the WRITE are unchanged — `week_selector.dart`,
  `plan_header.dart`, `train_provider.CurrentPlanNotifier`, and the cloud push
  of `user_progress.current_phase` via `updateProgress → syncProgressNow`.
hive_key_prefix: progress
hive_key_formula: >
  `userBox.get('progress')` — a single map keyed by the literal string
  `progress`, not a per-row composite key. Fields touched by this path:
  `current_phase`, `current_week`, `plan_generated_at`, `phase_started_at`
  (all written by `commitPhaseAdvance`), plus the separate
  `phase_repeat_nudge_pending` flag written through `MigratedKey`.
sync_methods: >
  `UserRepository.updateProgress` fires `syncProgressNow()`, which reaches
  `sync_profile.dart::_syncUserProgress`. Unchanged by this unit — the hoist
  did not alter what is written or when it syncs.
restore_methods: >
  `sync_profile.dart::_restoreUserProgress` and
  `auth_session_bootstrapper.dart` both route through
  `UserRepository.mergeCloudProgress` (Unit A / OI-83), which max-guards
  `current_phase`. Unchanged by this unit and re-verified as still reachable.
cloud_table: user_progress
cloud_columns: current_phase, current_week, plan_generated_at, phase_started_at
contract_test_path: test/contracts/pro_phase_advance_behavioral_test.dart
ist_handling: >
  not_applicable to the relocation. `commitPhaseAdvance` stamps
  `plan_generated_at` / `phase_started_at` from ONE `DateTime.now()` instant and
  that code was not touched. The hoisted block introduces no new date key and no
  new counter reset, so there is no new IST surface.
provider_invalidations: >
  DELIBERATELY LEFT IN THE WIDGET LAYER. `ref.invalidate(phaseRepeatNudgeProvider)`
  did not move with the code: `phaseRepeatNudgeProvider` is declared at
  `lib/features/home/providers/home_provider.dart:957`, and the moved code now
  lives in `lib/shared/**`. ROUND-1 REVIEW CORRECTED THE STRENGTH OF THIS CLAIM —
  the first draft called it a hard rule and cited `lib/CLAUDE.md` rule 7, but
  rule 7 is about import STYLE (relative within a feature, package: for
  shared/core), NOT direction, and FOUR `lib/shared → lib/features` imports
  already exist (hive_tab_scaffold.dart:75, user_repository.dart:10,
  video_share_button.dart:5, wardroom/ward_status_strip.dart:3) with no gate
  enforcing it. Round 2 corrected this count from three: the first grep matched
  only the `package:` spelling and missed the relative `../../../features/` one. So it is a CONVENTION,
  not an invariant. The design is kept on its own merits rather than on the
  wrong citation: the nudge's Hive WRITE is shared-layer work and belongs beside
  the cross-account belt in markPhaseRepeatNudgePending; a provider INVALIDATION
  is widget-layer work. The shared advance RETURNS `repeatNudgeFlagged` and the
  screen invalidates, which also avoids adding a fourth edge to a list that
  should be shrinking. The post-success invalidation set (`currentPlanProvider`,
  `todayWorkoutProvider`, `calendarWeekProvider`, `workoutStatsProvider`,
  `streakProvider`, `allExercisePRsProvider`, `aiInsightProvider`,
  `graduationStatsProvider`) is unchanged and still fires from the screen.
telemetry_op_types: >
  Unchanged event SET, changed emit LOCATION for two of them.
  `phase_unlock_plan_generated` and `phase_unlock_preempted_before_generate`
  now fire from `pro_phase_advance.dart`; `phase_unlock_initiated`,
  `phase_unlock_gate_routed_pro`, `phase_unlock_gate_routed_free`,
  `phase_unlock_advance_busy`, `phase_unlock_completed` and
  `phase_unlock_counter_already_advanced` still fire from the screen.
  `phase_advance_conflict_skipped` and `phase_advance_declined_rows_stale` keep
  `source: 'graduation_screen'` — that string names the SURFACE, not the file,
  and changing it would make every row already collected uncomparable.
cross_account_guard: >
  verified unchanged. The cross-account belt lives inside
  `markPhaseRepeatNudgePending` (`HiveUserSession.currentOwnerFullId != null`
  before `MigratedKey.write`), and that function moved neither its guard nor its
  callers. The hoisted code calls it exactly as the closure did.
forbidden_patterns_checked: >
  no raw `Hive.box(` (all access via `UserRepository` / `MigratedKey`);
  no `setState` for shared state (the relocated code touches no widget state);
  no `unawaited(` without an error sink introduced; no `Container(color:` +
  `decoration:`; no hardcoded colors; no `lib/shared → lib/features` import
  (this was the binding constraint on the signature — see
  `provider_invalidations`); no secret-shaped literals; no new
  `DateTime.now()` date key.
proposed_fix: >
  Two moves and one deletion, one commit.
  (1) The ~120-line `withPhaseAdvanceLock` closure moved from
  `graduation_screen._onPro` to `runGraduationPhaseAdvance` in
  `lib/shared/services/pro_phase_advance.dart`, beside `commitPhaseAdvance`
  where the other three advance paths already live. Its `bool?` return — whose
  three states the screen decoded positionally, and whose `false` covered TWO
  outcomes that already had distinct telemetry — became
  `GraduationAdvanceResult` (a four-case outcome enum plus `repeatNudgeFlagged`).
  (2) The ~250-line phase-2 preview UI (`_buildPhase2Preview`,
  `_buildPhase2Benefits`, `_PreviewDay`, `_phaseDisplayName`, `_phaseFocus`)
  moved to `lib/features/train/widgets/phase2_preview_card.dart` as
  `Phase2PreviewCard` / `Phase2BenefitsCard`. Both builders already took no
  `ref` and no `BuildContext` and touched no state, so this is a move, not a
  refactor.
  (3) The `graduation_screen.dart` entry was deleted from `_allowList` in
  `scripts/check_god_screen_max_lines.dart` in the SAME commit, so the gate
  passes on the real line count rather than by exemption. 909 → 552 lines.
  Move (2) was NOT in OI-84's recommended shape. The hoist alone landed the file
  at ~791 — nine lines of margin, which is the same condition that created OI-84
  (it sat six under, so a fix could not touch it). OI-84's own "~770" estimate
  had gone stale when Unit A grew the file to 909. Founder chose the fuller
  split when shown that arithmetic.
regression_test_planned: >
  Shipped, not planned. `test/contracts/pro_phase_advance_behavioral_test.dart`
  gains group D2 — four behavioral tests driving `runGraduationPhaseAdvance`
  against real Hive and real plan generation, one per outcome arm (`committed`,
  `preemptedBeforeGenerate`, `generatedButDeclined`, `busy`) — plus two source
  assertions (`graduation_screen retains NO advance mechanism of its own`;
  `graduation_screen is OFF the Gate 43 allow-list and under the ceiling on its
  own merits`). That behavioral coverage did not and could not exist before:
  the code was a closure inside a widget callback, so nothing could call it.
  Six pre-existing source-grep test files were re-pointed at the code's new
  home; ten of their assertions were then individually PROVEN to discriminate
  by perturbing the source and observing each fail (see `touched_layers_checked`
  tier 1).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on all 3 touched lib files (it also caught 3 now-dead imports in graduation_screen.dart — dart:ui, migrated_key.dart, injury_vocab.dart — all removed). Gate 43 green with the allow-list entry DELETED: 'OK — no screen exceeds 800 lines', and graduation_screen.dart absent from the ALLOW output. NEGATIVE CONTROLS: 9 source perturbations over 2 rounds made exactly the 10 intended assertions fail (orphan guard, start-date routing, telemetry union, plan_generated_at chain, advance-regrowth guard, blast-radius tier guard, 4 advance-choice seam assertions); all 4 touched files restored from copies and verified byte-identical by md5, never git checkout" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "group D2's 4 tests drive the real progress map through UserRepository against real plan generation, one per outcome arm. preemptedBeforeGenerate additionally asserts plan_start_date is UNCHANGED — what distinguishes 'skipped generation' from 'generated then declined', and the assertion that fails if the in-lock recheck is ever deleted" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "no migration and no column added/dropped/renamed; user_progress.current_phase, current_week, plan_generated_at and phase_started_at are still written by the same unmodified commitPhaseAdvance" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "code relocation only — no rows written or migrated" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this unit; backups/applied_migrations.json untouched" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron-dispatched function touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no table or policy touched" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no Storage surface touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read, written or referenced" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no Razorpay / OneSignal / Firebase surface touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "full unlock flow re-traced after the move: tap → gateAndVerify(phases_2_to_12) → _onPro → choice sheet → pre-lock live check → runGraduationPhaseAdvance → generateAndSchedule → commitPhaseAdvance → updateProgress → syncProgressNow → user_progress. phase_unlock_end_to_end_test.dart pins BOTH links of the new two-hop chain; asserting only the second would still pass if the screen stopped calling the advance at all" }
impact_analysis: >
  The unit moves code and deletes a gate exemption. The rendered output and the
  advance semantics are identical. ONE genuine behaviour delta exists and
  round-1 review caught it being overclaimed away.
  **Evaluation timing of the phase-2 preview changed from eager to lazy.**
  `_buildPhase2Preview()` was a METHOD CALL inside `ListView(children: [...])`,
  so `PlanGenerator.generateV4` ran during every `GraduationScreen.build()`. It
  is now `const Phase2PreviewCard()`, so `build()` runs when the element mounts
  (lazily, per SliverChildListDelegate's viewport + cacheExtent) and the const
  instance is canonicalized, so it does not rebuild when the parent does.
  Accepted deliberately, both consequences stated rather than hidden:
  (a) a full plan generation no longer runs on every unrelated parent rebuild,
  which is strictly better — running generateV4 on each graduationStatsProvider
  tick was waste; (b) `graduation_phase2_preview_failed` now fires roughly ONCE
  PER MOUNT (~per screen-open) instead of on every parent rebuild. That loses no
  failure signal — a generation that
  never runs cannot fail — but it changes the metric's denominator, so rate
  comparisons against pre-2026-08-03 samples are not like-for-like. The inputs
  (profile, current_phase) cannot change while this screen is displayed, so
  pinning them at mount costs nothing.
  The genuine risk was NOT the move — it was the six test files that
  source-grep `graduation_screen.dart` by path. Moving code out of a file that
  greps assert against silently turns those assertions vacuous: they keep
  passing while testing nothing, which is worse than deleting them
  (`feedback_source_grep_false_confidence.md`). Every one was re-pointed at the
  code's new home and then proven to still fail when that code is perturbed.
  Two second-order findings, both fixed here:
  (1) `docs/blast_radius.yaml:207-216` justified graduation_screen.dart's
  file-scoped `account` rule with "contains a confirmed direct write to the
  progress map (`_onPro()`)". After the hoist that is FALSE. The tier is
  correct and unchanged — the screen is still the UI entry point for the PRO
  advance and gates `phases_2_to_12` — but the stated reason had to be
  restated, because a rule whose justification is false reads as coverage it
  does not have (the same class as the `check_writer_reader_drift.dart` citation
  corrected in `lib/CLAUDE.md` on 2026-08-02, for a script that never existed).
  (2) The hoist could have moved the progress write into a path classified
  BELOW `account`, silently weakening the review gate while every other test
  stayed green. It did not — `docs/blast_radius.yaml:226` gives
  `pro_phase_advance.dart` its own file-scoped `account` rule — but that was
  ASSERTED rather than assumed, in a new test, so the next move cannot regress it.
---

# Graduation screen exceeded the Gate 43 ceiling and shipped on an allow-list exemption (b4e9c7)

Closes **OI-84**. Companion to `c8f3d1` (Unit 3c), which created the allow-list
entry, and to `d1f6b3` (Unit A), which grew the file to 909 lines.

## Why this is filed as a diagnose-doc

There is no user-facing bug here, and the commit is a `refactor:`, so the
commit-msg gate does not demand this document. It is written anyway, following
Unit 6's precedent (`2729c37c`, the CQRS split closing OI-44, which shipped two
diagnose-docs for an equally behaviour-neutral change). The reason is that the
*risk* of this unit is entirely in the seams — six source-grep tests, a
blast-radius justification, and a telemetry `source:` string — and none of that
is legible from the diff alone.

## The ratchet

`scripts/check_god_screen_max_lines.dart`'s allow-list is documented in its own
header as one that "MUST shrink to empty when the audit ladder closes". Every
movement before 2026-08-01 was a removal: C3 took `active_workout` 2430 → 456;
C4 took `train` / `profile` / `ai_coach` from 2419 / 2274 / 1906 to 312 / 376 /
357. `graduation_screen.dart` was the first addition, authorized in chat after
the founder was shown that the gate has no per-run exception — no env var, no
`--warn-only`, it exits 1 unconditionally — so Unit 3c could not otherwise
proceed.

This unit removes that entry. The list is back to six, all of them original C4
targets, and the direction is back to shrinking.

## Why the split is larger than OI-84 specified

OI-84 recommended the hoist alone and estimated it would land the file "at
~770". That estimate was made when the file was 892 lines. Unit A then added 17
lines, so the same hoist landed at ~791 — **nine lines of margin**.

Nine lines is the OI-84 condition all over again. The board item exists
*because* a file sitting six lines under the ceiling blocked a fix that needed
to touch it, and the three review rounds of Unit A alone added 77 comment lines
to this file at reviewers' request. Extracting the preview card as well takes it
to 552 — 248 lines of headroom — and was the founder's call once the arithmetic
was shown.

## What could not move, and why

`ref.invalidate(phaseRepeatNudgeProvider)` stayed in the screen. The provider is
declared in `lib/features/home/providers/home_provider.dart:957`, and
`lib/shared/**` may not import `lib/features/**`. The Hive write
(`markPhaseRepeatNudgePending`, which owns the cross-account belt) moved; the
provider invalidation did not; `GraduationAdvanceResult.repeatNudgeFlagged` is
the seam between them. `advance_choice_test.dart` now pins both halves AND
asserts `pro_phase_advance.dart` never mentions `phaseRepeatNudgeProvider`, so
the layering cannot quietly invert later.

`AdvanceChoice` stayed in the feature layer for the same reason — the shared
advance takes a plain `bool repeat`. The closure only ever asked
`choice == AdvanceChoice.repeat`, so nothing is lost.

## The `bool?` that was lossier than its own telemetry

The old closure returned `bool?`: `null` = busy, `true` = committed, `false` =
either *preempted before generating* or *generated then declined*. Those last
two already emitted **different** telemetry events, so the return type was
strictly less expressive than the instrumentation beside it. It is now a
four-case enum.

The screen deliberately still renders the same copy for both non-busy failure
modes. That is the pre-hoist behaviour and this unit changes structure, not
behaviour — the enum makes a future divergence *expressible*, and nothing
diverges yet.

## Round-1 review — 6 findings, all real, all fixed

Two context-blind reviewers, distinct lenses (behaviour-preservation; test/gate
integrity). Every claim was re-verified against the files before being acted on
(`feedback_audit_verifier_cannot_trust_own_subagent`). Nothing was refuted.

**Two of the six were in tests written specifically to catch that class**, which
is the finding that matters most here:

1. **The `'current_phase': nextPhase` negative guard went trivially true.** The
   pre-existing assertion banned that literal in `graduation_screen.dart`.
   Re-pointing it at `pro_phase_advance.dart` made it unfalsifiable — that
   literal has no route into a file where `nextPhase` is a parameter. Worse, the
   replacement ban-list named only helper FUNCTIONS, so a regrown raw
   `updateProgress({'current_phase': …})` in the screen — the exact Unit 3c /
   OI-45-finding-5 defect — would have passed every test in this batch. Now the
   write itself is banned in the screen, with an explicit companion assertion
   that the READ stays legal (the pre-lock abort check needs it).
2. **The blast-radius test covered one of the unit's two extraction targets**
   while its own comment claimed to cover "the hoist". `phase2_preview_card.dart`
   classifies `feature` — which is CORRECT (it is read-only UI; no
   progress-map write) — but that was asserted nowhere. Now pinned, so a future
   write there trips a test instead of silently landing in a weaker tier.
3. **The layering justification cited a rule that says something else** — see
   `provider_invalidations` above. Design unchanged, reasoning corrected.
4. **"Behaviour-preserving" was overclaimed** for the preview extraction — see
   `impact_analysis` above. Eager → lazy is real and is now documented.
5. Three stale `graduation_screen._onPro` references left in
   `pro_phase_advance.dart`'s own doc comments (`:267`, `:288`, `:309`) — the
   caller they name now lives 200 lines below them in the same file.
6. The gate comment said "909 → 555 lines"; the file is **552**. Written before
   three dead imports were removed. Both reviewers caught it independently.

Also fixed from the same round: the `runGraduationPhaseAdvance … commitPhaseAdvance`
chain regex was unbounded (`[\s\S]*?`) where every sibling regex bounds its
window, and `repeatNudgeFlagged` had no behavioral arm — all four outcome tests
passed `repeat: false`, so the flag assertion would have held even with the
whole pins/nudge branch deleted.

**The first attempt at that last fix was itself vacuous, and a mutation test is
what proved it.** It asserted an EQUIVALENCE —
`expect(result.repeatNudgeFlagged, nudgeWritten)` — which looked like a real
end-to-end check of the seam. It is not: one variable (`pins != null`) drives
BOTH the Hive write and the returned flag, so mutating that variable moves both
sides of the equivalence together. Substituting `repeatNudgeFlagged = repeat`
for `pins != null` left the test **green**. Self-consistency that is true by
construction is not a test.

The shipped version asserts against independent ground truth instead: with
`repeat: true` in a state that has no prior phase content, the G5 frame-shape
gate must refuse, so `pins` is null — precisely the case where `pins != null`
and `repeat` DISAGREE. Correct code flags nothing and writes nothing; the
mutation flags true and writes the nudge, failing both expectations. Verified
both directions: clean passes, mutated fails, source restored and md5-checked.
The premise (pins really is null in that state) is CHECKED by the assertion
rather than assumed — if the generator ever built pins there, the test fails
loudly instead of passing vacuously.

## Verification

- Gate 43 green with the allow-list entry deleted; `graduation_screen.dart`
  absent from the ALLOW output; 552 lines against the 800 ceiling.
- `flutter analyze` clean on all touched files.
- Group D2: five behavioral tests — one per outcome arm plus the
  repeat-nudge seam — against real Hive and real plan generation.
- Ten re-pointed assertions across six files individually proven to
  discriminate, by perturbation and restore-with-md5-verification.
