---
branch: post38-auth-fixes
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
tier: full
blast_radius: platform
reviewed_at: 2026-08-13T07:40:00+05:30
bpass_review: docs/reviews/04e29b25-review.md
closure_ledger: docs/audit/post38-auth-fixes.closure.yaml
---

# Plan review record — post38-auth-fixes (slice 0 + the PR #22 merge resolution)

## Scope of this record

This record originally covered **slice 0 only** — the prod/repo reconciliation plus the
new SoT-citation gate, landed as `d4a8de00`, reviewed ×2 on 2026-08-09 with the B-pass at
`docs/reviews/d4a8de00-review.md`. The batch's four remaining slices are sequenced under
the founder-ratified §4.12.1 split and each merges under its own record.

**Extended 2026-08-13 — the PR #22 merge resolution.** Two further commits landed on this
branch and are covered here rather than left implicit, because "converged" on a branch
record otherwise implies coverage this file did not describe (B-pass finding 5):

- `5fd5b337` — `log-client-error` v13 redeploy; closes OI-93's 4th instance and fixes two
  defects in the deploy tool itself. Diagnose-doc `a7c3f9`.
- `babea1a4` + merges `35a5e094`, `04e29b25` — the OI-id renumber (OI-100..105 →
  OI-109..114), the duplicate-id detector in `build_oi_index.dart`, the
  `bpass_record:`→`bpass_review:` key fix, and two catch-up merges of `origin/main`
  (which advanced twice mid-flight). Diagnose-doc `b7e3d1`.

**Review rounds for the extension — ×2 independent, context-blind, both on the plan
BEFORE execution** (§4.12.1), then a B-pass on the result:

- **Round 1 (Sonnet):** returned UNSOUND. 3 P0s — the `bpass_review` key mismatch that
  would have hard-failed this very gate; a gate simulation that exits early on `GITHUB_REF`
  and prints a meaningless PASS; and `safe_push.sh` invoked with its arguments in the wrong
  order.
- **Round 2 (Opus, on the hardened plan):** returned UNSOUND again, finding defect *classes*
  round 1 had not — the renumber target block was already taken (OI-106 existed on unpushed
  local `main`), and the renumber had to move BEFORE the merge or it would silently rewrite
  `main`'s six published entries. Per §4.12.1 the successive rounds surfacing *different*
  classes rather than more of the same is the convergence signal.
- **B-pass:** `docs/reviews/04e29b25-review.md` — 5 findings, all P2, all fixed. The most
  important was a test that could not fail for the property it asserted (a same-digit-width
  fixture where lexical and numeric sort coincide) — the Gate-44 class, inside the commit
  whose selling point is mutation-proof discipline.

## Round 1 — context-blind, 2026-08-07 (16 findings)

Two independent reviewers, one on code, one on docs. The severe findings were
verified by me against source before any of them entered a fix — subagents quote
reliably and reason unreliably.

Highest-value finding: **P0-1**, the OAuth watch trusting the
`onAuthStateChange` payload. `onAuthStateChange` is a `ReplaySubject` with no
`maxSize`, so sign-in → sign-out → retry would resolve against a *historical*
session. My test could not see it because the stub was a plain
`StreamController` — **the fake was more forgiving than production at the exact
seam carrying the defect**. Strictly worse than the bug being fixed.

## Round 2 — on the HARDENED tree, 2026-08-07 (11 further findings)

Run against the post-round-1 tree, per §4.12.1. Decisive signal: round 2's
findings were **largely defects introduced by round 1's own fixes** — including a
phantom method invented while *correcting a citation error*. That is the
explicit trigger to split rather than review a fifth time.

**Split ratified by the founder 2026-08-08** into five slices. Slice 0 is the
piece with zero open findings against it.

## Ground truth verified

Every live claim re-checked directly, not taken from a subagent:

| Claim | How verified |
|---|---|
| Migration 119 applied | `pg_attribute.attnotnull = false` on `client_errors.user_id` |
| `log-client-error` v12 ACTIVE | `list_edge_functions` |
| Anon lane writes | row `b3fb0885`, `user_id NULL`, `1.0.0+38 web` |
| Deployed source vs repo | payload decoded as UTF-8 and diffed — sole difference is the 6th allow-list entry |
| Blast radius | `blast_radius_from_diff.dart -` → `platform` |
| RLS unchanged by 119 | policy `auth.uid() = user_id` untouched; NULL still rejected for authenticated writers |

## B-pass — 2026-08-09, self-initiated per §4.3 (7 findings)

`docs/reviews/d4a8de00-review.md`. Ran on the *finished commit*, and still found
seven things, one P1. All resolved; four in code, three in docs.

The P1 is the one worth remembering: **14 ledger entries claimed
`closed_in_commit` for fixes that existed only as uncommitted working-tree
edits**, including a P0 whose own notes contradicted its own terminal_state. The
ledger lied in the reassuring direction. Rule now written into the ledger header:
*a closure ledger describes git, not intent — if you cannot name the commit that
carries it, it is not closed.*

Two gate-integrity findings (B2, B3) mattered disproportionately because they
were in **Gate 44 itself** — the artifact this slice exists to ship. Its contract
test never executed `main()`, so neutering the gate left the suite green; and
prose citations escaped the check even under `--strict`. Both closed, the second
mutation-proven.

## Where the 42 findings came from

Only 27 of 42 came from a review *round*. Three came from the pre-commit suite,
seven from the B-pass on the finished commit, five from scoping work. Reviews are
necessary and insufficient — the suite and the gates found things two rounds of
adversarial review did not.

## Convergence

`converged` for slice 0: every finding against it is terminal in the ledger
(42/42), the gates pass, 2858 tests pass, and the two findings that would have
misled a reader are corrected in the artifacts rather than only in prose.

Not claimed as converged: slices 1–4. Their findings are `blocked_on_user`
against their named slice with `fix_state:` recording that the code is written
but in no commit.
