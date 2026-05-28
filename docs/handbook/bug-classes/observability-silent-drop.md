---
title: Rate-limited telemetry sink silent-drop
category: bug-classes
source_memory: feedback_observability_silent_drop.md
last_reviewed: 2026-05-28
---

# Rate-limited telemetry sink silent-drop

## The class

A rate-limited or budget-gated server-side sink returns "200 OK" past its threshold (with a hidden `rate_limited: true` flag the client never inspects), so:

- The client treats the 200 as success and keeps POSTing.
- Server discards the events.
- Hundreds of production failures go invisible.
- Every other bug becomes harder to find because the meta-bug hides them.

## How to detect

- Telemetry table flatlines or shows a sudden drop in row count for a user who is actively encountering errors.
- Server logs show `rate_limited: true` responses but client code shows no cooldown.
- A noisy bug class (e.g. SQL state code storm) triggers a 100-event budget very early in the day; the rest of the day's signal lands in the silent path.

## Prevention

Any rate-limited or budget-gated server-side sink MUST:

1. **Return a distinguishable response.** Not "200 with a hidden flag." Either a different status code (429 with `Retry-After`), or a 200 body that includes both the rate-limit flag AND the next-window timestamp so the client can compute precise cooldown TTL.

2. **Have a priority lane.** Not every event is equal weight. Crashes, auth failures, SQL state codes (42P10/23502/23505/23503), and bug-class triggers MUST bypass the budget. Heartbeats / defence-in-depth-guard noise / happy-path success events MUST share the budget. Default to LOW; only promote to HIGH for P0 signal classes.

3. **The client MUST honor the signal.** Set an in-memory cooldown, suppress subsequent LOW-priority POSTs until the window resets, continue POSTing HIGH-priority events. Without client-side suppression, you waste bandwidth on rows you'll discard server-side.

4. **Twin tests pin the priority allowlist.** If client + server have independent lists, drift is inevitable. Pair the Dart test (`test/safety/error_telemetry_rate_limit_test.dart`) with the Deno test (`supabase/functions/log-client-error/index_test.ts`) — both assert the same HIGH/LOW classification for the same op_types.

5. **Cap the HIGH allowlist size.** Sanity-bound (~30 entries). Every HIGH entry bypasses the budget — over-classifying defeats the rate limit. Enforced as a Deno test that fails if `HIGH_PRIORITY_OP_TYPES` crosses 30 entries.

## How to verify before merging a "quietly succeed" branch

- Search the codebase for `return ok({ ok: true,` patterns inside a rate-limit or budget branch. If the return body has a flag the client doesn't read, you've reproduced this class.
- Grep client callers of the function; confirm at least one caller inspects the response body, not just the status code.
- Check whether the function has a priority lane. If 100% of events share one budget, the next noisy bug class will swallow signal.

## Instances

- `log-client-error` enforced a per-user 24h rate limit of 100 events; past the threshold returned `200 {ok: true, rate_limited: true}`. Client treated 200 as success. Founder hit 100 events by 04:10 UTC from a 42P10 storm; the rest of the day's +25 production failures landed exclusively in the dropped path — ZERO new `client_errors` rows.

- Prior cousin: APK Test #12.2 / Task #3 widened the validator from rejecting unknown error_codes to truncating them — same family of bug (client telemetry dropped silently for the entire app's lifetime before that fix). Both classes share the pattern "server silently discards client telemetry; client unaware."

## References

- Diagnose-doc: `docs/diagnoses/2026-05-16-observability-silent-drop-9d12af.md`.
- Related: [`live-verification.md`](../audit/live-verification.md), [`lens-methodology.md`](../audit/lens-methodology.md) lens 19 (telemetry coverage on async failure legs).
