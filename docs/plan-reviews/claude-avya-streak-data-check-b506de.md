---
branch: claude/avya-streak-data-check-b506de
date: 2026-10-06
blast_radius: catastrophic
review_rounds: 9
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/053014089025-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-08-hermes-streak-freeze-c2.md
---

# Plan-review record — streak decay persists after THIS account's restore settles; a stale cloud row stops overwriting freeze state (`claude/avya-streak-data-check-b506de`)

Founder report 2026-10-06 (Home shows streak 16 with 2 freezes, account upendra). Plan of record: `docs/plans/streak-freeze-restore-ownership.md` (v5). Two units: Unit 2 (diagnose c9d2f6) then Unit 1 (diagnose b4e7a1); one commit per unit, split with hunk-level staging because six files carry both units.

## Rounds

Ten context-blind Sonnet reviewers over four rounds; every reviewer claim the plan relied on was re-read by the coordinator before use.

- **R1** (v1): Unit 1 P0 (a failed-op set read from `_safeRestoreOp`'s catch is blind: every op swallows its own error and returns normally -> collect at the `_reportSyncFailure` funnel with a zone-scoped sink); Unit 2 P0 ("local non-null wins" defeats the optimistic lock and removes the only cross-device freeze pull on the lightweight path -> delegate to the mutation-proven `mergeFreezeProgress`).
- **R2** (v2): Unit 2 P1s (the leaf extraction rested on a false premise: import cycles already exist and two source-grep contracts read the rule; the cross-device first-PRO grant regressed against the clobber -> asymmetric grant carry); Unit 1 P1 (the marker-setting wrapper had no behavioral test -> read the uid through `_liveUserId`, end-to-end tests through `SyncHarness`).
- **R3** (v3): Unit 1 CONVERGED on mechanism, process slice CONVERGED; Unit 2 one P1 (`syncFreezes` read `_supabase.currentUser?.id`, null under `SyncHarness`, so no push could ever be observed -> `_liveUserId`, byte-identical in production) plus P2s. Not split.
- **R4** (delta on v4): two P1s, both in additions I made in v4 (the optional SYMMETRIC grant carry is undone by `_restoreFreezes` and the conflict retry; the owner guard reddened two existing fixtures). v5 resolves both with the reviewers' own prescriptions (carry DROPPED, fixtures made truthful) and adds no new design: a net reduction. No round 5: a round over a deletion plus a fixture list is mechanical (`mechanical_only`), and the platform B-pass reviews the implemented code. `review_rounds: 4` says exactly this.

## Ground truth

Live read-only SELECTs (project `dedsavbjuwgarrhphgnl`, 2026-10-06 06:50 IST) on the founder's `user_progress`, `scheduled_workouts`, `workout_logs`, `subscriptions`; read-only `client_errors` for 2026-09-17, 09-21..10-06 (the F3 refill-revert signature on the morning of the report; no critical-op failure rows 06:45-06:49). Every cited file:line re-read in the session; every plan table value re-derived by hand against the real `mergeFreezeProgress`.

## B-pass (implemented code)

Three fresh context-blind reviewers on the staged diff (Unit 1 code, Unit 2 code, documents and claims): 25 findings, 0 P0, 0 P1, 6 P2, 19 P3, all verified against the code before triage. 19 fixed in the batch with a behavioral test and a mutation each; 3 carry a recorded `blocked_on_user` terminal state (a migration apply, an Edge Function deploy, a scope call); 3 were corrections of the closure ledger itself. Triage in `docs/reviews/streak-freeze-restore-ownership-bpass.md`.

## Execution evidence

Unit 2: 41 behavioral tests in the freeze-merge file (plus 7-test weeks group in the 50-test monotonic file), 7 + 5 B-pass mutations all red. Unit 1: 59 behavioral tests, 10 + 12 B-pass mutations all red. Four mutations on the two writer-to-reader pins, all red; one on the sole-writer contract. Final tree: `flutter analyze --no-fatal-infos` (whole project) 0 errors / 0 warnings (356 infos); full suite `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` 7854 passed, 9 skipped, 0 failed; pre-commit gate loop OK (all `check_*.dart` gates). Numbers are also recorded in both diagnose docs (tier 1).

## Not done here

No commit, push, APK build, migration apply, Edge Function deploy or production write was made by the session. Founder decisions taken in chat: `current_streak_weeks` is a lifetime counter that a restore never lowers (decision A); the one-freeze shortfall in the founder's own ledger is left as it is (no production write). Open founder decisions (closure ledger `blocked_on_user`): F8 freeze-spend rule and notice wording, `LAST-WORKOUT-DATE` (widen this batch or its own unit), the `WEEKS-PUSH-RPC` migration go, the `RESIDUAL-EF-CAPS` Edge Function deploy go.

## Addendum A (slices B1, B2, U6 and the deploy record)

Plan of record: `docs/plans/streak-freeze-restore-ownership-addendum-a.md` (v4), reviewed by context-blind Sonnet reviewers over three rounds before any code (its header names them; the rest of v4 after round 3 is a subset of what round 3 checked clean). The slices that landed on this branch each took their own code-stage B-pass, all `verdict: accepted`: B1 `docs/reviews/restore-user-snapshot-paged-reads-bpass.md`, B2 `docs/reviews/restore-legacy-paging-bpass.md`, U6 `docs/reviews/streak-freeze-notice-bpass.md`. The Edge Function change (B1) was deployed to production on the founder's per-action go (live v10, 2026-10-07, record in diagnose e4c1d7). Slices C1, D and C2 are NOT part of this landing; each takes its own plan-review round and B-pass before it lands.

## Addendum A, slices C1, D and C2 (migrations 156 and 157; catastrophic by content)

The merge diff now carries two SECURITY DEFINER migrations (156 replaced the body of `update_user_progress_snapshot`; 157 adds `raise_streak_week_marker`), so the tier is catastrophic and the record names one Hermes report and one B-pass review for the whole diff.

- **Plan review:** the four rounds above cover the base plan; addendum A took three rounds before any code (45 + 43 + 30 findings); C2's own design (section 8, v7 of the addendum) took two further rounds of three context-blind Sonnet seats each (21 findings, then 0 P0 / 3 P1 / 8 P2 / 12 P3, all folded in, none changed the design). 4 + 3 + 2 = 9 rounds. Ground truth re-verified: every cited file:line re-read, the live schema and ACL read before the dry-run, `git grep` on `origin/main` for the Hermes P1.
- **Code stage:** C1: B-pass x2 + Hermes x4 (`docs/reviews/a5cf217dfc2f-review.md`, `docs/audit/2026-10-08-hermes-streak-freeze-c1.md`, accepted); D: B-pass x2 rounds (accepted, 14 mutants); C2: B-pass x2, Hermes x3 (`docs/audit/2026-10-08-hermes-streak-freeze-c2.md`, accepted), 26 mutants RED, `docs/reviews/053014089025-review.md` (accepted). The cited `bpass_review` is the staged-diff review of the final slice, whose table lists the earlier ones.
- **Live evidence:** migration 156 applied 2026-10-08 (cloud_version 20261007184012) and 157 applied 2026-10-08 (cloud_version 20261008164155), each on the founder's per-action go after an always-aborting dry-run on production; post-apply reads and an anon-key probe (42501) recorded in the ledger notes of `backups/applied_migrations.json`.
- **Rollout:** the migration is applied BEFORE the merge, so no merged client calls a missing function; this record lands in its own commit after the code commit, as the plan says.
- **Not done here:** the device check on the founder's phone and the sign-out/in comparison of the Edge Function log with the live row count (runtime verification, CLAUDE.md section 5) remain with the founder.
