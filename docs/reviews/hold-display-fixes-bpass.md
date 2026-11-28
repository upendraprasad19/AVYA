---
reviewed_at: 2026-07-25T14:20:00+05:30
staged_against: 35023903c530
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — hold-display-fixes — 35023903c530

Self-initiated per §4.3 (blast-radius `account`, computed with
`scripts/blast_radius_from_diff.dart`, not assumed). Fresh context-blind Sonnet over the staged diff,
no conversation context passed. Both findings re-verified by the author before acceptance
(`feedback_audit_verifier_cannot_trust_own_subagent`).

## Finding 1 — P0 — process-integrity (gate evasion)
- **file:line:** `docs/audit/hold-display-fixes.closure.yaml:17-18`, `docs/ship_dark_pending_review.yaml` (new entry)
- **claim:** The closure ledger and ship-dark entry cited batch/branch `hold-display-fixes` and review
  docs that did not exist, while the working branch was still `hold-display`. The keystone gate
  `scripts/check_plan_review_record_exists.dart` keys strictly on **branch name**, so at merge it would
  have resolved `docs/plan-reviews/hold-display.md` — which exists from the PREVIOUS batch (`4f4e9518`)
  carrying `review_rounds: 1`, `verdict: converged`, `bpass: accepted`.
- **failure scenario:** The gate goes **green** on an artifact that never reviewed this diff. D1, L1 and
  L3 would merge to `main` with the merge-time review gate satisfied by a prior batch's record. This is
  precisely the anti-fabrication property the gate exists to enforce — defeated by accident, not intent.
- **verification:** `git branch --show-current` → `hold-display`;
  `ls docs/plan-reviews/hold-display-fixes.md` → missing; `ls docs/plan-reviews/hold-display.md` →
  exists. Reviewer traced the branch-name keying in `check_plan_review_record_exists.dart`.
- **resolution:** FIXED. Branch renamed `hold-display` → `hold-display-fixes` so the gate resolves this
  record, and this file + `docs/plan-reviews/hold-display-fixes.md` were written to back the citations.
  Author independently confirmed the branch name and the missing/present files before accepting.
- **status:** accepted

## Finding 2 — P2 — test-coverage (overclaimed regression coverage)
- **file:line:** `test/contracts/hold_display_read_path_test.dart` — the "beyond maxWeek" case
- **claim:** That test passes identically with the L1 fix reverted — a date-week-15 hold is outside
  `completedWeekNumbersFrom`'s `maxWeek: 12` loop regardless of the predicate. It sat beside two genuine
  regression cases, presenting 3-for-3 coverage where only 2 would catch a regression.
- **failure scenario:** A future refactor reverts the `is_hold` exclusion; the group still shows a
  mostly-green shape and the weakened case reads as protection it never provided.
- **verification:** The reviewer **reverted the predicate locally and re-ran** — CONTIGUOUS and
  LATE RETURN failed as expected; the maxWeek case still passed.
- **resolution:** FIXED by honest relabelling rather than deletion or a fake assertion. Renamed to
  `CHARACTERIZATION: a hold beyond maxWeek was never miscounted anyway`, with a comment stating it
  passes with the fix reverted and naming the two cases that actually fail without it. It still earns
  its place: it documents *why* the pre-fix bug was intermittent, which is the fact that made the
  reviewer-mandated date parameterization necessary in the first place.
- **status:** accepted

## Lens coverage (clean lenses, with evidence)

- **writer_reader_drift** — Clean. Traced `is_hold` end to end: sole writer
  `workout_schedule_write_service.dart:287-288` (`holdWeek()`), sole gated call site
  `keep_training_phase1_action.dart:31-34`. Sole production caller of `completedWeekNumbers()` is
  `week_selector.dart:122` (`grep -rn "completedWeekNumbers(" lib/`). Confirmed
  `HoldWeekInfo.isCompleted` (`workout_schedule_read_service.dart:845-846`) is an independent predicate
  via `_holdDatesByOrdinal`/`getScheduleForDate` and never routes through `completedWeekNumbers`, so
  excluding hold rows costs the H-chips nothing. Confirmed the legacy `redoWeek4()` flag-OFF path never
  writes `is_hold`, so **the exclusion is provably inert when the flag is OFF**.
- **function_exception_swallow** — Clean. `git diff --cached | grep -n "functions.invoke\|FunctionException"` → 0.
- **blast_radius_mismatch** — Clean. Recomputed `account`; cross-checked `docs/blast_radius.yaml`
  (`lib/core/services/**` → account; `lib/features/train/**` → feature). Max = account, matches.
- **secrets_in_tree** — Clean. `grep -inE "sk-[a-zA-Z0-9]|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN"` → 0.
- **unawaited_no_error_sink** — Clean. `grep -n "unawaited("` over the diff → 0; no new fire-and-forget.

### Additional verification performed
Ran the suites directly (`hold_display_read_path_test.dart` + `phase_relative_week_label_test.dart` +
`week_completion_check_test.dart`) — all green. Ran
`dart run scripts/validate_audit_closure.dart` → PASS, `closed_count=5` matches 5 terminal entries.
Parsed `ship_dark_pending_review.yaml` with PyYAML → valid; confirmed no script consumes it (it is a
manually-maintained ledger by design). `flutter analyze` on the touched Dart files → no new errors.
**Hand-verified the date-week arithmetic for all three hold-start cases (weeks 5 / 8 / 15) against
`plan_start = 2026-06-01` by direct computation** — all match the tests' own comments.

## Founder triage notes

Both accepted and fixed in-batch (§4.2). The P0 is the notable one: it was not a code defect but a
**discipline-artifact defect that would have silently disarmed the merge gate**. It was catchable only
because the reviewer checked whether the cited files existed rather than assuming the author's own
citations were true — the same class as the dangling test-file citation caught in the previous batch's
B-pass.
