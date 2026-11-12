---
branch: oi493b-duplicate-meals
scope: OI-493 Landing B (founder decision F4, "if we are logging same meal twice it should log twice"). A repeat of the same meal adds a second entry (first free occurrence key), UNDO and move never overwrite a newer entry, the v7 key migrator stops collapsing servings and leaves current-shape rows alone, one coach tag card and one screen tap save once (shared in-flight guards that survive a remount), and a zero AI total falls back to the items' sum.
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi493b-duplicate-meals-bpass.md
---

# Plan-review record: OI-493 Landing B

Plan: `docs/plans/oi493b-duplicate-meals.md`. Split from Landing A's plan in its round 1 (`docs/plan-reviews/oi493-nutrition-parity.md`), which carried every occurrence-key finding here. Every round used context-blind Sonnet seats with `docs/agent_brief_preamble.md` prepended and an exhaustive read-only command list (git read verbs, Read/Grep, the Hive 2.2.3 source); this is a prose plan with no draft diff, so the gate loop runs before the B-pass (§4.12.5).

## Round 1 (rev 1, two seats: A ground truth, B adversarial design)
No P0/P1. A: 4 P2 + 3 P3; B: 4 P2 + 4 P3. Every finding was re-checked by the coordinator against the code before rev 2.
- A confirmed the Hive claim (keystore insert before the first await, `box_impl.dart:82-88`, `keystore.dart:184-203`), every writer/reader line and the cloud push/restore paths.
- A1 an all-digit 8-hex hash (about 2.3%) makes a bare `_\d+$` strip wrong: one anchored regex for base and shape. A2 three retag tests break, not one (union, post-merge clamp, macroUpdates on collision). A3 a source pin on the search `.logFood(` window. A4 no migrator test exists; the migrator's doc comment claims v5 but uses hashCode. A5 the AI-text card's `_saving` is widget state (remount hole). A6 the saved-meal sheet pops before logging. A7 the shared future returns the same bool.
- B1 SingleFlight keyed by name would drop a second, different food of the same name: key on the write identity; a null run shows no toast. B2 the handler is built per call: the in-flight map must be static; an unmounted card's action must still be cleared. B3 no real double-dispatch path for the coach tool (`confirm` sets `executing` before its first await; retry = confirm; the only auto-run intent is the completion tile): B5 dropped. B4 two deletes in a row make the first UNDO restore the second row; the stash is not owner-bound. B5 the free-key choice must sit inside the existing try. B6 legacy rows still collapse. B7 a scan total edited to 0 now stores the item sum (stated). B8 the simulation harness (verified clean: it clears `nlog_` first and logs each slot once a day).
Outcome (rev 2): all folded in; B5 removed; `restoreLastDeleted(expectedKey:)` + owner guard; static in-flight map + notifier captured before the await; SingleFlight on the write identity, also covering the AI-text save (in the notifier) and the scan save; legacy migrator rows keep one entry each.

## Round 2 (rev 2, one convergence seat: ground truth + design)
Converged: no P0/P1. 2 P2 + 4 P3, all folded in as rev 2.1:
- F1 (P2) a scan save's null SingleFlight run left `_saving` true: the flight is taken before the flag is set.
- F2 (P2) the AI-text in-flight null reported "Already saved." in red, false if the first save then fails: a new
  `WriteResult.inFlight()` shown as a neutral "Saving meal…".
- F3 (P3) the owner-hash guard needed a null rule: null on either side refuses.
- F4 (P3) the owner guard covered `restoreLastDeleted` only: `deleteLog` records the owner per deleted key (bounded),
  checked by both UNDO paths.
- F5 (P3) repoint list: the two UNDO test files named with lines; the three retag tests confirmed (:103, :179, :238), the
  file's other tests (:28, :68, :303, :331) do not collide.
- F6 (P3) the legacy migrator loop reads the live box for occurrence keys.
The seat verified the dropped B5 (the only `ToolDispatcher.instance.execute` caller is `confirm`; `confirm`/`retry`
callers are `tool_confirm_card.dart:48,75` and `tool_confirm_sheet.dart:50`), the non-autoDispose
`pendingLogActionsProvider`, the static-map race (a timer cannot interleave between a future completing and its
continuations), and every line reference in rev 2.

The rounds went 0 P1 -> 0 P1 with shrinking P2 counts (8 -> 2); the plan is executed as rev 2.1.

## Build and B-pass
Draft committed `2a27c7dc` after the local gate loop (whole-project analyze 0 warnings, pre-commit gates, targeted tests
under Kolkata and UTC, 20/20 mutants red); the full suite ran on CI for PR #253 (`land_pr --ci-only`: ci-green on
`2a27c7dc`). B-pass on that head, two fresh Sonnet seats (A read-only, lenses 1-5/7/8; B lens 6 by mutation): no P0/P1,
5 P2 and 7 P3, all fixed or closed with a reason in `520a7e0a` (second mutant batch 12/12 red). Review
`docs/reviews/oi493b-duplicate-meals-bpass.md`, verdict accepted.
