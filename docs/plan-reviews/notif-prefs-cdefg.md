---
branch: notif-prefs-cdefg
date: 2026-07-27
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/notif-prefs-cdefg-bpass.md
---

# Plan review — notif-prefs Units C..G

§4.12 record for the remainder of the notification-preferences arc. Unit B
shipped separately (`3bca83a8`) after rounds 1–3; this branch carries C, D, E, F,
A and G, plus a fourth round — the implementation B-pass, which found more than
the three planning rounds combined.

## Rounds

| Round | What it changed |
|---|---|
| 1–3 (pre-implementation) | Refuted five claims I had relayed from subagent research; found that round 1's own corrections introduced two P0s; found round 2's correction named the wrong template. Drove the decision to ship B alone. |
| 4 (B-pass, this branch) | **One P0 and three P1s, four of five mine.** Details in the B-pass record. |

That distribution is the honest summary: three rounds of planning did not catch
what one round of reading the actual diff did. The P0 in particular could only
exist once code was written — I threaded a parameter through the wrong branch of
a function, which no plan review can see.

## Ground truth

Every load-bearing claim verified against source or live data, not against
subagent prose:

- `buildAiContext` really ends `return trimSnapshotToBudget(context, budget: 9500)`
  (`ai_snapshot_builder.dart:420`) — so emitting after the spread genuinely
  escapes the trimmer. This is the whole justification for the emission point.
- Round 3 claimed 4 of 6 preference readers were already latest-desc. **Checked
  all four** rather than accepting it: `workout-window-closing`,
  `streak-guardian`, `weekly-recap-ready`, `expiry-reminder` all use
  `.order("snapshot_date", { ascending: false })`. The other two were date-pinned
  and are fixed.
- `MigratedKey` falls back to `configBox` on **both** read (`:46-48`) and write
  (`:93-100`) — read the lines before deciding not to use it.
- The live baseline (0 of 91 rows, 1 row dated today, 3 users fresh within 3
  days) is what makes a today-pinned read inert; it is the reason F1/F7 matter.

## Corrections I made to my own work, recorded so they are not repeated

1. **A test that passed for the wrong reason.** The trim fixture used one large
   non-keep blob — the trimmer shrank that and never reached the key. Rewritten
   so keep-set content alone exceeds the budget.
2. **A test that false-positived.** The adoption test reported three functions
   as unguarded; they use dot access rather than a quoted key. Checked before
   "fixing" three non-bugs.
3. **Presence is not placement.** The P0 sat behind an adoption test asserting
   the file *contained* the guard call. It did. That is the general lesson.

## Deviations from the plan, taken deliberately

- **F11/F12 refuted.** The finding said inverting the PRO flag orphans
  `isPro`/`extra['isPro']`. It does not — the screen still needs to know whether
  the *user* has PRO to decide locked vs interactive. Recorded as
  `verified_clean`, not silently ignored.
- **Unit G's payload rename not done.** The plan said to rename the
  `proactive_promotion` payload kind. A contract test pins it and nothing in
  `lib/` reads it, so renaming would break a pinned test and split historical
  rows from new ones for no benefit.
- **`rank_promotion` added to `ProactiveType` but not day-deduped** (F8):
  `shouldSendProactive` compares a single `last_proactive_type` slot, so stamping
  a promotion would let a same-day `pr_celebration` fire again.

## Convergence

Converged: every P0/P1 is fixed in-branch with a regression test, and the
remaining P2/P3s are accurate, non-blocking, and carry terminal states in
`docs/audit/notif-prefs-c-to-g.closure.yaml` plus entries in
`docs/audit/open_issues.md`.

## The acceptance criterion is NOT yet met

`snapshot_json ? 'notification_preferences'` must go **0/91 → non-zero**. That
needs a client build in a real user session; it cannot be proven from CI. Every
test in this branch passes while that number stays zero — which is precisely how
this feature looked healthy for months. Stated here rather than left implicit,
because "all tests green" is exactly the signal that failed last time.
