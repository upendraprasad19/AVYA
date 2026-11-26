---
branch: oi50-exlog-aggregate-read
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/6d0855844893-review.md
hermes_report: not_required
---

# Plan review — `oi50-exlog-aggregate-read`

Unit 7 of the OI-25/44/45/46/48/50 batch. **Closes OI-50.** Diagnose `d4e7c2`.

## Tier

Measured on the actual staged set, after the LAST edit:

```
git status --porcelain | sed 's/^...//' | dart run scripts/blast_radius_from_diff.dart -
→ account
```

`account` comes from `lib/core/services/workout_read_service.dart`; every
`lib/features/train/**` file in the diff is individually `feature`. The trailing
`-` is load-bearing — without it the script reads its own empty staged diff.

Re-measured three times, because the changed set grew twice (round 1 added three
train files, round 2 added `workout_repository.dart`, the B-pass added
`train_provider.dart`). The tier never moved off `account`.

## Ground truth verified

Every load-bearing claim checked against the artifact, not against prose:

- The restore writer's field subset — read `sync/sync_workout.dart:733-767`
  directly: `set_number` at `:763`, top-level `duration_seconds` at `:766`,
  `sets[]` written only inside the `:777` non-empty-join guard.
- The modern writer emits no top-level `duration_seconds` on exlog rows — the
  `:477` occurrence is on the `wlog_*` row, confirmed by reading the enclosing
  map's `'type': 'workout_log'`.
- `hive_field_rename_migrator.dart` does NOT backfill `sets_completed` — the
  pair appears only in a commented-out usage example (`:25-31`), so nothing
  self-heals these rows.
- Both refuted hypotheses (below) tested, not argued.
- Every behavioral assertion proven by negative control.

## Round 1 — 6 findings

Full table in the diagnose-doc. The consequential one, **F1, was that my scope
was wrong**: I had claimed "two readers"; there were five, and the fix as first
written left three broken. `lib/features/train/CLAUDE.md` had already been
edited to assert "two readers each rolled their own" — an overclaim that would
have shipped as documentation.

F2 was a gate whose failure message recommended the exact call that causes this
bug (`bestPerSetDuration` for a total). F3 caught that my `_perSetList` used
null-coalescing where the code it replaced measured both arrays — so my own
in-code comment "Semantics unchanged" was false.

## Round 2 — 4 findings, ALL round-1 regressions

Run on the hardened diff with the reviewer told explicitly that its primary job
was to attack round 1's corrections. It found **nothing wrong with the original
work** — every material finding traced to a round-1 fix:

- a **sixth** reader the round-1 sweep missed (`workout_repository.dart:941`,
  feeding the AI coach);
- my round-1 fix made `expanded_exercises.dart` render a **total** under the
  label "best";
- my round-1 `hasAggregateDuration` guard made a duration **permanently
  un-clearable** on rows carrying both per-set durations and a top-level total;
- round 1's own numeric corrections were still wrong in four places.

I declined one round-2 recommendation: routing `workout_repository.dart:978`
through `aggregateSetCount` as well. That site reads the legacy EMBEDDED
`exercise_logs` shape where `sets` is a **scalar**, so the helper (which treats
`sets` as a List) would have introduced a new bug.

## B-pass — accepted

5 findings, all fixed pre-merge. Record: `docs/reviews/6d0855844893-review.md`.
The P1 was a **seventh** reader (`train_provider.dart:1556`) — the PR-banner
divisor collapses to 0 on the APK Test #12.1 shape and silently suppresses a
genuine PR. I had explicitly told the reviewer to assume a seventh existed,
because the count had already moved twice.

## Convergence

| | P0/P1 | P2 | P3 | new defects in the ORIGINAL work |
|---|---|---|---|---|
| Round 1 | 2 | 3 | 1 | 6 |
| Round 2 | 1 | 2 | 1 | **0** — all traced to round-1 fixes |
| B-pass | 1 | 1 | 3 | 1 (the seventh reader) |

Severity is decreasing and round 2 found nothing new in the original work.
The B-pass P1 is one more instance of the SAME defect class already being fixed,
found by widening the sweep — not a new kind of problem, and it was a two-line
change. **Verdict: converged.**

The honest caveat, written into `lib/features/train/CLAUDE.md` itself: the
reader count went 2 → 5 → 6 → 7 across three rounds. Anyone trusting that
sentence should grep before relying on it.

## Not a §4.12.1 "split it" signal

Successive rounds surfacing *new material issues in the original work* is the
split signal. That is not this shape: rounds 2 and 3 found (a) regressions from
round 1's own corrections and (b) more instances of the one defect class the
unit exists to close. Splitting would have shipped a fix that left four of seven
readers broken — strictly worse.

## Feature-flag

`account` tier does not require one, and the founder explicitly chose to ship
live unflagged: today's output is simply wrong (a rendered 0 where real data
exists), there is no correct old behaviour to preserve, and a switch whose only
effect is to restore a zero is not a safety valve. Same reasoning as Unit 3c's
monotonic guard.

## Process finding

The round-2 reviewer ran its own gate negative control by injecting a violation
into `week_selector.dart` and then "reverting" it — which restored that file to
git HEAD and **silently wiped this batch's edit to it**. Caught only because a
later grep for the citation line returned nothing; `git status` still looked
plausible. A read-only reviewer that writes to the tree can destroy work. The
B-pass brief was amended to forbid any file modification, and every subsequent
claim was re-verified against the tree rather than the review report.
