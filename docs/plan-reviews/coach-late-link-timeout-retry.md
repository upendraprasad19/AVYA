---
branch: coach-late-link-timeout-retry
scope: OI-505. (a) The coach push's text lookup is anchored to the instant the row's key encodes, so a turn linked hours late links to its server row instead of uploading a second keyed row (kill switch configBox['disable_coach_turn_time_window']). (b) SendMessageNotifier bounds every coach call (chat 75 s, photo 120 s, turn 90 s incl. the one 401 re-send); CoachCallBudget stops the abandoned call's retry loops; TimeoutException is classified by type. (c) The Retry button sends client_retry true and ai-proxy replays the newest complete text-only row of that client_key (6 h cap, 503 in_progress for a young pending row; env kill switch DISABLE_CLIENT_KEY_REPLAY=1). No migration; only ai-proxy is redeployed.
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-late-link-timeout-retry-bpass.md
---

# Plan-review record: coach late link, chat time limit, Retry of a finished turn

Plan: `docs/plans/2026-11-13-coach-late-link-timeout-retry.md` (executed as rev 5). Every round used one fresh, context-blind
Sonnet reviewer with the agent brief preamble and an exhaustive read-only command list, verifying each claim against the code
and live state; the coordinator re-checked every finding in the code before folding it in (plan section 7 carries the
per-finding dispositions).

## Round 1 (rev 1)
11 findings, all taken: the retry marker idea was born here (a replay keyed on the key alone is stale for a deliberate
repeat within the 60 s client window), the window arithmetic of fix 1, and the media path.

## Round 2 (rev 2)
7 findings: replay gated on an explicit `client_retry`; the notifier (not callFunction) owns the timeout; the 401 re-send
bounded; `tool_calls` as an object (`proactive-coach-promotion`); the pending-row handling.

## Round 3 (rev 3)
10 findings: `resolveKeyedReplay` with an injected `fetchRows` so the wiring is unit-testable; Array.isArray guard; the 6 h
replay age cap; `args.count` for the legacy marker; limit 10 on step 1; 4b (media replay) dropped with a verified reason.

## Round 4 (rev 4 to rev 5, convergence)
7 findings, none P0 or P1, all taken (no new mechanism class): the exact test labels, the guard-vs-discriminating split for
the L tests, the `tokens_used` column, and the finished-decision shape of the resolver. Verdict converged.

## B-pass (code review of the CI-green head 9e9b0c85)
Two fresh Sonnet seats, `docs/reviews/coach-late-link-timeout-retry-bpass.md`: no P0 or P1. Two P2 and six P3, all fixed in
this batch and each mutated (Q1 to Q3 red): a restored sibling no longer bars its own server row from an unlinked turn
(restore-then-push), five registry cites of `supabase_service.dart`, a year-9999 key and a throwing step 1, a telemetry
rethrow, a fixed-string warn on a failed keyed lookup, a weak pin anchor, and wording drift in the records.
