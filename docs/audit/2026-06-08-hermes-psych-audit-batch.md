---
hermes_pass_id: 2026-06-08-hermes-psych-skill-and-audit
ran_at: 2026-06-08T07:40:00+05:30
batch_scope: main..HEAD (psych-skill-and-audit-2026-06-07 — 47-finding audit + std-encoding incident)
lens_set: [L21, L22, L23, L1, L36, L28, L39]
agents_dispatched: 7
findings_total: 9
findings_by_severity: { P0: 1, P1: 0, P2_real: 2, partial: 4, false_alarm: clean-on-rest }
verdict: accepted
---

# Hermes Pass — psych-skill-and-audit-2026-06-07 (E-pass, pre-merge)

7 parallel fresh-context Opus lenses over the whole branch. Catastrophic blast-radius
(live-deployed payment EFs). The per-commit B-passes already cleared the Batch-6 +
incident commits in isolation; this E-pass targeted cross-commit / full-read defects.

## Summary
- **1 P0 (ship-blocker) — FIXED + redeployed + boot-verified.**
- 2 real low-severity findings — fixed in-batch.
- 4 PARTIAL / defense-in-depth — fixed or accepted.
- All other lens checks CLEAN.

## Findings by lens

### L21 (EF semantics) + L36 (idempotency) — **P0, FIXED (f5d8c3)**
Both lenses independently caught: `verify-payment` declared a second `const existingSub`
(idempotency pre-SELECT, ~line 490) colliding with the pre-existing active-sub
`const existingSub` (~line 279) in the same handler → **module-load SyntaxError → v14
wouldn't boot**. The verify_jwt=true deploy smoke MASKED it (gateway 401s the unauth probe
before the module loads). Renamed to `paymentSubRow`; **v15 redeployed + anon-Bearer
boot-verified** (module returns its own 401, not 503). Diagnose `f5d8c3`. This is the
single highest-value catch — a diff-only review structurally cannot see it.
Other L21 functions (razorpay-webhook, proactive-coach-promotion, pr-detection,
i-see-you-callout) read end-to-end CLEAN.

### L22 (schema-payload parity) — **CLEAN / PARTIAL (pre-existing, accepted)**
verify-payment's new insert carries the identical NOT-NULL column set as the old upsert
(nothing dropped). razorpay-webhook insert: full parity. One PARTIAL: `razorpay_order_id:
payment.order_id ?? null` against a NOT-NULL column — pre-existing (in the old upsert too),
unreachable under the Razorpay-Orders flow, NOT a batch regression. Accepted.

### L23 (service-role auth) — **CLEAN (0 findings)**
proactive-coach-promotion's F44 `isAuthorizedCronCall` gate sits before all privileged
work; verify-payment's OI-29 ownership assertion (`notes.user_id === userId`) still precedes
every write; the pre-SELECT keys on a unique `razorpay_payment_id` already proven to belong
to the caller; i-see-you/pr-detection cron gates precede the new scans.

### L1 (writer/reader drift) — **1 PARTIAL, FIXED**
F19 SoT, deployments_complete, weight_logs, subscription-expiry pairs all CLEAN. One real
gap: the `goal_screen` key `'recomp'` → `plan_screen._mapGoal` → token `'recompose'` bridge
was the one un-pinned link on the F19 failure surface — if it drifts, onboarding writes an
unknown token → maintenance fallback while every test stays green. **Fixed:** added a bridge
assertion to `recompose_goal_targets_test.dart`.

### L28 (service invariants) + L26 (CQRS) — **2 findings, FIXED**
(a) The AI `switchGoal` tool's server enum omitted `recompose` → the coach literally couldn't
switch a user to the batch's headline new goal. **Fixed:** added `recompose` to
`switchGoal.ts` enum + description. (b) The client dispatcher wrote `primary_goal` without a
`FitnessGoals.isKnown` revalidation (the value's own SoT) → defense-in-depth gap on the F19
class. **Fixed:** `tool_dispatcher._executeSwitchGoal` now rejects unknown tokens before the
write. CLEAN: default=build_muscle at every entry; `FitnessGoals.of(unknown)` asserts-then-
falls-back; F1 server cap enforced server-side with no trial-field lockout; no hidden mutation
in the new getters.

### L39 (restore round-trip) + L37 — **CLEAN on the fixes; 1 cross-batch note**
F37 sleep pagination, F38 plan re-anchor (idempotent, completed-day-preserving), F39 dead
`sets_completed` removal — all round-trip CLEAN, no field-name drift. **Cross-batch note:**
`git diff main..HEAD` shows the branch missing main's additive-restore local-wins guards —
because the slow-boot batch (`a767725` + merge `1baf10d`) landed on main AFTER this branch's
fork point `1e11a97`. This is **branch staleness, not a removal** — resolved by resyncing the
branch with main before the `--no-ff` merge (preserving both main's guards and this batch's
F37/F38/F39 fixes).

## Triage / action items
- [x] P0 verify-payment duplicate const → fixed (f5d8c3), v15 redeployed + boot-verified.
- [x] L1 recomp-bridge test → added to recompose_goal_targets_test.dart.
- [x] L28 switchGoal enum `recompose` → added (source; ships with next ai-proxy deploy).
- [x] L28 dispatcher `isKnown` guard → added to tool_dispatcher.
- [x] L39 branch staleness → resync branch with main before merge (the merge step).
- [accepted] L22 `razorpay_order_id ?? null` — pre-existing, unreachable; not a batch regression.

## Verdict: accepted
The single P0 is fixed + verified live; all real findings fixed in-batch. Merge may proceed
after the main-resync (L39 note). The E-pass earned its keep: it caught a live-broken payment
function that 4 B-passes + the author's re-reads missed.
