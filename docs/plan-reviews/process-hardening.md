---
branch: process-hardening
date: 2026-08-30
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/2ef6e60d897d-review.md
---

# Plan-review record — process-hardening (platform)

Keystone record for the §4.12 merge gate. Platform tier because
`scripts/_dart_bin.sh` (`blast_radius.yaml:198`), `scripts/_git_lock.sh`,
`scripts/safe_merge.sh` and `CLAUDE.md` are each individually pinned there —
confirmed by running `blast_radius_from_diff.dart` against the staged list
(`platform`), not read off the registry by eye.

## What the branch is

Five process countermeasures, each traceable to a defect in the previous batch
(`profile-phase-fixes`, merged `a7a254b8`), which took 17 review findings —
about half of them mechanical.

1. **Execution guards** on `scripts/_dart_bin.sh` and `scripts/_git_lock.sh`.
   Both define only shell functions, so EXECUTING one was a silent no-op that
   exited 0. That is not hypothetical: `sh scripts/_dart_bin.sh run <script>`
   was used repeatedly on 2026-08-30 and gate/diagnose-doc validations were
   reported as passing on the strength of that exit code.
2. **`safe_merge.sh` advisory precheck** for a `bpass_review:` whose verdict is
   not `accepted` — unfixable after the merge, because CI reads that file AT
   the merge commit.
3. **`skill_tuning_lib.dart`** now accepts the same-day `(x)` disambiguator its
   own SKILL.md convention uses.
4. **CLAUDE.md**: rule 21's mutate-it-and-run-it clause, §4.12 point 5
   (gate loop before review rounds that have a diff), a §4.9 row on extraction
   breaking source-grep contracts in untouched files, two §7 rows.
5. Tests across four files.

## Ground truth verified

Every factual claim was checked by execution, not reading — by me and
independently by all three reviewers:

- The precheck's premise: `git cat-file -e a7a254b8^1:docs/plan-reviews/
  profile-phase-fixes.md` → absent. The record lives on the branch, not main.
- The `recordSlug` port matches `plan_review_record_lib.dart:140-145`,
  including the `origin/origin/x` double-prefix case.
- 5 suffixed `(x)` headers already existed in SKILL.md that the old matcher
  could match none of (old pattern 15 headers, new 20 — a difference of 5).
- The guards fire on every execution form tested and on **no** sourcing form:
  `sh -c '. f'`, dot-source in a function, in a subshell, bash `source`,
  absolute path, and the real five-hook `sh -n` + `.` pattern.
- Full suite **5141 passed / 0 failed**; gate loop green.

## Review rounds

**B-pass** (`docs/reviews/2ef6e60d897d-review.md`) — **3 findings, 0 false
alarms, all fixed.** Two of them were this batch committing the exact classes
it was written to close: the precheck read the WORKING TREE on `main` for a
record that lives on the branch (a no-op guard against no-op guards, whose
three tests passed only because the fixture committed onto `main`), and the
guards were forward-slash-only so `sh 'scripts\_name.sh'` — the dominant
spelling in this environment — sailed past them. Third: raw branch name
instead of `recordSlug()`.

**Round 1** — **6 findings, 3 actionable, all fixed.** The precheck was silent
on the two likeliest operator errors (no `bpass_review:` field; a field naming
an uncommitted file), both of which CI hard-rejects. Two mutation gaps: the
guard's bare-filename pattern arm and the verdict grep's line-anchoring were
each untested, and removing either left every test green. Rule 21's clause also
did not flag itself as self-attested the way rule 24's ledger does.

**Found while fixing round 1, not by any reviewer:** the gate loop blocked this
batch's own honest tuning entry, because `check_skill_tuning_history`'s matcher
required the date immediately closed by `**` and so matched none of the 5
suffixed headers already in the file. The failure shape is a false FAIL that
pushes toward the wrong repair — flatten the date, lose the disambiguation.
Fixed in both regexes; the `anyDatedHeader` half matters more, since a suffix
it cannot see fails to TERMINATE a block, letting one entry be credited with a
neighbour's review.

**Round 2** (on the hardened state, per §4.12.1) — **verdict `converged`, no
P0s, 7 findings, all folded in.** Two were documentation-accuracy misses in
CLAUDE.md itself: a §7 row claiming 4 tests where there are 5 and "reddens
exactly one" where it reddens two (stale within its own batch — a test was
added during remediation and the prose was not re-derived), and rule 21's
clause scoped to "source-grep tests" while every example justifying it is a
BEHAVIORAL test, exempting the exact class its case study indicts. Three were
declared defenses with no test at all — the backslash normalization on both
guards, and `refs/heads/` tag disambiguation — each confirmed by reintroducing
the bug and watching the suite stay green. Plus a nested-paren regex edge case
with both a false-negative and a false-PASS direction, and a benign
shell-vs-Dart parser divergence, recorded in place rather than "fixed" because
it can only fail safe.

## Convergence

Round 2 returned `converged` and explicitly judged its findings not to meet
§4.12.1's split bar: independent of each other, none touching the core
guard/precheck logic, and none carrying the risk that round 1's fixes did. All
seven were folded into this same commit per §4.2. Every fix that could be
mutation-proven was, and each mutation was verified to have actually applied
first — three times this session a mutation silently failed to apply
(a mangled `sed`, a bad Python escape, a regex that hit comment prose instead
of code), and each would have produced a green run readable as proof of
nothing.

## Verification at the point of this record

- `flutter test` — **5141 passed, 0 failed**.
- `sh scripts/pre-commit.sh` — full gate loop, exit 0.
- `sh -n` on all three shell scripts.
- Guards: execute-must-fail (full path, bare filename, backslash) → 64;
  sourcing and `sh -n` → unaffected.
