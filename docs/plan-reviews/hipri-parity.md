---
branch: hipri-parity
date: 2026-09-10
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/4f6eb6532418-review.md
---

# Plan-review record — server-side HIGH_PRIORITY_OP_TYPES parity (account)

⚠ **WRITTEN AFTER THE MERGE, AND THAT IS THE FIRST THING THIS RECORD SHOULD SAY.**
`dcb94a93` merged `hipri-parity` without this file. `git_safety_hook.dart`'s
advisory precheck caught it — **at push time, which is after the merge**, exactly
the gap CLAUDE.md §7 documents for that hook ("fires only AFTER the merge — by
then the repair is a full `git reset --hard` unwind"). I did not unwind, because a
push was already in flight and `feedback_git_landing_verification` is explicit:
never kill a commit or push, fix forward. So the CI run for `dcb94a93` is expected
to fail this gate. That is a real red on `main`, caused by me, recorded here rather
than papered over.

**Why `safe_merge.sh`'s precheck did not catch it either:** that one warns when a
record claims `bpass: accepted` while its `bpass_review:` file lacks
`verdict: accepted`. It does not warn when the record is **absent entirely**. Two
prechecks, neither covering the plain missing-record case at merge time.

## What the change is

Nine lines: `"realtime_subscribe_skipped_free_tier"` added to
`HIGH_PRIORITY_OP_TYPES` in `supabase/functions/log-client-error/index.ts`, plus a
comment. `supabase/functions/**` is account-tier by path, which is what triggers
this record.

It completes the previous commit, which added the same event to the CLIENT list
(`ErrorTelemetry.highPriorityOpTypes`) and stopped there. The two lists are pinned
equal by `test/contracts/high_priority_op_types_parity_test.dart`.

## Rounds — what review this actually got, stated precisely

| round | what |
|---|---|
| 1 | The ×3-round + B-pass review of `realtime-pro-gate` (`docs/plan-reviews/realtime-pro-gate.md`). Its **B-pass finding 5 explicitly named this**: *"check whether a server-side twin list needs the same addition."* |
| 2 | The full suite at pre-push — which FAILED, `present in client only: {realtime_subscribe_skipped_free_tier}` — followed by re-verification of the fix. |

**This is not two independent context-blind rounds and must not be read as one.**
Round 1 is a review of the parent change that named this gap in advance; round 2 is
a mechanical gate that caught my failure to act on it. The record is honest about
that rather than inflating a nine-line data fix into a review it never had.

## Ground truth verified

- `flutter test test/contracts/high_priority_op_types_parity_test.dart` → 2/2.
  **No mutation proof is offered or needed: the test discriminated against a REAL
  one-sided edit**, which is stronger evidence than a synthetic mutation.
- Entry count measured: **28** against the 30-entry sanity cap asserted at
  `supabase/functions/log-client-error/index_test.ts:120`. Under, but two away, and
  that file's own comment says to audit and consolidate at ~30.
- ⚠ **Neither half is live.** The client entry ships in the next APK; the server
  entry needs a `log-client-error` deploy, which has NOT been authorized and is not
  part of this batch.

## The lesson, which is the point of writing this at all

**A review finding names a SITE, not the CLASS.** Finding 5 told me to check the
server twin. I fixed the client, shipped, and let a contract test find the other
half — `feedback_mistake_guard_without_its_mirror` #26, verbatim, one commit after
reading the sentence that predicted it.

And the reason it reached `main` at all: every check I ran before the merge was
green — targeted tests, the pre-commit gate loop, whole-tree analyze — and **none
of them includes this contract**. Only the full suite does, and the full suite runs
at pre-push, i.e. after the merge. `feedback_green_check_input_set_width`.
