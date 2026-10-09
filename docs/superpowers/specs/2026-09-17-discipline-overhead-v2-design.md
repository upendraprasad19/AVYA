# Discipline Overhead Reduction v2 — S/M/L Fix Tiering

**Date:** 2026-09-17
**Status:** APPROVED (founder, 2026-09-17)
**Blast radius:** L-class (touches CLAUDE.md) — this batch must satisfy its own rules: ×2 plan review + B-pass + plan-review record.
**Evidence base:** all numbers measured this session (git log classification + file counts verified live); not transcribed from docs.

## 1. Problem

Founder asked: map what happens when a bug is reported, find where time goes, cut it.

Measured evidence (2026-09-01 → 09-17):

| Signal | Value | Source |
|---|---|---|
| Sept fix commits classified | ~60% product / ~18% review remediation / ~11% grep-brittleness repoints / ~8% tooling self-fixes | 65 commits, subject-level classification |
| Plan-review records needing ≥3 rounds | 40 of 178 (worst: 9) | grep `review_rounds:` + round files |
| Late-round finding class (non-convergent records) | compile-mechanical (missing declaration/import), design stable since round 5 | `regen-wave-unit2-round9.md` own admission |
| Review depth spent on internal tooling | telegram-admin-bot consumed ~9 of 65 Sept commits in one day (3 rounds + Hermes + 3 remediations) | git log |
| Biggest product-bug cluster | founder-visible UI/UX defects (5-obs batch in one day) — invisible to every review stage | obs-batch + diagnose INDEX |
| Grep-contract brittleness | 7 repoint commits in Sept; 5+ documented recurrence classes | commits + common-pitfalls.md |
| Custom-picker bug | RECURRED 2026-09-17 vs original 2026-05-15 (a5d29c) — diagnose-doc existed but did not hold | diagnose INDEX |

Core diagnosis: the pipeline is asymmetric — heavyweight code-reading stages catch logic bugs (they earned it: history-poisoning P0, path traversal, fail-open gates) but are blind to visual bugs (founder = QA loop), and burn reviewer time on work the analyzer does free.

## 2. Design

### 2.1 S/M/L fix tiers (CLAUDE.md new §4.12.6)

| Tier | Definition | Pipeline |
|---|---|---|
| **S** | Fix touches UI/widgets/screens ONLY; ≤2 files; diff <100 lines; NO sync/payment/auth/schema/EF/plan-engine/CLAUDE.md symbols; not a recurrence-class bug | Observation → bug-history lookup → fix in worktree → `flutter analyze lib/` + targeted tests → slim diagnose doc → commit → merge → push. NO ×2 plan review. B-pass SKIPPED. |
| **M** | Everything not S and not L | Current pipeline + compile-gate before every review dispatch |
| **L** | Payment/auth/sync/schema/EF/plan-engine/CLAUDE.md (matches `docs/blast_radius.yaml` catastrophic/platform rules) | Current pipeline UNCHANGED (×2 + B-pass + Hermes per existing gates) |

Auto-escalation (mechanical, never the fixing agent's judgment):
- Classifier (`scripts/blast_radius_from_diff.dart` + content rules) is the SoT for L; S is defined as everything the classifier does not force to M/L AND the size/seam constraints hold.
- Any gate failure, any test touching a sync/payment symbol, or diff growing past 100 lines mid-fix → tier becomes M automatically.
- Recurrence-class bugs (INDEX.md class match) → minimum M.

### 2.2 Batched APK builds

S-class fixes accumulate on `main`; the APK build happens when the FOUNDER initiates it (unchanged approval rule — never agent-initiated), not per-fix by default. "Fix is on main" ≠ "device build required now". This is an attention decoupling, not an approval change.

### 2.3 Compile-gate before review dispatch

Once drafted code exists in the worktree, `flutter analyze lib/` runs BEFORE any reviewer dispatch (plan-review round, B-pass, Hermes). Reviewer briefs add: "compile-class findings are out of scope — the analyzer ran." Scope is `lib/` (whole tree), NOT per-file — the `part of` lesson (readiness-flip, 2026-09-02): per-file analyze reports clean on a tree that does not compile.

### 2.4 Convergence shortcut (plan reviews)

A review round whose findings are ALL mechanical/citation-class (no design or logic finding) closes the record without another full dispatch. The record self-declares `mechanical_only: true`. Trust model: same self-attestation as `tier: ship_dark_build` (§4.12.4). The §4.12.5 split-and-ship rule stays the escalation path for rounds that keep finding MATERIAL issues.

### 2.5 Chronic-seven sweep

Convert the 7 repeatedly-broken grep pins to behavioral or wide-window (±40 lines) assertions in this batch:
1. `test/contracts/proactive_coach_promotion_test.dart` (congrats.ts extraction)
2. `test/contracts/streak_guardian_eligibility_test.dart` (message.ts extraction)
3. snapshot_contract citation drift (`future_prediction`/`morning_alert` line shifts)
4. `test/contracts/` readiness_sheet part-of import case (d5686216 class)
5. usage-counters slice-1 ledger census (ed4d5f05)
6. swap-undo snackbar self-pop repoint (df6f3922)
7. cron-batch manifest citations (f57e8339)

Exact file list re-verified at implementation time from the cited commits — commit hashes are pointers, not guarantees.

### 2.6 Conversion-on-touch policy (CLAUDE.md pitfall-row amendment)

Any test or file:line citation touched in a future batch gets converted to behavioral or wide-window form in THAT batch. No global gate (a grep-detects-grep gate would be its own brittleness).

### 2.7 Slim S-class diagnose template

For S-tier fixes: symptom / writer+reader by file:line / fix / test path. `touched_layers_checked` collapses to UI + client-code rows for pure-UI fixes (validator requires the field non-empty, not all 12 tiers). Full 12-tier template MANDATORY for recurrence-class bugs at any tier.

### 2.8 Batch-close process telemetry

New `scripts/batch_process_telemetry.dart` (+ mutation-proven test, rule 24): aggregates per batch — the plan-review record's convergence stats (`review_rounds`, `mechanical_only`), S-tier escape ledger status, diagnose/review file counts + `tier: s_fix` share, and gate failures from the `.claude/.gate_failures.log` that `pre-commit.sh` persists (7-day window + top offender). Printed by the existing Stop hook (`batch_close_hook.dart`) at batch close. Local-only for now; CI wiring deliberately not built.

**Scope correction (plan-review R1, 2026-09-18):** review-findings-by-class (compile/logic/citation) and explicit M/L counts are NOT in the shipped reader — plan-review records don't carry a structured finding-class field, and building one is its own change. Tracked on the OI board (telemetry v2).

### 2.9 S-tier escape ledger

`docs/audit/s_tier_escapes.yaml` (same shape as `docs/ship_dark_pending_review.yaml`): any P0/P2 escaping through an S-class fix triggers the evidence-based tightening review (which stage should have caught it; one targeted rule change, not reflex ceremony). Zero escapes over a batch horizon = candidate to relax the tier further.

## 3. Learning loops created

- `mechanical_only` flags make review convergence countable for the first time.
- The escape ledger gives the S-tier a feedback loop (earns its looseness or loses it on data).
- Telemetry turns "where does time go?" from a session-long investigation into one command.

## 4. Explicitly deferred (filed, not forgotten)

- **OI-A:** Device verification expansion (design C): Patrol flows for the UI-bug cluster, screenshot tests, canary APK. Highest-value follow-on; real engineering, own batch. Minted via `scripts/mint_oi.sh` in this batch.
- Aggregator CI wiring (runs locally via Stop hook only).

## 5. Invariants preserved

- L-class pipeline untouched. ×2 plan review retained for M. Behavioral tests still run at pre-push/CI for all tiers. No `--no-verify`. All judgment-stage catches remain intact (the B-pass catch rate — 12 remediation commits in Sept — is real and is exactly why S-tier scope is drawn narrowly).

## 6. Success criteria

- S-class bug report → on `main` same session, with no review dispatches.
- No increase in escaped P0/P2s attributable to S-tier (escape ledger empty or every entry closed with a tightening).
- Non-convergent plan-review share drops (measurable via `mechanical_only` + telemetry).
- Grep-repoint fix commits trend toward zero in subsequent months (telemetry-verified).
