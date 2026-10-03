---
hermes_pass_id: 2026-06-29-hermes-opt-h-restore-marker
ran_at: 2026-06-29T21:10:00+05:30
batch_scope: working-tree (branch opt-h-restore-marker, staged)
lens_set: [L1, L11, L15, completeness-critic]
agents_dispatched: 4
findings_total: 8
findings_by_severity: { P0: 0, P1: 2, P2: 5, false_alarm: 1 }
verdict: block_ship
---

# Hermes Pass — opt-h-restore-marker

## Summary

The marker MECHANISM is correctly built — all four lenses confirm: no writer/reader
drift (L1 clean), no cross-account leak (L15: shared-key + in-blob-owner is sound +
fail-safe), the tally captures every op + excludes sub-refresh, and the B-pass P0
(background path stamping the marker) is fixed. **But the `healthy → restoreLightweightAlways`
SKIP is too aggressive, and the feature's value proposition does not survive scrutiny.**
Two compounding realizations (verified by the orchestrator against code):

1. **The "partial-restore-never-heals bug" it claims to fix does not exist.** The gated
   `restoreFromCloudForUser` runs the FULL restore on EVERY returning login (in the
   background, c5a1f2 — `restoring_screen.dart:212`). A partial restore therefore
   self-heals next login. The marker is an **optimization** (skip the redundant
   re-fetch), not a bug-fix — the diagnose-doc misframes it.
2. **The skip drops freshness the every-login full restore was quietly providing** — and
   the perceived-speed benefit is ~nil because c5a1f2 already renders /home instantly
   (the full restore was already backgrounded). So the skip trades real
   freshness/correctness for a background-egress saving the user never perceives.

## Findings

### L1 — writer/reader drift — CLEAN
Marker `toMap`↔`tryParse` keys symmetric; owner identity identical on both sides
(`userId == HiveUserSession._currentOwnerFullId`); `version` int pinned through a real
Hive round-trip; no bypass reader of `restore_complete`. Note (not a bug): `completed_at`
is forensic-only (no reader uses it for a decision).

### P1-A (critic F1 + L11) — healthy-skip drops the freeze max-merge
`restoreLightweightAlways` (the entire healthy-skip body) pulls `_restoreUserProgress`
(SELECT * cloud-wins overwrite) but NOT `_restoreFreezes` — the refill-aware
`mergeFreezeProgress` that unions the permanent `used_dates` ledger + clamps available
0..3 + never regresses `first_pro_grant_done` (ADR-0014 / c5a1f2 / f9d2e7). Compounded by
a key-name drift: the Hive ledger is `streak_freeze_used_dates` (singular); the cloud
column is `streak_freezes_used_dates` (plural). `_restoreUserProgress` writes cloud names
verbatim → a dead plural key; the singular ledger is refreshed ONLY by `_restoreFreezes`,
which the skip never runs. A freeze consumed locally in the slow-boot /home window (the
exact case the union was built to protect) is no longer protected on the skip path.
**Verified:** freeze keys (grep), `_restoreFreezes` absent from `restoreLightweightAlways`.

### P1-B (L11 + critic F2) — cron/server-written surfaces go stale on a healthy single device
The every-login full restore was the client's only pull for SERVER-written surfaces.
A healthy-skip runs only lightweight, so these never refresh until a marker-invalidating
event: **rank_promotions** (the `evaluate-rank-promotions` cron writes `user_profile.current_rank_code`
— pulled by lightweight — AND appends `rank_promotions` history — Step-C, skipped → the
promotion-history list / "you got promoted" celebration strands), **notifications_inbox**
(re-engagement/plateau/expiry crons insert rows), **saved_diet_plan**, **streaks**.
Severity P1 for rank (retention-critical celebration); P2 for the rest.

### P2 (critic F4) — marker-healthy doesn't cross-check data-present
The marker proves "this owner completed a restore at version 1" but NOT "the data is still
present". `syncBox` is shared + never cleared on swap/`clearAllData`; if a user-scoped box
is wiped (Hive corruption recovery) while syncBox survives, the skip runs only lightweight
→ empty Home, healthy marker, next login skips again. The silent-permanent-gap the marker
was meant to kill, via a different wipe vector. No reader cross-checks marker-healthy
against `hasLocalData`.

### P2 (L15 ×3) — robustness/doc
- Shared-key marker is a deliberate exception to the `wrapUserScopedBox` rule (doc note).
- No swap-time restore cancellation (pre-existing; no leak — owner re-assert + in-blob tag protect).
- Marker can outlive a DPDP account-delete (delete wipes user boxes, not the shared syncBox marker; low-likelihood given Supabase uid semantics; cheap `clearRestoreMarker` on the delete path closes it).

### FALSE_ALARM (critic F3) — fresh-install dual-path race
`_restoreIfNeeded` still uses the OLD `hasLocalData` heuristic, never reads the marker;
`restoreFromCloud` never writes it; a fresh syncBox → `missing` → full restore. The two
heuristics coexist without harmful disagreement.

## Verdict: block_ship — needs a founder decision

The mechanism is sound; the FEATURE is the problem. The skip (a) fixes a non-existent bug,
(b) delivers ~no perceived speed (c5a1f2 already instant), (c) costs real freshness
(P1-A freeze merge, P1-B rank/inbox/diet/streaks) + corruption-resilience (P2 F4). The
legitimate goal it gestures at — reduce the redundant every-login re-fetch (real egress at
scale) — is the job of a proper DELTA restore (the deferred Unit 2 / server-clock), NOT an
all-or-nothing skip.

## Options (founder decision)
- **A — Abandon Unit 1** (revert the branch). Keep the every-login background full restore
  (correct + fresh + self-healing; instant home already). Recommended. Preserve the
  learnings (created_at-is-insert-time; asymmetric-path marker trap; the cron-pull
  dependency) in memory; the egress optimization, if wanted, is Unit 2 done properly.
- **B — Salvage via narrowing the skip:** healthy-skip runs lightweight + `_restoreFreezes`
  + the Step-C completeness surfaces + a `hasLocalData` cross-check + clear-marker-on-delete,
  skipping ONLY the expensive bulk-history Step B. Fixes every finding but is fragile
  (each new surface must be classified skip-able vs must-refresh) for a benefit the user
  doesn't perceive.

## Action items
- [ ] Founder: choose A (abandon) or B (narrow-skip).
- [ ] Either way: the diagnose-doc's "bug-fix" framing must be corrected to "optimization".
