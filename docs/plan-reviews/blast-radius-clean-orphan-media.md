---
branch: blast-radius-clean-orphan-media
plan: docs/plans/blast-radius-clean-orphan-media.md
date: 2026-10-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/39cf276d4dea-review.md
---

# Plan review - `supabase/functions/clean-orphan-media/**` becomes catastrophic tier

Founder decision (2026-10-11), answering ledger row B6 of OI-321: "blast radius tier for recommended catastrophic. Yeah, okay. Recommended catastrophic." Plan: `docs/plans/blast-radius-clean-orphan-media.md`. One registry rule in `docs/blast_radius.yaml`, a 12-test contract test, two keystone end-to-end cases, ledger row B6 closed. This batch's own tier is `platform` (the registry is a platform file), so it needs `bpass: accepted` and not `hermes`. Execution mode: inline, one coordinator, no subagent writes.

## Review rounds

- **R1** - one fresh context-blind Sonnet reader, read-only (71 tool calls), on the v1 plan and the staged draft. Verdict: the change works, no P0/P1. 9 findings: 1 P2 (F1: "27 readers share `_shared/subscription.ts`" is a count of `from("subscriptions")` call sites, not importers, and the design decision drawn from it was wrong) and 8 P3 (wrong line cites, an overclaim in the registry comment, "the other catastrophic rules are untouched" asserting 2 of 5, the CLI test not pinning max semantics, a mutant that was not a widening, the test covering one of four glob engines, the record trail, and the inputs to the delete decision that stay platform). All folded.
- **R2** - a different fresh Sonnet reader, read-only (84 tool calls), on the post-R1 plan and diff. Verdict: no P0/P1, the mechanism sound. 11 findings: 4 P2 (a wrong "private copies" claim when three of the four registry readers are importable; the merge-time keystone, the gate that enforces what the tier is for, had no assertion; the plan named the wrong second document; a stale "27 unrelated readers" in the test header) and 7 P3. All folded; the keystone now has two end-to-end cases.
- **B-pass** (`docs/reviews/39cf276d4dea-review.md`) - one fresh Sonnet reader on the real staged diff: 0 P0/P1/P2, 8 P3, all verified by the main thread and fixed in the same batch. One of the fixes added a test (a file of any kind under the directory classifies catastrophic).
- **Converged-after-fold is a SELF-ATTESTATION, not a third plan review.** The B-pass reviews the real final diff.

## Ground truth

- Code read at the base `df2b1282` and the staged tree by both reviewers and the main thread: the registry (first match wins, header line 14; base catastrophic block lines 41-51; the `supabase/functions/**` catch-all the last function rule), the classifier `scripts/blast_radius_from_diff.dart`, the commit-time gate `scripts/check_code_review_pass_exists.dart:153-164, 244-264`, the merge-time keystone `scripts/check_plan_review_record_exists.dart:836-866`, `docs/operations/CRON_REGISTRY.md:37`.
- Before the rule, every file under the directory classified `platform` (measured with the classifier, once per file). After it: `catastrophic`.
- No live system was read or written: no database, no Edge Function, no network call. Nothing is deployed, applied or migrated.
- Run, not just read (final tree): `blast_radius_clean_orphan_media_catastrophic_test.dart` 12/12, `plan_review_record_gate_e2e_test.dart` 16/16, `safe_merge_test.dart` 15/15, `clean_orphan_media_pro_recheck_test.dart`; `sh scripts/pre-commit.sh` exit 0 on the final staged tree. `flutter analyze lib/` (0 warnings, 0 errors, 59 infos, none in the touched file) was run before the B-pass; `lib/` has not changed since.

## Mutation (CLAUDE.md section 4.4 rule 21), results

Each mutant was computed and anchor-checked before any write, the original restored in `finally`, and the restore byte-compared (sha256).

- **M1-M11 against the contract test: 11 of 11 red.** Delete the rule (6 reddened); move it below the catch-all (6); widen to `clean-orphan-media*/**` (4); tier platform (4); single-segment glob (4); glob names a wrong directory (7); promote `_shared/subscription.ts` (3); tier account (4); drop the `admin-*` neighbour (1); the classifier takes the last path's tier, not the max (1); the commit-time gate's reader cannot parse `catastrophic` (1).
- **K1-K2 against the two new keystone cases (re-run for this record on the final tree): 2 of 2 red.** K1 (the keystone's own rules reader cannot parse `catastrophic`) and K2 (its hermes check disabled) each redden exactly one test, "catastrophic path (clean-orphan-media/): a platform-grade record WITHOUT hermes FAILS"; the control "WITH an accepted hermes report PASSES" stays green in both, as it should.
- **N1-N4 against the file-kind test added after the B-pass: 4 of 4 red.** A feature-tier rule for `*.md`, `fixtures/**`, `.*` or `*.json` inserted above the catastrophic one reddens exactly the new test and leaves the other eleven green, so that test is the only protection against the class.

## Section 4.6 disposition (feature-flag protocol)

Not applicable: no payment, sync, auth, AI-prompt or plan-generator change. The platform tier's `feature_flag` requirement is waived on purpose and recorded in the plan (registry data; the off state is deleting the one rule line; no script enforces the requirement - `scripts/safe_push.sh:132-135`, `scripts/reconcile_ci.dart:41`; same waiver as OI-282).

## Scoping decisions the merge ratifies

- The pins on the delete path (`test/contracts/clean_orphan_media_pro_recheck_test.dart`, the `clean_orphan_media_pro_recheck` SoT entry, the backup payloads) stay `feature`, exactly like the pins of every other catastrophic function. Promoting them would be an exact-path rule and a separate founder call.
- `_shared/subscription.ts`, `_shared/paged_fetch.ts`, `_shared/cron_telemetry.ts`, the candidate RPC `find_orphan_chat_media` (migration 071) and the cron definition stay `platform` on purpose; a migration edit is lifted to catastrophic anyway when its text mentions SECURITY DEFINER.
- Raised to the founder, not decided here: `_shared/purge_user_storage.ts` (the account-deletion Storage purge) and `rolling-context/index.ts:522` (deletes summarised `ai_coach_interactions`) are also data-deleting and still `platform`.

## Authorization

The tier itself is the founder's decision (above). The commit go was given on 2026-10-11 ("commit go for blast radius ... yes commit"), for the two commits of this branch: the staged change (b668194b) and this record. Push, PR and merge are separate gos that have not been given; the merge is only via `sh scripts/safe_pr_merge.sh <pr>`.
