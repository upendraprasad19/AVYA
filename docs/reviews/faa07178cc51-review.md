---
reviewed_at: 2026-11-03T16:00:00+05:30
staged_against: faa07178cc51
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, writer_reader_drift, contract_test_coverage, cross_document_consistency]
findings_count: 3
verdict: accepted
verdict_note: two independent Sonnet seats (round 1 call sites and docs, round 2 Dart SDK sink semantics and board integrity); 0 P0, 0 P1, 3 P3; all three fixed in this batch
---

# Code Review — faa07178cc51

OI-451: the unreachable try/catch in `_out` and `_err` of `scripts/land_pr.dart` is deleted; a source pin and the board move (open to closed) ride along. Both seats returned no P0 or P1.

## Finding 1 — P3 — cross_document_consistency (round 1, residual too narrow)
- **claim:** the closure named only the refused path; every early exit before the `done` handlers are installed is covered by the same residual.
- **status:** accepted — fixed: closure wording widened (closed_issues.md, OI-451).

## Finding 2 — P3 — guard_without_its_mirror (round 2, flush window)
- **claim:** while `_finish` runs `stdout.flush()` the sink is bound (`io_sink.dart` `_isBound`), so a write throws StateError; the deleted catch would have absorbed a late zone-handler write there.
- **status:** accepted — verified in the SDK source; stated as an accepted narrow residual in the `_out` doc comment and the closure (needs a late uncaught async error inside a 2 s window on a broken stdout; the run's exit code path is otherwise unchanged).

## Finding 3 — P3 — contract_test_coverage (both rounds, pin regex)
- **claim:** the pin's `[^}]*` capture stops at the first brace, so a body that grows a nested block would weaken it.
- **status:** accepted — residual: both bodies are one statement; the pin reddens when the catch is restored (mutant run, 1 failure).

## Tuning entry
- **2026-11-03** - blast-radius platform - 3 findings (P3); 0 false_alarm; tuning: none (a reviewer's "unreachable catch" deletion needed the SDK sink source, not only the repo, to find the flush-bound window).
