---
reviewed_at: 2026-10-24T20:05:00+05:30
staged_against: 9d8fab4e9004
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: accepted
---

# Code Review — 9d8fab4e9004 (branch payment-hardening, commit 1 of the batch: U1, OI-350 / OI-359, diagnose b5e8d2)

The reviewer (a fresh Sonnet agent, no conversation context, exhaustive command list, no scripts or database) read the
staged diff at hash `3f23267e849d`: the verify-payment ownership guards moved directly after the Razorpay GET, the
"U1:" Deno tests, the Dart order pin, the diagnose-doc and the registry. It ran 8 mutations of the guards under the
mutation protocol (backup, one at a time, sha256 restored after each; final sha256 equal to the start). The three
findings were fixed in the same staged commit, which moved the hash to `9d8fab4e9004` (this file's name); the fix is
two test blocks in `verify-payment/index_test.ts` and three edits to the diagnose-doc, no code change.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** supabase/functions/verify-payment/index.ts:422 (tests: index_test.ts, the "U1:" block)
- **claim:** The 403 compare is strict `!==`, but no test fed a `notes.user_id` of another type. Mutation M5 (`!==` to `!=`) left all 44 Deno tests green; under `!=`, a notes.user_id of `[callerId]` passes the guard. Not reachable today (create-razorpay-order writes string notes), but the guard's strictness was pinned only by the Dart source regex.
- **verification:** change `if (notesUserId !== userId) {` to `!=` and run `NO_COLOR=1 $HOME/.deno/bin/deno test --no-check --allow-all --node-modules-dir=none supabase/functions/verify-payment/`.
- **suggested-fix:** a U1 test with `user_id: [USER]` (and a number) expecting 403 and no capture.
- **status:** accepted — fixed: "U1: an AUTHORIZED payment whose notes.user_id is {an array holding the caller's id, a number, an object}: 403, and no capture request is sent". Re-run of M5: 0 red before, 1 red after (the array case); restored, sha256 466c5a3a… unchanged.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** supabase/functions/verify-payment/index.ts:422-433 (tests: index_test.ts, the "U1:" block)
- **claim:** The caller's OWN created / failed payment had no test (the plan's table says "own, captured / authorized / created / failed: unchanged"). Mutation M12 (the 403 also refusing the caller's own `created` payment) left all 44 Deno tests green; the client treats any non-200 as a soft failure, so the regression would be quiet.
- **verification:** apply `notesUserId !== userId || payment.status === "created"` and run the Deno suite.
- **suggested-fix:** a positive control: own `created` (and `failed`) answers 200 with the status echo, no capture.
- **status:** accepted — fixed: "U1 control: the caller's OWN {CREATED, FAILED} payment: 200 with its status echoed, no capture", asserting the exact body `{verified: false, error: "Payment status is '<status>', not 'captured'"}` and zero capture POSTs and inserts. Re-run of M12: 0 red before, 1 red after (own CREATED); restored.

## Finding 3 — P3 — writer_reader_drift (docs)
- **file:line:** docs/diagnoses/2026-10-24-verify-payment-owner-before-capture-b5e8d2.md ("Writer and reader")
- **claim:** The diagnose-doc gave the guards as `:399-438`; they end at 433 (the registry already said 399-433). It also named live v30 as origin/main 3af16319 while the plan's rollback names `6bfbd402`, with nothing connecting the two.
- **verification:** `sed -n '433p;435p' supabase/functions/verify-payment/index.ts`
- **suggested-fix:** 399-433; one line on the rollback SHA.
- **status:** accepted — fixed: 399-433, and a rollback sentence (forward deploy of the payload built from `6bfbd402`, plan section 6). Checked before writing it: `git diff --stat 6bfbd402 3af16319 -- supabase/functions/verify-payment/` is empty and none of the `_shared` files changed between them is imported by verify-payment, so 6bfbd402 is the code live v30 runs.

## Lenses returned clean (reviewer's evidence, condensed)
- writer_reader_drift: the client (`razorpay_service.dart:911`, `:915`, `:1011`) trusts only 200 + verified:true; the webhook twin checks notes on a signed payload and reads nothing of verify-payment; every moved registry range was read and lands on the code it names (+5 consistent with the added comment lines).
- function_exception_swallow: no `.functions.invoke(`, no new catch.
- blast_radius_mismatch: verify-payment is catastrophic (`docs/blast_radius.yaml:42`); rollback documented in plan section 6; no-switch rationale in plan F-2 and the diagnose-doc.
- secrets_in_tree: no credential-shaped literal in the staged diff.
- unawaited_no_error_sink: no new un-awaited promise.
- missing_input: `OTHER_USER` (harness :25), `Scenario.intercept` (:155, wired :247, run before the Razorpay router, every request recorded) exist with the shape used.
- asserted_fixture_value: the U1 control (one capture POST with `{amount: 34900, currency: "INR"}`, one insert) makes the zero-capture assertions meaningful; bodies and statuses match the code.

## Mutations run (reviewer)
| # | mutation | tests red | verdict |
|---|---|---|---|
| M1 | both guards back below the echo | Deno 4, Dart 1 | caught |
| M1b | guards between capture and echo | Deno 3, Dart 1 | caught |
| M2 | duplicate check after capture, early one deleted | Deno 4, Dart 1 | caught |
| M3 | only the 403 below the echo | Deno 2, Dart 1 | caught |
| M4 | only the 400 below the echo | Deno 2, Dart 2 | caught |
| M5 | `!==` to `!=` | Deno 0, Dart 2 (regex) | Finding 1, now Deno 1 |
| M6 | early 403 returns 200 | Deno 2 | caught |
| M12 | 403 also refuses own `created` | Deno 0, Dart 2 (regex) | Finding 2, now Deno 1 |

## Founder triage notes
Self-triaged by the author under the founder's commit go for this batch (2026-10-24): all three findings accepted and
fixed in this commit; no false alarm.

## Tuning entry
- **2026-10-24** - blast-radius catastrophic - 3 findings; 0 false_alarm; tuning: none (lens 6's "mutate the way a real regression re-enters" produced both P2s: a loosened compare and a widened refusal, neither a deletion).
