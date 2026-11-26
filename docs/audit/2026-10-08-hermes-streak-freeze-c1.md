---
hermes_pass_id: 2026-10-08-hermes-streak-freeze-c1
ran_at: 2026-10-08T00:10:00+05:30
batch_scope: Slice C1 working tree (uncommitted) plus docs/plans/streak-freeze-restore-ownership-addendum-a.migration-draft-c1.sql
lens_set: [L1, L14, L15, L16, L22, L23, L35]
agents_dispatched: 4
findings_total: 6
findings_by_severity: { P0: 0, P1: 0, P2: 0, P3: 6, false_alarm: 7 }
verdict: accepted
---

# Hermes Pass - Slice C1 (streak-freeze restore ownership)

Catastrophic tier by content (`SECURITY DEFINER` function body replaced). Four Sonnet seats (founder's standing Sonnet-only rule; a recorded deviation from this skill's Opus default), run in one wave of four: L1; L14; L15+L16+L23; L22+L35. No DB access for the seats; the coordinator ran the live read-only checks named below. Preceded by two B-pass seats (client, migration) whose findings are in the diagnose doc `47de4f`.

## Summary
- 0 P0, 0 P1, 0 P2, 6 P3, 7 false_alarm/verified_clean.
- Ship-blockers: none.

## Findings by lens

### L1 - writer/reader drift (seat 1)
Clean. The RPC is the only server writer of the two columns; the two production callers of `mergeCloudProgress` both pass `istToday` and the parameter is `required`; no EF or other upsert writes either column; every reader (`evaluate-rank-promotions`, `streak-guardian`, `proactive-coach-promotion`, `weekly-report`) reads a value that can now only rise, which is the intent.
- P3 (design): a re-onboard sends weeks 0 and a NULL date; the server keeps the old values. Terminal state: `verified_clean` as intended semantics (the client restore was already max-wins for weeks; recorded in the diagnose doc). The test-account reset path is covered: `.claude/skills/reset-test-user/SKILL.md` step 4 enumerates every table with a `user_id`, which includes `user_progress`.

### L14 - schema and constraints (seat 2)
Clean. Types, nullability, the only CHECK (`streak_freezes_available` range), the `UNIQUE (user_id)` arbiter and the absence of triggers all hold. Coordinator live check 2026-10-08 (read-only, project dedsavbjuwgarrhphgnl): constraints on `user_progress` are exactly `user_progress_streak_freezes_available_range` and `user_progress_user_id_unique`; zero non-internal triggers; exactly one `update_user_progress_snapshot` with the 13-argument signature. Closes the seat's only caveat (live objects not created by a migration file).

### L15 / L16 / L23 - restore, cross-account, service-role (seat 3)
No new cross-account or cross-user path. The restore's sink guard (`ownerChangedSince`) and the hydrate's captured box are unchanged and are not weakened; `istToday` is computed in the same synchronous stretch as the guard; the RPC's `auth.uid()` guard is verbatim.
- P3: a device whose clock is two or more days BEHIND IST treats a cloud date equal to real IST-today as beyond its ceiling: malformed, local kept, reported. Fails safe (stale local date, no corruption). Terminal state: `verified_clean`, accepted by design (the ceiling mirrors the server clamp, which is the real defence).
- P3: weeks can no longer be lowered through the RPC. Same as L1's note; intended.

### L22 / L35 - live-apply safety, rollout (seat 4)
No P0-P2. The apply is one `CREATE OR REPLACE` plus one `DO` block in the apply tool's single transaction, so a failing assertion rolls the replace back. The closing assertion fails closed on a NULL ACL, a PUBLIC grant, a dropped role and a wrong arity; collation ordering cannot false-fail. Shipped clients are safe (signature and payload keys unchanged, no PGRST202 window); a main deploy before or after the apply is safe. The literal reverse block diffs to zero lines against migration 115's body, comments stripped (85 lines each).
- P3: if the live ACL has drifted from the asserted set, the block raises and aborts the apply. A safe stop, not a false pass. Terminal state: closed by the plan's pre-apply ACL read (A7 step a) and the dry-run (A1), both run before the apply.
- P3: the dry-run's `auth.users` seeding can fire new-user triggers that collide with the explicit `public.users` seed. Terminal state: closed by the plan's seed-row-count assertions; an abort rolls back.
- Mechanical items for the apply: the preamble delete range is lines 1-6 up to the `END OF DRAFT PREAMBLE` marker (the Intent/Destructive/Rollback/Linked headers stay), and the `<6hex>` placeholder becomes `47de4f`.

## Founder triage
Verdict: accepted (no finding above P3; every P3 has a terminal state above).

## Action items
- [x] re-onboard keeps old weeks/date: verified_clean (intended; reset-test-user covers `user_progress`).
- [x] clock-behind device: verified_clean (fails safe, by design).
- [x] live ACL drift could abort the apply: closed by the pre-apply ACL read and the A1 dry-run (run before the apply).
- [x] dry-run seed trigger collision: closed by the seed-row-count assertions.
- [x] preamble strip range and diagnose id placeholder: mechanical, done at the strip step.
- [x] live objects invisible to file review: closed by the coordinator's live `pg_constraint` / `pg_trigger` / function-count query (2026-10-08).
