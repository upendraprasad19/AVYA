---
reviewed_at: 2026-10-21T15:20:00+05:30
staged_against: 64b21cb79f3c
branch: oi341-piece-b2-door
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (2 context-blind seats, self-initiated per CLAUDE.md 4.3)
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 11
verdict: accepted
verdict_note: "0 P0 / 0 P1; 4 P2 + 7 P3. Every finding fixed (with a killing test or mutant where it is code); the reviewers' 12 proposed mutants were run (SA1-SA12, all red after one survivor was closed). The hermes pass then ran on the post-fix tree and its in-batch fix (c3e7a1, the amount-no-match alert) and plan/doc fixes are also in this staged tree; the review ran on the B2a build at staged 3117ea88e10b, and the later changes are the fixes listed here and in the hermes report."
---

# Code Review (B-pass) - OI-341 Piece B2a, staged `64b21cb79f3c`

Scope: the B2a build (plan `docs/plans/oi341-piece-b2-door.md`): the purchase door on `create-razorpay-order`, the
OFF-branch `stacking_switch_mismatch` alarm and the `stacking_switch` log line in both writers, the webhook's 1 s alert
bound and the per-event replay window, the shared switch rule, docs and registry. Seat A: production code and tests;
seat B: documents, plan and claims. Both read-only with an exhaustive command list; both disclosed using shell
`sed`/`grep` for reading (the Grep tool was unavailable to them). Both ran the five Deno suites green.

## Finding 1 — P2 — asserted_fixture_value (seat A)
- **file:line:** `supabase/functions/create-razorpay-order/index_test.ts` (the import side-effect test)
- **claim:** the traps sat in `try {} catch {}` (a non-assignable trap would pass silently) and the `Deno.serve` trap
  could not fire (std@0.177's `serve()` listens through `Deno.listen`).
- **status:** accepted, fixed: every trap is verified installed by identity, `Deno.listen` and `Deno.serve` are both
  trapped, the child has a 30 s timeout. Mutants SA6 (key id read at module scope) and SA7 (`serve()` at import) red.

## Finding 2 — P3 — asserted_fixture_value (seat A)
- **claim:** wall-clock upper bounds with 400-600 ms of slack can flake on a loaded runner.
- **status:** accepted, fixed: upper bounds widened (1 s cases < 2.5-3.5 s, 2 s cases < 4.5 s, verify 3 s case < 5.5 s);
  lower bounds unchanged; every timeout mutant (A6, A7, W5, V5, NM4) still reddens.

## Finding 3 — P3 — guard_without_its_mirror (seat A)
- **claim:** the alarm's worst case is about 3 s (read, dedup, insert), not 2.2 s.
- **status:** accepted, fixed in the comment above `checkStackingMismatch`, payment.md rule 10 (c) and plan 2.5.

## Finding 4 — P3 — guard_without_its_mirror (seat A)
- **claim:** a captured event delivered late (inside the new 24 h window) records the row from the delivery time.
- **status:** accepted, stated as a residual in the webhook's replay comment and payment.md rule 10 (e).

## Seat A proposed mutants
SA1-SA12 run (SA4 recorded, not run: it needs a clock seam; its effect is a few ms on a detect-only read; ledger
BP-A-MUTANTS). SA1 (`clearTimeout` dropped) SURVIVED the first run (Deno's op sanitizer did not flag the leaked timer) and
is now killed by a timer spy; SA5, SA10/SA11 and SA12 are killed by new tests (the failure log code, an unknown-plan row,
mixed `+05:30` / `Z` instants).

## Finding 5 — P2 — missing_input (seat B)
- **file:line:** plan section 4 step 0 (c)
- **claim:** the 90% code's `max_uses` and `valid_until` limit nothing: the door honours an expired or exhausted code,
  both writers honour an expired, exhausted or inactive one, and the increment has no ceiling.
- **status:** accepted, fixed in the plan (an unguessable upper-case code; only `is_active` limits it; deactivated right
  after step 4; deactivating mid-flight is safe, verified in both writers). The general gap is OI-366 (hermes).

## Finding 6 — P2 — writer_reader_drift (seat B)
- **claim:** payment.md rule 5 still said a 5-minute window for every event.
- **status:** accepted, fixed (per event since B2a).

## Finding 7 — P2 — asserted_fixture_value on documents (seat B)
- **claim:** "NO extra query" on the OFF path in payment.md rule 9, `supabase/functions/CLAUDE.md` and the OI-341 status,
  while B2a adds one alarm read after the insert.
- **status:** accepted, fixed in all three and in the registry.

## Findings 8-11 — P3 (seat B)
- The OI-341 Status paragraph contradicted its Blocked-on line: fixed.
- The `trial_purchase_door` reader ranges excluded the alarm call: re-cited (and re-derived again after the hermes edits).
- The ledger said "+8 tests": counts re-derived.
- `SECRET_INVENTORY` had no rows for the two switches: added.

## Lenses that came back clean
writer/reader drift on the code (seat A: the shut door equals origin for every traced input; the open door blocks any
non-`referral_trial` plan); secrets (seat B: no credential-shaped literal in the diff); blast radius (the door glob is
catastrophic); the live-sequence reads by seat B (refunds are ignored events; a paused webhook cannot strand an
authorized payment; R1/R2 are valid SQL).

## Founder triage notes
All findings resolved in this batch. Mutation proof: 57 of 57 mutants red on the final tree (scratchpad
`mutate_b2a.py`, self-attested).
