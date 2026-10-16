---
branch: oi282-blast-radius-globs
plan: docs/superpowers/plans/2026-10-03-oi282-sync-engine-platform-tier.md
date: 2026-10-04
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi282-blast-radius-globs-bpass.md
---

# Plan review — oi282-blast-radius-globs

§4.12 record. The plan was reviewed in two rounds by context-blind reviewers (round 2 ran two reviewers, one on
mechanism and one on process, against the plan as hardened by round 1), and the staged implementation then got a
B-pass in two rounds (the second on the tree after the first round's fixes). Everything material is folded in the
same commit; what is not fixed is named below rather than absorbed.

## What this is

`docs/blast_radius.yaml` classified only `lib/core/services/sync/**` as platform, so a diff touching only the sync
engine's own core (the orchestrator, the retry queue, the retry controller, the coalescer, the SyncDomain contract
and its wrappers, the cloud-delete queues, the schedule restore-merge helpers, the freeze-merge host, the rules the
schedule merge delegates to, the template identity a push keys on and its migrator gate, the reset hook) computed
`account` and cleared no platform gate: the plan-review record needed no `bpass: accepted`. Two restore merges the
engine calls from outside the services layer (the progress map's in `user_repository.dart`, the notification
preferences' in `notification_prefs_repository.dart`) sat at account and feature. OI-282 recorded the hole (fourth
instance of the `blast_radius_registry_coverage` class; diagnose `f2c8a5`). The batch adds 21 exact-path platform
rules plus `sync_domains/**` under one written three-prong boundary, repoints one dead rule, derives the completeness
check from what the engine files import, export or declare as a part across all of `lib/`, proves the real merge
keystone end to end, removes two stray root files and files OI-301 for the missing root guard.

The registry is itself platform tier, so this change is held to the review it imposes.

## Rounds

| Round | Reviewers | Result | What it changed |
|---|---|---|---|
| 1 | one, on the first plan | not converged, no P0 | six `sync_*` globs became exact paths plus a derived test; the commit moved from `chore(` to `fix(governance)` with a full diagnose-doc; the cost figures were corrected (an earlier 6 / 7 / 7 was wrong: it counted commits touching `sync/**` as if not already platform; measured is 2 / 3 / 5 for five files / engine class / first draft) |
| 2 | two, on the post-round-1 plan: A mechanism (1 P2, 6 P3), B process (1 P1, 2 P2, 5 P3) | converged on condition of local folds, no P0 | the boundary was drawn by no single rule (the freeze-merge host declined while the schedule merge helpers were promoted; a migrator called one-shot against its own header), so it is now written once and applied to every file the engine reaches, with four promotions; the derivation was rooted at one file and left `day_swap_rules.dart` undecided (found by both reviewers independently), so it now covers every engine file; an exactness test, the three-arm keystone design with an explicit-rule control and the tier named in the message, the OI-301 board wording, the closure ledger, the skill entry and a stale OI-70 residual were corrected |
| B-pass 1 | one, on the staged implementation (full loop green first: analyze, pre-commit, full `flutter test` +7553 ~9) | no P0, 1 P1, 5 P2, 4 P3; every finding verified by the author against the files, none a false alarm | the directive reader ignored `part` (the engine's own composition mechanism) and the derivation stopped at the services layer: it now reads `part` and covers all of `lib/`, which promoted two restore merges hosted outside the layer; the boundary is three prongs with the cap on the third only; "decided" means platform or declined by name, and four files held at account by explicit rules are recorded; surviving mutations closed; declined reasons name the engine-called function; the e2e control no longer is an engine import, and arms were added for the directory glob and for a path outside the layer; the bug-class index rows are in the debugging skill; the pre-push consequence of the profile repoint is written down |
| B-pass 2 | one, fresh and context-blind, on the tree after B-pass 1's folds (full suite green on it first: +7560 ~9) | no P0, no P1, 2 P2, 7 P3; every finding verified by the author against the files, none a false alarm | the cost cap was doing a scope decision's work for `auth_session_bootstrapper.dart` (a second restore writer that CALLS the engine), so callers are now a stated scope limit, decided by name and pinned in a `_callers` map (`auth_session_bootstrapper`, `sync_state_provider`) with a test and mutations of its own; the `supabase_service` reason now names the two functions the engine core calls in it (`callFunction` with its cold-start retry, `ensureFreshToken` coalescing) and is a disclosed borderline; the cost totals were re-measured from an absolute window start (717 / 286, not 716 / 285); two of the registry's own line cites were reworded; bug class 2.87's "ten `part` files" now reads a library of ten files; the plan's keystone-validator range was corrected to 788-868; the S-tier and `bpass` consequence for `notification_prefs_repository.dart` is written down; prong 1 says why `sync_domain` / `sync_error` / `sync_flags` are listed; the retry scheduler `sync_state_provider.dart`, disclosed in prose only, joins the pinned callers |

Each reviewer finding was verified against the source before it was acted on; none was taken on a reviewer's word.
The folds were also swept for their own consequences: promoting `user_repository.dart` made one older test
(`blast_radius_progress_map_writer_paths_test.dart`) stale, found by the value-semantics grep and repointed in the same
commit, and the registry line cites that the two new rules shift by five were re-swept.

## Ground truth (verified against code and live state)

- All 21 exact rules and `sync_domains/**` resolve to platform under the real classifier; classifying every tracked
  path (4,581) under the base registry (read by SHA, byte-identical to the checked-in copy) and under the new one moves
  exactly 30: 28 account to platform (the 19 services-layer engine files, the 8 `sync_domains/` wrappers and
  `user_repository.dart`), `notification_prefs_repository.dart` feature to platform, `profile_write_service.dart`
  feature to account.
- The derived completeness check reads `import` / `export` / `part` / `part of` across all of `lib/`: 40 roots, 64 files
  needing a decision, 43 platform, 21 declined by name with the engine-called function, 0 undecided; against the registry
  as of the base commit the same derivation lists 29 undecided. Every declined reason was checked against the code.
- The real merge keystone, run end to end in throwaway repos (six arms): an engine-only merge without `bpass` is
  rejected with the tier named as the reason for an exact path, a nested path, the `sync_domains/**` directory glob and a
  path outside the services layer; the same merge with `bpass` passes; an account-tier control with no engine edge
  passes. Against the old registry the engine scenario exits 0, which is the hole.
- The two known callers of the engine (`auth_session_bootstrapper.dart`, a second restore writer, and
  `sync_state_provider.dart`, the retry scheduler) are decided by name in the contract test's `_callers` map: each must
  exist, stay below platform, not be reached by the derivation, appear in neither `_engine` nor `_declined`, and still
  make the call it is pinned for (read from comment-stripped source). The call sites were read in the code
  (`auth_session_bootstrapper.dart:900`, `sync_state_provider.dart:184/190`).
- Mutation proof (rule 21, self-attested): 61 cases, 61 killed, 0 survivors, 0 not applied, 0 restore failures, run
  against the final text of the registry, both tests and the two caller files; against the registry as of the base
  commit the contract test (36 tests) is red on 27 and the keystone group on 4 of 6.
- Cost, measured before deciding: 717 non-merge commits since 2026-08-04T00:00+05:30 (60 days), 286 already platform;
  newly platform = 2 (the five files OI-282 names), 3 (the engine class), 6 (shipped), about one per ten days,
  classified against the base registry by SHA (the worktree registry would read zero). The window starts at an absolute
  timestamp because a date-only `git log --since` takes the current time of day.
- Dead rule: 1 of the 90 exact-path rules at base named a path that never existed; a rot test now fails on any such
  rule. The registry has 161 rules (139 at base), 111 of them exact-path, all present and tracked.
- Full gate loop on the final staged tree (§4.12.8): `flutter analyze --no-fatal-infos --no-pub` 0 warnings / 0 errors
  (the same 343 pre-existing infos); `sh scripts/pre-commit.sh` all gates passed; the three registry-reading test files
  green (36 + 14 + 5 = 55). The full `flutter test` was green on the v4 tree (+7560 ~9, 39:44) before the second B-pass;
  the v5 fold changed one test file, registry comments and docs (no `lib/` code), and the full suite runs once more at
  pre-push on the committed tree.
- Keystone rehearsal: the real merge gate run on a `--no-ff` merge of this branch's 19 files into a scratch repo seeded
  with `origin/main`'s registry. With this record: PASS (1 merge with a valid record). Negative control with the record
  omitted: FAIL, "blast-radius=platform (>= account) but has no plan-review record".

## Authorization

The founder's instruction was "go with batch A", given in answer to "needs your yes or no on OI-282 first". The
written rule counts only "commit", "push" and "ship". The reading acted on: this session's permission mode is `auto`
(read from the session metadata), the founder's standing auto-mode directive is to run an approved batch to done and
pause only for a live prod apply, an APK, a genuine product fork or a hard blocker (none applies), and a branch push
plus a PR that the founder merges by hand is reversible. If that reading is wrong, the PR is closed unmerged.

## Waivers and policy calls put to the founder (the merge ratifies them)

- **`feature_flag` is not met**, deliberately: the change is registry data, its "off" state is the old registry, and
  no gate enforces the requirement (`scripts/safe_push.sh:132-134`: the reviewer, not a gate, catches its absence).
  Every future engine change will have to answer it, which is the policy OI-282 asked for.
- Width (21 exact rules plus `sync_domains/**`, not five files), the six promotions under the third prong
  (`streak_progress_service`, `template_identity`, `template_identity_migrator`, `day_swap_rules`, and outside the
  services layer `user_repository` and `notification_prefs_repository`), the two schedule restore-merge helpers and
  `singleton_lifecycle_registry` kept on the first two prongs, the cost cap (at most one newly-platform commit per
  60 days, on the third prong only), and the declines: `workout_write_service` and `nutrition_write_service` (held by
  the cap), `supabase_service` and `profile_target_recompute` (both disclosed borderline: the first is shared transport
  that carries the engine's cold-start retry and token coalescing, the second passes the cap but not the verb list) and
  the rest of the consulted files. Each is one registry rule plus a line in the contract test; because the registry is
  platform tier, a reversal costs a full pipeline run.
- Callers of the engine are a stated scope limit, not a cost call: `auth_session_bootstrapper.dart` and
  `sync_state_provider.dart` stay account and are pinned in `_callers`. To flip one: add its exact rule, list it in
  `_engine` and delete its `_callers` entry; it then costs 3 and 1 newly-platform commits per 60 days.
- Side effects of the tier moves: `profile_write_service.dart` is now account tier and so loses the §4.12.6 S-tier fast
  path; `notification_prefs_repository.dart` (feature to platform) loses it too and needs `bpass: accepted` when it is
  the only code touched, as `user_repository.dart` newly does; and a push whose only non-docs change is
  `profile_write_service.dart` or `notification_prefs_repository.dart` now runs the full local test suite in
  `scripts/pre-push.sh` (measured cost over 60 days: nil).

## Deliberately not closed

- **OI-301** — no gate stops a stray file at the repo root; a new platform-tier gate needs its own plan, and what is
  legitimate at the root is itself an open question (21 tracked root directories, `node_modules/` with 142 files).
- The derivation follows what the engine files reach, one hop: a file reachable only through a DECLINED file is not
  derived, and it cannot see a CALLER of the engine. The two known callers are decided by name in `_callers`
  (`auth_session_bootstrapper.dart`, a second restore writer that also calls `mergeCloudProgress`: 6 commits touch it,
  3 would be newly platform; `sync_state_provider.dart`: 3 commits, 1 newly platform). Any other caller is not found
  by the test; written in the test header and the diagnose doc.
- The local classifier and the catastrophic review-acceptance gate read only the working-tree registry. The merge
  keystone, which enforces `bpass`, takes the max tier over the range base and HEAD since OI-70, so a deleted rule
  does not lower the tier enforced at merge. Unchanged here.
