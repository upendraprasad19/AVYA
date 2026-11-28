---
branch: ci-gate-skip-fix
date: 2026-07-29
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ci-gate-skip-fix-bpass.md
---

# Plan review — ci-gate-skip-fix

A P0: CI's Audit Gates job failed on `96c6fac2` (already merged to `main`)
because `.github/workflows/test.yml`'s "Run all check_*.dart gates" step
bare-invoked `scripts/check_closes_oi_cited.dart`, which requires a
`<commit-msg-file>` argument. `scripts/check_gate_scripts_wired.dart`
(Gate 33 — the check whose entire job is to catch a gate not wired into both
`pre-commit.sh` and `test.yml`) reported PASS on that same commit, because
its dynamic-wiring inference reads absence-from-a-case-skip-block as
presence-in-coverage. Tier is `platform`: the branch touches
`.github/workflows/test.yml`, `scripts/pre-commit.sh` (test-pinned, not
edited), and `scripts/check_gate_scripts_wired.dart`, all categorically
`platform` per `docs/blast_radius.yaml`.

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (general-purpose agent), on `f258f6bd` | **PASS.** 1 P2, 2 P3. P2 (test hand-copied Gate 33's private parsing logic instead of importing it) and one P3 (wrong `§4.3` citation, should be `§7`) fixed in `0a4b4ed1`. The other P3 (an "11 vs 12" count) was missed in that same commit — a real process gap, closed two rounds later. |
| 2 — independent, context-blind (general-purpose agent), on the round-1-hardened branch | **PASS.** 2 P3. Re-caught the still-open "11 vs 12" count (fixed in `99fd20ee`) and confirmed `docs/plan-reviews/ci-gate-skip-fix.md` did not exist yet (expected — this record). No P0/P1 found; both rounds independently reproduced the root cause and the fix end-to-end rather than trusting the diagnose-doc's narrative. |
| B-pass — fresh context-blind (sonnet, `/code-review` skill) | **PASS → accepted.** 1 P1 (this record didn't exist yet — closed by writing it), 1 P3-turned-real (see below). Detail in `docs/reviews/ci-gate-skip-fix-bpass.md`. |

## Why this is converged rather than merely green

The B-pass found something both plan-review rounds missed: the shared
`extractCaseSkips` function (extracted from Gate 33 in response to round 1)
scanned an ENTIRE case arm for script names, including its command body —
not just its pattern list. `check_closes_oi_cited.dart`'s own explanatory
comment restates its filename inside that body, so a future edit deleting
the real case pattern while leaving the comment would have made this fix's
own regression test keep passing. Traced and confirmed: this coincidentally
never affected Gate 33's own PASS/FAIL verdict (a redundant literal mention
elsewhere in the same file protects it), but the new test has no such
redundancy. Fixed by making the parser track each arm's pattern-list
separately from its command body, with a negative control proving the old
logic really did misclassify a comment-only name (extracted verbatim from
`f258f6bd` and run standalone against a synthetic case block).

That is three rounds each catching something the others missed, plus one
process gap (the "11 vs 12" count) that survived TWO rounds because I fixed
only some of a round's findings without re-checking the rest — closed on the
third pass, not silently dropped. What makes this converged, not just green:
every fix after round 1 was verified with a live re-run of the actual gate
and test suite (91-scope Gate 33, 5/5 then 46/46 tests), not assumed correct
from the previous round's confidence.

## Ground truth

Verified directly, not taken from the diagnose-doc's own prose: the pre-fix
`96c6fac2` blobs of `test.yml` and `check_gate_scripts_wired.dart` genuinely
lacked `check_closes_oi_cited.dart` (`git show 96c6fac2:<path> | grep -c`);
`scripts/pre-commit.sh` genuinely already had it; `check_closes_oi_cited.dart`
is the ONLY `scripts/check_*.dart` file requiring a positional CLI argument
(swept all 81, cross-checked against both current skip-lists); the naming
collision in round 1's first draft of the shared library really did push
Gate 33's count from 91 to 92 and really did crash on bare `dart run`
(reproduced live, twice, by two different review rounds); the comment-only
false-positive really was misclassified by the pre-extraction parser
(reproduced live via the extracted `f258f6bd` logic against a synthetic
block).

## Residuals, stated

- A future args-required `check_*.dart` gate still depends on a human
  remembering to skip-list it in both `pre-commit.sh` and `test.yml`, and to
  add it to Gate 33's `_allowList`. Not new — every other `_allowList` entry
  already carries this same reliance. Structurally eliminating it (e.g. a
  script tagged with its own argument-arity, read by both surfaces from one
  place) is a separate, larger change, deliberately not bundled into this
  P0 fix.
- `extractCaseSkips` still assumes each case arm's pattern-list closes with a
  `)` on its own scanned line and each arm ends with a bare `;;` line —
  matches every case block in this repo today (verified against both:
  `pre-commit.sh`'s `$GATE_NAME` and `$REMINDER_TIER` blocks, and `test.yml`'s
  single block), not verified against hypothetical shapes this repo doesn't
  use.
