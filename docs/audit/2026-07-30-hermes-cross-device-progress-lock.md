---
hermes_pass_id: 2026-07-30-hermes-cross-device-progress-lock
ran_at: 2026-07-30T14:45:00+05:30
batch_scope: cross-device-progress-lock branch vs main@6258622b (staged working tree)
lens_set: [L1, L11, L14, L15, L22, L23, L27, L34, L35, L37, L39]
agents_dispatched: 11
findings_total: 33
findings_by_severity: { P0: 0, P1: 7, P2: 11, P3: 8, false_alarm_or_clean: 27 }
verdict: accepted
---

# Hermes Pass — cross-device-progress-lock (Unit 3b)

Dispatched after round-1 review, round-2 review, and B-pass all landed clean. This pass
found substantially more than those three passes combined — 9 of 11 lenses returned REAL or
PARTIAL findings, and several converged independently on the *same* underlying defects from
different angles, which is the strongest signal available that they're real rather than lens
noise. Two of the most load-bearing claims were independently re-verified by me (not just
trusted from subagent prose) before this report was written:

- **L35 F2** ("`applied_migrations_parity_test.dart` fails right now") — **confirmed** by
  running `flutter test test/contracts/applied_migrations_parity_test.dart` myself: it fails
  with exactly the claimed message. This is *expected* — migration 115 hasn't been applied yet
  (task #49, gated on explicit go-ahead) — not a new defect. Noted, not "fixed" here.
- **L37 REAL 4** ("37 tests, not 38") — **confirmed** by running the wiring test file myself:
  `00:00 +37: All tests passed!`. The diagnose-doc's stated count is off by one; corrected below.
- **L1-2 / weekly-recalc as a 4th writer** — **confirmed** by reading
  `supabase/functions/weekly-recalc/index.ts:307-341` myself: a raw `.upsert()` on
  `user_progress.total_workouts_done` that never touches `streak_progress_version`, with its
  own `Math.max(recomputed, existing)` guard against demotion from *its own* stale reads, but
  no protection against a *client* resending a stale, lower value through the RPC afterward
  (the RPC's `COALESCE` accepts any non-null value, including a lower one).

## Summary

- **0 P0.** The anon-executable-grant P0 from round-1 stays fixed — 4 lenses (L14, L23, L27,
  and L1 implicitly) independently re-verified it live and it holds.
- **7 P1** — all accepted, fixed in this batch (below). None require a design reversal; all are
  bounded, precedented patterns already used elsewhere in this file/codebase.
- **11 P2** — 9 accepted/fixed in this batch, 1 spawned as a follow-up (pre-existing,
  out-of-diff-scope), 1 folded into an adjacent P1 fix.
- **8 P3** — mix of fixed (cheap, same-file) and documented-as-accepted-residual with reasoning
  (self-healing, narrow window, or genuinely out of scope).
- **Ship-blockers before merge:** none of these are P0, but the P1 cluster (same-device stale
  overwrite reproducing the exact race this batch exists to fix; monotonic-field demotion via
  three independent mechanisms; a silent version-drop reachable on a documented Hive shape) are
  serious enough that I am fixing all of them before proceeding to the plan-review record,
  consistent with §4.2 no-deferrals — none of these are being pushed to a separate future pass;
  they are defects in the diff itself, found before merge, which is exactly what pre-merge review is for.

## Findings by cluster (deduplicated across lenses)

### C1 — `_stampProgressVersion` silently drops the version when Hive `progress` is absent — P1, REAL
**Lenses:** L1 (L1-3), L11 (F3), L34 (Finding 4), L37 (REAL 1) — 4 independent convergences.
`sync_service.dart:2144-2145`: `if (progress == null) return;`. `pushOnboardingProgressSnapshot`
and `_replayPendingOnboardingSync` both explicitly declare this a supported state
(`rawProgress == null ? 0 : …`, `progress == null ? <String,dynamic>{} : …`) — the stamper
disagrees and silently no-ops, so the next writer starts from `expectedVersion = 0` against a
cloud version the server actually advanced, guaranteeing a forced retry with zero signal.
**Triage: fix in batch.**

### C2 — Retry helper writes a pre-await stale Hive snapshot back over fresher local state — P1, REAL
**Lens:** L27 (F1), the single most severe finding in this pass.
`sync_restore_completeness.dart:168-178` (`_retrySyncFreezesOnceAfterConflict`) recomputes
`merged` from `localAvailable`/`localUsed` captured *before* two network round-trips
(`syncFreezes:32-36`), then writes those stale values back into a freshly-read Hive map. A
same-device overlap (routine — 5 call sites fire `unawaited(syncFreezes())`) lets a
`commitConsume()` write land in the gap and then get silently undone by the retry helper,
including erasing a date from the *permanent* used-dates ledger. This reproduces, inside the
fix, the exact class of race the batch exists to close. **Triage: fix in batch.**

### C3 — Monotonic fields can still demote, via three independent mechanisms — P1, REAL
**Lenses:** L1 (L1-2, weekly-recalc 4th writer), L27 (F2, client blind-resend on retry), L22
(F1, `update_streak_progress`'s two NOT NULL freeze columns un-COALESCE'd — separate but
adjacent gap in the same function).
The diagnose-doc's `impact_analysis` claims the lost-update race is closed for all 11 guarded
fields; it is closed for the *version mismatch* case but not for a same-version resend of a
lower value (`COALESCE(p_x, existing)` accepts any non-null value, including a smaller one),
and `weekly-recalc` writes `total_workouts_done` through a path that never touches the version
at all. Per `feedback_monotonic_field_recompute_demotion.md` / diagnose `3a7b9f`, this class
needs an only-increment guard at the write layer, not a client-side assumption.
**Triage: fix in batch** — change `total_workouts_done`'s handling in both RPC UPDATE branches
from `COALESCE(p_x, existing)` to `GREATEST(COALESCE(p_x, existing), existing)`; this closes
the gap regardless of which of the 4 writers races.

### C4 — Cross-account guard fails open on NULL `p_user_id` / NULL `p_expected_version` — P1/P2, REAL
**Lenses:** L23 (Finding 1 — p_user_id; Finding 2 — p_expected_version), L14 (Finding 1 — same),
L27 (F5 — same).
PL/pgSQL `IF <x> <> NULL` evaluates to NULL, which an `IF` treats as false, so both guards
(`auth.uid() IS NOT NULL AND p_user_id <> auth.uid()` and `v_current_version <> p_expected_version`)
silently pass through on a NULL input instead of rejecting. Not reachable from the three shipped
Dart callers today (all coerce to non-null), but the function is `authenticated`-executable by
design (a live PostgREST RPC), so this is a real gap in the function's own contract, not a
theoretical one. **Triage: fix in batch** — explicit `IS NULL` checks added to both guards, both
RPC bodies.

### C5 — Cross-account write via missing userId ownership check in shared-state writers — P2, REAL
**Lens:** L15 (F1-F4), a cohesive single-lens finding.
`_stampProgressVersion` and the freeze-retry helper's Hive write both resolve "whose box is
this" from the *live* session at write time, not from the `userId` the calling method was given,
and both land after 1-2 awaited round-trips. A sign-out/sign-in-as-different-user race inside
that window writes user A's data into user B's box; `GuardedBox` only checks session-vs-box
identity, not payload provenance. Precedent: diagnose `c7d4f6`. **Triage: fix in batch** — thread
`userId` through both write sites and short-circuit (no write) if it no longer matches the live
session owner at write time, mirroring the existing `HiveUserSession` guard pattern.

### C6 — `_stampProgressVersion` is non-monotonic — P2, REAL
**Lens:** L27 (F3). Unconditional `box.put`; three overlapping same-device writers can stamp an
older version over a newer one, burning the single-retry budget silently. **Triage: fix in
batch** — add a monotonic guard (`if (newVersion > existingVersion) write`).

### C7 — Silent, un-telemetried drops on `rawRes == null` — P2, REAL
**Lenses:** L34 (Finding 2), L37 (REAL 2). Two of the three drop paths
(`sync_profile.dart:361`, `sync_restore_completeness.dart:126`) have zero telemetry, while the
sibling `retryVersion == null` drop 11 lines away does. The diagnose-doc's own P3 acceptance of
this ("effectively unreachable") is contradicted by tracing the actual RPC: both RPCs return
NULL for row-absent, so NULL does not prove row-existence, and the state is self-perpetuating
(every subsequent sync silently no-ops forever, since the restore path also leaves it stale).
**Triage: fix in batch** — add `logEvent` calls at both sites; correct the diagnose-doc's P3
framing.

### C8 — New drop-telemetry events ship at LOW priority, inconsistent with the sibling pattern — P2, REAL
**Lens:** L34 (Finding 1). `sync_freezes_retry_dropped` / `sync_user_progress_retry_dropped`
aren't in `highPriorityOpTypes`, so they're silently discarded during exactly the cooldown
window (backend degradation) when they matter most — the same reasoning that already promoted
`streak_freeze_first_pro_grant` / `streak_freeze_lapse_reset` to HIGH three lines away in the
same list. **Triage: fix in batch** — add both new op_types to `highPriorityOpTypes`.

### C9 — `progressData` casts hard-fail instead of degrading, inconsistently within one function — P2, REAL (bounded)
**Lens:** L37 (REAL 3). `pushOnboardingProgressSnapshot` uses `as int?` (throws on a non-int)
where the sibling `_syncUserProgress` in the same file uses the defensive
`(x as num?)?.toInt()` two lines away. The diagnose-doc's claim that `_sanitize` guards this is
inaccurate — `_integerOnlyColumns` contains zero progress fields. All current writers store
`int` today (so PARTIAL on reachability), but the inconsistency is a real, cheap-to-close gap.
**Triage: fix in batch** — align all casts to the defensive pattern.

### C10 — Zero concurrency coverage; all 14 SQL cases run sequentially in one transaction — P2, REAL (test gap)
**Lens:** L27 (F4). The `FOR UPDATE` blocking-and-re-read behavior — the actual mechanism this
whole batch depends on — is asserted by reasoning in this report (verified by reading both
`FOR UPDATE` blocks) but never exercised by two genuinely concurrent sessions. **Triage: fix in
batch** — add a real two-session concurrency test (two overlapping `execute_sql` calls, not
sequential statements in one transaction).

### C11 — `restore-user-snapshot` EF/RPC field-parity has zero test enforcement, and the diagnose-doc's stated blast radius for the drift is wrong — P2, REAL
**Lenses:** L39 (F1 — no test references the EF at all; F3 — not a registered SoT reader).
Separately, **L39 F2** traced the actual restore ordering (`user_progress` restores *before*
`freezes` on both paths) and found the diagnose-doc's claimed failure mode ("`_restoreFreezes`
reads `cloudVersion=null`, falls back to `expectedVersion=0`") **cannot happen** — `_restoreUserProgress`
already carries `streak_progress_version` into Hive first. **Triage:** fix the diagnose-doc's
factually-wrong claim (this batch); add a repo-side (not live-EF-dependent) contract test
pinning the EF's projected column list against the RPC's guarded-field list (this batch) — this
is testable today without needing the EF redeploy that's already tracked as a separate residual.

### C12 — Test count off by one; diagnose-doc says 38, actual is 37 — P3, REAL, confirmed
**Lens:** L37 (REAL 4), independently confirmed by me running the suite. **Triage: fix in batch**
(one-line diagnose-doc correction).

### C13 — `restore-user-snapshot`'s `template_id` embed has no user-scope assertion — P2, REAL, pre-existing
**Lens:** L23 (Finding 3). Confirmed live: the FK embed
(`template:template_id(id, name, workout_type, template_exercises(*))`) is scoped only on the
parent row; nothing constrains `template_id` to a template the caller owns, and the read runs
under `SUPABASE_SERVICE_ROLE_KEY` (RLS bypassed). Requires a victim's template UUID, which
isn't exposed cross-user anywhere found (`cross_owner_rows_today = 0` live). **This function is
untouched by this diff except for its header comment** — the diagnose-doc's own scope is a
`streak_progress_version` optimistic-lock fix, not an EF authorization audit, and this defect
predates the branch. Per this session's own precedent (the SoT-parity-gate hardening spawned
separately from round-2 for the identical reason), this is a genuinely separate, unscoped
defect. **Triage: spawn as a follow-up task, not bundled into this batch.**

## FALSE_ALARM / verified-clean (not re-litigated; evidence is in each lens's raw report)

L1: `updated_at` stamping, Hive singular/plural naming, `progressData` key parity, `as int?`
reachability (superseded by C9's precision framing). L11: EF projection carries the version
(confirmed). L14: the arbiter itself (non-partial UNIQUE, clean), the TOCTOU window (self-heals,
all racing writers touch disjoint columns), the sibling insert-branch NOT NULL exposure
(unreachable from shipped callers, subsumed into C3's precision framing via L22 F1). L22: RPC
parameter-list parity, no payload keys dropped, `syncFreezes`'s pre-existing un-clamped push
(unchanged by this diff), no post-115 column drift. L23: the P0 grant fix (re-confirmed from
scratch), `CREATE OR REPLACE` doesn't spawn a shadow anon-executable overload, `search_path`
hijack not possible, the live EF's own auth guard (re-fetched and re-read). L35: the 4-line
migration header, the exact rollback `DROP FUNCTION` signature, the re-inlined migration-096
body (diffed programmatically — zero drift), old-client compatibility of the replaced RPC. L39:
the `pushOnboardingProgressSnapshot` round-trip on a fresh device (traced end-to-end, clean).

## Action items

- [x] C1 — `_stampProgressVersion`: create the map instead of no-op on absent `progress`.
- [x] C2 — freeze retry helper: stop writing a pre-await stale snapshot back to Hive.
- [x] C3 — `GREATEST`-guard `total_workouts_done` in both RPC UPDATE branches.
- [x] C4 — explicit `IS NULL` checks on both RPC guards (`p_user_id`, `p_expected_version`), both functions.
- [x] C5 — thread `userId` ownership check into `_stampProgressVersion` + freeze retry helper.
- [x] C6 — monotonic guard on `_stampProgressVersion`.
- [x] C7 — telemetry on both silent `rawRes == null` drops; correct diagnose-doc's P3 framing.
- [x] C8 — promote new drop-events to `highPriorityOpTypes`.
- [x] C9 — align `progressData` casts to the defensive pattern.
- [x] C10 — add a genuine two-session concurrency test.
- [x] C11 — fix diagnose-doc's wrong blast-radius claim; add EF/RPC field-parity contract test.
- [x] C12 — correct "38 tests" → "37 tests" in the diagnose-doc.
- [ ] C13 — spawned as a follow-up task (pre-existing, out of this diff's scope): `restore-user-snapshot`'s unscoped `template_id` embed.

## Founder triage

Autonomous batch (per standing "Autonomous auto mode" convention) — no P0 found, so this
proceeds without a pause. All P1/P2 findings fixed in this same batch per §4.2 no-deferrals;
C13 spawned separately per the established pre-existing-defect carve-out. Verdict set to
`accepted` once all `[x]` items above are actually landed and re-verified (not just planned) —
see the end of this document for the closing status update.

## Closing status update (2026-07-30)

All 12 in-scope action items (C1-C12) landed and re-verified, not merely marked `[x]` at
triage time: full `flutter test` re-run after every fix (final run: 4020 passed, 0 failed
beyond the single expected `applied_migrations_parity_test.dart` case pending migration
115's live apply, 3 skipped — unrelated device-only tests), `flutter analyze` clean, and the
live SQL harness re-run in a rollback transaction against `dedsavbjuwgarrhphgnl` after every
SQL-touching fix (final count: 21/21 cases `ok`, including C3's `total_workouts_done`
GREATEST-guard case and its siblings added by later review rounds). C13 remains correctly
spawned as a separate follow-up, not blocking this verdict. Verdict: **accepted**.
