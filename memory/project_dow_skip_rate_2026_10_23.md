# dow-skip-rate (OI-390, Batch A) — retrospective, 2026-10-23

**What shipped (branch `dow-skip-rate`, uncommitted at time of writing):** `classifyScheduleDay` (one due/done rule),
one anchored IST walk `_eligibleDaysBack` behind `getDayOfWeekCompletionStats` (replaces the rate map) and
`getWorkoutAdherence`; the day-of-week pattern fires only for a singled-out weekday with true counts; a debug-only sim
seam (`simSkipsDay`, dev button "Sim +4 wk, skip Mondays") to seed it on device.

**Process:** plan rev 5 after 4 review rounds (converged); founder approved 2026-10-23 with D3 (stale-claim deletes,
sequenced after the fixed build is on device) and D4 (OI-397 Batch B IST-throughout, OI-398 rolling-context
re-embeds, OI-399 getProgressSummary adherence). T7/T14 use upendra's live rows (read-only SELECT). 18 of 18 mutants
red; one first-run survivor (M7) was a fixture whose second miss sat in the current, partly unwalked week.

**Lessons:** (1) an absent denominator is not 0% (`feedback_absent_denominator_as_zero.md`); (2) a "fabrication" the
coach can quote is a writer bug; (3) when a guard (condition 1) shares a fixture with a stricter guard (condition 3),
check which one is actually holding the result back, or the mutant survives.

**Owed:** commit/push/merge on founder go; on-device check (U6 recipe); D3 deletes after the device step.
