---
branch: worktree-retirement-autonomy
date: 2026-09-29
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/858880296599-review.md
---

# Plan-review record — worktree retirement autonomy + tool-boundary docs (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart CLAUDE.md` →
`platform`, driven by the CLAUDE.md edit (matches the `live-test-budget-docs.md` precedent
exactly). An earlier stdin-piped check (`git diff | ... -`) returned `feature` — args-mode with
the real path is the correct invocation; the stdin form appears blind to CLAUDE.md's own
path-based escalation rule. Not re-litigated further here since the real gate (pre-commit's own
`NOTE: blast-radius=platform` output) already agreed independently.

## What this branch is

Documentation only — no code, no schema, no Edge Function, no test. Two additions to root
`CLAUDE.md`, both closing gaps surfaced by the `schedule-status-single-writer` batch (2026-09-29):

1. **§4.13 point 8** — names a real gap: point 6's prose assumes a plain-shell `cd`-based
   worktree session, never anticipating a harness that scopes a worktree as its own session with
   its own exit gate (`EnterWorktree`/`ExitWorktree`). Codifies the founder's explicit 2026-09-29
   instruction: once a batch's full pipeline lands (committed, pushed, merged, CI green), retire
   the just-finished worktree autonomously and report it done — never ask. Scoped tightly to the
   session's own just-finished worktree; never a sweep of others found lying around.
2. **§4.9 pitfall row** — the specific technical mechanism: `retire_worktree.dart` checks the
   BARE LOCAL `main` ref (`git branch --merged main`, no fetch anywhere in its path), so after a
   GitHub-PR-web-UI merge (which lands only on `origin/main`), primary's stale local `main`
   produces a false `[branch not merged]` verdict until fast-forwarded.

Per §4.3, a docs/process-only ≥account change takes a self-consistency review rather than an
adversarial bug-hunt; that is the standard applied for round 2 below (the B-pass agent was
explicitly briefed for self-consistency + accuracy verification, not code-bug lenses, since
there is no code in this diff).

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Self-review while authoring, ground-truth-verified live against the actual scripts (not assumed from memory) | Confirmed the core mechanism claim myself before drafting the text around it: `grep -n "merge\|Merge" scripts/retire_worktree.dart` → line 158 is `git branch --merged main`, no `origin/main` in the automated path. Confirmed §4.13 points 1–8 sequential, no gap/duplicate (point 5 unbolded-lead, a grep-pattern artifact not a doc defect). Confirmed no contradiction with point 6's "not a blocking gate"/"never `--force`" framing. |
| 2 | Context-blind self-consistency B-pass (fresh Sonnet, `docs/reviews/858880296599-review.md`) | 1 finding — P3, non-blocking (missing cross-reference to the pre-existing `_mainSyncWarning()` §7 row, a complementary-not-contradictory sibling mechanism at a different trigger point). 0 P0/P1/P2. Independently RE-confirmed the core mechanism claim from scratch (same conclusion, arrived at separately) and, unprompted, verified the `ExitWorktree` tool-boundary quote against the tool's real schema (available to it via `ToolSearch`) — verbatim match, plus the `action` enum and the `"remove"`-skips-repo-safety-checks claim, both confirmed accurate. |

**Converged at round 2**: the B-pass surfaced zero material issues — only one optional
completeness suggestion, which was folded in immediately (see below) rather than argued over.
Per §4.12.1 the split/re-review signal is *successive rounds surfacing new material issues*;
that did not occur, and a genuinely independent second verification of the single highest-risk
factual claim (agreeing with round 1 by an entirely separate method) is a stronger convergence
signal than a third round would add here.

## Ground truth

Every consequential claim in the shipped text was verified against the real files, by the
author, before and independently of the reviewer:

- `scripts/retire_worktree.dart:158` — `git branch --merged main`, confirmed via direct `grep`+`Read` (author) and full-file read (reviewer), same conclusion, same line number, two different methods.
- `scripts/retire_worktree.dart:341-342` — the `orphan sweep skipped` message the pitfall row's prescribed slug-scoped invocation relies on — confirmed via `sed -n '338,344p'` (author).
- `ExitWorktree`'s quoted tool instructions — confirmed verbatim by the reviewer via `ToolSearch`, cross-checked by the author against this same session's own earlier `ToolSearch` load of the identical schema.
- §4.13 points 1–8 sequential, no duplicate/gap — confirmed independently by both author (`awk` range + `grep`) and reviewer (`Read` of the full range).

## The one finding, and why it wasn't argued over

**Finding 1 (P3, self_consistency):** the new text doesn't cross-reference the pre-existing
`_mainSyncWarning()` mechanism (§7, `discipline_hook.dart` row) — a structurally similar
local-vs-`origin/main` drift detector, added 2026-09-24 for a different incident (a VPS clone
silently drifting 300 commits behind). The reviewer correctly determined this is NOT a
contradiction (different trigger point: `SessionStart` vs. mid-session post-`ExitWorktree`), just
a missed pointer. Folded in as a one-line parenthetical on point 8's `Sequence:` line rather than
disputed or deferred — the fix cost less than the argument would have.

## Known residue, stated rather than left

None material. The stdin-vs-args blast-radius classifier discrepancy (see "Tier" note above) is
already documented as a known gotcha in `docs/plan-reviews/live-test-budget-docs.md`; not
re-documented a second time in CLAUDE.md itself to avoid duplicating the same caution in two
places for one tool-invocation quirk.

**Verdict: converged.**
