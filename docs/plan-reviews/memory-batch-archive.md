---
branch: memory-batch-archive
date: 2026-08-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/memory-batch-archive-bpass.md
---

# Plan-review record — §5 memory-index row (platform)

One-row change to the §5 per-batch checklist. Docs/process-only, so per §4.3 the review is a
**self-consistency pass on the wording**, not an adversarial bug-hunt.

## The problem, stated as a rule asymmetry

§5 row 10 read *"MEMORY.md index updated"*. It mandated the **write** and defined no removal —
structurally identical to §4.13's original worktree lifecycle (`new-worktree.sh` created,
nothing retired, until it reached 106 dirs / 17 GB). The consequence is measured, not
theoretical: **each of the last three `/consolidate-memory` passes had to archive 4 shipped
batch lines**, and on 2026-08-11 one was still labelled `IN-FLIGHT` the day after it merged.

## The fix, and why it is a rule change rather than a mechanism

The default destination for a shipped batch becomes a `MEMORY_ARCHIVED.md` line; an index line
is earned only by a residual that is not already an OI — and filing that OI removes the need.
Tested against the 4 batches archived on 2026-08-11: **3 would never have been indexed**
(`safe_push` → OI-100…104, `google-signin` → OI-88, `gate-registry` → its only non-OI item was
the unset Supabase secrets, which should itself have been an OI).

**A detector was deliberately NOT built, and the row says so.** `oi-mechanism.closure.yaml` D5
records that a SessionStart digest + two gates for exactly this was built, reviewed twice, and
**withdrawn wholesale** — round 2 found defects introduced by round 1, including *"a parser
that fixed an exact-string match by becoming permissive enough to swallow a prose bullet."*
Scars are at OI-68/OI-69; OI-69 is still open (*"Nothing detects this backlog going stale
AGAIN"*). Re-proposing a hook here would have been the third §4.1.5 miss in one session — the
first two (test sharding, the Gate 41 rebuild) both cost a full cycle. The rule change needs no
parser, which is precisely where the previous attempt died.

## Ground truth — verified directly

| Claim | Verified how |
|---|---|
| CLAUDE.md is platform tier | `docs/blast_radius.yaml:68` |
| A batch was mislabelled IN-FLIGHT | `git merge-base --is-ancestor train-signout-notif-bugs main` → merged; merge `be74bf63` dated 2026-08-10 |
| `post38-auth-fixes` correctly NOT archived | same test → not merged, 3 commits ahead (the check discriminates) |
| Two files named MEMORY.md | `git ls-files memory/` → 6 tracked; repo `memory/MEMORY.md` is a "NOT the live memory index" stub |
| Harness path shape `<mangled>` | `scripts/discipline_hook.dart:155` resolves `$home/.claude/projects/$mangled/memory/MEMORY.md` |
| Three passes × 4 archived lines | read all three retrospectives; 08-03 "3 merges + 4 batch archives", 08-08 "Archived 4", 08-11 "Archived 4" |
| The withdrawn mechanism | `oi-mechanism.closure.yaml` D5; OI-68 at `open_issues.md:1162`; OI-69 open on `OPEN_INDEX.md` |

## Round 1 — self-consistency on the draft

Two P1s. **(1)** The draft claimed a batch sat mislabelled "**weeks**" after merging; it was
**one day** — a false timeline in a governing document. **(2)** It said "MEMORY.md" unqualified
while two files bear that name, and the repo one is a stub created *because* that ambiguity
already caused 3 months of staleness.

## Round 2 — on the corrected text

One P2, and it was **introduced by round 1's own fixes**: the corrections took the row to **12
lines** in a checklist of 1-liners (next longest: 3). Compressed to 10 with the rationale moved
to the retrospective, keeping the rule, the disambiguation and the no-detector warning. No new
material findings beyond that — round-2's single finding was presentational rather than
design-inverting, which is the §4.12.1 signal that the unit has converged rather than needing a
split.

## Verification

Gate 18 `check_doc_internal_consistency.dart` PASS · `check_claude_md_citations.dart` exit 0 ·
`check_no_deferral_euphemism.dart` PASS. Diff scope: `CLAUDE.md` only, one checklist row.
