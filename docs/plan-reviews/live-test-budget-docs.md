---
branch: live-test-budget-docs
date: 2026-09-07
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0acbed4f3155-review.md
---

# Plan-review record — the §5 documentation owed by the T19 timeout fix (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart CLAUDE.md
.claude/skills/debugging/SKILL.md docs/audit/open_issues.md docs/audit/OPEN_INDEX.md` →
`platform`, driven by the CLAUDE.md edit. Args mode, not stdin: piping paths WITHOUT a trailing
`-` silently classifies the STAGED set instead and returns `feature` for everything.

## What this branch is

Documentation only — no code, no schema, no Edge Function. It closes the §5 rows owed by the
preceding fix (diagnose `a7c3e9`, merged `aebc097d`, CI green):

1. **CLAUDE.md §4.9** — the `@Timeout` row defined its own class as *"spawns a subprocess"*, which
   is precisely why nobody applied it to a live network call. Widened, and the row title too.
2. **`.claude/skills/debugging/SKILL.md`** — new bug class **2.63** (a test bounded by something it
   does not control; plus the green-run-that-ran-nothing half), and a guard in the §2 header.
3. **OI-167** — nine duplicated bug-class numbers in that skill, found by nearly minting a tenth.

Per §4.3 a docs/process-only ≥account change takes a **self-consistency review of the wording**
rather than an adversarial bug-hunt. That is the standard applied.

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Self-review while authoring | 3 — a mangled line-continuation in the guard's own prescribed command; an OI-max survey that missed `# OI-` single-hash headings; and a **bug-class number collision I had just created** |
| 2 | **Context-blind B-pass** (`docs/reviews/0acbed4f3155-review.md`) | **6 — 0 P0, 2 P1, 3 P2, 1 P3; 0 false alarms** |
| 3 | Independent re-derivation of all 6 | every finding confirmed; one of my own corrections found to still be wrong |

**Converged at round 3**: round 3 produced no NEW defect classes — it confirmed round 2 and
tightened one number. Per §4.12.1 the split signal is *successive rounds surfacing new material
issues*; that did not occur here.

## Ground truth

Every numeric claim in the shipped text was re-derived from the files by the author, not taken
from the reviewer's prose (the standing rule: subagent numeric claims are unverified until
checked). All six findings held. The verification also **corrected the reviewer in one place and
was itself corrected in another** — see below.

- duplicated numbers: `grep -oE '^### 2\.[0-9]+' … | sort -n | uniq -d` → **9** (36–41, 53–55)
- true max: **2.63**; the prescribed guard command returns `63` staged, `62` at HEAD
- `build_oi_index.dart` quote: line **110**, not 114-115
- OI-167 free across BOTH boards at every heading level; index regenerates to 86 open
- `grep -c "Process\.\(run\|start\)" test/edge_functions/ai_proxy_test.dart` → **0**

## The two findings worth carrying forward

**A filter narrower than the thing being counted returns zero and looks like proof.** My census
of "which bug-class numbers are cited elsewhere" filtered to lines also containing
`bug.?class|debugging skill`. Most real citations say no such thing — one reads
`2.36 (FunctionException not unpacked → masked errors)` — so the census returned zero for five
numbers, and OI-167 declared them *"mechanically safe to renumber"*. Unfiltered: **all nine are
cited.** The zero came from the filter, not the world, and it was sitting in a `Verified:` field,
which is what makes it dangerous — it looks audited. ⚠ I then partially corrected the reviewer,
saying 2.36 was uncited; **it was right and I was wrong**, because I re-ran the same narrow
filter. The finding is not just "the filter was narrow" but that I reached for it twice.

**A citation derived against the pre-edit file is invalidated by the edit that ships it.** OI-167
cited exact line numbers in the very file the diff modifies; the 17-line header block this diff
inserts pushed every one down by 17. Correct when derived, wrong when committed, and no gate
catches it. Fixed by dropping the line numbers for section identity — they would rot again on the
next edit regardless.

## Known residue, stated rather than left

`build_oi_index.dart:114-115` is still cited staleley in **CLAUDE.md §7's** "OI number uniqueness"
row — the source my wrong citation was copied from. Outside this diff's four files; recorded in
the review's Finding 5 so it is not lost.
