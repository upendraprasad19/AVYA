---
reviewed_at: 2026-11-28T14:00:00+05:30
staged_against: the uncommitted Windows TZ fix on top of 90258e5f (branch oi348-landing3c)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror]
findings_count: 5
verdict: accepted
---

# Code Review: the gate time zone fix (diagnose d0b7e4)

One fresh, context-blind, read-only Sonnet seat on the uncommitted fix. 0 P0, 0 P1, 2 P2, 3 P3. Both P2s were
re-checked by the author before folding (the `sh` env drop reproduced; OI-268 read on the board).

## Finding 1 — P2 — doc overclaim
- **claim:** the diagnose doc said `TZ` "does get through" Git's `sh`, using a `UTC` control. A value with a slash is
  dropped before the native child starts; the control did not generalise.
- **status:** fixed (diagnose doc rewritten; measured with a native `cmd` child).

## Finding 2 — P2 — missed bug history
- **claim:** OI-268 (open, 2026-09-29) already reported the sweep half, with a fix shape and a requested test. The diff
  and doc did not cite it, and the recurrence text dated both pins to c44dfc.
- **status:** fixed (recurrence corrected; OI-268 closed with the outcome; a behaviour test added through the sweep's
  real spawn).

## Finding 3 — P3 — the Linux CI limit
- **claim:** on Linux a default of "not Windows" behaves like the real default, so CI could not see that mutant.
- **status:** fixed (source pin on the default; the limit stated in the doc).

## Finding 4 — P3 — weak sweep pin
- **claim:** the source pin matched only the single-quoted spelling of the variable name.
- **status:** fixed (either quote style; the behaviour test covers what the pin cannot).

## Finding 5 — P3 — stale line cite
- **claim:** `contract_sweep_e2e_test.dart` cited a line number in `contract_sweep.dart` that moved.
- **status:** fixed (line number removed).

## Founder triage notes
None: no finding changes a founder decision.

## Tuning entry
- **2026-11-28** - blast-radius platform - 5 findings; 0 false_alarm; tuning: none. The seat's board search by
  mechanism (the variable, not the script that failed first) found the open issue the author's search missed.
