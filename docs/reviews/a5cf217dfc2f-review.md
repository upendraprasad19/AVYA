---
reviewed_at: 2026-10-08
kind: B-pass (2 context-blind seats) + Hermes pass (4 seats) on one working tree, attested against the staged diff
branch: claude/avya-streak-data-check-b506de
slice: C1 (streak-freeze restore ownership, addendum A)
blast_radius: catastrophic
staged_diff_hash: a5cf217dfc2f
verdict: accepted
---

# Review - Slice C1 (migration 156 + the client date merge)

Catastrophic tier by CONTENT: migration 156 replaces the body of the `SECURITY DEFINER` function `update_user_progress_snapshot`. The client half (`UserRepository.laterIsoDate`, `mergeCloudProgress`, the two callers) is `lib/core/**`, account tier.

## What reviewed it

| Artifact | Scope | Result |
|---|---|---|
| B-pass seat A (Sonnet, read-only) | client: `laterIsoDate`, the date branch, kill switches, telemetry, `last_workout_date_latest_wins_behavioral_test.dart` | 0 P0/P1/P2; 2 P3 test gaps |
| B-pass seat B (Sonnet, read-only) | migration draft vs 115, harness copy, SQL cases, text test | 0 P0/P1; 1 P2 (a future date already stored cannot be lowered), 3 P3 |
| Hermes pass (4 Sonnet seats, one wave) | L1, L14, L15/L16/L23, L22/L35 | 0 P0/P1/P2; 6 P3 (all terminal); `docs/audit/2026-10-08-hermes-streak-freeze-c1.md`, `verdict: accepted` |

## Findings and their terminal states

- Seat A P3-1 (a malformed cloud date's `progress_restore_field_malformed` emit untested): FIXED with a test; mutation (emptying the malformed loop in `reportProgressDemotionsDeclined`) reddens it.
- Seat A P3-2 (`istToday` reaching the ceiling through `mergeCloudProgress` untested): FIXED with a test (same rows, two `istToday` values).
- Seat A P3-3, P3-4 (malformed local repaired only when the cloud has a good date; `0000-01-01` counts as well-formed): by design, harmless.
- Seat A P2 (the client ceiling cannot stop a device whose own clock runs ahead): by design; the server clamp is the defence.
- Seat B P2 (a future date already stored): verified clean by a live read-only check, 0 of 32 `user_progress` rows later than IST-today + 1.
- Seat B P3 (weeks can no longer be lowered through the RPC): intended, matches the restore's max-merge.
- Seat B P3 (the harness does not exercise the closing assertion): the assertion ran live, twice (the dry-run and the apply).
- Hermes L14: also checked live (read-only) that `user_progress` has only the freezes range CHECK and `UNIQUE (user_id)`, no triggers, one 13-argument function.
- A coordinator finding while clearing the pre-commit gates: `_isoDayPlusOne` hand-rolled a `YYYY-MM-DD` key (Gate ist-date-key). Replaced with `istDateStr`; all 27 + 130 targeted tests re-run green and `flutter analyze` clean after the change.

## Evidence beyond the reviews

- 20 client mutants (D01-D20) all red against the three test files, files byte-identical after; 5 mutants on the migration text all red.
- A1 dry-run on live (an always-aborting block, nothing persisted): live body md5 equal to migration 115's; the 10 new SQL cases pass on the new body; the old body fails exactly the 4 discriminating cases (lower weeks, older date, both future-date clamps) and passes the 6 controls.
- Applied live 2026-10-08 on the founder's "Go approved": post-apply the body carries both rules, ACL `{postgres, service_role, authenticated}` unchanged, `search_path=public`, `prosecdef`, 13 arguments, one function, the comment preserved, `anon` cannot execute; an anon-key POST of 13 named keys was rejected `42501 permission denied for function update_user_progress_snapshot` (not `PGRST202`); the anon-revoke SQL rows for the snapshot function are all true.
- Gates 14, 39, 40, 11, schema-refs, SoT parity and ist-date-key pass on the staged tree.

## Verdict

accepted. No finding above P3 is open; every P3 has a terminal state above.
