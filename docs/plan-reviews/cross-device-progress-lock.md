---
branch: cross-device-progress-lock
date: 2026-07-30
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ba6a334fae4a-review.md
hermes: accepted
hermes_report: docs/audit/2026-07-30-hermes-cross-device-progress-lock.md
---

# Plan review — cross-device-progress-lock

This is Unit 3b of the OI-25/44/45/46/48/50 batch: OI-45's CROSS-DEVICE half (Unit 3a already
closed the same-device half — `docs/plan-reviews/progress-map-consolidation.md`, which names this
unit as its own residual). Migration 056 (2026-05-11) had already built `update_streak_progress`,
an optimistic-lock RPC for the exact race its own header names ("Device A consumes a freeze,
writes available=0 at T1. Device B has a stale read, refills to 2 at T2. Cloud reflects 2, the
consume is silently undone.") — but it sat with ZERO callers for 2.5 months; `SyncService.
syncFreezes` instead pushed the same 4 columns via a raw, version-blind `.upsert()`, the exact
unprotected path the RPC was built to replace. A sibling gap existed for the 11 other
`user_progress` fields `_syncUserProgress` pushes — no RPC existed for those at all. This unit
(1) wires `syncFreezes` to the dormant RPC, (2) adds migration 115's new sibling RPC
(`update_user_progress_snapshot`) for the other 11 fields, sharing ONE whole-row version counter,
and (3) routes all three unprotected writers (`syncFreezes`, `_syncUserProgress`,
`pushOnboardingProgressSnapshot` — a THIRD writer found only by round-1 review) through
version-aware writes with bounded single-retry. Tier is `catastrophic` via
`blast_radius_from_diff.dart`'s content-rule: both RPCs are `SECURITY DEFINER`.

Investigation also found two independent, previously-undiscovered bugs while building the fix,
both caught by live-testing against real Postgres before either shipped: a bare-INSERT fresh-row
branch with no `ON CONFLICT` guard, and a P0-class `p_freezes_last_refill` TEXT-vs-`date` type
mismatch that would 42804 on literally the first real call (this RPC had zero callers until this
batch, so the bug was 100% latent).

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (general-purpose agent), on the first-hardened diff | **PASS.** 1 P0 + 2 P1 + 1 P2 + 1 P3, all independently re-verified by me (not accepted on the reviewer's word) and fixed before round 2 was dispatched. P0: `update_user_progress_snapshot`'s `REVOKE ... FROM PUBLIC` alone left it anon-executable — Supabase's platform grants EXECUTE on new `public`-schema functions DIRECTLY to `anon`/`authenticated`, bypassing `PUBLIC` entirely; reproduced live in a rollback transaction, root-caused via `pg_default_acl`/`pg_proc.proacl`, fixed with an explicit `REVOKE FROM PUBLIC, anon, authenticated`. P1a: a THIRD unprotected writer, `UserRepository.syncOnboardingToSupabase`, missed in the original pass — routed through a new `pushOnboardingProgressSnapshot` method sharing the same RPC + retry helper. P1b: this doc's `restore-user-snapshot` deployment-status claim was wrong (live-queried: v3, ACTIVE, not "not yet deployed") — corrected throughout. P2: fresh-insert branch left 4 schema-defaulted columns un-COALESCE'd, newly reachable by the P1a fix itself — wrapped in `COALESCE(p_x, <default>)`. P3: both retry helpers' early-return paths had no telemetry (later found NOT "effectively unreachable" as first assessed — see Hermes C7). |
| 2 — independent, context-blind (different agent, no memory of round 1), on the round-1-hardened diff | **PASS.** Confirmed all 5 round-1 fixes correct via its OWN independent re-verification (re-ran the P0 grant rollback-transaction test, diffed the live EF source, re-queried `information_schema.columns`, re-ran all 14 SQL cases + 37 Dart tests itself). Found ONE new issue: round-1's own P1a fix inserted a new ~79-line method BEFORE 3 existing SoT-registry-cited methods, shifting each down ~80 lines without `check_sot_registry_parity.dart` catching it — a real blind spot in that gate (proves a cited symbol appears somewhere in its range, not that the range brackets the declaration). Fixed the 4 stale citations; the gate-hardening itself was attempted, found to false-positive 45-80+ times against unrelated pre-existing citation conventions, and spawned as its own separately-scoped follow-up rather than forced through. |
| 3 — independent, context-blind, narrowly re-verifying B-pass round-2's fixes (below), on the round-2-B-pass-hardened diff | **PASS.** 1 real P1 + 1 documentation gap; the other 3 fixes it examined (test rename, `deployments_complete` GREATEST guard, freeze-retry ownership guard) confirmed correct as landed. The P1: round-2 B-pass's OWN fix for the user-progress retry helper's stale-snapshot bug was itself incomplete — an all-or-nothing swap that silently dropped `detected_experience_level` for the onboarding caller (independently re-verified by reading `onboarding_provider.dart:465-528` directly: `saveProgress` writes only 6 fields, never that one, strictly before the sync call). Redesigned as a per-field merge (`SyncService.mergeRpcParamsPreferringNonNull`, `@visibleForTesting`, 6 dedicated behavioral tests incl. the exact regression scenario). The doc gap: this diagnose-doc had no dedicated section for B-pass round-2's own 6 findings, the SQL harness cited a review file that was never written, and test-count citations were stale — all fixed as part of resolving this round's own finding. |

**B-pass round-1** (`docs/reviews/4488c520a021-review.md`, on the round-2-hardened diff): 1 P3
(migration's inline rollback gave only prose, not copy-pasteable SQL, for reverting
`update_streak_progress` — fixed by inlining migration 096's exact body). No functional or
security findings.

**Hermes pass** (11 lenses, `docs/audit/2026-07-30-hermes-cross-device-progress-lock.md`,
required before this record per catastrophic tier): found substantially more than every prior
round combined — 9 of 11 lenses returned REAL or PARTIAL findings, several converging
independently on the same defects from different angles. 0 P0, 7 P1, 11 P2, 8 P3 across 13
clusters (C1-C13). All 12 in-scope clusters fixed in this batch (silently-dropped version stamps,
a same-device race the batch's OWN fix had reproduced, 2 more monotonic-field demotion gaps,
NULL-guard failures on both RPCs' auth checks, 2 more missing ownership guards, silent
un-telemetried drops, a genuine two-session concurrency test, a wrong blast-radius claim in this
doc plus a new EF/RPC field-parity test, and a test-count correction); C13 (a pre-existing,
out-of-scope IDOR in `restore-user-snapshot`'s `template_id` embed) spawned as its own follow-up
task per the established pre-existing-defect carve-out, not silently dropped. Closing status
update appended 2026-07-30 confirming every fix was actually re-verified (full suite + live SQL
harness), not just marked done at triage time.

**B-pass round-2** (dispatched after all Hermes fixes landed; its own report was never persisted
to `docs/reviews/` at the time — a real process gap, itself caught by round 3 above and now fixed
by this record's existence plus the diagnose-doc's reconstructed "B-pass round-2" section): 6
findings — a stale test assertion (Hermes C2's rename not reflected in the wiring test), the
user-progress retry helper missing the SAME fresh-Hive-read fix Hermes C2 gave the freezes side,
`deployments_complete` missing the GREATEST guard its sibling `total_workouts_done` got, the
freeze-retry helper's SEPARATE final write-back missing the ownership guard Hermes C5 gave only
the version-stamp call above it, this diff's undocumented §4.6 feature-flag waiver, and a stale
SoT-registry line-range contradiction. All 6 fixed in the same commit; re-verified via the live
SQL harness (20/20 cases at that point).

**Final B-pass** (`docs/reviews/19eeb84131e2-review.md`, dispatched fresh after round 3's fix
landed, explicitly told not to assume clean despite the extensive prior history): 1 real,
currently-dormant finding — `longest_gap_days` was the only one of 3 "record" fields in the same
UPDATE statement still on bare `COALESCE` rather than `GREATEST` (no live writer populates it
today, confirmed by grep, so not yet exploitable, but fixed to match its two already-fixed
siblings rather than left inconsistent for whenever a future writer starts populating it) — plus
2 investigated-and-confirmed false alarms (a Hive-key naming split that turned out consistent;
the already-tracked `restore-user-snapshot` redeploy gap). Fixed; live-verified 21/21 SQL cases.
This review's own hash-lineage is documented inline in its file: it supersedes an
identically-worded report filed at an earlier hash (`8d5a2f558995`) that predates this same
finding's own fix — re-filed rather than re-reviewed from scratch, since the only diff between
the two hashes IS this finding's own suggested fix applied verbatim plus its regression test,
both independently live-verified.

## Why this is converged rather than merely green

Six independent review passes (3 context-blind rounds, 3 B-pass-class dispatches) plus one
11-lens Hermes deep-pass, and EVERY SINGLE ONE found at least one real, previously-undetected
defect — the strongest possible evidence that this diff genuinely needed all of them, not that
review rounds were run past the point of value. But the trend across them is the real convergence
signal: round 1 found a live P0; Hermes (framed completely differently — lens-based, not
diff-narrative-based) found 12 more REAL issues nothing before it had caught, including bugs
INSIDE round 1's own fixes (the freeze retry helper reproducing, inside this batch's own fix, the
exact same-device race the whole batch exists to close); B-pass round 2 found issues in HERMES's
own fixes (the user-progress side of the exact bug Hermes C2 had just fixed on the freezes side);
round 3 found a bug INSIDE B-pass round 2's own fix (the incomplete all-or-nothing merge); the
final B-pass — dispatched fresh, explicitly warned not to go easy — found exactly ONE real issue,
already dormant, matching a fix pattern already independently reviewed and accepted twice before
in the identical statement, plus two lenses' worth of investigated-and-confirmed-clean findings.
That is the shape §4.12.1 describes as the alternative to splitting: successive rounds keep
finding *smaller and more localized* issues, not larger or more numerous ones — genuine
convergence, not a unit too large to review.

Every fix at every round was verified by re-running the actual tests and the live SQL harness
afterward, never assumed correct from a finding's plausibility: `flutter test` full-suite green
(4020 passed, 0 unexpected failures, 3 skipped — unrelated device-only tests; the sole failure,
`applied_migrations_parity_test.dart`, is the correctly-expected state until migration 115's
separately-authorized live apply) and the live SQL harness at 21/21 `ok` in a rollback transaction
against `dedsavbjuwgarrhphgnl`, both re-confirmed after the LAST fix landed, not just after an
earlier round.

## Ground truth

Verified directly against live code, live Postgres, and live deploy state at every step, never
taken from any round's own prose: the P0 anon-executable grant was reproduced live AND
independently re-derived from `pg_default_acl`/`pg_proc.proacl`, not just asserted; the
`restore-user-snapshot` EF's actual deployment status (v3, ACTIVE) was live-queried, not read from
this doc's own earlier (wrong) claim; the ::date-cast P0 and the ON CONFLICT gap were caught by
running the REAL INSERT against the REAL column types in a rollback transaction, not by reading
the SQL; every SoT-registry citation fix (4 the first time, 6 more the second time) was verified
by direct grep + read against the actual current line numbers, not trusted from any prior round's
count; the round-3 finding was independently re-verified by reading
`onboarding_provider.dart:465-528` directly, confirming `detected_experience_level` genuinely
never reaches Hive's `progress` map for that caller; the final B-pass's dormancy claim
("`p_longest_gap_days` is always NULL today") was independently re-confirmed via
`grep -rn "'longest_gap_days'\]" lib/`, finding zero Hive write sites; every one of the 21 SQL
regression cases was executed live in a rollback transaction against project `dedsavbjuwgarrhphgnl`
at least once after its introducing fix, and the full 21-case set was re-run live after the LAST
fix in this unit, not assumed still-passing from an earlier run.

## Residuals, stated

- **Migration 115 is NOT yet applied.** Written, live-tested (21/21 cases green in a rollback
  transaction), but the actual `apply_migration` call requires its own explicit, separate
  authorization per CLAUDE.md §4.3 — plan/review convergence is not deploy approval, and this
  session's standing autonomous-batch convention does not cover a live prod apply. OI-45 stays
  OPEN until the migration is applied AND the extended `security_definer_anon_revoke.sql` grant
  checks are re-run post-apply to confirm live reality matches intent.
- **`restore-user-snapshot` Edge Function needs an explicit redeploy** (separate action, same
  §4.3 authorization requirement) to carry the freezes-projection fix (4-col → 5-col) live — the
  EF is already live (v3, ACTIVE) and its restore path is attempted by default, so this is a real
  drift, not inert future-proofing, though the client degrades safely in the meantime (traced and
  pinned by `restore_user_snapshot_freezes_projection_parity_test.dart`).
- **Unit 3c** (`graduation_screen.dart`'s narrower stale-`nextPhase` bug, found by Unit 3a's round
  1): not started, needs its own conflict-resolution design.
- **Task #41** (behavioral test for `advanceProPhaseIfExpired`/`_maybeAdvancePhase`'s real
  production callsites, found by Unit 3a's B-pass): not started.
- **`scripts/check_sot_registry_parity.dart`'s stale-range blind spot** (found by this unit's own
  round 2, then re-triggered a 4th time by this unit's own Hermes fixes): the gate proves a cited
  symbol appears SOMEWHERE in its cited range, not that the range brackets the declaration. A
  declaration-proximity hardening was attempted and reverted (45-80+ false positives against
  pre-existing, apparently-deliberate citation conventions this registry uses elsewhere). Spawned
  as its own follow-up task, not silently dropped.
- **L23 Finding 3** (Hermes, pre-existing, untouched by this diff except a header-comment fix):
  `restore-user-snapshot`'s `template:template_id(...)` embed has no user-scope assertion on the
  FK target — no demonstrated live exploit path found, but a real defense-in-depth gap. Spawned
  as its own follow-up task.
