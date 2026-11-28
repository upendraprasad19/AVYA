---
reviewed_at: 2026-11-28T22:25:00+05:30
branch: oi530-plan-json-measure
review_type: b-pass
blast_radius: platform
reviewer: claude-sonnet-via-agent (one fresh context-blind seat, commit a23e72622eed vs origin/main bde20648)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input]
findings_count: 3
verdict: accepted
---

# B-pass review - OI-530 Landing A (a restore reads the plan bundle once)

Scope: `restore-user-snapshot` (`restore_reads.ts` `deriveWorkoutPlan` + `assembleTables({singlePlanRead})`,
`index.ts` env switch `RESTORE_SINGLE_PLAN_READ_OFF`), the client legacy restores
(`sync_service.dart` `_legacyPlanAndProgressRestores`, kill switch `disable_restore_single_plan_fetch`), the
tests and the registry. Plan: `docs/plans/oi530-landing-a-one-plan-read.md`.

Verdict: no P0/P1. Three P2 registry cites, all verified against `git show origin/main:<file>` and fixed in
this batch.

## Findings + disposition

| # | Sev | Finding | Verified | Disposition |
|---|---|---|---|---|
| 1 | P2 | `docs/sot_registry.yaml` `restore_reads.ts` cites `135-140` (referral_redemptions) and `131-134` (referral_codes) not shifted by the +5 header lines | yes: on main the tuples were at 135-140 / 131-134, now 140-145 / 136-139 | FIXED |
| 2 | P2 | `restore_reads.ts, line: 56` (user_preferences tuple) now points at the `user_profile` read | yes: tuple at 61 | FIXED |
| 3 | P2 | `index.ts` `97-165` handler range not shifted by +2 handler lines | yes: on main 165 was the line before the handler's closing `});` (166); now 167 / 168 | FIXED as 97-167 (the reviewer proposed 168, which would newly include the `});`; kept the old extent) |

Every registry cite of every file in the branch diff was then listed (`sync_service.dart` 60, `index.ts` 2,
`restore_reads.ts` 4); the reviewer had mapped all non-sentinel `sync_service.dart` cites through the four
hunks and found each shifted correctly; the other `index.ts` cite is the `1-9999` sentinel.

## Checked clean (reviewer, re-read by me)
- Exception swallow: the shared fetch is strict; a failure reaches `_safeRestoreOp` for both
  `restore_workout_plan` and `restore_user_progress` (both in `kStreakCriticalRestoreOpTypes`); only the
  `recordNonFatal` reason string changes (plan section 6.5 accepts it).
- Account swap: the row is fetched `.eq('user_id', userId)` with the captured id; `_restoreUserProgress`
  re-checks `ownerChangedSince` before its write. `_restoreWorkoutPlan` has no such guard, unchanged from
  before (the old per-op read and the single-call `preFetched` path had the same shape; the share opens no
  new window).
- Missing input: `deriveWorkoutPlan` matches `select("plan_json").limit(1)` for a missing row, empty list and
  null column; it copies the row, so the `freezes` slot is untouched; the `workout_plan` key keeps its
  position for old clients' `_kSingleCallBundleKeys` check.
- No secret values; no new `unawaited`.

## Mutations (reviewer, sha256-restored after each)
- M1 swallow the shared fetch (`try/catch` returning `[]`): the failed-shared-read marker test reddened.
- M2 drop the `shared ??=` cache: the request-count test reddened.
- M3 disable the kill-switch branch: the switch test reddened.
- `restore_legacy_single_plan_fetch_test.dart` 4/4 and Deno `restore-user-snapshot/` 129/129 green on the
  restored tree.

## Tuning entry
- **2026-11-28** - blast-radius platform - 3 findings; 0 false_alarm; tuning: the registry parity gate only
  checks bounds, so a hand shift of ONE cite in a file leaves its siblings pointing at neighbouring tuples
  (recurrence of the "registry ranges: recompute from anchors, per commit" lesson: I remapped every
  `sync_service.dart` cite through difflib but shifted the TS file's cites by hand). Brief the reviewer with
  the hunk headers of every registry-cited file and ask for a per-cite map; it found all three in one pass.
