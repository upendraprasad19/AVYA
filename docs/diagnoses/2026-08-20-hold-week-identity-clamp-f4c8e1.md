---
bug_id: f4c8e1
date: 2026-08-20
batch: fob1-week-identity
blast_radius: account
status: fixed
symptom: >
  FOB-1 of OI-60. Six in-repo surfaces printed the clamped week 4 to a free-tier
  holder, at every hold ordinal, forever. `getCurrentWeekNumber()`
  (workout_schedule_read_service.dart:1096) ends in `.clamp(1, 4)` and a hold
  week starts at `plan_start + 28`, so every consumer of it reports 4 for the
  whole hold. The shipped Train surfaces had already chosen the opposite rule —
  plan_header.dart drops the week counter while holding and the HOLDING · Hn pill
  carries the identity (diagnose c8b3f2 D1) — so the app CONTRADICTED ITSELF
  across tabs: Train said "HOLDING · H2" while Home's eyebrow said "WK 4", the
  Profile subtitle said "Week 4", the journey timeline said "WEEK 4 OF 4" over a
  full progress bar and offered "0 weeks to complete Phase 1", the Roadmap header
  said "WK 4 / 12", and the share-as-video card stamped "WEEK 4 RECAP".
  Two of the six were NOT in the FOB's own file list as written:
  phase_roadmap_screen.dart reaches the clamp indirectly through
  `getProgramWeek` = `programWeekFor(phase, getCurrentWeekNumber())`, and
  profile_content.dart was named only via its provider.
concept: hold_week_identity
sot_registry_entry: hold_week_identity
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 287, source: "holdWeek() — the ONLY writer of is_hold / hold_ordinal. Unchanged by this batch; cited because the identity is derived from these row stamps, so a writer field rename silently empties every surface below" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 909, source: "weekIdentity() — NEW. The single answer to 'what week is it', returning WeekIdentity.hold(ordinal) on a live hold day and WeekIdentity.week(clamped) otherwise. Reads nowWall(), so the dev time-travel seam holdWeek() writes against also drives reads" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 890, source: "activeHoldWeeks() — NEW. holdWeeks() gated on enable_hold_weeks; THE one read-side flag gate" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 895, source: "activeHoldOrdinalFor() — NEW. holdOrdinalForDate() gated on the same flag. The raw pair stays ungated so tests can exercise the row contract directly" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 113, source: "WeekIdentity — NEW value type. weekInPhase XOR holdOrdinal; deliberately carries NO projected number, so `4 + ordinal` cannot be reintroduced through it" }
readers:
  - { file: lib/features/train/providers/train_provider.dart, line: 1009, source: "weekIdentityProvider — widget-side seam; watches currentPlanProvider so taking a hold repaints the counter" }
  - { file: lib/features/train/providers/train_provider.dart, line: 970, source: "holdStatusProvider — REWIRED to activeHoldWeeks()/activeHoldOrdinalFor(); it no longer restates the flag check, so there is exactly ONE gate" }
  - { file: lib/features/home/screens/home_screen.dart, line: 319, source: "the DAILY eyebrow. Home carries no HOLDING pill, so unlike the Train header it SUBSTITUTES 'HOLDING · Hn' rather than dropping the segment" }
  - { file: lib/features/profile/providers/profile_provider.dart, line: 313, source: "UserStatsData now carries holdOrdinal alongside the clamped currentWeek, both from ONE weekIdentity() read so they cannot disagree across a midnight rollover" }
  - { file: lib/features/profile/screens/profile/journey_timeline.dart, line: 92, source: "'WEEK n OF 4' label → 'HOLDING · Hn'. The /4 progress bar is deliberately NOT branched — see impact_analysis" }
  - { file: lib/features/profile/screens/profile/profile_content.dart, line: 32, source: "the profile subtitle 'Phase n · Week m · goal'" }
  - { file: lib/features/train/screens/phase_roadmap_screen.dart, line: 63, source: "_DeploymentHeader — the week COUNTER is suppressed while holding; the percent and bar stay derived from the program week, which is honest" }
  - { file: lib/features/profile/screens/reports_screen.dart, line: 1387, source: "share-as-video inputProps gains holdOrdinal; the Remotion composition renders 'HOLD Hn RECAP' when present" }
  - { file: lib/core/utils/hold_week_labels.dart, line: 30, source: "the five PURE formatters every surface renders through. Extracted after the B-pass inverted an inlined ternary and all 16 tests still passed — a source grep cannot see a logic inversion. holdOrdinal is the single discriminator in each, so 'holding but ordinal null' is not representable" }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + formatDateKey(date)"
sync_methods: [syncWorkoutData, _syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, week_number, day_of_week, status]
contract_test_path: test/contracts/hold_week_identity_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 910, fn: "weekIdentity reads nowWall() — seam-aware, NOT DateTime.now(); this is what let the fix be exercised under the test clock at three different ordinals" }
  - { file: lib/core/utils/ist_date.dart, line: 65, fn: "nowWall — the single wall-clock seam shared with holdWeek()'s Monday normalization" }
provider_invalidations: [currentPlanProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  Unchanged. weekIdentityProvider watches currentPlanProvider, which already
  carries the authUserIdTokenProvider chain, and every row read goes through the
  user-scoped GuardedBox workoutBox. No new cloud read or write is introduced —
  the whole change is display-side, over rows the hold read path already served.
forbidden_patterns_checked:
  - "4 + ordinal projection into user_progress.current_week — the FOB's explicit do_not. NOT done: WeekIdentity carries no projected number at all, and the hold arm asserts weekInPhase is NULL so a future caller cannot quietly add one. Pinned by 'the identity NEVER projects 4 + ordinal at any ordinal'."
  - "second flag gate — a new PlanEngineFlags.holdWeeksEnabled read in each surface. NOT done: the gate lives once in activeHoldWeeks/activeHoldOrdinalFor and holdStatusProvider was rewired to delegate rather than keep its own copy."
  - "hold chips driving selectedWeekProvider — SelectedWeekNotifier.build (train_provider.dart:1023) was deliberately LEFT clamped; hold rows sit at week 5+ and getWeek(5) is empty, so un-clamping it renders 'Week 5 hasn't started yet' over a week the user is training. That is OI-125's named trap, not this batch's work."
  - "Container(color:+decoration:) — no Container was touched."
proposed_fix: >
  Add a service-level WeekIdentity seam (week-in-phase XOR hold ordinal, never a
  projection) with the enable_hold_weeks gate in exactly one place, expose it to
  widgets via weekIdentityProvider, and adopt it on the six in-repo surfaces that
  printed a week counter. Leave the progress-bar/percentage inputs alone where
  the clamped value is genuinely honest.
regression_test_planned: >
  TWO files. test/contracts/hold_week_labels_test.dart — 16 table-driven cases
  asserting the exact rendered string on BOTH arms of all five formatters (added
  after the B-pass; inverting profileWeekSegment's ternary reddens 4 of them,
  where the same inversion reddened 0 before it existed). And
  test/contracts/hold_week_identity_behavioral_test.dart — 17 cases driving the
  REAL holdWeek() writer. Mutation-proven on both protective legs: neutering the
  hold arm of weekIdentity reddens 3 tests; removing the flag gate from the
  active* pair reddens 5 across this file and hold_display_read_path_test.dart.
  The flag-OFF group is the §4.12.4 byte-identical evidence — it materializes
  real holds with the flag ON, turns it OFF, and asserts the identity equals the
  raw getCurrentWeekNumber() value with hold rows still on disk.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze: 0 errors, 0 warnings; issue count 258, unchanged from the pre-batch baseline. B-pass returned 2 findings (1 P1 reactivity, 1 P2 untestable coverage); both fixed in-batch, verdict accepted" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "read-only over existing schedule_* rows; the behavioral test drives the real holdWeek() writer and reads back through the new seam. No new key, no schema change" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "display-only change; no column added, dropped or renamed" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no write path touched" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no Edge Function touched. The coach snapshot is FOB-3's and needs an ai-proxy redeploy, which is why it was deliberately NOT bundled here" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron-dispatched function touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no table read or written" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or added" }
  - { tier: 11, name: external_services, status: verified, evidence: "remotion/src/components/WeeklyRecapVideo.tsx gains an OPTIONAL holdOrdinal prop; a caller that omits it renders byte-identically, so no existing render breaks" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the Dart→Remotion inputProps contract is the only cross-surface seam and both halves moved in this commit; holdOrdinal is null for every user while the flag is OFF" }
impact_analysis: >
  Inert until the flip. Every branch added keys on a hold state that
  `enable_hold_weeks` (default OFF) makes unreachable, so with the flag OFF
  weekIdentity() returns exactly getCurrentWeekNumber() and all six surfaces
  render their pre-batch strings. That equality is asserted directly rather than
  assumed.

  Two things were deliberately NOT changed, because the clamped value is honest
  for them and branching would have made them wrong. (a) journey_timeline's
  `WardBar(pct: currentWeek / 4.0)` — during a hold currentWeek is 4 and the
  phase's four weeks genuinely ARE elapsed, so a full bar is correct; feeding it
  a hold ordinal would divide an H-number by 4. (b) phase_roadmap's percentage
  and bar, derived from the program week — four of twelve program weeks really
  are done. Only the COUNTER is dishonest for a holder, so only the counter is
  suppressed.

  Residuals, neither of them deferred. `ai_snapshot_builder.dart:96` still feeds
  the coach the clamped-derived program week; that is FOB-3's by the board's own
  division of OI-60 — FOB-3 rewrites the same lines to add the `hold` block and
  requires an ai-proxy redeploy under its own §4.3 authorization, so touching it
  here would have shipped a half-changed snapshot contract with no redeploy.
  `telegram-bot/bot.py` is upstream_blocked: a separate project on the OpenClaw
  VPS (CLAUDE.md §2), not in this tree.

  Does not move OI-60 to closeable. Four flip-on blockers remain (FOB-3, FOB-4,
  FOB-5, FOB-7a/b) and the flip-on commit still needs its own full ×2 review.
---

# f4c8e1 — the hold-week clamp printed "week 4" on six surfaces

## What was actually wrong

`getCurrentWeekNumber()` is clock-derived and ends in `.clamp(1, 4)`
(`workout_schedule_read_service.dart:1096`). A hold week is materialized at
`plan_start + 28` or later, so **for every hold, at every ordinal, forever, it
returns 4.** Everything downstream inherited that.

The Train tab had already been fixed for this once — `plan_header.dart` drops
the week counter while holding, and the `HOLDING · Hn` pill carries the identity
instead (diagnose `c8b3f2`, D1). The rest of the app never adopted the rule, so
the app disagreed with itself depending on which tab you were on:

| Surface | A holder saw | Should be |
|---|---|---|
| Train header | `HOLDING · H2` | ✅ already correct |
| Home eyebrow | `... · WK 4 · PHASE 1` | `... · HOLDING · H2 · PHASE 1` |
| Profile subtitle | `Phase 1 · Week 4 · ...` | `Phase 1 · Holding · H2 · ...` |
| Journey timeline | `WEEK 4 OF 4` | `HOLDING · H2` |
| Journey milestone | `0 weeks to complete Phase 1` | `Phase 1 complete · holding at H2` |
| Roadmap header | `WK 4 / 12 — 33% complete` | `HOLDING · H2 — 33% complete` |
| Share-as-video | `WEEK 4 RECAP` | `HOLD H2 RECAP` |

## Why the FOB's own file list was not the answer

Two surfaces were found by reading source rather than by trusting the filing:

- **`phase_roadmap_screen.dart`** does not call `getCurrentWeekNumber()`. It
  calls `getProgramWeek(phase)`, which is
  `programWeekFor(phase, getCurrentWeekNumber())` — the clamp is one level down.
  A grep for the clamp would have missed it; the FOB list happened to name the
  file anyway, with a comment claiming it had been moved off the clamp. It had
  been moved off the *direct* call, not off the clamp.
- **`profile_content.dart`** was named only through its provider
  (`profile_provider.dart → profile_content.dart`), and reads
  `stats.currentWeek` in a subtitle string.

## The fix

One new seam, one gate:

```dart
// workout_schedule_read_service.dart
List<HoldWeekInfo> activeHoldWeeks()            // holdWeeks() + flag gate
int? activeHoldOrdinalFor(DateTime date)        // holdOrdinalForDate() + flag gate
WeekIdentity weekIdentity()                     // hold ordinal XOR clamped week
```

`WeekIdentity` carries `weekInPhase` **or** `holdOrdinal`, never both and never a
projected number. That is deliberate: FOB-1's `do_not` bans projecting
`4 + ordinal`, which manufactures the value the UI already ruled dishonest and
demotes a phase-2 holder from program week 8 to 5 (diagnose `c9f4a2`). Because
the type has no field to hold a projection, one cannot be reintroduced through
it, and the test asserts `weekInPhase` is **null** while holding rather than
asserting it equals some other number.

`holdStatusProvider` was rewired to call the `active*` pair instead of keeping
its own `PlanEngineFlags.holdWeeksEnabled` check, so the read side now has
exactly one gate rather than two copies that could drift apart.

## What was deliberately left alone

- **`WardBar(pct: currentWeek / 4.0)`** in the journey timeline. During a hold
  `currentWeek` is 4 and the phase's four weeks really are elapsed, so a full bar
  is honest. Branching it to the ordinal would divide an H-number by 4.
- **The roadmap percentage and bar.** Four of twelve program weeks really are
  done. Only the *counter* lies to a holder.
- **`SelectedWeekNotifier.build()`** (`train_provider.dart:1023`) stays clamped.
  Hold rows sit at week 5+ and `getWeek(5)` is empty, so un-clamping it renders
  "Week 5 hasn't started yet" over a week the user is actively training. That is
  the trap OI-125 names explicitly.

## Mutation proof

| Mutation | Tests reddened |
|---|---|
| `weekIdentity()` always takes the week arm (the pre-fix state) | 3 |
| flag gate removed from both `active*` readers | 5 (across this file and `hold_display_read_path_test.dart`) |
| `profileWeekSegment`'s ternary inverted (the B-pass's own defect) | 4 — and **0** before `hold_week_labels_test.dart` existed |

## What the B-pass caught that the implementation missed

Two findings, both real, both fixed in-batch.

**P1 — the seam was right and two surfaces still could not see it.** `UserStatsNotifier.build()`
read the identity through a plain singleton call, so `userStatsProvider` had no dependency-graph
edge to the hold write. The five tabs live under `StatefulShellRoute.indexedStack`, so an
already-mounted Profile tab is never rebuilt on tab-switch — a user who opened Profile before
holding would keep seeing `WEEK 4 OF 4` there while Home and Train said `HOLDING · H1`. The batch
would have *reintroduced* the cross-tab contradiction it exists to close, on two of its six
surfaces. Fixed with `ref.watch(weekIdentityProvider)`.

**P2 — the surface coverage could not fail.** The reviewer inverted a ternary and all 16 tests
passed, because the only coverage was a grep for a token. The lesson worth keeping: this batch
shipped two mutation proofs on the service seam and cited both — and the label layer, which is
what a user actually reads, had zero behavioral coverage. Mutation-proving a seam does not
mutation-prove the surfaces consuming it.

**Residual, stated rather than glossed:** extracting the formatters closes the label *logic*.
No widget test mounts these five screens, so a surface that stopped calling its formatter
altogether is still caught only by the presence-grep. That is larger work than this batch and is
not a flip-on blocker.

## Residuals — routed, not deferred

- `ai_snapshot_builder.dart:96` still feeds the coach the clamped-derived program
  week. This is **FOB-3's**, by the board's own split of OI-60: FOB-3 rewrites the
  same lines to add the `hold` block and needs an ai-proxy redeploy under its own
  §4.3 authorization. Changing it here would have shipped a half-changed snapshot
  contract with no redeploy behind it.
- `telegram-bot/bot.py` is **upstream_blocked** — a separate project on the
  OpenClaw VPS (CLAUDE.md §2), not in this repository.
