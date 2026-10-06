---
branch: ops-alerting-b2a2a
date: 2026-09-27
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/46c9b9ff3bde-review.md
---

# Plan-review record — Unit B2a-2a: alert_client_errors_spike breadth/offline-noise rewrite (migration 147)

Keystone record for the §4.12 merge gate. Platform tier (no `SECURITY DEFINER`,
classified on the written migration file) ⇒ ×2 review + a B-pass; no Hermes.
Diagnose doc: `docs/diagnoses/2026-09-27-alert-client-errors-spike-filter-drift-recurrence-d2c9f4.md`
(bug id `d2c9f4`). Recurrence of the 2026-06-06 spike-filter-drift class
(diagnose `f0b9d3`).

## Rounds 1-2 (converged pre-drafted-diff)

Established the design against live `client_errors` / `ops_alerts_30min`
(jobid 43, migration 143's body): count DISTINCT (user, message-prefix,
second) moments instead of raw rows; exclude a named offline-noise regex
signature with an explicit never-offline override for real HTTP statuses and
four server-answered exception types (offline-caused client TIMEOUTS
deliberately stay counted — undercounting a real incident is worse); add a
per-user breadth arm and a server-error-class breadth arm, both scoped to
exception-shaped rows (`error_code NOT IN ('event','info')`) to exclude the
routine `subscription_refresh_query_returned_null` breadcrumb; unify all three
arms into one parenthesized fire condition and one `severity_rank` reused for
both the emitted severity and a new rank-based dedup. Both rounds converged
against the design before the diff was drafted; no material findings carried
forward.

## Round 3 — drafted-diff review (converged, 2 findings, both fixed)

Dispatched per §4.12.5 once the migration + all three contract test files
were drafted and the local gate loop had been run.

- **P1 (`feedback_green_check_input_set_width` class):** the new
  `ops_alerts_spike_breadth_test.dart`'s server-error-class-arm guard
  assertion used a fixed 400-char lookback window before `AS server_events`
  that bled 72 chars into the adjacent, textually-similar `users`-arm clause —
  so a mutation removing JUST the server_events arm's own exception-shaped
  guard left the assertion green (the users arm's guard, still present,
  satisfied the same substring window). Fixed by replacing the windowed
  substring check with an exact whole-literal match of the full column
  definition. Mutation-proven: removing only the server_events guard now
  reddens exactly that 1 test (confirmed by the reviewer's own mutation,
  re-run after the fix).
- **P2 (stale citation):** the diagnose doc claimed
  `alert_thresholds_sync_test.dart` was "8/8" green — a copy-paste from the
  neighboring `alert_cron_failures_sync_test.dart` line (correctly 8/8). The
  actual count is 4 (`grep -c "^  test(" test/contracts/alert_thresholds_sync_test.dart`).
  Fixed in both locations in the diagnose doc.

Also independently re-verified during this round: the `lib/core/services/subscription_service.dart:911-912`
citation (an earlier stale path,
`lib/features/profile/services/subscription_service.dart:905-914`, had
already been caught and corrected before this round); the live 36-day replay
numbers (8 firing ticks, 4 real incidents, all via the `server_events >= 3`
arm); the offline-signature override counts (770/6199 offline-shaped, 0
overridden, override regexes independently matching 8/66 live rows — not
vacuous).

## Self-triggered B-pass (`docs/reviews/46c9b9ff3bde-review.md`) — accepted

Dispatched against the full staged diff before the merge, per §4.3's
self-initiation requirement. 1 finding:

- **P1 (`guard_without_its_mirror`):** `cnt` — the primary threshold-gated
  metric — does NOT get the `error_code NOT IN ('event','info')` guard the
  new `users`/`server_events` arms explicitly get, even though this same
  migration's own header names the exact breadcrumb
  (`subscription_refresh_query_returned_null`) that motivated adding the
  guard to the other two arms. Independently re-verified live by the
  coordinator, matching the reviewer's exact numbers: 28 occurrences of the
  named breadcrumb over 36 days (41 total across every event/info-coded
  op_type matching the outer breadcrumb-reinclusion regex); non-material
  today (`max(cnt) = 24` vs the 40 floor).

  **Resolution — not a SQL fix.** Two SQL-only fixes were considered and
  rejected: narrowing `cnt` to match the other arms would regress migration
  087/f0b9d3's own P0 fix (catching genuine failures the client mislabels
  `error_code='event'`); a name-based exclusion for this one op_type is
  exactly the "transient denylist" pattern diagnose `f0b9d3` already rejected,
  since the same client-side mislabeling recurs under ~25 other op_types. The
  real fix — renaming the client call site's op_type so it stops matching the
  failure-reinclusion regex — is a `lib/` change naturally in scope for the
  next unit in this batch (B2a-2b, client telemetry), not this pure-SQL
  migration. Filed **OI-254**, documented in the migration's own header
  comment, the diagnose doc (3 locations), and this review file's finding
  status. Added and mutation-proved a new pinning test asserting `cnt`'s
  column definition carries no `FILTER` clause, so a future silent narrowing
  or widening on either side of this asymmetry is caught.

Skill self-evolution: `.claude/skills/code-review/SKILL.md` Tuning history
gets a same-dated entry (2026-09-27) describing the finding and its lesson —
a fix that hardens two new arms against a named noise source while leaving
the pre-existing primary metric exposed is easy to miss because the diagnose
doc's own narrative frames the breadcrumb problem as solved.

## Regression tests

- `test/contracts/ops_alerts_spike_breadth_test.dart` (new, 11 tests) — 5
  mutation experiments across the batch (parenthesization removal, dedup-rank
  degradation, the P1 window-bleed fix, the OI-254 pinning test, and the
  round-3 reviewer's own re-run), each reddening exactly 1 expected test.
- `test/contracts/alert_thresholds_sync_test.dart` (rewritten, 4 tests).
- `test/contracts/alert_cron_failures_sync_test.dart` (8 tests, unchanged
  count, 1 assertion widened to accept `cron.alter_job(`).

## Ground truth

Every live fact (job body, 36-day replay, offline-signature counts, the
breadcrumb occurrence counts) re-derived read-only on project
`dedsavbjuwgarrhphgnl` by the coordinator and independently by round 3 and
the B-pass. Migration 147 was applied live on 2026-09-27 with explicit
founder authorization in chat ("go ahead"), separate from plan approval, per
§4.3 — a harness-level Auto Mode Production-Deploy classifier denied the
first attempt and cleared on an identical retry per the founder's direct
request to re-check. Post-apply live verification: `cron.job` shows jobid 43
(unchanged), schedule `*/30 * * * *` (unchanged), active=true, command body
byte-matching the new design.
