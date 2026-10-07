---
reviewed_at: 2026-08-30T21:30:00+05:30
staged_against: 6ad3920e
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind subagent)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, same_class_in_the_fix]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — `board-budget` @ `6ad3920e`

Third independent pass on this branch, after two context-blind plan-review rounds.
All five findings **fixed in-batch**; none carried.

**Why this pass earned its keep after two rounds had already run:** rounds 1 and 2 both
read `check_context_artifact_budget.dart` and neither noticed that `--record` executed
*before* the report. The B-pass found it by comparing the gate against the precedent its
own docstring claims to mirror — `check_apk_size_within_bounds.dart` — rather than by
reading it in isolation. **A claim of "modelled on X" is a checkable assertion, and
nobody had checked it.**

## Finding 1 — P0 — process — `docs/plan-reviews/board-budget.md` absent

- **claim:** Platform-tier branch with no plan-review record; `check_plan_review_record_exists.dart`
  fails the build at the merge commit in CI. Two substantive rounds had run and neither was
  captured in the structured form the gate reads.
- **verification:** `find docs/plan-reviews -iname "*board-budget*"`
- **status:** fixed — record written, `review_rounds: 3`, `verdict: converged`, `bpass: accepted`.

## Finding 2 — P1 — guard_without_its_mirror — `--record` could bless a hard breach

- **file:line:** `scripts/check_context_artifact_budget.dart` (record branch, was `:89-106`)
- **claim:** `--record` ran BEFORE the report: no old→new comparison, no drift, no mention of the
  pass/warn/fail already computed. Gate 13 — the gate this one's docstring says it mirrors — puts
  `exit(1)` at `:119` **above** its record step at `:129`, making the branch structurally
  unreachable on a breach. This gate had inverted the one ordering that made the precedent safe.
  Worse than silent: the FAIL path *prints* `--record` as its escape hatch, so an operator tripping
  the newly-added shrink floor would erase the evidence with one paste. The existing e2e only
  exercised a *fresh* baseline, so it shared the blind spot — the same author-model failure lens 6
  had already caught once on this file.
- **verification:** `grep -n "record" test/scripts/context_artifact_budget_e2e_test.dart`
- **status:** fixed — record moved below the report; refuses when any artifact is `fail` unless
  `--force-record`; per-artifact lines now print `old B -> new B (drift)`. Three e2e tests added
  (refusal writes nothing, `--force-record` blesses and still prints the FAIL, ordinary record
  shows the delta).

## Finding 3 — P1 — same_class_in_the_fix — no re-baselining trigger; the gate would decay

- **file:line:** `scripts/check_context_artifact_budget.dart` + `backups/context_artifact_sizes.json`
- **claim:** Cumulative check, globbed into every commit, with nothing defining WHEN to re-baseline —
  no §5 row, no cadence. From 194,850 B the hard block sits ~10–14 days out at the historically
  observed rate, and it blocks **every commit in the repo**, not only board edits. §4.13 point 6
  had to learn this exact lesson ("WHEN — the trigger, without which this is just prose"). Compounded
  by the WARN tier being invisible locally: `pre-commit.sh:368` runs gates as `>/dev/null 2>&1`.
- **verification:** `sed -n '368p' scripts/pre-commit.sh`
- **status:** fixed — §5 checklist row added as the trigger; the local-suppression asymmetry is
  documented in the gate header (CI at `test.yml:264` does *not* suppress, but only runs on
  main/develop pushes and PRs).

## Finding 4 — P2 — same_class_in_the_fix — diagnose-doc citation wrong a THIRD time

- **file:line:** `docs/diagnoses/2026-08-30-context-budget-no-shrink-mirror-d7f3b1.md:19`
- **claim:** Cited `context_budget_lib.dart:171`; the status ternary is at `:183`. It was `162` in
  round 1 (also wrong) and round 2's commit message explicitly claims to have fixed it. Two
  deliberate corrections, both wrong, in the document whose subject is stale citations.
- **verification:** `sed -n '183p' scripts/context_budget_lib.dart`
- **status:** fixed — `:183`. **Mechanism recorded**, because the number alone teaches nothing: each
  citation was captured by grep and then invalidated by a *later edit to the same file in the same
  commit*. A line number read before you finish editing the file is stale by construction. Capture
  citations last, or re-derive them immediately before commit.

## Finding 5 — P2 — same_class_in_the_fix — a retracted number survived in a second file

- **file:line:** `docs/audit/LENS_REGISTRY.md` (L54 row)
- **claim:** Still carried `"in 30 days (~+3,200 tok/day)"` — the exact figure round 2 retracted and
  corrected, but only in `context_budget_lib.dart`. Round 1 and round 2 never revisited this file.
- **verification:** `grep -o "in 30 days ([^)]*)" docs/audit/LENS_REGISTRY.md`
- **status:** fixed — corrected to 31 days / ~9,347 B/day / ~2,600 tok/day, with a note that a number
  restated in a second document gets corrected in neither. A repo-wide sweep found no other live
  copy. The registry's own `Total: 53 lenses` header was stale too and is now 54.

## Verified clean (live, not read)

Regenerated `OPEN_INDEX.md`, `GATE_INDEX.md` and `diagnoses/INDEX.md` from source — all three
byte-identical to the committed copies. `.gitattributes` forces `eol=lf` repo-wide and the working
tree is 0-CRLF for all three tracked artifacts, so the recorded byte baselines hold on a Linux CI
checkout — the specific risk a byte-size baseline invites. Gate absent from both skip-lists, so it
runs unmodified in pre-commit and CI. No script other than the generator/parser pair reads
`OPEN_INDEX.md` row text. Two of five mutation legs reproduced independently (hard growth band → 8
red, shrink floor → 6 red), matching the ledger exactly.

**Reviewer's own near-miss, recorded because it is instructive:** its first blast-radius check used
`--stdin` instead of the literal `-`, silently falling through to the arbitrary-file-args mode —
reproducing `feedback_mistake_blast_radius_positional_mode.md`. Caught before it became a false
finding.

## Founder triage notes

All five accepted and fixed in-batch (§4.2). No finding downgraded, none carried.
