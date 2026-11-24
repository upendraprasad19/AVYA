---
branch: oi348-landing2
date: 2026-11-23
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/oi348-landing2-bpass.md
---

# Plan-review record — OI-348 Landing 2 (B8 rank floor, B9 unit sync, B10 restore speed; B2 in PR B/C)

Plan: `docs/plans/oi348-walk-fixes-landing2.md`, v4 CONVERGED. Four units, one context-blind Sonnet
seat per unit per round, each verifying every claim against the code and the live project
(`dedsavbjuwgarrhphgnl`, read-only). Every round after round 1 ran on the previous round's revised
text. This record covers PR A (B8, B9, B10); B2 lands in PR B / PR C with its own record.

## Rounds
- **Round 1 (v1): `not_converged`.** B8: 2 P1 (blast-radius content rule escalates any migration
  whose text says the definer phrase; no EF test seam) + P2s. B9: 2 P1 (`getUnitsMetric` becomes a
  throwing read; 13 test seeds of the old key would go green for the wrong reason). B10: 1 P0
  (the subscription refresh overlap races restore steps A/C on `progress` via
  `grantFirstProFreezes` / `resetToFreeCapOnLapse` + `syncFreezes`: DROPPED) + 3 P1 (null prefetch
  = silent empty; EF not shown to be the bottleneck → cap 3 + timings; no parity seam). B2: 2 P1
  (ambiguous OUT names; concurrent call loses its result → advisory lock + final re-select).
- **Round 2 (v2): `not_converged`.** B8: 2 P1 (auth must stay a literal `isAuthorizedCronCall(req)`;
  client stamp/Home need pure seams). B9: 1 P1 (toggle snap-back on a `build` re-read). B10: 1 P0
  (three source-grep tests + 4 registry rows read `index.ts`) + 1 P1 (self-referential parity →
  golden from e28cdab8). B2: 1 P0 (ledger-paired gate: M2 cannot ride unapplied → PR C) + 1 P1 (web
  deploy check).
- **Round 3 (v3):** B8 `converged`, B2 `converged` (P2s applied). B9: 1 P1 (adopter placed in
  `_ensureLocalUser`, which never runs at a persisted-session launch → both post-restore heals).
  B10: 2 P1 (tuple layout undefined; freezes anchor).
- **Round 4:** B9: 1 P1 (legacy configBox fallback until adoption). B10: 4 P1 (bundle key
  `ai_coach_interactions`; anchor `["freezes",`; `q` label from the tuple name; wiring-test rewrite
  detail).
- **Round 5:** B9 `converged`. B10: 2 P1 (paged vs query kind; per-slice `vUid` check vacuous).
- **Round 6 (B10 delta seat):** 1 P1, mechanical (the `users` read uses `.eq("id", vUid)`; all 29
  reads enumerated) → applied; `converged`, `mechanical_only: true`.

No design changed after round 1; rounds 2-6 moved test wiring, rollout order and spec precision.

## Ground truth verified
Read: `rank_service.dart`, `rank_ladder_data.dart`, `home_screen.dart`, `_shared/rank_engine.ts`,
`evaluate-rank-promotions/index.ts` + test, `proactive-coach-promotion/index.ts` + test,
`blast_radius_content_rules_lib.dart`, the cron-auth / notification-prefs / promotion contract tests,
`user_repository.dart`, `profile_write_service.dart`, `sync_profile.dart`, `user_config_migrator.dart`,
`auth_provider.dart`, `restoring_screen.dart`, `heal_after_restore.dart`, `profile/screen.dart`,
`profile_content.dart`, `body_measurements_provider.dart`, `restore-user-snapshot/{index.ts,
paged_reads.ts, paged_reads_test.ts}`, `_shared/paged_fetch.ts`, `sync_service.dart`,
`sync_health.dart`, `subscription_service.dart`, `streak_progress_service.dart`. Live, read-only:
`pg_get_triggerdef` of `trg_dispatch_proactive_coach_promotion` (no WHEN), `rank_promotions` /
`ai_coach_interactions` counts, `max_connections` 60, `referral_codes` policies, constraints and
grants.

## Execution
Inline, one worktree per PR (§4.12.7), decided at start: PR A `oi348-landing2`; PR B / PR C in
`oi348-landing2-referral`.
