---
branch: restore-single-call
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
hermes: accepted
hermes_report: docs/audit/2026-06-30-hermes-restore-single-call.md
bpass: accepted
bpass_review: docs/reviews/restore-single-call-bpass.md
---

# Plan-review record — restore-single-call (C3 single-call restore)

> §4.12 keystone record. The plan was reviewed THREE context-blind rounds + a Hermes 8-lens
> pass + a focused re-verify, on a fully ground-truthed premise, BEFORE a line was written.
> `bpass:` flips to `accepted` once the B-pass (`docs/reviews/restore-single-call-bpass.md`)
> landed with `verdict: accepted` (P0:0 P1:0; 1 P2 docstring fixed in-batch). Plan:
> `~/.claude/plans/restore-single-call-c3.md` (§12).

## Verdict: CONVERGED (bpass accepted · hermes accepted)

## What this batch is
Replace the gated `restoreFromCloudForUser` ~27-call client round-trip flood (web restore p95
97 s) with ONE service-role Edge Function (`restore-user-snapshot`) returning a jsonb bundle the
client applies via the SAME `_restoreX` loops (a `preFetched` inject; legacy path byte-identical).
Fail-closed, embed-faithful, leak-scoped, kill-switched, with a verbatim legacy fallback. Folds
the trivial C1 water_logs duplicate-index drop (apply-gated). ADR-0017.

## Review arc (all context-blind; every load-bearing claim live-verified by the lead)
- **Ground-truth audit** — premise (web p95 97 s robust; android sparse), 137-policy C2 scope,
  C1 covering-indexes-already-exist, payload sub-MB, the 30-table leak inventory, the 8s
  `authenticated` statement_timeout, `relforcerowsecurity=false`, the 3 embed shapes — all
  verified by direct Read + live SQL (`scratchpad/ground-truth-restore-perf.md`).
- **R1** (×2 reviewers) → the 3-component overhaul is INCOHERENT (C1/C2/C3 independent; a
  DEFINER/service-role read bypasses RLS so C2 ≠ restore-perf) → **split; founder chose C3 first**.
- **R2** (3 lenses + critic) → 3 P0 (8s RPC timeout → EF; incomplete leak inventory;
  entry-point blindness) + 6 P1 → founder chose **gated path, EF vehicle**.
- **R3** (2 lenses + critic) → **CONVERGED, zero new P0/P1** (all R2 fixes verified landed).
- **Hermes** (8 lenses + master) → **block_ship** (2 P0: flat-bundle-breaks-nested-parsers;
  no-fail-closed-contract) + 5 P1 + 5 P2; **leak surface SOUND** (A→B leak + JWT-as-apikey =
  false alarms). All 12 folded into plan v5 → **focused 2-seam re-verify CONVERGED**.
  `docs/audit/2026-06-30-hermes-restore-single-call.md`.

## Multi-tier coverage (this batch's verification, §6)
- **Client code** — `flutter analyze` 0 errors/0 warnings; full test/sync + test/contracts green (1951).
- **Hive** — fail-closed bundle contract behaviorally pinned (`restore_single_call_bundle_validation_test.dart`,
  6/6); apply/merge semantics reused UNCHANGED from the legacy path (`restore_freezes_merge_test`,
  `restore_plan_json_authoritative_test` pure-helper behavioral tests).
- **Postgres schema** — live `pg_indexes`/`pg_roles`/`information_schema`/`pg_class` verified
  (covering indexes exist; authenticated 8s timeout; relforcerowsecurity=false; the 3 user_id-less tables).
- **Edge Function** — code written (`restore-user-snapshot/index.ts`); ADR-0016 auth contract;
  fail-closed + leak-scoped. NOT YET DEPLOYED (founder-gated) — live A/B/anon-token smoke is the
  end-to-end proof, mandatory before GA.
- **Migrations** — C1 dup-index drop (SQL in plan §7); created+applied+json-recorded at the gated apply.
- **RLS** — N/A to the EF (service_role bypasses; scope is in the EF body, verified by the smoke).
- **Client→server contract** — the bundle SHAPE reproduces each legacy read verbatim (embed nesting,
  uuid serialization, column names, caps); fail-closed validation + legacy fallback on any fault.

## Decisions recorded
- Split the overhaul; C3 first (the only true restore-perf win). C1 (1-line dup drop) folded;
  C2 (137-policy RLS) spun out as a separate catastrophic batch.
- service-role EF, NOT an authenticated RPC (8s statement_timeout cliff). ADR-0017.
- Scope to the gated path only; background + lightweight paths unchanged.
- Inherit the 3 latent row-caps verbatim (un-capping is a documented follow-on).

## Gated next steps (each its own explicit founder go)
EF deploy (verify_jwt=true; host-shell deploy + live A/B/anon smoke) · C1 migration apply
(+ `backups/applied_migrations.json` pairing) · APK build · on-device verification + before/after
restore telemetry. Then C2 (separate). Baseline = web restore p95 97 s.

## Artifacts
`~/.claude/plans/restore-single-call-c3.md` · `docs/audit/2026-06-30-hermes-restore-single-call.md`
· `docs/reviews/restore-single-call-bpass.md` (B-pass) · ADR-0017 · SoT `restore_single_call`.
