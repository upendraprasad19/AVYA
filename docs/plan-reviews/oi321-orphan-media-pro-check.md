---
branch: oi321-orphan-media-pro-check
date: 2026-10-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/982faf1d75a8-review.md
---

# Plan-review record — OI-321, `clean-orphan-media` must not delete on an unreadable PRO check (`oi321-orphan-media-pro-check`)

Plan: `docs/plans/oi321-orphan-media-pro-check.md` (v3, the consolidation of v1 plus both rounds' amendments). Diagnose: `docs/diagnoses/2026-10-11-clean-orphan-media-unreadable-pro-check-f0b6d8.md` (FULL template: a recurrence of `f2b9d4` and bug class 2.49). Closure ledger: `docs/audit/oi321-orphan-media-recheck.closure.yaml`.

`bpass: accepted` (2026-10-11, `docs/reviews/982faf1d75a8-review.md`): one fresh context-blind reader on the staged diff (7c0f3481d18d), 8 findings (0 P0, 0 P1, 1 P2, 7 P3, 0 false alarms), each verified against the code by the main thread; all fixed except Finding 6 (a founder decision on the blast-radius tier) and the optional part (b) of Finding 4, which is a recorded decision. The flip is in the commit that adds this record, after the review file landed in `5c001dd6`.

## Rounds

- **Round 1** (v1; a fresh context-blind Sonnet reader, read-only): 0 P0, 0 P1, 7 P2, 6 P3. The main finding was a bug-history miss: the first grep searched the TOKEN (`maybeSingle`) and the INDEX one-liner for `f2b9d4` names `checkPro`, so it did not match; the unit is a direct recurrence, so the diagnose-doc takes the FULL template with `related_bugs` and `recurrence`. The rest were pins, gates and process. Round-1 verdict: `harden`.
- **Round 2** (v2, the post-round-1 plan, so review #2 ran on the amended plan; another fresh reader): 0 P0, 0 P1, 6 P2. No mechanism problems. The one structural fold was REMOVING a naive `failed`-status escalation that would have paged the founder on a single blip. Round-2 verdict: `harden`, all six folded into v3.

`review_rounds: 2` (§4.12.1). `verdict: converged` is self-attested and rests on: no P0 or P1 in either round, round 2 surfacing only pins, gates and process plus the removal of one mechanism (not a new one), and no third plan round being run; the later code-level B-pass was a separate read of the staged code, not a plan round. The B-pass later reversed the round-2 fold in a narrower form: Finding 1 showed that a SYSTEMATIC unreadable state ended `success` with zero deletions every day, and the precedent the plan had cited for the quiet path (`re-engagement`) was wrong; the real one (`weekly-recalc/index.ts:415-420`) escalates on a ratio. The shipped rule is a ratio, not the naive escalation round 2 removed: at least 5 undecided candidates AND a majority of the scanned ends the run `failed`/500.

## Ground truth verified (reviewers read-only; the main thread re-verified each claim before folding it in)

The live `find_orphan_chat_media` body (`pg_get_functiondef`, migration 071, last body), the live `subscriptions` status values and the NULL `end_date` count, the deployed function version (v14) and its backup payload, every one of the 27 `from("subscriptions")` reads under `supabase/functions` (opened at its line), the storage-js error shape (`StorageApiError { message, status }`, no `code`, read from the Deno cache), `alert_cron_failures` (migration 147) paging on any `failed` row, and the deploy bundler's relative-import handling for the new `./logic.ts`.

## Reviewer process notes

All rounds were dispatched read-only with an exhaustive command list. The B-pass reader reported it could not run the `dart run` gates or read the live database (outside its list); the main thread ran the gates and the whole-tree `deno check` itself. A runner incident in the main thread's own mutation harness (basename-keyed backups, two files named `index.ts`) was caught by the end-of-run byte-compare and is recorded in the diagnose-doc.

## Founder decisions

1. Blast-radius tier for `supabase/functions/clean-orphan-media/**` (ledger row B6, `blocked_on_user`): the registry has no glob for it, so it is classified as the platform default although `CRON_REGISTRY.md` calls it the highest-consequence endpoint behind the shared secret. Nothing in the code depends on the answer.
2. The live Edge Function deploy (ledger row D1) needs its own explicit go; protocol in the plan, section 4. Until then OI-321 stays open and the fix is not live.
