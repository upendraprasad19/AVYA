---
reviewed_at: 2026-10-25T01:40:00+05:30
staged_against: f73e86b09ad0
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
---

# Code Review — f73e86b09ad0 (branch payment-hardening, commit 4 of the batch: U3, OI-366, diagnose f2c9a8)

Two context-blind Sonnet reviewers (exhaustive command lists, no scripts, no database, mutation protocol with
sha256-restored backups; every final sha256 equal to the start, no unstaged file left):
- **Round A** read the staged commit at `beee28f0d9f2` and ran 10 mutants: 7 findings (2 P2, 5 P3).
- **Round B (delta)** read only the round-A fixes (staged at `657e30b88cac`) and ran 11 mutants, also under
  TZ=UTC: 2 findings (2 P3), no P0-P2.

All 9 accepted: 8 fixed in this commit, 1 (A4) answered by the branch's docs commit. The fixes moved the hash to
`f73e86b09ad0` (this file's name). The author re-ran every surviving mutant after its fix (scratchpad
ph/mutate_u3_bpass.py, 11 mutants, and two on the new source pin): each is now red. Neither reviewer found a way
past either limit, a fail-open guard, or a change to the tolerant payment writers.

## Round A

## Finding A1 — P2 — guard_without_its_mirror
- **file:line:** supabase/functions/validate-promo/index.ts:121-131; create-razorpay-order/index.ts:270
- **claim:** The handlers' use of the IST day was unpinned (only the unit rule was): a UTC-shifted clock in either door, removing the expired case, or skipping the whole strict switch (falling into the tolerant path) left the Deno suites green outside 00:00-05:30 IST.
- **verification:** reviewer mutants V1, V4, V5, V6: green.
- **suggested-fix:** an exhaustive default; frozen-clock handler tests.
- **status:** accepted — fixed: `const usability = promoUsableAt(promo)` with an exhaustive `default` that refuses; frozen-clock tests at 00:01 and 23:59 IST in both doors; and, because the tolerant path compares with LOCAL midnight (so under TZ=Asia/Kolkata it can mimic the IST rule; that is why V4 first stayed green for the author too), two inputs where the paths differ in any time zone (a malformed `valid_until`, `is_active` "true"). V1, V4, V5, V6 red.

## Finding A2 — P2 — missing_input (user-visible copy)
- **file:line:** supabase/functions/create-razorpay-order/index.ts:171
- **claim:** "Try again in a few minutes" for a fixed 1-hour UTC bucket (a wait of up to 59 minutes); the client shows only `error`. The diagnose also overstated the client retry (only 502/503/504 are retried).
- **verification:** supabase_service.dart:527-528; razorpay_service.dart:488-494.
- **suggested-fix:** name the wait.
- **status:** accepted — fixed: exported `retryMinutes()` ("1 minute" / "N minutes"), the message names it; the source pin in create_order_rate_limit_writer_to_reader_test.dart repointed (not loosened) and red when the old copy returns; the diagnose corrected. verify-payment keeps "a few minutes": its bucket is 10 minutes.

## Finding A3 — P3 — guard_without_its_mirror
- **file:line:** create-razorpay-order/index_test.ts ("U3: over the limit (-1)")
- **claim:** Retry-After was asserted only to lie in [1, 3600]; a wrong computation survived (C8).
- **verification:** reviewer mutant C8: green.
- **suggested-fix:** assert the rest of the hour.
- **status:** accepted — fixed (within 5 s of the rest of the current UTC hour); C8 red.

## Finding A4 — P3 — blast_radius_mismatch (docs)
- **file:line:** docs/architecture/payment.md; supabase/functions/CLAUDE.md
- **claim:** neither describes U3 in this commit.
- **verification:** `git diff --cached --name-only`.
- **suggested-fix:** add them in this commit.
- **status:** accepted — answered by the branch's docs commit (the plan's commit 5, same pull request): payment.md rule 2 and rule 11(d), and SoT rows for `create_order_rate_limit`, `promo_validate_rate_limit`, `promo_usable_rule` plus the non-count refusal in supabase/functions/CLAUDE.md, already prepared. Rollback (the switch set to `true`) is in SECRET_INVENTORY in this commit.

## Finding A5 — P3 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml (founder-digest `latestEndRead + expiringSoon`, `lapsedYesterday`)
- **claim:** both ranges pointed at the weekly-keys read (stale before this batch).
- **verification:** read the cited lines.
- **suggested-fix:** recompute from anchors.
- **status:** accepted — fixed (956-982 and 1068-1080, from code anchors); round B read every range citing the four touched files: correct.

## Finding A6 — P3 — function_exception_swallow
- **file:line:** create-razorpay-order/index.ts:161; validate-promo/index.ts:94; verify-payment/index.ts:286
- **claim:** a counter answer that is neither -1 nor a count passed ("fails closed" held for an RPC error only).
- **verification:** migration 128 (never NULL today).
- **suggested-fix:** refuse unless a number >= 1.
- **status:** accepted — fixed in all three (including verify-payment's existing limit, same shape): `!Number.isInteger(usedCount) || (usedCount < 1 && usedCount !== -1)` answers like an RPC error with a code-only line; tests for null, 0 and 1.5 in each, verify-payment's with an origin control. Removing the check is red in each (3 tests).

## Finding A7 — P3 — asserted_fixture_value
- **file:line:** _shared/founder_digest_content.ts:115-118; create-razorpay-order/index_test.ts (today at load)
- **claim:** the comment lacked the hourly-bucket day-boundary slop; a test evaluated today's IST date at load.
- **verification:** read.
- **suggested-fix:** copy the sentence; compute in the test.
- **status:** accepted — fixed.

## Round B (delta, on the round-A fixes)

## Finding B1 — P3 — guard_without_its_mirror
- **file:line:** supabase/functions/validate-promo/index.ts (the `default:`)
- **claim:** the exhaustive default (unreachable today) was pinned by nothing at runtime; flipping it to answer valid left everything green.
- **verification:** reviewer mutant I: green.
- **suggested-fix:** a source pin, or say it is unreachable.
- **status:** accepted — fixed: a pin in promo_usable_rule_writer_to_reader_test.dart requires the `never` check and the refusal and forbids `valid: true` in the block; both mutants (answer valid, `never` dropped) red. Stated as unreachable in the diagnose; CI's `deno check` fails on a fifth member.

## Finding B2 — P3 — guard_without_its_mirror (redundant clause)
- **file:line:** the three bad-result checks
- **claim:** `typeof usedCount !== "number"` is dead (`Number.isInteger` is false for every non-number).
- **verification:** reviewer mutant H: green, equivalent.
- **suggested-fix:** drop it.
- **status:** accepted — removed in all three; the diagnose's mutant wording now says the whole check.

## Lenses returned clean (both rounds, condensed)
- Ordering and bypass: each limit is consumed right after the JWT check, before every other read and before the Razorpay order; no early return precedes it; a refused (-1) request burns no unit (ON CONFLICT ... WHERE used < limit).
- Fail-closed: RPC error and non-count answers refuse; -1 still reaches the rate-limited answer.
- Kill switch: exactly "true", read once per request; OFF is byte-identical to origin in the goldens (create-order six scenarios, validate-promo ten); the new checks sit inside `if (guardsOn)` in both doors.
- promoUsableAt vs live rows: `valid_until` is `date NOT NULL`; leap days, timestamp strings and offsets compare correctly; max_uses 0 is exhausted.
- FrozenDate: restored in `finally`, per-file isolates, statics inherited, no module-load capture of Date; each frozen test reddens under a clock mutant, under TZ=Asia/Kolkata and TZ=UTC.
- Client surface: order refusals arrive as the `error` string; validate-promo refusals are HTTP 200 `{valid:false, reason}`; the paywall closes before the order call, so a refused promo is not a dead end.
- The tolerant writers are unchanged and do not import promo_rules (contract).
- Log safety: the new lines interpolate only the generated request id or the JWT user id; the log contract is green and validate-promo is now scanned.
- secrets_in_tree, unawaited_no_error_sink: none.

## Founder triage notes
Self-triaged by the author under the founder's commit go for this batch (2026-10-24): 9 accepted (8 fixed, 1
answered by the docs commit of the same pull request), no false alarm.

## Tuning entry
- **2026-10-25** - blast-radius catastrophic - 9 findings; 0 false_alarm; tuning: none (a guard against a time-zone regression must be tested where the process time zone cannot hide it: the legacy path compared with LOCAL midnight, and the suite runs under TZ=Asia/Kolkata, so "falls back to the old path" was invisible; freeze the clock at a minute where IST and UTC disagree, and add an input where the old and new paths differ in every zone).
