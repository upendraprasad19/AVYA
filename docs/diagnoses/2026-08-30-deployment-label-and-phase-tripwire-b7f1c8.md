---
bug_id: b7f1c8
date: 2026-08-30
batch: profile-phase-fixes
status: fixed
blast_radius: account
symptom: |
  Founder observation on the Train screen: the deployment eyebrow above the
  week strip always read "DEPLOYMENT 01" regardless of which phase/deployment
  the account was actually on. Same screen, separate observation: the week
  selector showed "PHASE II" as the FIRST (current) group with no "PHASE I
  (DONE)" group to its left — "where did phase one go?"

  ROOT CAUSE 1 (confirmed by direct code read — file:line below): the
  eyebrow text was a hardcoded literal `'DEPLOYMENT 01'` interpolated with
  the real phase name and week, never the real phase/deployment number. Every
  account, at every phase, would always read "DEPLOYMENT 01".

  ROOT CAUSE 2 (investigated exhaustively, NOT newly fixed here — see
  "what this diagnose-doc does and does not fix" below): the missing
  "PHASE I" group is diagnose c9e4b7's already-known display anomaly
  (`docs/diagnoses/2026-08-09-past-phase-display-and-expired-copy-c9e4b7.md`),
  reproducing on the SAME founder account it was originally filed against.
  c9e4b7's own fix (a display-recovery wrapper) explicitly left the
  underlying root cause open as "a separate investigation." This batch
  extended that investigation (see impact_analysis) rather than re-attempting
  the underlying fix, and landed on a live tripwire instead: a full sweep of
  `user_progress.current_phase > 1` across the ENTIRE database found exactly
  2 accounts total, ever — upendraprasad19@gmail.com (this founder account)
  and amar@gmail.com (a known E2E test account per this repo's own bug
  history, diagnose e2a4f7) — and BOTH hit the identical
  strict-empty-history anomaly. No organic (non-test) user has ever been
  confirmed in this state. Given that, digging further into two known
  test/QA accounts' historical data was judged lower-value than a live
  tripwire that will observably fire the day a real user hits this shape.
concept: past_phase_display_recovery
sot_registry_entry: past_phase_display_recovery
# NOTE (plan-review round 2 finding 4): this doc bundles TWO fixes touching
# TWO registered concepts. `past_phase_display_recovery` (above) owns the
# tripwire; `deploymentEyebrowLabel` is registered under `hold_week_identity`
# instead — that is where this file's other formatters live and where its
# hold-aware fields belong. Both registry entries were updated in this same
# commit; the single `sot_registry_entry:` field above names the primary one
# because the validator takes exactly one.
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "pastPhaseBlocksForDisplay — tripwire telemetry on the strict-empty + currentPhase>1 branch (byte-identical `recovered` return either way)", line: 1443 }
  - { file: lib/core/utils/hold_week_labels.dart, method_or_widget: "deploymentEyebrowLabel — pure formatter, phase-derived deployment number (registered under the hold_week_identity concept)", line: 164 }
readers:
  - { file: lib/features/train/screens/train/screen.dart, method_or_widget: "deployment eyebrow — now calls deploymentEyebrowLabel(phase: plan.phase, ...) instead of a hardcoded literal", line: 242 }
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: "past-phase strip — the ONLY caller of pastPhaseBlocksForDisplay (unchanged by this batch)", line: 145 }
hive_key_prefix: "n/a — display-only; no new Hive key"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a for the eyebrow fix (pure display formatting); user_progress for the tripwire's diagnostic context (phase_started_at read, not written)"
cloud_columns: [current_phase, deployments_complete, phase_started_at]
contract_test_path: test/contracts/hold_week_labels_test.dart
ist_handling: "n/a — no date keys, cloud date columns, or counter resets touched"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [past_phase_blocks_strict_empty]
cross_account_guard: |
  Inherited. The tripwire's dedup flag (`_strictEmptyTripwireLogged`) is
  instance state on the `WorkoutScheduleReadService` singleton, reset in the
  EXISTING `_onUserChanged()` lifecycle hook
  (`SingletonLifecycleRegistry.notifyUserChanged()`, fired by
  `HiveUserSession.openForUser` on every sign-in) — the same mechanism every
  other singleton in this codebase uses to avoid leaking in-memory state
  across an account switch. No new cross-account surface; `deploymentEyebrowLabel`
  is a pure function with no Hive/network access at all.
forbidden_patterns_checked:
  - "No Container(color:+decoration:) introduced (gate check_container_color_decoration.dart)."
  - "No raw Hive.box( — deploymentEyebrowLabel takes plain ints/strings/bool, no storage access."
  - "No new .from().select() column reference — the tripwire reads phase_started_at from the EXISTING UserRepository.instance.getProgress() map, already read elsewhere in this file; check_schema_column_refs.dart is unaffected."
proposed_fix: |
  Two independent, small changes, bundled here because both surfaced from
  the same investigation and both touch the Train screen's phase-display
  area:

  1. **DEPLOYMENT hardcode.** Extracted the eyebrow's inline ternary into a
     pure formatter, `deploymentEyebrowLabel` (`lib/core/utils/
     hold_week_labels.dart`), matching the EXISTING convention in that exact
     file for every other hold-aware label (see that file's own header: an
     inline ternary here was already proven untestable once — a B-pass
     inverted one and 16 tests still passed, because a source-grep cannot
     see a logic inversion). `phase` (not `deployments_complete`) drives the
     deployment number directly: `deployments_complete = current_phase - 1`
     (`user_repository.dart:186-195`, an existing, unrelated invariant this
     fix does not touch), so the deployment IN PROGRESS is `phase` itself —
     and `plan.phase` is already the value `WeekSelector`/`HoldRoadmapStrip`
     use for their own phase labels on this exact screen, so this reuses
     that read instead of introducing a fourth independent "what phase am I
     on" read path (the recurring writer/reader-drift class this repo has
     hit 15+ times).
  2. **Phase-2+ display tripwire.** `pastPhaseBlocksForDisplay` now logs
     `past_phase_blocks_strict_empty` (once per account per session) whenever
     it reaches the strict-empty + `currentPhase > 1` branch — regardless of
     whether the recovery sub-path manages to salvage any blocks. Purely
     additive: the method's return value (`recovered`) is unchanged in every
     case.
regression_test_planned: |
  Two files, matching this repo's existing pattern of pairing a pure
  formatter with a table-driven exact-string test
  (`test/contracts/hold_week_labels_test.dart`) and a real-Hive behavioral
  test for anything that touches actual schedule data
  (`test/contracts/past_phase_display_recovery_behavioral_test.dart`,
  extending the SAME file diagnose c9e4b7 already built for this concept).

  `hold_week_labels_test.dart` new group `deploymentEyebrowLabel`: asserts
  the exact rendered string for phase 1 / phase 2 (the pre-fix bug's exact
  shape — "DEPLOYMENT 01" printed for a phase-2 account) / phase 12
  (zero-pad boundary) / holding (week counter dropped). 4/4 green.

  `past_phase_display_recovery_behavioral_test.dart` new group E: real Hive
  round-trip reusing the file's existing `seedDriftedAccount` fixture (the
  founder's own live numbers). Asserts the tripwire fires exactly once on a
  drifted phase-2+ account, does NOT fire again across repeated calls in the
  same session (guards the dedup — WITHOUT it this would post a real network
  call per WeekSelector rebuild, which happens on every scroll frame), and
  does NOT fire for a healthy (non-drifted) account. 3/3 green (9/9 total in
  the file with the pre-existing groups).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on all 4 touched files; 9/9 green in hold_week_labels_test.dart + past_phase_display_recovery_behavioral_test.dart." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "past_phase_display_recovery_behavioral_test.dart group E drives a real Hive box open/write/read, not a mock." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live SQL swept the ENTIRE user_progress table for current_phase > 1 — exactly 2 accounts, both already-known test accounts, both reproducing the anomaly. See impact_analysis." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes this path." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table access changed." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service in this path." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "The DEPLOYMENT label is now derived from the same plan.phase this screen already reads for WeekSelector/HoldRoadmapStrip — one client-side read, no server round-trip. The tripwire's diagnostic value is specifically that it closes the client->server observability gap: the anomaly was previously visible only via a manual live SQL sweep." }
impact_analysis: |
  USER-VISIBLE (fix 1): the deployment eyebrow now reads the account's real
  deployment number instead of always "DEPLOYMENT 01".

  NOT USER-VISIBLE (fix 2, the tripwire): purely additive observability. No
  rendered output changes.

  BLAST RADIUS `account` — driven independently by TWO catch-all rows in
  `docs/blast_radius.yaml` (first-match-wins, declaration order):
  `lib/core/utils/hold_week_labels.dart` falls under the `lib/core/**`
  catch-all (line 317) and `lib/core/services/workout_schedule_read_service.dart`
  falls under the `lib/core/services/**` catch-all (line 313) — no dedicated
  rule names this file specifically; the OLD pre-split monolith
  `workout_schedule_service.dart` is what line 240 pins, a different
  filename. Only `lib/features/train/screens/train/screen.dart` and
  `lib/features/train/widgets/week_selector.dart` are `feature`-tier (line
  297). CORRECTED (B-pass finding 4, same batch): this paragraph originally
  claimed `workout_schedule_read_service.dart` was individually
  feature-tier — checking each touched path independently against the live
  registry shows it is account-tier on its own, same as the eyebrow-label
  file. Doesn't change the overall verdict (still `account`, now
  doubly-driven), only the stated reasoning.

  WHY THE MISSING-PHASE-I ANOMALY IS NOT RE-FIXED HERE, STATED EXPLICITLY SO
  IT IS NOT MISTAKEN FOR NEGLECT: c9e4b7 already shipped the display-layer
  fix (a recovery wrapper) and explicitly deferred the DATA root cause as a
  separate investigation, naming `sync_service.dart`'s restore path as an
  unconfirmed leading candidate. This batch continued that investigation:

  - Every CLIENT *advance* path for `current_phase`
    (`advanceProPhaseIfExpired`, `PhaseProgressReconciler.reconcile`,
    `runGraduationPhaseAdvance`, the dev sim) routes through
    `commitPhaseAdvance` (`pro_phase_advance.dart:304-350`), which ALWAYS
    resets `current_week: 1` and bumps `phase_started_at` together with the
    phase bump. The founder account's live state
    (`current_phase=2, current_week=8, phase_started_at` still the ORIGINAL
    2026-04-27) is structurally unreachable through that function.
  - CORRECTED TWICE (plan-review rounds 1 and 2, same batch). This bullet
    originally read "every CLIENT write path" and stopped at the
    advance-side writer above. Round 1 added the second write path —
    `UserRepository.mergeCloudProgress` (`user_repository.dart:299-381`,
    OI-83) — but ruled it out on the strength of its doc comment's
    empty-local-Hive case ("byte-identical to the old merge"). Round 2
    showed that ruling-out was scoped too narrowly, and the CODE (not the
    doc comment) settles it. Verified directly:

    * `mergeCloudProgress` is called from `_restoreUserProgress`
      (`sync_profile.dart:779`), which runs inside `restoreLightweightAlways`
      (`sync_service.dart:1243`) — the branch taken on every returning-user
      sign-in when Hive is NON-empty (`sync_service.dart:1222-1230`), not
      only on a fresh/empty-Hive restore.
    * The merge is ASYMMETRIC across exactly the three fields in question:
      `current_phase` IS in `monotonicProgressFields`
      (`user_repository.dart:235-239`) so it is local-max-wins
      (`:368-377`), while `current_week` and `phase_started_at` are NOT in
      that list and therefore take the cloud value unconditionally
      whenever cloud is non-null (`:312-314`).
    * The merged result is written straight back to local Hive
      (`sync_profile.dart:783`).

    So there IS a fully-organic client-side path to the observed shape:
    `commitPhaseAdvance` bumps phase + week + date together locally, then
    pushes fire-and-forget via `unawaited(syncProgressNow())`
    (`user_repository.dart:448` — mandated by coding rule 1, never awaited).
    If that push has not landed before the next launch (app closed right
    after a workout, a network blip — ordinary offline-first usage, not a
    QA action), the next sign-in's restore keeps the advanced
    `current_phase` but reverts `current_week` and `phase_started_at` to
    the stale cloud values, then persists that combination locally — after
    which local and cloud agree on the wrong shape and nothing ever flags
    it again.

    NOT CONFIRMED for either account, and deliberately not asserted as the
    cause: `client_errors` retains data only from 2026-08-01 (verified by
    live query), and zero `progress_restore_demotion_declined` /
    `phase_advance_conflict_skipped` events exist for ANY account in that
    window. With only 2 accounts ever reaching phase 2 in a pre-launch app,
    that is an absence of population, not evidence the mechanism does not
    fire.
  - No Edge Function or cron writes `current_phase` (3 Edge Function hits on
    the field, all reads for AI/reporting context).
  - No in-app admin screen references `current_phase`.
  - A full-table sweep (`user_progress.current_phase > 1` joined to
    `scheduled_workouts`, checking rows before `phase_started_at`) found
    EXACTLY 2 accounts, ever, both already-identified test/QA accounts, both
    reproducing the anomaly (`amar@gmail.com`: current_week=1 — matching
    `commitPhaseAdvance`'s reset signature — but total_workouts_done=0,
    consistent with the dev-sim fast-forwarding the counter without a real
    28-day training history behind it).

  Conclusion (REWRITTEN by plan-review round 2 — the round-1 version
  claimed client-side paths were cleared, and that claim was false; see the
  twice-corrected bullet above). There are now TWO live hypotheses, and
  neither is confirmed:

  1. **A client-side restore race** (`restoreLightweightAlways` →
     `_restoreUserProgress` → `mergeCloudProgress`), which is structurally
     reachable through entirely ordinary offline-first usage and which
     produces exactly the observed `current_phase` advanced /
     `current_week` + `phase_started_at` stale shape. Silent by design: no
     telemetry fires when a NON-monotonic field is overwritten from cloud,
     so this leaves no trace to grep for.
  2. **Direct Postgres manipulation** during past QA/testing (founder
     confirmed no memory of doing so personally — plausibly a past
     agent-driven test session or the dev-sim harness, neither of which
     leaves a code-level trail either).

  What IS established: `commitPhaseAdvance`, the gated advance-side writer,
  cannot produce this state, and no Edge Function, cron, or admin screen
  writes `current_phase` at all.

  WHY THE TRIPWIRE IS STILL THE RIGHT SHIP HERE, given hypothesis 1 is now
  live rather than excluded: the tripwire is root-cause-agnostic by
  construction — it fires on the SYMPTOM (strict-empty history on a
  phase-2+ account) regardless of which mechanism produced it, so it
  observes hypothesis 1 exactly as well as hypothesis 2. What has changed
  is the follow-up: coupling `current_week`/`phase_started_at` to
  `current_phase` in `mergeCloudProgress` (accept cloud's week/date only
  when cloud's phase is also >= local's) would CLOSE hypothesis 1 rather
  than merely observe it. That is a change to a `platform`-tier
  monotonic-merge function with its own kill-switch, its own OI (OI-83)
  history of two prior review rounds getting the field list wrong, and a
  blast radius well beyond this batch's three display/restore fixes —
  filed as OI-150 rather than bundled here, because it is a distinct
  data-integrity change to a different concept, not a piece of the work
  under review. It is tracked on the board, not left as an intention.

  RISK OF THE TRIPWIRE: none to correctness (return value unchanged in every
  branch). The dedup guard is the one thing that could regress silently if
  removed — WITHOUT it, `WeekSelector`'s scroll-driven rebuilds would turn
  this into a real network call per frame for any account in the drifted
  state. Both behavioral tests in group E pin this directly (fires once;
  does not fire again on repeated calls in the same session).
related_bugs: [c9e4b7]
recurrence: |
  Writer/reader drift class (mismatched "what phase am I on" reads), but with
  a twist worth recording distinctly: the DEPLOYMENT hardcode was not a
  drifted read at all — it was a read that was never wired up in the first
  place (a literal string standing in for one, presumably from an early
  mockup/placeholder that shipped verbatim). Grep for other `'…  01'`
  /`'DEPLOYMENT 0'`-shaped literals near phase/deployment display code if
  this class resurfaces — a hardcoded placeholder that happens to be correct
  for the FIRST value it will ever see (deployment/phase 1, the common case
  for every new account) is exactly the shape that survives testing
  undetected until an account old enough to reach phase 2 renders it.
---

# DEPLOYMENT hardcoded to "01" + a live tripwire for the still-unexplained missing-Phase-I state

See the YAML above for the full writer/reader map, the 12-tier check, and
why the second, deeper investigation into the missing-Phase-I anomaly ended
in a tripwire rather than a re-attempted root-cause fix.

## Why bundle two unrelated-looking fixes in one diagnose-doc

Both surfaced from the same founder-reported observation session on the same
screen (Train, the phase/deployment header area), and both are small,
independently reviewable changes with no shared code path — bundling here
is a documentation convenience matching how this repo has bundled sibling
findings before (c9e4b7 itself covered two symptoms — missing history AND
hardcoded expired-card copy — in one doc), not a claim that they are the
same bug.

## The investigation that did NOT result in a code change

A full account-level sweep for the missing-Phase-I anomaly is worth
recording even though it did not produce a root-cause fix, so a future
session does not re-run the same investigation from scratch: query pattern,
findings, and the reasoning for stopping at a tripwire are all in
`impact_analysis` above. The founder was asked directly whether they
recalled manually editing this account's phase in Postgres; the answer was
no, which is why this is left open (not written off as confirmed
contamination) with a live catch mechanism rather than closed.
