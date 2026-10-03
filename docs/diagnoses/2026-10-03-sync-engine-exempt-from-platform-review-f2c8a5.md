---
bug_id: f2c8a5
date: 2026-10-03
batch: oi282-blast-radius-globs
status: fixed
blast_radius: platform
symptom: >-
  The sync engine's own core (the orchestrator, the retry queue, the retry
  controller, the serialiser, the reachability probe, the restore paginator, the
  SyncDomain contract and its wrappers, the two cloud-delete queues, the schedule
  restore-merge helpers, the host of the freeze merge, the rules the schedule merge
  delegates to, the template identity a push keys on and the migrator that gates it,
  and the cross-account reset hook) was account tier, because docs/blast_radius.yaml
  classified only lib/core/services/sync/** as platform. So were two restore merges
  hosted outside the services layer (the progress map's and the notification
  preferences'). A diff touching only those files cleared no platform gate: the
  plan-review record needed no `bpass: accepted`. The same inquiry found one rule
  that had never fired: the account rule for the profile write service named a path
  that does not exist.
concept: blast_radius_registry_coverage
recurrence: >-
  Fourth instance of the same COVERAGE failure in docs/blast_radius.yaml, and the
  first on the lib/ side. a3d7b1 and c9f1d3 (both 2026-07-27, both fix(governance))
  closed the scripts/ side; the 2026-07-19 sweep before them missed the keystone-gate
  family. Same cause each time: a directory glob or a hand-typed list says what
  someone thought of, and a subsystem that spans directories gets only the directory
  that was thought of. sync/** names the directory the part files live in; the core one
  directory up (the orchestrator, the queue, the coalescer, the SyncDomain wrappers, the
  serialiser, the probe) never got a rule and defaulted to the account catch-all, and
  the engine also reaches two restore merges in lib/shared/repositories/ and
  lib/features/profile/services/. The catch-all's own comment ("add an explicit rule
  ABOVE this line") was a prose instruction and prevented nothing, exactly as in c9f1d3.
  Closed structurally again: the engine set is DERIVED from what the engine files
  import, export or declare as a part across all of lib/, every file reached must be
  platform or declined by name, and the boundary it follows is written down once.
related_bugs: a3d7b1, c9f1d3
sot_registry_entry: blast_radius_registry_coverage
writers:
  - { file: docs/blast_radius.yaml, method: paths_rule_sync_engine, line: 421 }
  - { file: docs/blast_radius.yaml, method: paths_rule_out_of_layer_restore_merges, line: 71 }
  - { file: docs/blast_radius.yaml, method: paths_rule_profile_write_service_repointed, line: 314 }
readers:
  - { file: scripts/blast_radius_from_diff.dart, method_or_widget: main, line: 120 }
  - { file: scripts/check_plan_review_record_exists.dart, method_or_widget: _parseRules, line: 112 }
  - { file: scripts/check_code_review_pass_exists.dart, method_or_widget: parseRules, line: 28 }
  - { file: scripts/check_blast_radius_coverage.dart, method_or_widget: parseRules, line: 30 }
  - { file: test/contracts/blast_radius_sync_engine_platform_test.dart, method_or_widget: main, line: 332 }
  - { file: test/scripts/plan_review_record_gate_e2e_test.dart, method_or_widget: oi282_keystone_group, line: 244 }
  - { file: test/contracts/blast_radius_progress_map_writer_paths_test.dart, method_or_widget: tierFor, line: 42 }
hive_key_prefix: n/a — repo governance metadata, no app state
hive_key_formula: n/a — repo governance metadata, no app state
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/blast_radius_sync_engine_platform_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "a lib/ file an engine file imports, exports or declares as a part that is below platform with no recorded decision (declined by name)", absent_after_fix: true }
  - { pattern: "a declined entry that no engine file reaches any more", absent_after_fix: true }
  - { pattern: "an exact-path registry rule that names a file which does not exist", absent_after_fix: true }
  - { pattern: "an engine path claimed by a wildcard rule instead of its own exact-path rule, or a platform wildcard under lib/core/services/ besides sync/** and sync_domains/**", absent_after_fix: true }
  - { pattern: "a known caller of the engine (auth_session_bootstrapper, sync_state_provider) decided only in prose: promoted, reached by an engine file, gone, or no longer calling the engine while still listed below platform", absent_after_fix: true }
proposed_fix: >-
  Add twenty-one exact-path platform rules (nineteen in the services layer, two outside
  it) and the sync_domains/** directory under one written boundary; repoint the dead
  profile_write_service rule at the file's real path; DERIVE the completeness check
  (every lib/ file that an engine file imports, exports or declares as a part, and every
  sync_*.dart on disk, must be platform or named in a declined-with-reason map); fail on
  any declined entry the engine no longer reaches, on any exact-path rule that names a
  missing file, on any engine path claimed by a wildcard and on any other platform
  wildcard under lib/core/services/; decide the two known CALLERS of the engine by name
  (a map whose entries must stay below platform, unreached by the engine and still
  calling it); and prove the merge keystone itself now demands `bpass: accepted` for an
  engine-only change of every rule kind added, with an account-tier control that has no
  engine edge.
regression_test_planned:
  - test/contracts/blast_radius_sync_engine_platform_test.dart
  - test/scripts/plan_review_record_gate_e2e_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "22 registry rules (21 exact + sync_domains/**) + 1 repointed rule; contract test 36/36 green with the fix and 27 of 36 red against the registry as of 4259d0ed; mutation matrix 61 cases, 61 killed, 0 survivors (Verification section); keystone e2e 14/14; no lib/ code changed" }
  - { tier: 2_hive, status: not_applicable, evidence: "repo governance metadata, no local state" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no database involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no database involvement" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: verified, evidence: "no runtime contract; the real merge keystone (check_plan_review_record_exists.dart) run end to end in a throwaway repo against the real registry rejects an engine-only merge whose record lacks bpass, with the tier named as the reason, for each kind of rule added (an exact path, a nested exact path, the sync_domains/** directory glob, an exact path outside the services layer), and passes the same merge with bpass and an account-tier control that has no engine edge without it" }
impact_analysis: >-
  No user-facing impact. The exposure was that a change to the code that decides what
  is pushed to, and accepted from, the cloud on behalf of every feature could land with
  a plan-review record that needed no `bpass: accepted` and no feature_flag answer, while
  the same kind of change under sync/** needed both. account tier still required a
  record and a code review, so this was a thinner gate, not no gate. Nothing indicates
  it was exploited: the e5b2a9 batch happened to touch sync/sync_resilience.dart and was
  handled at platform by hand, and its B-pass (Finding 8) is what noticed. The dead
  profile_write_service rule meant the canonical profile writer had been feature tier
  since 2026-05-28; one commit touched it in the last 60 days and that commit was already
  gated for other reasons.
---

# The sync engine's core was exempt from the platform review tier

## What was wrong

`docs/blast_radius.yaml` has one platform rule for the engine: `lib/core/services/sync/**`
(line 63). The files that ARE the engine's core sit one directory up, in
`lib/core/services/`, and fell through to the account catch-all below:

| File | What it decides |
|---|---|
| `sync_service.dart` | push and restore orchestration (ten files: it composes nine `part` files under `sync/`) |
| `sync_queue.dart` | what is retried, and when it is dead-lettered |
| `sync_retry_controller.dart`, `serial_slot.dart`, `backend_probe.dart` | capped, probe-gated, serialised push retry (e5b2a9) |
| `sync_coalescer.dart`, `sync_domain.dart`, `sync_error.dart`, `sync_flags.dart`, `sync_domains/**` | fan-out coalescing, the SyncDomain contract and its eight wrappers |
| `paginate_all.dart` | restore paging (a row past 1000 was once silently dropped) |
| `pending_exlog_deletes.dart`, `pending_template_deletes.dart` | cloud-delete queues (a dropped entry resurrects a deleted row, OI-246 / OI-252) |
| `plan_integrity_reconciler.dart`, `plan_window_reanchor.dart` | the schedule restore MERGE: which copy wins (OI-285 already calls it platform) |
| `streak_progress_service.dart` | hosts `mergeFreezeProgress`, the restore freeze merge the engine calls at `sync/sync_restore_completeness.dart:180`, `:237`, `:397` (the file is also the streak-freeze writer) |
| `day_swap/day_swap_rules.dart` | the hybrid-rest predicate and the week bounds the schedule merge delegates to (`plan_integrity_reconciler.dart:158-175`); its own doc says the predicate is "Shared by ... the restore merge"; it also writes the `arranged_at_ms` stamp the merge compares |
| `template_identity.dart`, `template_identity_migrator.dart` | the cloud primary key a template push keys on (`sync/sync_workout.dart:1575`, restore rebuilds keys at `:1861`) and the gate on that push (`if (!migrated) return;`, `:1549-1550`) |
| `singleton_lifecycle_registry.dart` | the cross-account reset hook the engine registers with |
| `lib/shared/repositories/user_repository.dart` | `mergeCloudProgress`, "PURE merge for a cloud→Hive `progress` restore (OI-83)", called by the engine at `sync/sync_profile.dart:983` |
| `lib/features/profile/services/notification_prefs_repository.dart` | `adoptFromCloud`, "THE restore leg this concept never had" (OI-98), which merges the cloud preferences over the local ones through `mergeCloudNotificationPrefs`; the engine calls it at `sync/sync_profile.dart:1073` |

The last two rows are the same defect one step further out: the engine reaches them from
other directories (`lib/shared/repositories/`, `lib/features/profile/services/`), so a
derivation that stopped at the services layer would have left them at account and feature.
The e5b2a9 B-pass (Finding 8) found the first class by running the classifier by hand on three
of these files; OI-282 recorded it with a candidate fix naming five files; the two outside the
services layer were found by this batch's own B-pass.

## Writer and reader

- **Writer:** `docs/blast_radius.yaml`, the single writer of every file's tier.
- **Readers:** four independent engines resolve it with first-match-wins globs and none
  imports another (`blast_radius_from_diff.dart`, `check_plan_review_record_exists.dart` — the
  merge keystone that demands `bpass: accepted` at platform and above —
  `check_code_review_pass_exists.dart`, `check_blast_radius_coverage.dart`). A wrong tier in
  the writer is read identically by all four, so the keystone cannot catch a coverage miss;
  only the registry's coverage can. The four copies of the glob engine are textually identical
  (checked by the B-pass).
- **Order matters.** The two rules for files outside the services layer sit with the other
  `lib/` platform rules near the top (`:71-72`), because `lib/shared/repositories/**` (`:339`,
  account) and `lib/features/profile/**` (`:399`, feature) would otherwise claim them first.

## Why the comment did not prevent it

The catch-all carries its own instruction: "If a new service is clearly platform-scoped, add an
explicit rule ABOVE this line." No rule or test forced the question when `sync_queue.dart`,
`sync_coalescer.dart` or `serial_slot.dart` landed, so each took the account default. This is
c9f1d3's lesson verbatim — a prose comment is not a guard.

## The dead rule

`lib/core/services/profile_write_service.dart` (account) names a path that has never existed:
the profile write service has lived at `lib/features/profile/services/profile_write_service.dart`
since 2026-05-21, a week before the rule was written (2026-05-28). So the rule never fired and
the canonical profile writer resolved to `lib/features/profile/**` → feature. A registry-wide
scan found exactly one such rule among 90 exact-path rules (111 now, all present on disk and
tracked). It is repointed, and a test now fails on any exact-path rule that names a missing
file, which is also what stops the new exact rules from rotting on a rename.

## The boundary

Round 2 of the plan review showed that the first draft drew the line by no single rule: it
promoted the two schedule restore-merge helpers on "a restore merge decides which copy wins"
while declining the file that hosts the freeze merge, and it described one migrator as
"one-shot" when its own header says it re-runs every launch. The B-pass then showed that the
rewritten rule still read as one uniform test while the cost cap, the cross-account hook and the
scope were applied unevenly. It is now written once, in the registry block's header comment
(`:426-448`), as three prongs, and applied to every `lib/` file an engine file reaches:

> A file is platform when it is **(1) engine machinery** (the code that itself pushes, queues,
> retries, serialises, probes, pages, or runs a restore merge, plus the contract, error taxonomy
> and per-domain path flags those parts are built on: `sync_domain`, `sync_error`,
> `sync_flags`), listed whatever its churn; or
> **(2) cross-account isolation** the engine registers with; or **(3) shared with other code, but
> its own words say a function in it MERGES the cloud copy with the local one, supplies the
> identity a push keys on, gates a push, or is a rule the restore merge itself delegates to,**
> and promoting it alone adds at most one newly-platform commit per 60 days against the base
> registry. A file the engine only consults (a type, an accessor, a utility, telemetry, transport,
> ingest, a domain read, a payload builder, a computation applied to the winners after a merge, a
> writer) stays below platform and is declined by name in the test with the function the engine
> calls.

The scope is what the engine files REACH. A CALLER of the engine is not found by that derivation, so
the two known ones are decided by name in the test's `_callers` map and judged on their own words,
below.

The cost cap attaches to prong 3 only, on purpose: machinery is the thing the platform review is
for, however often it changes (`sync_queue.dart` adds 2 commits and `plan_integrity_reconciler.dart`
adds 3, and both are listed), whereas a shared file that merely hosts one decision must not drag
in every unrelated commit that touches it. The verbs in prong 3 are explicit so that borderline
files are decided against a list rather than argued case by case. Decisions, with their cost
(commits touching the file / newly platform on their own over the 60 days to 2026-10-03, against
the registry as of `4259d0ed`):

| Candidate | Prong and evidence in the code's own words | Touching / alone | Decision |
|---|---|---|---|
| `sync_queue.dart` | 1: the persistent retry queue | 5 / 2 | platform (machinery, uncapped) |
| `plan_integrity_reconciler.dart` | 1: "restore merge: completed-day-preserving, arrangement-wins"; the schedule restore merge the engine runs | 7 / 3 | platform (machinery, uncapped) |
| `plan_window_reanchor.dart` | 1: the plan-window re-anchor both restore writers share | 0 / 0 | platform |
| `singleton_lifecycle_registry.dart` | 2: generic scaffold for cross-account singleton resets (13 registrants, the engine is one); the tier definition names "cross-account" | 0 / 0 | platform |
| `streak_progress_service.dart` | 3: `mergeFreezeProgress` doc: "Pure merge ... for the restore path (`_restoreFreezes`)" | 1 / 0 | platform |
| `template_identity_migrator.dart` | 3: called from `_syncWorkoutTemplates` / `_restoreWorkoutTemplates`; the push returns early unless it reports migrated | 2 / 0 | platform |
| `template_identity.dart` | 3: callers use its null "to route legacy rows through `TemplateIdentityMigrator` instead of the cloud push/restore path"; the push keys on `cloudIdFromKey` | 1 / 0 | platform |
| `day_swap/day_swap_rules.dart` | 3: "Shared by [isRest], the restore merge ..."; the reconciler delegates `isRestHybrid` and `mondayOf` to it | 2 / 1 | platform |
| `lib/shared/repositories/user_repository.dart` | 3: `mergeCloudProgress` "PURE merge for a cloud→Hive `progress` restore (OI-83)", mirrors `mergeFreezeProgress` | 3 / 0 | platform (B-pass finding 5) |
| `lib/features/profile/services/notification_prefs_repository.dart` | 3: `adoptFromCloud` "THE restore leg this concept never had", merging through `mergeCloudNotificationPrefs` | 3 / 0 | platform (found by the sweep for finding 5) |
| `workout_schedule_read_service.dart` | 3: `currentWeekColumnProjection` doc: "the sync-projection decision"; the engine also consults `isTerminalScheduleRow` | 18 / 7 | account: over the cap |
| `workout_write_service.dart` | 3 on the verbs (`exlogKey` is "single SoT for exlog key", the identity the exercise-log restore keys Hive rows on) | 9 / 5 | account: over the cap (recorded in `_declined`, B-pass finding 4) |
| `nutrition_write_service.dart` | borderline on the verbs (`clampRestoredNutritionRow`, "public restore-path entry point", the same clamp the local write path uses) | 5 / 4 | account: over the cap (recorded in `_declined`, B-pass finding 4) |
| `template_service.dart` | the engine delegates one cleanup (`cleanSyncTemplateSchedule`) and decides what to clean and when itself | 5 / 1 | account: a domain service, no decision in it |
| `lib/features/profile/services/profile_target_recompute.dart` | `derivedTargetInputsChanged` gates the restore recompute and `recomputeDerivedTargets` runs on the merged map: a computation applied to the winners | 1 / 0 | account: **borderline, disclosed**; it is the one file that passes the cap but not the verb list, so flipping it is one registry rule |
| `day_swap/day_swap_result.dart` | "Value types ... Pure: no Hive, no I/O" | 1 / 1 | account: types |
| `supabase_service.dart` | 1, borderline: the orchestrator calls `callFunction` (cold-start retry) and `ensureFreshToken` (coalesced refresh) on its push and restore paths, but the same transport serves AI, payments and telemetry, and what is retried, and when, is decided in `SyncQueue` / `SyncRetryController` | 3 / 0 | account: shared transport, **borderline, disclosed**; promoting it adds no commit on its own but pulls every AI and payments transport change into the sync review |
| `error_telemetry.dart`, `subscription_service.dart`, `health_sync_service.dart`, `migrated_key.dart`, `restore_telemetry_policy.dart`, `result.dart`, and outside the services layer `profile_write_service.dart`, `equipment_vocab.dart`, `date_utils.dart`, `ist_date.dart`, `app_constants.dart`, `bmr_calculator.dart`, `coach_memory.dart`, `ai_coach_repository.dart` | telemetry, entitlement state, ingest, an accessor, a telemetry decision, a type, the profile writer, a normaliser, calendar and clock helpers, constants, arithmetic, a model, a payload builder | not needed: no prong is met | account or feature: consulted, not deciding (each named with the engine-called function in the test) |

**Callers of the engine** are outside what the derivation reaches (no engine file imports them), so
the scope rule does not decide them. Two are known, both judged on their own words and decided by
name in the test's `_callers` map (each entry must stay below platform, must not be reached by an
engine file, and must still make the named call, so the decision cannot outlive the code):

| Caller | Prong and evidence in the code's own words | Touching / alone | Decision |
|---|---|---|---|
| `auth_session_bootstrapper.dart` | 1, literally: `hydrateFromCloud` runs its own restore merge (the users row; the progress map through `mergeCloudProgress`, `:900`) and its comment calls it the twin of the engine's `_restoreUserProgress` ("so the two restore writers cannot drift", `:896-898`) | 6 / 3 | account: a CALLER, outside the scope the boundary derives, and otherwise post-auth routing; **borderline, disclosed**. Flipping it costs 3 newly-platform commits per 60 days and puts an auth-routing file under `feature_flag` |
| `lib/shared/providers/sync_state_provider.dart` | 1, arguably: decides WHEN the engine retries (the 5-minute auto-drain timer, `:202-204`; the drain and the forced retry on reconnect, `:184`, `:190`); WHAT is retried, capped and dead-lettered is decided in `SyncQueue` and `SyncRetryController` | 3 / 1 | account: a caller; **borderline, disclosed** |

The cost is not the reason for either call: a caller is simply outside what the derivation can
see, and a promoted caller would have to become a derivation root (its own imports then need
decisions). The cost figures are given so the founder can flip either with one registry rule, one
`_engine` entry and a deleted `_callers` entry.

## Cost, measured before deciding

Promotion is not free: a change to a platform file needs `bpass: accepted` in the plan-review
record and the `feature_flag` requirement the platform tier lists. Much of the cost is
enforcement rather than new work: §4.3 already makes a B-pass the author's job for any code batch
at account tier or above, and what platform adds is that the keystone refuses a record without it
(`check_plan_review_record_exists.dart:833`). So the churn was measured with one
`git log --no-merges --name-only` pass over the window from 2026-08-04 00:00 IST to the base
commit: 717 non-merge commits, 286 already platform or above (431 below) under the registry as of
the base commit `4259d0ed`. Each commit's full file list was classified under that registry,
counting commits that rise from below platform to platform:

| Rule set | Commits newly platform |
|---|---|
| the five files OI-282 names | 2 |
| the engine class (12 exact paths + `sync_domains/**`) | 3 |
| the first draft (15 exact paths + `sync_domains/**`) | 5 |
| the shipped set (21 exact paths + `sync_domains/**`) | 6 |

About one commit per ten days. Leave-one-out over the shipped set: removing `plan_integrity_reconciler.dart`
or `sync_queue.dart` leaves 4, removing `day_swap_rules.dart` leaves 5, removing any other leaves 6;
the two files outside the services layer add none. An earlier draft of this analysis said 6 / 7 / 7 by
counting commits that touch `sync/**` as if they were not already platform; classifying each
commit's whole file list corrected it. A second trap in the same measurement: classifying against the
WORKTREE registry, which already carries the new rules, would read every engine commit as already
platform and report zero, so the baseline is read from the base commit by SHA. A third trap: a
date-only `--since=2026-08-04` takes the CURRENT time of day (git's approximate dates), so the
window start moves between runs. Run at 21:01 on 2026-10-03 it excluded one commit made at 20:53 on
2026-08-04 and gave 716 / 285, which is what this analysis first recorded; run after midnight it
gives 717 / 286. The second B-pass round caught the mismatch. Every decision figure (2 / 3 / 6 and
the per-file costs) is identical either way, and the window is now an absolute timestamp
(`--since=2026-08-04T00:00:00+05:30`).

## The fix

Nineteen exact-path rules in the services layer and `sync_domains/**` above the
`lib/core/services/**` catch-all, plus two exact-path rules for the restore merges hosted outside
it (above the `lib/shared/repositories/**` and `lib/features/profile/**` rules they must beat).
Exact paths over a `sync_*.dart` glob, deliberately: a glob auto-promotes future files with nobody
deciding, and a name glob would also have missed `serial_slot.dart`, `backend_probe.dart` and
`paginate_all.dart`.

**The structural half matters more than the list.** The completeness check is DERIVED:
`test/contracts/blast_radius_sync_engine_platform_test.dart` reads the import, export and `part`
directives of every engine file (the listed paths, everything under `sync_domains/` and `sync/`,
and any `sync_*.dart` on disk: 40 files) across all of `lib/`, and lists the family on disk; every
file found must be platform or be named in the test's `_declined` map with a reason. Today that is
64 files: 43 platform, 21 declined, 0 undecided; against the registry as of `4259d0ed` the same
derivation lists 29 undecided. Add a new engine file, a new `part`, or an import from an engine
file, and the test fails until its tier is decided — the shape a3d7b1 used for git hooks. Four
properties are pinned on purpose, each because a review showed it missing:

- the directive reader is tested on a synthetic source (double-quoted, conditional, export, `part`
  and `part of`, a keyword with no space before its quote, two directives on one line, a
  commented-out import, relative resolution against the importing file's own directory, a `lib/` file
  outside the services layer), and `part` is also asserted against the real engine library: it is how
  the engine itself is composed, and a reader that ignored it would leave a part file placed outside
  `sync/` on the account catch-all unseen;
- "decided" means platform or declined, never "some rule claims it": four files had explicit
  account rules written for other reasons and so counted as decided with no recorded reason (two of
  them meet the verbs and stay account on cost alone); every declined entry must still be reached by
  an engine file, so the map cannot outlive the code;
- exactness: every engine path is claimed by its own exact rule, a brand-new `sync_*.dart` is NOT
  claimed, and no platform wildcard under `lib/core/services/` exists besides `sync/**` and
  `sync_domains/**`, or a `*_queue.dart` would auto-promote future files;
- the known callers: the derivation cannot see a file that CALLS the engine, so the two known ones
  are decided by name in `_callers`, and each entry must stay below platform (a promoted caller is
  decided: delete it), must not be reached by an engine file (then the derivation owns it), and
  must still make the call named in the entry, read with comments stripped (a stale caller is not a
  caller). Without that, the decision would be prose that nothing could contradict.

The merge keystone is proven separately, in `test/scripts/plan_review_record_gate_e2e_test.dart`,
as six arms over one record shape: an engine-only merge without `bpass:` is REJECTED with
"blast-radius=platform requires bpass: accepted" (so the tier is the reason, not a record error)
for an exact path, a nested exact path (`day_swap/day_swap_rules.dart`), a file under the
`sync_domains/**` directory glob and an exact path outside the services layer
(`user_repository.dart`, which must beat the repository rule below it); the same merge with
`bpass: accepted` PASSES; and an account-tier file with no engine edge
(`lib/features/ai_coach/zz_keystone_control.dart`, account by a directory rule of its own) without
`bpass:` PASSES. The keystone has its own copy of the glob engine, which is why each kind of rule
gets an arm.

## Verification

Self-attested (§4.4 rule 21). The mutation driver is a scratch script in the session's scratchpad,
not in the repo: each case backs the target up, applies ONE text mutation, confirms the text
changed, runs the named test file(s), records the exit code and the failing tests, restores from
the backup and compares the bytes.

- **With the fix:** the contract test is green 36/36, the keystone e2e file 14/14 (the OI-282 group
  is six arms) and the repointed progress-map test 5/5.
- **Without the fix** (case M00, the registry as of `4259d0ed`): the contract test is red on 27 of
  36 and the OI-282 e2e group on 4 of 6; the two arms that stay green are the control and the
  "with `bpass: accepted`" arm, which pass under either registry, as they should.
- **Mutation matrix: 61 cases, 61 killed, 0 survivors, 0 not applied, 0 restore failures**, run
  against the final text of the registry, of both tests and of the two caller files (every case
  confirmed APPLIED, restored and byte-compared, and the failing test names read on every case:
  the callers cases go red on the callers test, not on something incidental):

| Cases | One change to… | Red tests per case |
|---|---|---|
| M00 | the whole registry reverted to the base | 27 of 36 + 4 of 6 |
| M01-M19 | one exact services-layer rule deleted | 3 (4 for `sync_queue`, `backend_probe`) |
| M20-M21 | `sync_domains/**` deleted / narrowed to `sync_domains/*` | 2 each |
| M22 | the whole block moved below the `lib/core/services/**` catch-all (order) | 23 |
| M23 | `sync_queue.dart` platform → account | 3 |
| M24-M27 | a rule widened to `lib/core/services/*.dart` / glob-ified / pointed at a missing path / the dead profile rule restored | 6, 2, 5, 2 |
| M28-M33 | derivation inputs: a made-up import (in `sync_service.dart`, and in `day_swap_rules.dart`, which is not the orchestrator), a double-quoted import, a conditional-import alternative, an `export`, a new `sync_zz_probe.dart` on disk | 1 each |
| M34-M36 | the test's own reader resolves against the wrong root / loses double quotes / the `day_swap_result` declined entry removed | 3, 1, 2 |
| M37-M39 | keystone e2e: the `sync_queue` rule deleted; the keystone's own tier lookup made last-match-wins; the `day_swap_rules` rule deleted | 1, 4, 1 |
| M40-M43 | a `part` naming a new undecided file; the reader loses `part`; loses a keyword with no space before the quote; loses a second directive on one line | 1, 2, 1, 1 |
| M44-M46 | the `user_repository` rule deleted, the `notification_prefs_repository` rule deleted, the `user_repository` rule moved below `lib/shared/repositories/**` | 4, 3, 4 |
| M47-M50 | the engine stops importing `template_service` (stale declined entry); a `*_queue.dart` platform wildcard added; the declined entry for `workout_write_service` removed; the one for `ist_date.dart` removed | 1, 1, 2, 2 |
| M51-M53 | keystone e2e arms: the `sync_domains/**` rule deleted; the `user_repository` rule deleted; moved below the repository rule | 1 each |
| M54 | the test counts any non-catch-all rule as a decision again (the old "claimed" meaning) | 2 |
| M55-M60 | the callers map: a platform rule is added for `auth_session_bootstrapper.dart` / its `_callers` entry names a missing file / an engine file imports `sync_state_provider.dart` (so the derivation owns it) / `auth_session_bootstrapper.dart` stops calling `mergeCloudProgress` / that call survives only in a comment / `sync_state_provider.dart` stops calling `SyncQueue.instance.drain` | 1, 1, 2, 1, 1, 1 |

  The B-pass's surviving mutations (a keyword with no space, two directives on one line, a stale
  declined entry, a platform wildcard) are M42, M43, M47 and M48, and its `part` finding is
  M40/M41; the second B-pass's callers finding is M55-M60; all are killed now. The one mutation the
  second reviewer's own pass left alive (a new import inside a DECLINED file) is the documented
  one-hop limit, not a gap in the callers map.
- **Nothing else moved.** All 4,581 tracked paths classified under the base registry (read by
  SHA, byte-identical to the checked-in copy) and under the new one: 30 change tier, none other.
  28 account → platform (the 19 services-layer engine files, the 8 `sync_domains/` wrappers and
  `lib/shared/repositories/user_repository.dart`), `notification_prefs_repository.dart` feature →
  platform, `profile_write_service.dart` feature → account; the other 4,551 are unchanged. (An
  earlier tally of 28 was taken before the two out-of-layer promotions.)
- **Registry shape:** 161 rules (139 at base), 111 exact-path (90 at base), every exact path
  present on disk and tracked.
- **Registry line cites** moved by five below `:67`; every cite outside the historical records
  either sits at or below `:67` or was already stale at the base (see the plan, D4).

## What the reviews changed

- **Round 1** (on the first plan) returned not converged, no P0: it replaced six `sync_*` globs with
  exact paths plus a derived test, moved the commit from `chore(` to `fix(governance)` with this
  full doc, and corrected the cost figures.
- **Round 2** (two reviewers, mechanism and process) returned converged on condition of local
  folds, no P0, and every fold is in. The boundary above (A: inconsistent treatment of three
  engine-called files and an untrue "one-shot" reason; B and A independently: `day_swap_rules.dart`
  undecided because the derivation reached one hop). The derivation widened to every engine file.
  This doc's first "known residual" was wrong for the keystone (OI-70 closed 2026-07-27: it takes the
  max over the range base and HEAD). The e2e control no longer depends on a file the contract test
  can flip. OI-301's board wording now names the real reason.
- **B-pass, round 1** (one reviewer, on the staged implementation) found no P0, one P1, five P2 and
  four P3, and every finding was checked against the source before it was acted on (the costs, the
  `part` count, the call sites and the line cites all reproduced). All are folded: the directive reader
  now reads `part` (P1: a part file outside `sync/` was invisible to the guard); the boundary's
  cap, the cross-account prong and the scope are written down and applied uniformly (three P2);
  the four files that stayed account through explicit rules are recorded with their reasons and
  their cost, and `_declined` may hold them (P2); the derivation covers all of `lib/`, which turned
  up two restore merges outside the services layer, now platform (P2); the bug-class index row
  for 2.85 is in the debugging skill, with the two rows (2.80, 2.81) that earlier sessions left out;
  the surviving mutations are closed (a keyword with no space, two directives on a line, a stale
  declined entry, a platform wildcard); the declined reasons name the function the engine calls; the
  e2e control is a file with no engine edge and the keystone has an arm for the directory glob and
  for a file outside the services layer; and the pre-push consequence of the profile repoint is
  written down below. Promoting `user_repository.dart` and `notification_prefs_repository.dart`
  changed the value of a stored fact, so §4.1.5.3's sweep ran again for them: it found one test that
  pinned the old tier (`blast_radius_progress_map_writer_paths_test.dart` asserted
  `user_repository.dart` is `account`, which would have gone red at pre-push). It is repointed to
  `platform` with the reason in the same commit, and the registry-line cites that the two new
  rules shift by five were re-swept (plan D4).
- **B-pass, round 2** (a second fresh reviewer, on the tree after round 1's fixes; the full suite
  was green on it, +7560) found no P0 and no P1, two P2 and seven P3, and again every finding was
  checked against the files before it was acted on (none was a false alarm). The two P2 were
  boundary calls the first fix had left half-made: the cost cap was still doing the work of a scope
  decision for `auth_session_bootstrapper.dart` (a second restore writer that is a CALLER of the
  engine), and the `supabase_service.dart` reason omitted the two functions the engine core calls
  in it. Folded: callers are now a stated scope limit, decided by name and pinned in `_callers` (a
  new test with six mutations of its own), the cost is given only as the price of flipping, and the
  `supabase_service` reason names `callFunction` (cold-start retry) and `ensureFreshToken`
  (coalescing) and is a disclosed borderline. The seven P3: `sync_state_provider.dart`, which decides
  WHEN the engine retries, was disclosed in prose and pinned by no test, so it joins `_callers`; the
  cost totals did not reproduce (717 / 286, not 716 / 285: a date-only `--since` takes the current
  time of day; the decision figures were identical); the registry quoted two of its own line numbers
  that the first round's two new rules had moved by five; bug class 2.85 called `sync_service.dart`
  "ten `part` files" (a library of ten files, nine `part` directives); the plan cited the keystone
  validator's range one line-pair short (788-868); the S-tier and `bpass` consequence for
  `notification_prefs_repository.dart` was unstated; and `sync_domain` / `sync_error` / `sync_flags`
  were listed without the boundary saying why (prong 1 now names the contract, error taxonomy and
  path flags). While folding, the test header's count of cap-held declines (two) was corrected to
  three.

## Known residuals — stated, not hidden

- The local classifier (`blast_radius_from_diff.dart`) and the catastrophic review-acceptance gate
  (`check_code_review_pass_exists.dart`) read only the working-tree registry. The merge keystone,
  which is what enforces `bpass`, takes the max over the range base and HEAD since OI-70 (closed
  2026-07-27), so a commit that deletes its own protecting rule is not graded by the deleted rule at
  merge. Unchanged here.
- The derivation follows what the engine files reach, one hop: a file reachable only through a
  DECLINED file is not derived (21 such files exist today; none was read, they were judged by name
  and importer), and it cannot see files that CALL the engine. Two callers are known and decided
  by name in `_callers` (see the table in the boundary section): `auth_session_bootstrapper.dart`,
  a second restore writer (`hydrateFromCloud` merges the users row and routes the progress map
  through `mergeCloudProgress`; 6 commits touch it, 3 would be newly platform on their own), and
  `sync_state_provider.dart`, which schedules the retries (3 commits, 1 newly platform). Both stay
  account because a caller is outside the scope the boundary derives, not because of the cost;
  both are disclosed borderline calls. Any OTHER caller is not found by the test.
- The directive reader errs toward demanding a decision: a directive-shaped line inside a block
  comment or a multi-line string would match (checked, fail-safe direction).
- Borderline calls, disclosed so the founder can flip them with one rule each (the registry is
  platform tier, so a reversal costs a full pipeline run): `profile_target_recompute.dart` (passes
  the cap, not the verb list), `nutrition_write_service.dart` and `workout_write_service.dart` (meet
  or nearly meet the verbs, over the cap), `supabase_service.dart` (shared transport that carries
  the engine's cold-start retry and token coalescing; free to promote in churn, but it would pull
  every AI and payments transport change into the sync review), and the two callers above. To flip
  a caller, add its exact rule, delete its `_callers` entry and list it in `_engine`, which makes it
  a derivation root whose imports then need decisions.
- Side effects of the tier moves, none of them a defect. `profile_write_service.dart` computes
  `account` where it was `feature`, so a diff touching only it loses the §4.12.6 S-tier fast path.
  `notification_prefs_repository.dart` (feature to platform) loses it more strongly: S-tier is a
  fix that skips the plan review and the B-pass, and the merge keystone now demands
  `bpass: accepted` (`check_plan_review_record_exists.dart:833-834`) for a record touching it;
  `user_repository.dart` (account to platform) newly needs `bpass: accepted` too. And a push whose
  only non-docs change is `profile_write_service.dart` or `notification_prefs_repository.dart` now
  runs the full local `flutter test` in `scripts/pre-push.sh` (it skips the suite only when the max
  tier is `feature`, lines 172-190). The measured cost over 60 days is nil for the profile writer:
  one commit touched it, a 120-file sweep that already touched platform paths; and 3 / 0 for each
  of `notification_prefs_repository.dart` and `user_repository.dart` (touching / newly platform).
- The `feature_flag` requirement of the platform tier is not met for this batch, deliberately: the
  change is registry data, its "off" state is the old registry, and no runtime behaviour moves. No
  gate enforces that requirement (`scripts/safe_push.sh:132-134` says so: it is the reviewer, not a
  gate, that catches its absence). It is a waiver of a stated tier requirement, decided in the plan
  and put to the founder in the PR description, where the merge ratifies it.
- No gate stops a stray file at the repo root: this batch also removes `existsSync` and
  `build_log.txt`, and the missing guard is OI-301.
