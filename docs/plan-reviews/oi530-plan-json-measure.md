---
branch: oi530-plan-json-measure
plan: docs/plans/oi530-landing-a-one-plan-read.md
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi530-landing-a-bpass.md
---

# Plan Review — OI-530 Landing A (a restore reads the plan bundle once)

- **Scope of this branch:** Landing A only (`docs/plans/oi530-landing-a-one-plan-read.md`). The wider plan
  `docs/plans/oi530-per-day-schedule-sync.md` (Landings B/C, schedule sync by week row) is committed here as a
  design document; it converged at review round 8 (draft 8) and no B/C code is in this commit range. Split under CLAUDE.md §4.12.1.
- **Blast radius:** `platform` (`scripts/blast_radius_from_diff.dart` over the branch paths).
- **Founder decision:** Option C + the quick win, 2026-11-28. EF deploy needs its own go (§4.3).

## Rounds (context-blind Sonnet reviewers, each verified claims against code; rounds 1-2 also read the live DB, SELECT only)

| Round | Reviewed | Verdict | Landing-A findings | Disposition |
|---|---|---|---|---|
| 1 | whole plan, draft 1 | not converged (2 P0, 8 P1 — B/C) | #8: the EF change is not a one-line edit (READS run concurrently); stripping `plan_json` breaks no client reader (verified) | folded: placeholder slot + pure post-step |
| 2 | whole plan, draft 2 | not converged (7 P1 — B/C) | #6: a post-step append reorders the golden's keys; H-1 header; rollback needs the slot. #8: the lightweight helper swallows a fetch failure to `[]` (would settle the streak marker over an unrestored row); sharing one row list is safe (`Map.from` copy) | folded: placeholder keeps the key position; strict shared fetch, op names kept |
| 3 | Landing A plan only | **converged** (P2 only) | copy before strip (the fake shares row objects); `singlePlanRead` defaults false so every existing test is the rollback mode; timing test per mode; registry range; switch doc; test locations | all folded (plan section 6) |

## Ground truth verified (this session)
- `restore_reads.ts` READS reads `user_progress` `*` (:54-55) and `plan_json` (:68-70); `assembleTables` assigns
  tables by input index; index.ts reads nothing from `user_progress[0]` after assembly.
- Client readers: `_restoreUserProgress` copies then removes `plan_json` (`sync_profile.dart:1105-1124`);
  `_restoreWorkoutPlan` reads only `rows.first['plan_json']` (`sync_workout.dart:1556`).
- Legacy paths: `restoreFromCloud` and `restoreFromCloudForUser` step A each issued two `user_progress` reads.
- Found while building (a test caught it): a PostgREST builder sends a new request every time it is awaited, so a
  cached builder still made two reads; the shared read is an async closure's Future
  (`sync_service.dart` `_legacyPlanAndProgressRestores`).

## Mutations (rule 21)
- EF: (1) issue the skipped request anyway, (2) skip the strip, (3) derive from the wrong table: each reddened
  3 of 25 `restore_reads_test.ts` tests.
- Client: (1) swallow the shared-read error (the marker test reddened), (2) ignore the kill switch (the
  switch test reddened); the builder-caching defect itself reddened the request-count test before the fix.

## B-pass
- `docs/reviews/oi530-landing-a-bpass.md`: one fresh Sonnet seat on `a23e72622eed`; 3 P2 registry cites (the
  TS file's sibling cites not shifted), all fixed; reviewer mutants M1-M3 each reddened a test.

## Deploy (founder go 2026-11-28)
- `restore-user-snapshot` v16 -> v17 at 22:16 IST from `251f4858` (host-shell `emit_payload --auto` +
  `deploy_via_api`, verify_jwt true, 4 files). Before: live v16 decoded files equal `main` `bde20648` (4/4) =
  rollback source. After: decoded v17 files equal `251f4858` (4/4); anon-Bearer boot-verify = the module's own
  401 `{error: unauthenticated}`.
- Real-token check (founder, iPhone Safari, web build 1.0.0+51): two restores, both 200, 240,663 bytes (v16
  restores of the same size class were 333-336 KB), `restore_timings` with no `workout_plan_ms` (the plan read
  is skipped). The first load hung on the splash: telemetry shows a sign-out followed by a fresh OAuth session,
  then `HiveError: Box not found` across restore writers and providers = OI-526 (session close gap), not this
  change (the EF changes only which rows the server reads). A fresh tab loaded Home.
- Rollback: `RESTORE_SINGLE_PLAN_READ_OFF=true` (no redeploy) or `deploy_via_api.js --rollback
  restore-user-snapshot bde20648`.
