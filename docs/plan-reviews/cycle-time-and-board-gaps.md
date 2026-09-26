---
branch: cycle-time-and-board-gaps
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/cycle-time-and-board-gaps-bpass.md
blast_radius: platform
reviewed_at: 2026-08-17
---

# Plan review — `cycle-time-and-board-gaps`

Two independent context-blind rounds plus the mandatory ≥platform B-pass, each
run against the state produced by the previous one, per CLAUDE.md §4.12.

## What the batch does

**(T) Cycle time.** `flutter/bin/dart` is a wrapper: every invocation takes the
SDK update lock and shells out to `git rev-parse` on the Flutter checkout. The
lock SERIALIZES concurrent callers, so its cost scaled with the gate loop's job
count instead of dividing by it. `scripts/_dart_bin.sh` resolves the SDK exe
once per hook run; all five hooks source it behind a readable-and-parseable
guard. Measured on the real hook, same worktree, same gates, both exit 0:
**182149 ms → 98447 ms**. `dart --version`, which does nothing at all: **3.4–10.5 s**
via the wrapper, **0.07–0.22 s** via the exe.

⚠ Cite the RATIO, not the constants. Round 1 independently re-measured
`dart --version` at 829/887 ms vs 69/75 ms — same ~12× direction, an order of
magnitude off the recorded absolutes. They are load-dependent.

**(F) Board / discipline gaps.** `pre-merge-commit` was never installed, so a
CLEAN auto-merge ran NO hook — which is exactly how an OI number minted on two
branches reached `main` and sat 3 days 0 h 34 min before a human noticed. New
`check_oi_numbering_unique.dart` closes the mint-time half of OI-112. Plus the
git-safety env-prefix bypass, four gates with no invocation site, the euphemism
gate's staged-diff-only blind spot, orphan worktrees, and CLAUDE.md drift.

## Ground truth verified

Every measurement re-run rather than carried forward; every subagent numeric
claim confirmed against the file before use. Specifically established by
execution, not reading:

- The wrapper/exe timing, on the real hook, both exit 0.
- `.git/hooks/` held 4 hooks, not 5 — and Gate 32 said PASS anyway.
- The collision gate's own first live run reported PASS on a KNOWN-colliding
  branch (`Process.runSync` defaults to `systemEncoding`, mangling the em-dash
  so 0 of 77 headings parsed).
- The three-point predicate is a structural no-op whenever `base == mainline` —
  provable by construction, and true at two of its three documented placements.
- CI's `audit-gates` job checks out at depth 1, where a merge commit reads as
  parentless.
- `build_oi_index.dart` is invoked NOWHERE in CI (`grep -c` → 0).
- **The working repository is itself shallow** (`--is-shallow-repository: true`)
  while still resolving merge parents — which is why the shallow guard had to be
  narrowed twice.

## Rounds

**Round 1 — 2 BLOCKING, 4 MATERIAL, 3 MINOR.** Both blocking were defects this
batch introduced: the git-safety hook was DISARMED (naming a hatch variable in a
comment allowed a raw force-skip push), and the new hook was not installed while
Gate 32 reported green. All 8 closed; ledger entries R1-1…R1-11.

**Round 2 — 2 BLOCKING, 2 MATERIAL, 7 MINOR**, run on the hardened result. Both
blocking were defects round 1's FIXES introduced: the gate could not fail in CI
(and round 1 had relabelled that no-op "a checked answer, not a skipped one"),
and the hatch still leaked through a heredoc or multi-line commit message —
round 1's tests all used single-line messages. All 10 terminal; R2-1…R2-10.

**B-pass — 1 P0, 3 P1, 1 P2.** `docs/reviews/cycle-time-and-board-gaps-bpass.md`.
The P0 was generation three of the same bug: the hatch was bound correctly to a
statement, and the CALLER discarded that binding, so a harmless hatched
statement exempted an unrelated dangerous one. All 5 fixed.

## Why this is converged, stated honestly

Three passes, each finding a defect in the previous one's fix. §4.12.1 says
successive rounds surfacing new material issues is the signal to split and ship
the smallest converged piece. Founder decision 2026-08-17: **merge now, with
OI-119 funded as its own unit.** That is the split — not an assertion that no
defect remains.

What supports `converged` for what is merging:

- Every finding from all three passes is closed or terminal (32 ledger entries,
  Gate 40 `--strict` PASS, no `deferred:` key).
- The remaining known gaps are **pre-existing and not worsened here**: the DENY
  path's 13+ missed spellings and the suffix-matched wrapper allow. This batch is
  a net improvement in that exact direction (`FOO=1 git commit` went ALLOW →
  BLOCK). Both directions are now measured on OI-119 with a reproduction harness.
- The fix that kept regressing is now covered by tests at the level it kept
  escaping: library predicates returning statements rather than booleans, three
  end-to-end case matrices (37 cases) with controls in both directions, and
  mutation proofs on each leg separately so a partial regression cannot pass.

What would NOT be honest to claim: that a fourth pass would find nothing. The
evidence of this batch is that passes keep finding things in this one file.
That is precisely why OI-119 is funded separately rather than folded in.

## Residuals, explicit

- **OI-119** — funded as its own unit (founder, 2026-08-17). Ledger R2-9,
  `terminal_state: blocked_on_user` with the decision recorded.
- **OI-129** — the orphan worktree's premise was REFUTED (all 526 non-build
  files hashed raw AND CRLF-normalized against 9766 blobs → 0 unmatched).
  Only the `rm -rf` remains, refused by the harness safety classifier and
  deliberately not worked around.
- **OI-101, OI-106** — untouched, unchanged.
- **Octopus merges** report UNDETERMINED rather than being handled. Nothing in
  this repo produces one; `safe_merge.sh` takes a single branch.
- **Gate 32 checks presence and identity, not freshness.** That is OI-104's job
  and was deliberately not smuggled in: a content-hash check would hard-fail
  every commit whenever a hook is edited before the installer re-runs, with a
  remedy that writes to the git dir shared by every live session.
