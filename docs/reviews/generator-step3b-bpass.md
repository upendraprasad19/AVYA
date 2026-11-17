---
reviewed_at: 2026-11-16T11:30:00+05:30
staged_against: 794ded9064664911f158b43c3dacfb91bf7290ff
branch: generator-step3b
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 11
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 6 P2 and 5 P3; all fixed in the B-pass commit, none a false alarm
---

# B-pass: generator-step3b (Unit 3B, three goals and 90 minutes for advanced, OI-487 rest / OI-488)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head 794ded90, with CI green on that SHA
(PR #287). Two fresh Sonnet seats read the three-dot diff `origin/main...794ded90`:
- **Seat A, the heal, the profile write, Edit Profile and the goal table:** ran the heal and goal-list tests and mutated
  `legacy_goal_healer.dart`, `profile_write_service.dart` and `fitness_goals.dart` under a backup / sha256 protocol
  (restored, hashes equal).
- **Seat B, the minutes rule, the coach, the server enums and the gate:** worked in a detached review copy of the same
  head, ran the minutes, parity, gate-lib and chip tests and the two Deno tool tests, and mutated in that copy only.

Both briefs quoted the founder decisions d4, d69-d73 and the rejected alternatives of plan rounds 1-3. No finding
re-opened a decision.

## Finding 1 - P2 - writer_reader_drift - stale SoT line ranges (seat A)
- **file:line:** `docs/sot_registry.yaml`, the ranges citing `edit_profile_screen.dart`, `onboarding_provider.dart`,
  `profile_write_service.dart`.
- **claim:** only the `sync_service.dart` ranges were shifted; the other three files' ranges pointed 55 / 1 lines early,
  and `1-140` no longer held `updateField`.
- **status:** accepted, fixed (17 ranges re-derived from the diff, anchors spot-checked; `patchProfileWith` named).

## Finding 2 - P2 - guard_without_its_mirror - the heal's push is unpinned (seat A)
- **file:line:** `lib/features/profile/services/profile_write_service.dart` `patchProfileWith`, `if (wrote) _fireSync();`
- **claim:** `if (wrote) {}` survived every test (no Supabase user in tests).
- **status:** accepted, fixed (`debugOnFireSync` seam; a test counts one push per write, none on a null patch or a
  failed owner check; mutant red).

## Finding 3 - P2 - guard_without_its_mirror - the body-fat switch is unpinned (seat A)
- **file:line:** `lib/core/services/legacy_goal_healer.dart`, `bodyFatOff`.
- **status:** accepted, fixed (body-fat fixture, Katch-McArdle vs Mifflin; mutant red).

## Finding 4 - P2 - writer_reader_drift - the launch-path restore re-merges a legacy goal without healing (seat A)
- **file:line:** `lib/core/services/sync_service.dart` `_restoreIfNeeded` (`restoreLightweightAlways` /
  `restoreFromCloud`), `auth_session_bootstrapper.dart` `hydrateFromCloud`.
- **claim:** a legacy value the cloud still holds came back on every launch with local data and stayed until the next
  `/restoring` pass.
- **status:** accepted, fixed: `_restoreIfNeeded` heals after either branch (presence pin; mutants "removed" and "only
  in one branch" red). `hydrateFromCloud` is followed by `/restoring` (the post-auth gate), which heals; the
  `*ForSyncDomain` restore is flag-gated off. Both stated in the diagnose doc.

## Finding 5 - P2 - guard_without_its_mirror (d73) - the compass message names the raw token (seat B)
- **file:line:** `lib/features/ai_coach/widgets/compass_form_sheet.dart:117`
- **status:** accepted, fixed (`compassSwitchGoalMessage` through `FitnessGoals.label`; value test; mutant red).

## Finding 6 - P2 - guard_without_its_mirror (d73) - the server previews name the raw token (seat B)
- **file:line:** `supabase/functions/_shared/tools/plan/switchGoal.ts`, `regeneratePlanBlock.ts` (`previewSummary`)
- **claim:** the app shows "Switch goal → lose_fat" on the confirm sheet, bar and card.
- **status:** accepted, fixed (`_shared/tools/plan/goalLabels.ts`, `goalLabel`; Deno tests updated; the parity test pins
  the table against `FitnessGoals.label` and forbids the raw interpolation; mutant red). Live with the ai-proxy
  deploy (t306).

## Finding 7 - P3 - wording (d73) - the legacy chat onboarding's goal labels (seat A)
- **file:line:** `lib/features/onboarding/screens/onboarding_chat_screen.dart` `_formatOptionLabel`
- **status:** accepted, fixed (labels from `FitnessGoals.label`; presence pin forbids the old strings).

## Finding 8 - P3 - behaviour pin - Edit Profile level down then up (seat A)
- **status:** accepted, pinned (60 stays until the user taps 90 again; the 90 chip is offered again).

## Finding 9 - P3 - kill-switch semantics stated (seat A)
- **claim:** under `disable_profile_target_recompute` the heal writes the new goal beside the old targets.
- **status:** accepted, stated in the diagnose doc's accepted consequences.

## Finding 10 - P3 - presence pin too narrow (seat B)
- **file:line:** `test/contracts/session_minutes_by_level_test.dart` (the param passers' pin)
- **status:** accepted, fixed (no other `'session_duration_minutes'` read in either file).

## Finding 11 - P3 - the gate's selectable set is a second list (seat B)
- **file:line:** `scripts/goal_token_exhaustiveness_lib.dart` `serverGoalEnumProblems`
- **status:** accepted, fixed (`selectableListProblems` checks `FitnessGoals.selectableTokens` itself; the real list
  mutated to include `strength` fails the gate and the lib test; two cites of a test file that was never created,
  `fitness_goals_selectable_test.dart`, now name `goal_list_selectable_test.dart`).

## Founder triage notes
Self-triaged under the standing directive (work the board through; device checks at the end). Every finding fixed in
this batch.

## Tuning entry

- **2026-11-16** - blast-radius platform - 11 findings (0 P0/P1, 6 P2, 5 P3); 0 false_alarm; tuning: two lessons.
  - A naming decision ("names are X wherever a goal is named") needs a sweep of every string a user SEES, including
    server-built text the client shows verbatim (`previewSummary`) and a message composed from a chip: both seats found
    a d73 gap the plan's label sweep (client widgets only) missed.
  - A heal hooked on one restore entry point needs every entry point that merges the same key listed by name
    (`restoreFromCloudForUser`, `_restoreIfNeeded`'s two branches, `hydrateFromCloud`, `*ForSyncDomain`), with each one
    healed or ruled out in the doc.
