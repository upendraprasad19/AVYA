---
bug_id: d5b8f3
date: 2026-08-20
batch: hermes-fob1-fob5-remediation
blast_radius: account
status: fixed
symptom: >
  Hermes P1-A. FOB-1 (f4c8e1) fixed six surfaces that reached the clamped week
  through getCurrentWeekNumber(), and declared the class closed. It was not:
  holdWeek() ALSO persists the projected number onto the row itself
  (workout_schedule_write_service.dart:285, `copy['week'] = 4 + n`), and two
  surfaces render that field verbatim — the Home today-card
  (home_screen.dart:781,801, `workoutMode: 'Week $week'`) and the day-detail
  sheet (day_detail_sheet.dart:102,127, `'WEEK $week'`). At flip-on a holder at
  H1 would read "Week 5" in the today-card roughly 40px below the eyebrow that
  f4c8e1 had just corrected to read "HOLDING · H1" — the cross-tab contradiction
  that batch existed to close, reintroduced inside a single screen, and durable
  across reinstall because sync_workout.dart pushes and restores `week`.
  WeekIdentity's own doc-comment forbids a `4 + ordinal` getter; these surfaces
  reach the value without one.
  Two SEPARATE test-strength defects are fixed in the same commit, both found by
  the same pass: the identity→label WIRING had no behavioural coverage (mutating
  profile_provider to pass `holdOrdinal: null` left the full 4757-test suite
  green), and the a9d3f1 replay guard verified the revoke's PRESENCE but not its
  POSITION or spelling (three ACL-resetting mutations passed it).
concept: hold_week_identity
sot_registry_entry: hold_week_identity
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 285, source: "holdWeek() stamps copy['week'] = 4 + n. UNCHANGED — the stamp is load-bearing for the cloud week_number push and the deload cadence; the fix is that no LABEL may read it" }
  - { file: lib/core/utils/hold_week_labels.dart, line: 100, source: "rowHoldOrdinal() — NEW. The ordinal stamped on a schedule row, or null" }
  - { file: lib/core/utils/hold_week_labels.dart, line: 111, source: "rowIsHold() — NEW. is_hold accepted as a FAIL-SAFE discriminator only, so a row with a corrupt ordinal still suppresses the number rather than printing 4+n" }
  - { file: lib/core/utils/hold_week_labels.dart, line: 116, source: "todayCardWeekLabel() — NEW. Takes the ROW, never a week int, so the projected number is unreachable through it by construction" }
  - { file: lib/core/utils/hold_week_labels.dart, line: 129, source: "dayDetailWeekLabel() — NEW. Nullable, preserving the caller's original `week > 0` suppression" }
readers:
  - { file: lib/features/home/screens/home_screen.dart, line: 781, source: "today-card mode line, REWIRED to todayCardWeekLabel(schedule). No longer reads ['week'] at all" }
  - { file: lib/features/home/widgets/day_detail_sheet.dart, line: 102, source: "sheet header, REWIRED to dayDetailWeekLabel(schedule); the `if (week > 0)` guard now reads the LABEL, so a hold row with no week still states its identity instead of vanishing" }
  - { file: test/contracts/admin_metrics_functions_role_revoke_test.dart, line: 79, source: "a9d3f1 replay guard, HARDENED: public. and the arg-list parens are now optional in the detector, the revoke must appear AFTER the last create/drop of that function, and the role list is matched as a SET" }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + formatDateKey(date)  — unchanged by this fix; the row it addresses is the one holdWeek() upserts"
sync_methods: [_syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [week_number]
contract_test_path: test/contracts/hold_week_identity_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 909, fn: "weekIdentity() reads nowWall(), so the dev time-travel seam drives reads and writes alike" }
provider_invalidations: [currentPlanProvider, weekIdentityProvider, userStatsProvider]
telemetry_op_types:
  success: [hold_week_started]
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "\\['week'\\] read in home_screen.dart or day_detail_sheet.dart (comments stripped)", absent: true }
  - { pattern: "4\\s*\\+\\s*(ordinal|n) reachable from any label formatter", absent: true }
proposed_fix: >
  Route both row-derived surfaces through new pure formatters that take the
  SCHEDULE ROW rather than a week integer, so the persisted 4+ordinal stamp is
  unreachable from a label by construction. Harden the a9d3f1 replay guard to
  assert the revoke's POSITION and to tolerate both optional-qualifier spellings.
  Add a ProviderContainer wiring assertion plus a comment-stripped
  forbidden-token control, because the behavioural label tests alone could not
  catch a reverted call site.
regression_test_planned:
  - test/contracts/hold_week_identity_behavioral_test.dart
  - test/contracts/hold_week_labels_test.dart
  - test/contracts/admin_metrics_functions_role_revoke_test.dart
impact_analysis: >
  LATENT, not live. holdWeek() is called only from runFreeTierRepeatWrite, which
  is gated on PlanEngineFlags.holdWeeksEnabled — default OFF — so no is_hold row
  exists in production today and no user has seen "Week 5". The ship-dark
  byte-identical evidence for f4c8e1 is unaffected and was re-verified
  (userStatsProvider reports no hold with the flag off, even with real hold rows
  on disk). This therefore does NOT block the merge; it hard-blocks flip-on,
  which per CLAUDE.md §4.12.4 takes the full x2 review anyway.
  The row stamp itself is deliberately unchanged: cloud week_number is projected
  from it and the deload cadence reads it, so rewriting the stamp would be a
  data-shape change to fix a display bug. The fix is read-side only, so existing
  rows need no migration.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze 0 errors/0 warnings; TZ=Asia/Kolkata flutter test test/ --exclude-tags golden -> 4770 passed, 7 skipped, exit 0 (baseline 4757)" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "the row stamp is unchanged on disk — hold_week_identity_behavioral_test asserts row['week'] == 4 + ordinal on real holdWeek() output, then asserts both formatters suppress it. The fix is read-side only, so no migration of existing rows is needed" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change; the cloud week_number column and its push/restore path are deliberately untouched" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no data written or altered" }
  - { tier: 5, name: migrations_applied, status: verified, evidence: "no new migration; the only migration touched is the guard TEST over migration 120, whose .sql is byte-identical (sha256 e9190aef2008502df4ce2ac6b26c4939c9531741b0fd6ed8f805084de708d397)" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no Edge Function changed; grep -rn week_number supabase/functions/ returns zero matches" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron touched" }
  - { tier: 8, name: rls_policies, status: verified, evidence: "unchanged. The hardened replay guard re-asserts the founder_metrics_engagement ACL invariant; live proacl remains {postgres=X/postgres,service_role=X/postgres}" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the persisted stamp and its cloud projection are unchanged in both directions; only rendering changed, so a client on the old build and one on the new agree on stored state" }
related_bugs:
  - { id: f4c8e1, relation: "the batch this corrects — it closed the getCurrentWeekNumber() consumers and missed the stamped-field consumers" }
  - { id: c9f4a2, relation: "the original three-surface drift whose dishonest value (4 + ordinal) this prevents from resurfacing" }
  - { id: c8b3f2, relation: "D1, where the Train surfaces first chose 'a hold suppresses the week number'" }
  - { id: a9d3f1, relation: "the anon-executable SECURITY DEFINER leak whose replay guard is hardened here" }
recurrence: >
  THIRD instance of the same reviewing error inside one batch, and that is the
  finding worth keeping. Each time, a claim was verified at the layer being
  looked at and not one layer further:
  (1) the B-pass caught an inverted ternary that a source-grep could not see, so
      the LABELS were extracted into pure functions and given behavioural tests;
  (2) Hermes then caught that the ARGUMENTS passed to those labels had no
      coverage — mutating profile_provider to send null left the whole suite
      green, because every grep token survived the defect;
  (3) the first remediation attempt for (2) STILL let both call-site reverts pass
      green, and was only caught by re-running the mutations rather than trusting
      the fix.
  The generalisation: a positive grep passes while the wanted token survives
  ANYWHERE in the file, which is exactly why it cannot see a defect in an
  argument. Where a render cannot be pumped, assert the FORBIDDEN token
  negatively instead — and strip comments first, because an explanatory comment
  naming the token satisfies a raw-text match and silently neuters the check.
---

# Hold-week identity leaked through the PERSISTED stamp, not the clamp

## What f4c8e1 fixed, and what it left

f4c8e1 enumerated consumers of `getCurrentWeekNumber()` and `getProgramWeek()`
and corrected six of them. That enumeration is the whole story of this bug: the
Home today-card and the day-detail sheet call **neither** function. They read
`schedule['week']` — the field `holdWeek()` stamps as `4 + ordinal` — so they
were invisible to the sweep while displaying the exact number the sweep existed
to suppress.

The evidence was already in hand. `fob1-week-identity.closure.yaml:138` states
"hold rows sit at week 5+". Nothing followed that sentence to its readers.

## Why the fix takes the row

`todayCardWeekLabel(row)` and `dayDetailWeekLabel(row)` accept the schedule row,
never a week integer. A caller therefore cannot pass the projected number into
them, in the same way `WeekIdentity` carries `weekInPhase` XOR `holdOrdinal` and
so cannot represent a projection. Row-derived rather than provider-derived for
two further reasons: a bottom sheet needs no provider dependency, and a restored
row labels itself correctly with no live provider graph at all.

`is_hold` is accepted as a fallback discriminator ONLY in the fail-safe
direction — a row whose ordinal is missing or corrupt renders "Holding" rather
than falling through to "Week 5".

## Test strength — the part that matters more than the fix

The first remediation attempt passed all its own tests and still let both call
sites revert to the raw stamp. Re-running the mutations, rather than trusting
the green, is what caught it.

| Mutation | Before | After |
|---|---|---|
| `profile_provider` sends `holdOrdinal: null` | green | red |
| home today-card reverts to raw stamp | green | red |
| day-detail reverts to raw stamp | green | red |
| formatter appends the stamp | green | red |
| `rowIsHold` fail-safe removed | green | red |
| guard: parenless `drop` in a future migration | green | red |
| guard: unqualified `create` in a future migration | green | red |
| guard: revoke hoisted above `DROP`+`CREATE` | green | red |
| guard: `from authenticated, anon` (SAFE sql) | **falsely red** | green |

## What is deliberately NOT closed here

The forbidden-token assertion proves neither file reads `['week']`. It does not
prove what the widgets render, and a third spelling reaching the stamp another
way would slip it. Real closure is a pumped-widget test for both surfaces;
neither is pumpable today without a full Riverpod + Hive home harness. Stated
here rather than left implied.
