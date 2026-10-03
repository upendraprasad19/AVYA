---
branch: deploy-token-path
date: 2026-10-02
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/deploy-token-path-bpass.md
---

# Plan-review record — deploy token resolution (`deploy-token-path`)

Founder request 2026-10-02: "We have a working token in the other path, cross check, and also mark that in our Claude.md so that we do not use this token. Every time we waste time on this."

## Scope
The host-shell deploy tools and the live-SQL runner resolve the working Supabase Management-API token from any worktree (this tree `.supabase/`, the primary's `.supabase/`, legacy `supabase/.supabase/` last, with warnings); docs state which file works on the VPS; OI-165 closed with a live probe; OI-283 filed for the runners that have no CI runner; the four deploy tools move to account tier.

## Review rounds
- **R1**: fresh context-blind review of `9ea30235`: primary lookup design, git env scrub, Dart twin, warnings, doc wording that over-claimed. Fixed in `33048976`.
- **R2**: fresh context-blind review of the post-R1 tree: 0 P1/P2, 9 P3, all fixed in `987ce09b`. Findings of record: `docs/reviews/deploy-token-path-bpass.md`.

## Ground truth
The two tokens were measured with an HTTP status probe only (root `.supabase/`: 200; `supabase/.supabase/`: 401; no value printed). The fixed resolver was run from this linked worktree with `SUPABASE_ACCESS_TOKEN` unset and a read-only `select 1` via `check_onconflict_live_arbiter.dart`: token resolved, OK. 21 resolver tests run against real temp dirs and a real linked worktree, 4 mutations reddened.
