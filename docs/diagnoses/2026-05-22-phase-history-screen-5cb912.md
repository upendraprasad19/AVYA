---
bug_id: 5cb912
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 12 / Theme H-followup)
status: shipped
symptom: |
  Founder's wish 2026-05-21 evening: "i want the completed phases to
  be available to the user, which i can scroll and check."

  Pre-fix the train screen renders only the current 12-week window.
  Once a user unlocks Phase 2, Phase 1's completed history rolls out
  of view. The founder explicitly asked for a way to scroll back —
  not just to verify the data integrity Theme H restored, but as a
  durable reflection surface (PRs hit, weeks completed, dates).

  This is purely additive — a new screen reading existing Hive data
  with no mutation. Pairs with Theme H (b0baa5) which protects the
  underlying data from planGenerator overwrite (completed-day guard
  on upsertScheduled).
concept: phase_history_view
sot_registry_entry: scheduled_workouts_mutations
writers: []
readers:
  - { file: lib/features/train/screens/phase_history_screen.dart, method_or_widget: PhaseHistoryScreen — reads schedule_* keys from workoutBox, groups by phase number (1-4=Phase 1, 5-8=Phase 2, ...), filters to phases with at least one status=completed day, renders list of phase cards with date range + completion %., line: 1 }
  - { file: lib/core/router/app_router.dart, method_or_widget: /train/history GoRoute name=phaseHistory builds PhaseHistoryScreen, line: 343 }
  - { file: lib/features/train/screens/graduation_screen.dart, method_or_widget: "VIEW PAST PHASES" GestureDetector pushes /train/history under the GENERATE NEXT PHASE CTA, line: 130 }
hive_key_prefix: "schedule_"
hive_key_formula: "schedule_${istDateStr(date)}"
sync_methods: []
restore_methods: []
cloud_table: scheduled_workouts
cloud_columns: [date, week, status, completed_at, workout_name]
contract_test_path: test/contracts/phase_history_screen_test.dart
ist_handling:
  - { file: lib/features/train/screens/phase_history_screen.dart, line: 100, source: "reads `date` field directly from the schedule_* entries (already in IST date-key format per WorkoutWriteService.upsertScheduled). No date math; display only." }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: PhaseHistoryScreen reads via HiveService.instance.workoutBox which wraps via wrapUserScopedBox.
forbidden_patterns_checked:
  - "Surfacing in-progress phases (no completed days) as 'completed history'."
  - "Empty-screen with no copy when user has no completed phases yet — every screen handles loading / error / empty per CLAUDE.md §4.4 rule 13."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "phase_history_screen.dart (new) + app_router.dart route added + graduation_screen.dart entry point" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/phase_history_screen_test.dart — 6 assertions: file exists, route declared, entry button present, schedule_ reader, status=completed filter, empty-state copy" }
impact_analysis:
  callers_audited:
    - lib/core/router/app_router.dart (only route consumer)
    - lib/features/train/screens/graduation_screen.dart (only entry point)
  callers_updated_in_this_batch:
    - lib/features/train/screens/phase_history_screen.dart (new)
    - lib/core/router/app_router.dart (route)
    - lib/features/train/screens/graduation_screen.dart (entry button)
  callers_unchanged:
    - lib/core/services/workout_write_service.dart (no mutation paths added)
    - Cloud schema (no migrations — read-only screen)
proposed_fix: |
  Three pieces:

  1. NEW lib/features/train/screens/phase_history_screen.dart:
     - ConsumerWidget (no mutation = no need for state).
     - _loadPhaseHistory() reads workoutBox.toMap().entries, filters
       to keys starting with `schedule_`, groups by phase number
       derived from `week` field via `((week - 1) ~/ 4) + 1`, skips
       phases with zero completed days.
     - Per phase: total days, completed days, date range (min/max
       `date` field).
     - List view of _PhaseHistoryCard tiles, each showing PHASE N
       header + completion % chip + date range + "X of Y days
       completed" line.
     - Empty state: "No completed phases yet" + helper copy.

  2. Route /train/history in app_router.dart, name=phaseHistory.

  3. Entry point on graduation_screen.dart: "VIEW PAST PHASES"
     GestureDetector under the GENERATE NEXT PHASE CTA, pushes the
     route. Push (not go) so back-button returns to graduation.

  Future enhancements (NOT deferred bugs — discrete additive UX
  improvements):
  - Tap a phase card → modal with per-week breakdown (which day was
    workout, which was rest, completion timestamps).
  - PR table per phase (best lifts during that 4-week window).
  - Share button → PR card image for that phase.
  These are tracked in batch retrospective as discrete UX work
  items independent of this commit's data layer + minimum surface.
regression_test_planned:
  - test/contracts/phase_history_screen_test.dart — 6 source-grep assertions: file exists at expected path; GoRoute declared as /train/history name=phaseHistory; graduation_screen has VIEW PAST PHASES entry + pushes /train/history; PhaseHistoryScreen reads `startsWith('schedule_')`; filters by status==completed; renders empty-state copy.
related_bugs:
  - b0baa5  # Theme H — completed-day overwrite guard; this UI requires that data integrity
---
# Body

## Why graduation_screen as the entry point (not train header)

The founder's wish surfaced at graduation time — "I just finished
Phase 1, I want to see Phase 1's history before I move on to Phase
2". Graduation is the natural reflection surface. The
"VIEW PAST PHASES" link sits under the CTA so it doesn't compete
with the primary unlock action but is one tap away.

A future iteration could also add the link to the train screen
header for users who want to scroll back any time (not just at
graduation). That's an additive UX work item; this commit ships
the minimum durable surface.

## Why phase number derived from week (not stored explicitly)

The plan generator stamps `week` (1-4 within a phase) on every
schedule_* entry but does NOT stamp `phase_number` directly.
Derivation `((week - 1) ~/ 4) + 1` only works if `week` follows
the canonical 1-4 / 5-8 / 9-12 pattern across phases. The plan
generator does follow this convention (verified at
workout_schedule_read_service.dart:113 — `for (week = 0; week < 4)`
loop writes `week + 1` for each phase's W1-W4).

If a future plan generator changes the convention, this screen
would need a phase_number field on schedule_ entries. The math
is correct for the current generator; the dependency is
documented here for the next regenerator change.

## Empty state vs hidden link

The entry point on graduation_screen is always rendered — even
for a first-time user who has no completed phases yet. The
PhaseHistoryScreen handles the empty case with informational
copy ("No completed phases yet. Once you complete Phase 1, it
will appear here."). This is preferable to conditionally hiding
the link because:
- The user discovers the feature at graduation time.
- The link's mere presence telegraphs "your history will be
  preserved" — a reassurance for users worried about losing data
  after Theme H's pre-fix data corruption.
- Conditional hiding adds branching logic + tests for the
  "currentPhase == 1 AND zero completed days" predicate.

## Test coverage

Source-grep only for v1. Behavioral tests would need a Hive-test-
init fixture (per `lib/core/services/CLAUDE.md` pitfall on
MissingPluginException) + populated schedule_ rows + widget pump
+ tap simulation. Source-grep is sufficient for the structural
invariants (file exists, route declared, button present, reads
correct prefix, filters by status). A future contract test could
construct a populated workoutBox and assert the screen renders
the right number of phase cards.
