---
reviewed_at: 2026-10-22T21:30:00+05:30
staged_against: oi341-piece-b2b-client working tree on base 47cb142c (uncommitted; 27 files staged at dispatch)
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh context-blind read-only seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 15
verdict: accepted
---

# Code Review (B-pass) — OI-341 Piece B2b client (`oi341-piece-b2b-client`)

Two fresh Sonnet seats, both read-only (no dart, flutter, scripts, shell experiments, network, DB or state-changing
git; exhaustive command list in the brief), run after the full gate loop (full suite 10379 passed / 9 skipped;
pre-commit gate loop OK; 32/32 author mutants red). Seat A: lenses 1, 3, 4, 7 and docs accuracy. Seat B: lenses 2, 5,
6, 8 and payment over-grant semantics. Both seats were interrupted once by an expired login before producing output
and were resumed with their original briefs.

Neither seat found a P0 or P1. Distinct findings: 3 P2, 12 P3 (incl. one already fixed in the working tree when it
was reported). 0 false alarms. Every finding is terminal in `docs/audit/oi341-piece-b2b-client.closure.yaml`
(rows `B2B-BP-*`).

## Payment over-grant (seat B, the question asked)
No path grants a materially longer local entitlement than the server: with the door open `stacks_after` is the latest
TRIAL end and a paid row 409s, so client and server agree; windows where the estimate exceeds the server (a trial row
shrinking between order and payment, a retry fallback after the trial end, a payment never recorded) are bounded and
closed by the poll / verify / retry / `refreshFromSupabase`; high-value gates call `verifyFromServer` regardless.

## Finding 1 — P2 — guard_without_its_mirror (seat B)
- **file:line:** `lib/core/services/razorpay_service.dart` catch path, `if (conflict != OrderConflict.other) {`
- **claim:** the live 409 path's outer guard was unpinned; the P1 regex's lazy span jumped over it. Mutant `== alreadyPro`
  makes the trial branch unreachable and shows "You're already a PRO member." with every test green.
- **status:** fixed: pin P7 (outer guard directly before the trial branch); mutant N1 red.

## Finding 2 — P2 — asserted_fixture_value (seat B)
- **claim:** the trial copy selection (`_showAlreadyProFeedback` ternary) and the copy text were asserted nowhere.
- **status:** fixed: pure `orderConflictMessage` (T7: exact trial text, today's line byte-for-byte), pin P8; mutants N2,
  N3, N7 red.

## Finding 3 — P2 — writer_reader_drift, docs (seat A)
- **file:line:** `docs/plans/oi341-piece-b2-door.md` lines 17-20, 45, step 4 body, 607; B2a ledger `B2B-NEXT` title.
- **claim:** only step 5 was amended; the file held two orders and step 4 still put the stacked purchase before the
  merge, so an operator following step 4 would buy through the old client.
- **status:** fixed: step 4 relabelled 4a (door, then the B2b merge) / 4b (purchase through the new client); the three
  sentences and the ledger title now state one order.

## Findings 4-15 — P3
- Seat B P3-3 (fallback timing): verified clean; same output for the no-record case, the racy cases now use the
  order's own plan.
- Seat B P3-4 (goldens depend on IST): fixed; instants built from local wall-clock times, tests pass under IST and UTC.
- Seat B P3-5 (EST seal mixes zones): fixed; both branches print the local date; new UTC-expiry test, mutant N6 red.
- Seat B P3-6 (record written after an account switch): fixed; recorded only for the same signed-in user (pin P9,
  mutant N5 red).
- Seat B P3-7 (the paywall line does not read the door): verified clean, by design (merge after 4a).
- Seat B P3-8 (a throwing trial heal falls through to the server text): fixed via pure `isTrialRefusal` (T8). Its
  first form, an inline condition, let mutant N4 SURVIVE (the pin checked the use, not the computation); N4a-c red
  after the extraction.
- Seat A P3-1 (registry ranges): fixed on the final code (handlePaymentConfirmed 508-649 incl. its brace,
  _pollAndActivate 749-961, retry 963-1053, logSleep inline 550, `:733` prose).
- Seat A P3-2 (stale runbook cite `~:755-770`): fixed by symbol; lines 79 and 198 are dated facts (section 1 "verified
  at b8385b6c"), left as such.
- Seat A P3-3 ("overwrites on every path"): fixed; the registry and `lib/core/services/CLAUDE.md` name when it is
  replaced.
- Seat A P3-4 (plan P4 "four calls"): fixed; three calls over four sites.
- Seat A P3-5 (400-day clamp drops the notice for a long legitimate trial): fixed; 3650 days; mutants M8, N8 red.
- Seat A P3-6 (stale `[endLabel]` dartdoc): fixed.
- Seat A P3-7 (plan-review record missing): written, `docs/plan-reviews/oi341-piece-b2b-client.md`.

## Checked and clean (from the seats' reports)
FunctionException handling unchanged for non-409 and non-Map; nothing new can throw inside the order `try`; the one
new `unawaited` (`razorpay_checkout_record_unmatched`) logs no ids; the non-trial "already PRO" text is byte-identical;
order-id matching on native and web paths; the 4-entry bound; `isAfter` boundary; callbacks are no-ops at the only
caller; `methodBody` cuts at real member boundaries; the repointed 409 assertion is not weaker; no test greps a
removed literal; parity regexes match `index.ts:64` and the only definer, migration 159; blast radius platform via
`supabase/functions/CLAUDE.md` only, nothing catastrophic; no secrets.

## Re-verification after the fixes
42 distinct mutants red (M1-M33 without M16; N1-N8 with N4 rebuilt as N4a-c); targeted tests green under IST and
UTC; `flutter analyze` clean on the touched files; the full gate loop re-run before commit.

## Founder triage notes
All findings fixed or verified clean in this batch; verdict accepted by the author on the founder's standing B-pass
instruction.
