# Audit Scope — 2026-05-29 (post-APK-+31 comprehensive)

> Ahead-of-cadence comprehensive audit (quarterly was scheduled 2026-08-03). Triggered by
> founder: "we've done a lot of changes, make sure nothing is silently breaking" — focused on
> the long-horizon journey (onboarding → repeated rank promotions → repeated phase generation
> across ~1 year). Pairs with the year-sim harness (Phase B/C) as runtime verification.

## Baseline & window

- **Last shipped APK:** `1.0.0+31` at commit `3dc227c` (APK Test #16.2 +31).
- **Audit window:** `3dc227c..HEAD` (HEAD = `91a30a6`). ~12 commits, the founder-unvalidated set.
- **Working tree (uncommitted):** modified `scripts/check_migrations_applied.dart`,
  `check_writeservice_contracts.dart`, `check_writeservice_only.dart`; staged diagnose-doc
  (`2026-05-29-blast-radius-auto-prepend...`); untracked `backups/edge_function_payloads/*`
  (deploy archive) + `test/contracts/custom_exercises_mutations_writer_to_reader_test.dart`.

## Changed surfaces by blast-radius tier (source only, window)

| Tier | Surface | Risk |
|---|---|---|
| platform | `sync/sync_nutrition.dart`, `sync/sync_workout.dart` | sync fan-out / restore drift |
| platform | EF `weekly-recalc`, `evaluate-rank-promotions`, `proactive-coach-promotion`, `weekly-report` | cron correctness, rank authority |
| platform | migrations `068b`, `074`, `075`, `076`, `077` | apply-state parity, payload parity, alert crons |
| account | `rank_service.dart` (permanence fix), `nutrition_write_service.dart`, ai_coach repo | monotonic field, write contract |
| feature | `workout_repository.dart` **−287 lines**, `train_provider.dart` | **major train refactor — top regression suspect** |

## Lens set in scope (subset of 53; mapped to changed surfaces)

- **L1** writer/reader drift — sync + write service changes
- **L26** CQRS / pure-function discipline — `workout_repository` refactor (this file IS L26's precedent)
- **L27** concurrency on shared state — rank + streak writers
- **L21** Edge Function semantic correctness — 4 EFs changed
- **L22** schema-vs-payload parity — migrations 074-077
- **L13** migration apply pair-update — verify `backups/applied_migrations.json` vs live
- **L53** EF deploy reversibility — new `backups/edge_function_payloads/` archive
- **L4 / L31** cron auth+telemetry / cron efficiency — migration 076 alert crons
- **L25 / L45** intra-doc + citation drift — CLAUDE.md changed → `/sync-claude-md`
- **L8 / L10** contract-test + SoT coverage — many new contract tests in window
- Runtime verification of L1/L26/L27 for rank+phase = the Phase B/C year-sim.

## Execution

- **A1 engineering fan-out:** parallel subagents per lens-cluster against the window diff
  (not whole-codebase). MCP-verifiable lenses (L13 migration parity, L21/L53 EF deploy parity,
  L4/L31 cron health) verified directly via Supabase MCP + live queries — per
  `feedback_audit_findings_require_live_verification.md`, no finding actioned without file:line
  read + live SQL.
- **A2 industry-standards gap:** `docs/audit/2026-05-29-industry-standards-gap.md`.
- **A3 consolidate:** single backlog → closure YAML `docs/audit/2026_05_29_audit_closures.yaml`,
  every finding terminal-stated (closed_in_commit / upstream_blocked / verified_clean).
