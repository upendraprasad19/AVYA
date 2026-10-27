---
branch: blast-radius-data-deleting-paths
plan: docs/plans/blast-radius-data-deleting-paths.md
date: 2026-10-12
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/aca5136156fd-review.md
---

# Plan review - `rolling-context/**` and `_shared/purge_user_storage*.ts` become catastrophic tier

Founder decision (2026-10-11, in chat, answering the question the previous registry batch raised): the two other data-deleting paths, `_shared/purge_user_storage.ts` and `rolling-context/index.ts:522`, become catastrophic tier; recorded in paraphrase at `docs/plans/oi320-referrer-cap.md:77`. Started on "Registry rules... With discipline" (2026-10-12). Plan: `docs/plans/blast-radius-data-deleting-paths.md`. Two rules in `docs/blast_radius.yaml`, a contract test with a derived deleter scan, a commit-time-gate path-glob group, four keystone cases, three documentation edits. This batch's own tier is `platform` (the registry is a platform file), so it needs `bpass: accepted` and not `hermes`. Execution mode: inline, one coordinator, no subagent writes; every reviewer a read-only Sonnet reader with an exhaustive command list.

## Review rounds

- **R1** - one fresh context-blind Sonnet reader, read-only (85 tool calls), on the v1 plan and the staged draft. Verdict: sound with fixes, no P0/P1. 4 P2 and 5 P3: the claim that `_shared/user_owned_buckets.ts` "stays platform" was false for the one legitimate edit (the Deno test that pins its five names is catastrophic through the purge glob); "embeds ... then deletes" overclaimed (the embedding is best-effort); the commit-time half of the tier is blind to renames and non-ASCII names (reproduced by the main thread with a temporary index file; pre-existing, applies to all six earlier rules); the file-kind pin sampled seven names. Also a cite to the founder's words that the tree does not contain, an a4 mischaracterisation, and a false "narrowing would not avoid it". All verified and folded; the structural pin (every rule above the new ones is catastrophic), the mixed-diff keystone case and the extra mutants came from this round.
- **R2** - a different fresh Sonnet reader, read-only (84 tool calls), on the post-R1 plan and diff. Verdict: sound with fixes, no P0/P1, "the unit is not too large". 3 P2, 7 P3 and one optional hardening: nothing tested the commit-time gate's own path-glob loop (only a SECURITY DEFINER migration had been staged in its end-to-end test); the mixed-diff case killed "last path wins" but not "first path wins"; a header claim that both rules are insensitive to the keystone's `dotAll` difference (false for the rolling glob); stale numbers (registry lines, function-directory counts 6/4/5/8, `:433`, `:421-428`, six behavioural Deno tests plus one equality test); wildcard-widening mutants that survived; an understated cost statement; the plan widening the founder's two named files without listing it; file:line cites that rot; and an optional derived check. All verified and folded; the commit-time-gate group, the derived deleter scan, the wildcard probes and the scoping decision came from this round.
- **B-pass** (`docs/reviews/aca5136156fd-review.md`) - one fresh Sonnet reader on the real staged diff (hash `9476cfe014d2`, 100 tool calls, all four test files run): 0 P0/P1/P2, 6 P3, all verified by the main thread and fixed in the same batch. Finding 1 hardened the derived scan (literal self-check, `.test.ts`, raw HTTP DELETE); finding 5 showed that a reason the plan gave for not editing `CRON_REGISTRY.md` was wrong, and the edit was made.
- **Converged-after-fold is a SELF-ATTESTATION, not a third plan review.** The B-pass reviews the real final diff. The two plan rounds produced design changes in round 1 and test additions in round 2; the B-pass produced no design change.

## Ground truth

- Code read at the base `f2ad2b9f` and the staged tree by both reviewers, the B-pass reader and the main thread: the registry (first match wins; base catastrophic block :41-62, now :41-79; `_shared/**` :72 -> :89; catch-all :519 -> :536), all four `globToRegExp` copies, the commit-time gate (`check_code_review_pass_exists.dart:103-104, 200-217, 244-264`), the merge-time keystone (`check_plan_review_record_exists.dart:231-267, 798-806`), `rolling-context/index.ts` (:33-34, :393-398, :411-413, :421-440, :466-511, :517-523), `purge_user_storage.ts` (:119), `delete-account/index.ts` (:29-30, :325, :357, :373).
- Before the rules, every path in scope classified `platform` (measured with the classifier, once per path); after them `catastrophic`, with `_shared/user_owned_buckets.ts` and the shared helpers still `platform`.
- No live system was read or written: no database, no Edge Function, no network call. Nothing is deployed, applied or migrated.
- Run, not just read (final staged tree): the new contract test 20/20, the sibling `blast_radius_clean_orphan_media_catastrophic_test.dart` 12/12, `review_gate_staged_content_not_working_tree_test.dart` 10/10, `plan_review_record_gate_e2e_test.dart` 20/20, the cron-registry readers; `sh scripts/pre-commit.sh` exit 0; `flutter analyze lib/` 0 warnings and 0 errors; the complete suite `9047 passed, 9 skipped, 0 failed (`flutter test --exclude-tags golden`, TZ=Asia/Kolkata, final staged tree)`.

## Mutation (CLAUDE.md section 4.4 rule 21), results

Each mutant was computed and anchor-checked (exactly one occurrence) before any write, the original restored in `finally`, and the restore byte-compared (sha256) for all eight touched files; the one mutant that creates a file (a new Edge Function) was removed and checked. A mutant counts as red only when `flutter test` exits non-zero, and the reddened tests were read, not just counted. Runner `mut_dp/run.py` in the session scratchpad; the numbers below are from the FINAL run on the final tree (counts of reddened tests in parentheses).

- **48 of 48 mutants red, 0 survivors.**
- Rolling rule (R1-R7): delete it (8); move it below the catch-all (8); widen to `rolling-context*/**` (5); tier platform (7); tier account (7); single-segment `rolling-context/*` (6); a glob naming `rolling-contexts/**` (9).
- Purge rule (P1-P7): delete it (7); move it below `_shared/**`, the dead-text case (7); below the catch-all (7); tier platform (5); widen to `_shared/purge_*.ts` (5); narrow to the exact module, dropping the Deno test and any split-off (6); a glob naming `purge_users_storage*.ts` (7).
- Neighbours and over-promotion (X1-X6): promote `_shared/user_owned_buckets.ts` (3); promote `_shared/**` to catastrophic (6); drop the `cron_auth.ts` (1), `clean-orphan-media/**` (2), `admin-*/**` (1) or `delete-account/**` (2) rule.
- Lower-tier rules inserted above the new ones (N1-N7): for four file kinds above the rolling rule (`*.md`, `fixtures/**`, dotfiles, `*.json`) the any-kind test and the structural pin redden (2 each); for kinds NOBODY sampled (`*.yaml` above the rolling rule, a `*.sh` between the two rules, a `*.yaml` rule at the very top of the block) only the structural pin reddens (1 each), which is the test written for that class.
- Wildcard widenings (W1-W4): a prefix wildcard on the rolling glob, a prefix wildcard on the purge glob, the purge glob without `.ts`, `purge_user_storage**.ts` (5 each); each is caught by its own probe (a prefixed look-alike directory, prefixed and extension-dropped and `.bak` names, and the pinned subdirectory LIMIT).
- Engines: the classifier takes the last path's tier instead of the max (1); the commit-time review gate's rules reader cannot parse `catastrophic` (1).
- Commit-time gate against the new end-to-end group (C3-C5): the first-match `break` removed so a later broad rule overwrites the catastrophic one (4); the max loop takes the last path's tier (1) or the first path's (4).
- Premise rot (Q1-Q3), mutating the production sources themselves and restoring them: rolling-context no longer deletes (2); the purge no longer removes (2); delete-account no longer calls the purge (1).
- Merge-time keystone against the four new end-to-end cases (K1-K4): its rules reader cannot parse `catastrophic` (4); its hermes check disabled (4); `_maxTierAcross` takes the last path's tier (1) or the first path's (1). In K1 and K2 the four reddened tests are exactly the four "platform-grade record WITHOUT hermes FAILS" cases (clean-orphan-media, rolling-context, the purge module, the mixed diff); the "WITH an accepted hermes report PASSES" control stays green. K3 and K4 redden only the mixed-diff case, which carries a feature file sorting before and one sorting after the catastrophic path.
- Derived deleter scan (D1-D5): a brand-new Edge Function that deletes and is not in the registry (1); the matcher's `DELETE FROM` arm dropped (1), the raw-HTTP-DELETE arm dropped (1), the `.remove(` arm dropped (2), the `.test.ts` test-file convention dropped (1).

## Section 4.6 disposition (feature-flag protocol)

Not applicable: no payment, sync, auth, AI-prompt or plan-generator change. The platform tier's `feature_flag` requirement is waived on purpose (registry data; the off state is deleting the rule lines; no script enforces it - `scripts/safe_push.sh:132-135`, `scripts/reconcile_ci.dart:41`); same waiver as OI-282 and `blast-radius-clean-orphan-media`.

## Scoping decisions the merge ratifies

- The rules are wider than the two paths the founder named: the whole `rolling-context/` directory and a wildcard for the purge family (its Deno test, and a file split off it by name). `rolling-context/index_test.ts` is a source-grep wiring test for the Gemini-exhaustion alert, not a pin of the delete; it is in the tier because of the directory shape. Narrowing either rule is one edited line.
- `_shared/user_owned_buckets.ts`, the shared helpers `rolling-context` imports (including `_shared/paged_fetch.ts`, whose ordering decides which rows are deleted) and the cron definition stay `platform`; the pins on the delete paths stay `feature`, like those of every other catastrophic function.
- The cost lands on cross-cutting batches: the next Gemini-wide or prompt-wide batch that includes `rolling-context` becomes catastrophic as a whole (a hermes pass, a staged review file per commit, and a hermes pass before an APK build). Stated in the plan and in the registry comment.

## Terminal state of every item raised in review

| Item | Terminal state | Detail |
|---|---|---|
| Commit-time gates mis-read renames and non-ASCII names (`stagedPaths()` uses a plain `git diff --cached --name-only`) | `closed_in_commit` | Reproduced; filed as **OI-337** in the commit that lands this record, on the founder's go of 2026-10-12 (`oi/337` reserved on origin by `mint_oi.sh`). Pre-existing, applies to all six earlier catastrophic rules; the merge-time keystone is immune. |
| SQL in `supabase/migrations/**` that deletes rows is platform | `blocked_on_user` | Whether any migration path should be promoted is the founder's call. |
| Bucket-list test blind spots in `delete_account_purges_all_user_buckets_test.dart` | `closed_in_commit` | A file this batch does not touch; the Deno equality test (a required merge check) catches the first two. Filed as **OI-338** in the same commit (`oi/338` reserved), same go. |
| `CRON_REGISTRY.md:38` said nothing about the delete | `closed_in_commit` | Edited in this batch. |
| `WITH hermes` control for the purge path | `verified_clean` | Redundant; same gate line as the existing controls. |
| Every other finding of R1, R2 and the B-pass | `closed_in_commit` | Each fixed in this batch; the B-pass file lists its six with the fix. |

## Authorization

The tier itself is the founder's decision (above). The founder gave the commit go for the two commits of this branch (the staged change, `8638fe25`, and this record) and the go to file OI-337 and OI-338 on 2026-10-12. Push, PR and merge are separate gos that have not been given; the merge is only via `sh scripts/safe_pr_merge.sh <pr>`.
