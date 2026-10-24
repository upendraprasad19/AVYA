---
hermes_pass_id: 2026-06-30-hermes-restore-single-call
ran_at: 2026-06-30T22:00:00+05:30
batch_scope: restore-single-call (C3 single-call restore — plan restore-single-call-c3.md)
lens_set: [L23, L1, L39, L37, L21, L36, L27, L15]
agents_dispatched: 9
findings_total: 18
findings_by_severity: { P0: 2, P1: 5, P2: 5, false_alarm: 6 }
raw_verdict: block_ship
verdict: accepted
---

# Hermes Pass — C3 Single-Call Restore (plan review, pre-implementation)

> **Disposition:** the raw 8-lens pass returned **block_ship** on 2 P0 design gaps. Both P0s + all
> 5 P1 + 5 P2 were FOLDED into plan v5; a focused 2-seam re-verification then **CONVERGED**
> (`scratchpad/hermes-synthesis.md` + the v5 plan §2/§3/§4/§11). Per the hermes-pass triage
> ("accepted = all findings resolved — fixed, annotated, or spawned"), the final verdict is
> **accepted**. The implementation built from v5 reproduces every fix below; the full test/sync +
> test/contracts suite is green (1951 passing) and a behavioral fail-closed test pins H-2.

## Summary
Eight context-blind Opus lenses reviewed the converged C3 plan (a service_role Edge Function
replacing the gated `restoreFromCloudForUser` ~27-call fan-out). 18 consolidated findings.
**The catastrophic leak surface is SOUND** — the headline A→B cross-account leak (L15) and the
JWT-as-apikey hazard (L21) are correct FALSE ALARMS (Layer A `GuardedBox` + per-user namespaced
boxes structurally prevent the leak; the EF uses the verified `getUser(token)` e8a1c3 contract).
The 2 P0s were both EF↔client wire-contract gaps, now closed.

## Ship-blockers (P0) — RESOLVED in v5 + implementation
- **H-1 (P0) — flat bundle broke the 3 embed-shape parsers** (`nutrition_log_items` nested on
  nutrition_logs; `template_exercises` nested on workout_templates; `template:template_id(…)` on
  scheduled_workouts) → silent total loss of meal items + template workout content.
  **RESOLVED:** v5 §2 + EF — the bundle reproduces each legacy read's response VERBATIM incl. embed
  nesting; parsers hydrate unchanged. EF `restore-user-snapshot/index.ts` emits the nested selects.
- **H-2 (P0) — no fail-closed contract** — a partial-200 / missing-key / 200-with-error-body would
  be written as a COMPLETE restore (silent data loss; green telemetry).
  **RESOLVED:** v5 §2 + EF fails closed (any table error → non-200), emits ALL keys + `schema_version`
  sentinel; client `validatedSnapshotTables` treats absent-key/bad-schema/non-200 as a fault → legacy
  fallback. **Behaviorally pinned** by `test/sync/restore_single_call_bundle_validation_test.dart` (6/6).

## P1 — RESOLVED in v5 + implementation
- **H-3** subscriptions bundle/refresh inconsistency → v5 §3: `subscriptions` NOT in the bundle;
  `SubscriptionService.refreshFromSupabase()` stays a separate post-bundle call (grace-window logic).
- **H-4** null/empty v_uid fail-open → v5 §2 + EF: assert non-empty UUID `user?.id` after `getUser`,
  before any query → else 401 (`UUID_RE` guard).
- **H-5** uuid/text groupKey serialization (`workout_log_sets.workout_log_id` uuid vs
  `workout_log_exercises` text) → v5 §2/§4: EF emits canonical uuid string; null-exercise_id fallback noted.
- **H-6** `progress` singleton read→merge→put must be await-free (legacy 1-await-per-method atomicity)
  → v5 §4/§11 + `_restoreFreezes` keeps the await-free merge; single-call applies user_progress before freezes.
- **H-7** Layer A (`GuardedBox._assertOwnership`) is the cross-account backstop → v5 §11 names it +
  the orchestrator re-asserts `_supabase.currentUser?.id == userId` after the EF returns, before any write.

## P2 — RESOLVED in v5
- **H-8** referral dual-FK `.or` injection-safe only if v_uid UUID-shaped → v5 §2 invariant (folded with H-4).
- **H-9** cap inventory incomplete → v5 §3: full cap list (streaks 52, ranks 20, redemptions 50,
  templates 500, saved_meals 500 + scheduled 1000 / coach 1000 / completions default).
- **H-10** freeze replay stability → covered by the existing pure-helper behavioral test
  (`restore_freezes_merge_test.dart` — `mergeFreezeProgress`) which the single-call path reuses unchanged.
- **H-11** `duration_secs` vs `duration_seconds` distinct columns → v5 §2: EF projection column-verbatim.
- **H-12** coach_memory `SELECT *` would carry server-only risk scores → v5 §3 + EF: 10-column projection only.

## False alarms (recorded)
- **H-FA-1 (L15)** headline A→B Hive cross-account leak — structurally prevented by Layer A + per-user
  namespaced box files (verified on main).
- **H-FA-2 (L21)** getUser ordering / JWT-as-apikey — already complies with e8a1c3 + the gate.
- **H-FA-3/4/5 (L27/L36)** restoreLightweightAlways re-run not a new race; collapsing 27→1 NARROWS the
  user-write race window; schedule_<date> three-writer batch is replay-stable.

## Action items — all closed in plan v5 / implementation
Every P0/P1/P2 above is folded into `~/.claude/plans/restore-single-call-c3.md` (§2/§3/§4/§11) and built
into the EF + client refactor. Residual bounded scope (documented, not a hole): the sentinel covers key
ABSENCE, not row-level corruption — compensating guards = additive/local-wins merge + caps→completeness +
the in-pass legacy fallback; the gated post-deploy live A/B/anon smoke + on-device verification are the
end-to-end behavioral proof.

## Verdict: accepted
All 18 findings resolved (2 P0 + 5 P1 + 5 P2 folded; 6 false alarms recorded). Re-verification converged.
Ready for the B-pass + founder sign-off. Full findings + ground-truth: `scratchpad/hermes-synthesis.md`,
`tasks/wfiiwc6ho.output` (raw 8-lens master consolidation).
