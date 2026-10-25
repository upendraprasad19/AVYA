---
branch: drop-beat-my-coach
date: 2026-10-25
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/drop-beat-my-coach-bpass.md
---

# Plan-review record - drop Beat My Coach (OI-395, T3 of the exercise-library programme, platform)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED:** `git diff origin/main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -` printed
`Blast-radius: platform` for the 29 files of the branch. Each of `docs/blast_radius.yaml`, `_shared/snapshot_merge.ts`,
`_shared/notification_prefs.ts` and `daily-snapshot/index.ts` alone forces `platform`; without them it would be `account`. The
pre-commit NOTE on the batch's commits agreed independently.

**Feature flag:** not applicable, and the platform tier's `feature_flag` requirement is waived on purpose (same wording as the
waivers in `docs/plan-reviews/blast-radius-clean-orphan-media.md` and `blast-radius-data-deleting-paths.md`): this is a pure
deletion plus comment-only edits, with no payment, sync, auth, AI-prompt or plan-generator change; the old path stays in git and
the rollback in the plan restores it (`node .claude/deploy_via_api.js --rollback beat-my-coach 425bc63f --yes`). No gate enforces
`feature_flag` mechanically (`scripts/safe_push.sh:132`).

## What this branch is

Plan: `docs/plans/2026-10-25-drop-beat-my-coach.md` (r4), executed inline on this branch. The founder locked the decision (drop
Beat My Coach entirely, including the live Edge Function) in the exercise-library programme order; the live delete needs its own
explicit per-action go and is NOT part of any commit here.

The branch removes the dead feature: the Edge Function source `supabase/functions/beat-my-coach/` (never called by the app), the
never-mounted widget `challenge_card.dart`, two `AppConstants`, the badge `challengeWon` ("Coach Slayer", which could never unlock:
its only caller passed the literal `hasBeatCoach: false`) and every registry, test and doc entry that named them; repoints the one
test that pinned the deleted function as the cloud reader of `exercise_library` to `getFormCues.ts` and its registry entry; edits
three comment-only mentions in shared Edge Function files; and adds a contract test (`beat_my_coach_removed_test.dart`), a
closure ledger (`docs/audit/drop-beat-my-coach.closure.yaml`) and an Edge-Function-delete recipe with a new bug class to the deploy
skill. The live Edge Function is deleted in a separate founder-gated step; the PR is a draft until then, and OI-395 closes in a
docs-only Group B commit after the delete.

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Two context-blind Sonnet reviewers on the plan, every claim verified against code and live state | `not_converged`: 1 P0 (the SoT line range would overflow and fail two gates) and rollback / sequencing P1s. |
| 2 | Two fresh reviewers on the POST-round-1 plan (r2) | `not_converged`: 2 P1 (the live-bundle capture method was wrong; the OI close and ledger were scheduled before the delete). R3 and R4 were reversed (the three comment mentions and the blast-radius rule are edited, so the batch is `platform`). |
| 3 | Two fresh reviewers on r3, one applying units 1-9 to a scratch copy (107 non-network gates, Deno checks, about 15 flutter test files, 20+ mutations) | `converged`: 0 P0, 0 P1, every P2 / P3 applied in r4. |
| B-pass | Four fresh read-only adversarial reviewers on the implemented diff (`docs/reviews/drop-beat-my-coach-bpass.md`) | 19 findings (1 P1, 4 P2, 13 P3, 1 informational), 0 false alarms, each verified by the author; verdict `accepted`. The material one: the branch was 7 commits behind `origin/main`, which had made `docs/audit/OPEN_INDEX.md` a gitignored local build product while this branch edited it; the unpushed commit was rebased. |

Round 1 and round 2 returned material findings (section 4.12.1 reads that as a sign the unit may be too large); round 3
returned none, and the unit is a pure deletion with one live action held behind its own go, so it converged at three rounds
without a split.

## Rulings made during execution

Settled in the plan before execution: R1 to R7 (the badge goes with the feature; no cleanup migration; the comment mentions and
the dead blast-radius rule are edited; historical records are not rewritten; the live delete happens before the merge with a
Group A / Group B commit split; delete outright with no 410 stub). Added while executing:

- **B-pass finding 1:** rebase instead of merge. The Group A commit was local and unpushed, so it was rebased onto `origin/main`
  (twice, as main advanced) with no merge commit, because a conflicted merge runs gates written for authoring commits
  (`feedback_gates_unsatisfiable_at_merge.md`).
- **B-pass findings 2, 3, 6, 8, 9:** the new contract test and the repointed test were hardened and mutation-checked (M10-M21, all
  red) rather than left at the first draft.
- **Gate loop:** two `test/scripts` tests fail on this Windows machine and on a clean `origin/main` checkout alike while CI is
  green; they are filed as OI-415 with what is measured and what is not established, not called pre-existing.

## Verification state at the time of this record

- Mutation proof: 18 mutations of the new test (M1-M9d) plus 12 of its B-pass hardening (M10-M21), each confirmed applied and
  restored clean.
- Closure ledger `docs/audit/drop-beat-my-coach.closure.yaml`: 24 of 24 entries terminal (Gate 40): 17 `closed_in_commit`,
  4 `verified_clean`, 3 `blocked_on_user` (the live delete, the OI close with the `nutritionWeek` OI, the founder phone check of
  the badge total).
- Local gate loop on the final tree: `flutter analyze --no-fatal-infos` (whole project) exit 0 with 0 errors and 0 warnings; full
  `flutter test` 11,157 passed, 35 skipped, 2 failed (OI-415, outside this diff); Deno 1,477 passed. CI on the PR is the
  full-suite gate for `main`; its result goes in the PR description, not here.
- As of this record (commit 4) the live Edge Function delete, the Group B docs commit, marking the PR ready and the founder phone
  check were still open. Since then: the founder gave the per-action go and the live function was deleted on 2026-10-25 at
  12:00:00Z (`list_edge_functions`: 44 functions, none of them this one); the Group B docs-only commit closed OI-395, flipped
  the ledger rows and filed OI-427. Still the founder's: the phone check of the badge total (14, no Coach Slayer tile).
