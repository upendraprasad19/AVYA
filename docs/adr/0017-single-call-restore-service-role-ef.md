---
adr_id: 0017
title: Single-call cloud restore via a service-role Edge Function (not an authenticated RPC), fail-closed, embed-faithful
status: accepted
date: 2026-06-30
deciders: Upendra
---

# ADR-0017: Single-call restore via a service-role Edge Function

## Context

The gated restore (`restoreFromCloudForUser`, run every login) fires **~27 independent
India↔ap-southeast-1 round-trips** (Step A `Future.wait`×7, Step B ×14, Step C sequential×6 +
subscription) that contend for a small client connection pool; the slowest few set the tail.
Live telemetry (`client_errors restore_completed`): **web avg 34 s / p95 97 s / max 141 s**
(robust, current) and android max 1681 s (28 min, sparse/old). The cost is round-trip
contention + RTT, NOT data volume (a single-row `user_profile` fetch averaged 28 s).

A §4.12 ×2 review **split** an earlier 3-component "overhaul": C1 (indexes) was a no-op —
covering `(user_id,date)` indexes already exist (advisor shows 0 missing, 22 unused + 1 dup);
C2 (137-policy `auth.uid()`→`(select auth.uid())` RLS perf) helps app-wide steady-state but
NOT this restore path (a `SECURITY DEFINER`/service-role read bypasses RLS); only **C3** —
collapse the fan-out to ONE server call — attacks the measured pain. C1 (the 1-line dup-index
drop) + C2 (the catastrophic 137-policy rewrite) are spun out as independent batches.

## Decision

Replace the gated fan-out with **ONE service-role Edge Function** `restore-user-snapshot`
that reads every restore table for the calling user server-side and returns a single jsonb
bundle the client writes to Hive via the SAME `_restoreX` apply loops (an optional `preFetched`
inject param; the legacy fan-out stays byte-identical when it is omitted → zero parse drift).

Key properties:
- **Vehicle = service-role Edge Function, NOT an `authenticated` RPC.** The `authenticated`
  role carries `statement_timeout = 8s` (verified `pg_roles`); a single all-or-nothing RPC
  would 57014-ERROR for exactly the heavy-history tail the overhaul targets. `service_role`
  has no statement_timeout, and an EF matches the dominant service-role-only convention. Auth =
  the ADR-0016 contract (`createClient(URL, SERVICE_ROLE).auth.getUser(token)`), with a
  **non-empty-UUID `v_uid` assertion before any query → else 401**.
- **Leak-scoped (the only guard).** service_role bypasses RLS, so the EF body is the sole
  scope guard: every table filtered on the token-derived `v_uid`; the three `user_id`-less
  tables scoped via parent/dual-FK (`nutrition_log_items`/`template_exercises` via parent embed;
  `referral_redemptions` via `referrer_id=v_uid OR referee_id=v_uid`, injection-safe because
  `v_uid` is UUID-validated). Proven by a mandatory live A/B/anon-token smoke before GA.
- **Embed-faithful bundle SHAPE.** Each table value reproduces the legacy PostgREST response
  VERBATIM, including embed nesting (`nutrition_log_items` nested on nutrition_logs;
  `template_exercises` nested on workout_templates; `scheduled_workouts→template`) so the
  client parsers hydrate unchanged. A flat `{table: rows[]}` dump would silently drop meal
  items + template content (Hermes H-1).
- **Fail-closed.** ANY single table-query error → non-200 (no per-table swallow / partial 200).
  The bundle emits ALL keys + a `schema_version` sentinel; the client validates key-presence +
  sentinel and treats an absent key / bad schema / non-200 as a FAULT → runs the verbatim
  legacy fan-out THIS pass (never writes a partial bundle as a complete restore — Hermes H-2,
  behaviorally pinned by `restore_single_call_bundle_validation_test.dart`).
- **Order + cancellation preserved.** The client applies tables in the legacy A→B→C order
  (workout_plan→scheduled_workouts→schedule_completions on `schedule_<date>`;
  user_progress→freezes on `progress`); checks the cancel flag + re-asserts the Hive owner
  before any write (a fast account-switch must not write A's bundle into B's boxes).
- **Kill-switch + scope.** Behind local Hive flag `disable_single_call_restore`. Scoped to the
  gated path only; the empty-Hive background `restoreFromCloud` + every-login
  `restoreLightweightAlways` are unchanged and read the EF-produced Hive state.

## Alternatives considered

1. **Authenticated `SECURITY DEFINER` RPC (one PostgREST call).** Rejected: the `authenticated`
   8s `statement_timeout` (DEFINER does NOT lift it) would atomically fail the heavy tail — the
   exact accounts the overhaul exists for. The EF under service_role has no such cliff.
2. **Keep the 27-call fan-out; ship C1 indexes + C2 RLS-perf instead.** Rejected: C1's covering
   indexes already exist; C2 is irrelevant to a DEFINER/service-role restore path (R1 proved the
   three are independent wins). Neither removes the round-trip contention.
3. **Delta-sync (`gte(updated_at, last_synced)`).** Rejected — pinned anti-pattern: no synced
   table has a reliable mutation timestamp; the Step-B pages key on creation/event columns, so a
   row mutated-after-but-created-before the cutoff is silently dropped (late edits/completions).
   The full-history `since='2020-01-01'` window is unchanged.
4. **Flat `{table: rows[]}` bundle.** Rejected (Hermes H-1): breaks the three nested-embed
   parsers → silent total loss of meal items + template workout content.
5. **Un-cap the three latent row-caps in the bundle.** Not now — the EF inherits today's caps
   verbatim (safe at current volumes ≤894 rows/table/user); un-capping risks payload bloat and
   is a documented follow-on.

## Consequences

Good:
- Round-trips per gated restore: **27 → 1**; the RTT/contention tail (web p95 97 s) collapses.
- The legacy per-op path is preserved verbatim as the fail-closed fallback → no resilience loss.
- The fail-closed contract is behaviorally pinned; the apply/merge semantics reuse the existing
  pure-helper behavioral tests unchanged.

Bad / watch:
- service_role bypasses RLS → the EF body is the ONLY scope guard; every read carries the
  `v_uid` filter and the live A/B/anon smoke is mandatory before GA (OI-28 / ADR-0016 class).
- No RemoteConfig exists → the kill-switch is local; a prod regression rolls back via a revert
  APK + web redeploy (+ the automatic in-pass legacy fallback), NOT a remote flip.
- The bundle wire-contract must byte-match ~25 heterogeneous legacy parsers (embed nesting,
  uuid/text join keys, column names, caps) — a drift surface the ×3 review + Hermes enumerated;
  pinned by the EF projection spec + the contract tests.
- The bundle sentinel covers key ABSENCE, not row-level corruption (documented bounded scope;
  compensating guards: additive/local-wins merge + caps→completeness + in-pass fallback).

## Status

Accepted. Converged through R1 (split) → R2 (gated/EF) → R3 (converged) → Hermes (block_ship →
2 P0 folded → re-verify converged). Implemented on branch `restore-single-call`; full
test/sync + test/contracts suite green. The EF deploy, the C1 index-drop migration, the APK,
and the on-device A/B/anon smoke are each founder-gated. C2 (137-policy RLS) = separate batch.

## See also

- Plan: `~/.claude/plans/restore-single-call-c3.md` (§12 convergence record)
- Hermes: `docs/audit/2026-06-30-hermes-restore-single-call.md`
- Plan-review record: `docs/plan-reviews/restore-single-call.md`
- ADR-0014 (additive/local-wins restore), ADR-0016 (EF user-token auth contract)
- `feedback_mistake_restore_window.md`, `feedback_mistake_misdiagnosed_restore_completeness_bug.md`
- SoT concept `restore_single_call` (`docs/sot_registry.yaml`)
