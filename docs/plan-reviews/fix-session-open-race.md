---
branch: fix-session-open-race
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/fix-session-open-race-bpass.md
hermes: accepted
hermes_report: docs/audit/2026-06-21-hermes-fix-session-open-race.md
---

# Plan-review record — fix-session-open-race (b8e3f1)

§4.12 plan-review record for FIX-1 of the full-charter E2E fix-batch. Enforced by
`scripts/check_plan_review_record_exists.dart` at the merge-to-main commit (CI).

**Spec / plan:** `~/.claude/plans/lets-tackle-them-all-delightful-cascade.md`
(E2E fix-batch — §4.12 ×5 review → CONVERGED → SPLIT → ship FIX-1 alone).
**Evidence:** `docs/reviews/e2e-fullcharter-2026-06-21-evidence.md`.
**Diagnose:** `docs/diagnoses/2026-06-21-session-open-race-blank-home-b8e3f1.md`.

**Origin:** the full-charter web E2E walk (2026-06-21, test2) surfaced OBS-6 —
in-session sign-out → sign-in as a different user → **blank Home** (app-unusable),
plus a cold-boot deep-link "Something went wrong". The founder ordered the fix
plan reviewed ×2 with loophole-hunting; successive rounds kept finding material
issues, so the review ran to FIVE rounds, then SPLIT to ship only the smallest
converged piece (FIX-1, the sole app-unusable bug).

## Reviews (independent, context-blind) — 5 rounds
- **R1 (3 agents, correctness)** — killed "serve empty" *as written* (rejected as
  masking) and found "openForUser-on-sign-in" already shipped (FIX-3).
- **R2 (1 agent, hardened-plan correctness)** — confirmed the router-guard
  direction; demoted OBS-8a/8b out of FIX-1.
- **R3 (2 agents, regression / "must not break anything else")** — found the naive
  router guard BREAKS the CONTINUE escape (infinite loop) + loses induction
  deep-links; and that FIX-3 risks the just-shipped streak rework. → induction/muster
  exemption + continue-override added.
- **R4 (deep root-cause trace + ground-truth reads)** — **corrected the root
  cause**: rounds 1-3 mis-diagnosed OBS-6 as a routing bug; it is a
  **provider-rebuild race** against `wrapUserScopedBox`'s null-owner throw
  (`guarded_box.dart:292`), with NO route change. FIX-1 became two-layer (Part A
  serve-empty for the race + Part B router guard for cold-boot/mis-route).
- **R5 (minimal-unit safety)** — scoped to FIX-1 Part A, found NO new blocker;
  CONFIRMED safety by reading the actual `GuardedBox` write behavior (reads empty,
  writes THROW, namespacing isolates). Per §4.12 anti-5th-review → STOP reviewing,
  build test-first.

## Ground-truth audit (verified, not asserted)
Read directly (not via subagent prose): `guarded_box.dart` (`:235` disagreement
requires owner≠null; `:292` throw on owner==null; empty-stub read/write surfaces),
`app_router.dart` `_authRedirect` (full branch order), `auth_invalidation_provider.dart`
(`:50` emits `'<anon>'` when hiveOwner==null), `home_provider.dart:509`
(TodayWorkoutNotifier watches the token then reads workoutBox), `restoring_screen.dart`
(`_onContinueAnyway`, `_goHome`, `_kickoffRestore`), `induction_service.dart`
(`:33/:38` already null-owner-guarded → symptom (b) redirect read does NOT throw on
main → Part A covers any residual screen-read), `hive_user_session.dart` (listenable
under `_sessionLock`). Caught what rounds 1-3 missed (provider race, not routing) and
that the StartMissionBrief/onboarding paths needed the guard exemption.

## Verdict
Five rounds converged → SPLIT → ship FIX-1 (Part A + Part B) test-first. Per §4.12
anti-5th-review, the next verification was BUILDING it: a RED behavioral test
reproducing the provider-race throw (`guarded_box.dart:292`) → GREEN with serve-empty.

**bpass: accepted** — fresh context-blind Sonnet B-pass (5 lenses) + the 4 Hermes
lenses surfaced 6 findings; 3 fixed in-batch (P1 `_onContinueAnyway` telemetry; P1
§4.6 kill-switch on the platform-tier guard; P2 RangeError guard), 3 false_alarm/
by-design (app_router already account-tier via catch-all; telemetry LOW-by-design;
seam matches local convention). Record: `docs/reviews/fix-session-open-race-bpass.md`
(`verdict: accepted`).

**hermes: accepted** — 4 fresh Opus lenses (cross-account isolation, routing-loop,
provider-rebuild race, telemetry/test/SoT completeness). 0 P0/P1; isolation, routing,
and race verified CLEAN (no leak, no infinite loop, heal fires). 2 P2 resolved
in-batch. Report: `docs/audit/2026-06-21-hermes-fix-session-open-race.md`
(`verdict: accepted`).

NOTE — `guarded_box.dart` was re-tiered feature→**platform** in this batch (it is the
cross-account isolation primitive; its failure mode is cross-account leak). That makes
the branch's effective blast-radius platform and brings the §4.6 feature-flag
discipline (the kill-switch) into scope — both honored here.
