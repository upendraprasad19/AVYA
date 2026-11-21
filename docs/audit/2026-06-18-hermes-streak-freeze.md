---
hermes_pass_id: 2026-06-18-hermes-streak-freeze
ran_at: 2026-06-18T16:00:00+05:30
batch_scope: discipline-overhaul Phase 2 (streak/freeze rework — Units B/C/D1/D2, diagnose f9d2e7)
lens_set: [L27_concurrency, L15_16_sync_restore_completeness, L39_offline_first, L37_observability, L1_writer_reader_drift, L33_replaces_x_drops_field]
agents_dispatched: 4
findings_total: 9
findings_by_severity: { P0: 1, P1: 4, P2: 3, false_alarm: many }
verdict: accepted
---

# Hermes Pass — discipline-overhaul streak/freeze rework (f9d2e7)

Per-batch multi-lens deep pass, run BEFORE the push (founder-required; the
2-reviewer B-pass did not subsume it — see `feedback_dont_skip_planned_hermes_for_tokens`).
4 fresh context-blind agents (2 opus: concurrency + sync/restore; 2 sonnet:
telemetry + drift). It surfaced real issues the B-pass missed — chiefly the
telemetry priority gap and a stale contract comment — plus one sophisticated-but-
wrong concurrency hypothesis I verified down to FALSE_ALARM with a pinning test.

## Summary
- 0 unresolved ship-blockers. All actionable findings fixed in-batch or
  documented; the one P0-labelled item is dev-only + intentional.
- Net new fixes: telemetry HIGH-priority for the grant/lapse op_types (client +
  server), a gated-off reckon breadcrumb, a stale PER-WEEK comment, a sim
  dev-bypass doc, and a concurrency-race regression test.

## Findings by lens

### L27 — concurrency (opus)
- **P1 — progress-map lost-update on the completeWorkout consume→updateProgress sequence — FALSE_ALARM (verified + pinned).** The reviewer hypothesised that `commitConsume`'s fire-and-forget `updateProgress` races completeWorkout's line-1450 `updateProgress`, with a whole-map last-writer-wins reverting the freeze consume. The hypothesis rests on Hive updating its in-memory keystore only AFTER the disk-write await. That is FALSE for Hive's regular `Box`: `box.get` after a (not-yet-resolved) `box.put` returns the new value synchronously. Verified by `streak_decay_reckon_permanent_ledger_test` — the existing "PERSISTS the consume" case reads `available==0` synchronously after a fire-and-forget consume — and pinned by a NEW test ("completeWorkout sequence … lose NEITHER the consume NOR the count"). No mutex needed. (Lesson: verify subagent control-flow claims against the runtime — `feedback_audit_verifier_cannot_trust_own_subagent`.)
- **P1 — _restoreFreezes whole-map blind put clobbers concurrent non-freeze fields — FALSE_ALARM.** The reviewer assumed an `await` between `_restoreFreezes`'s `box.get` and `box.put`. There is none — the merge (`mergeFreezeProgress`) is a pure sync function — so the read-modify-write is atomic on the single-threaded event loop; no concurrent write can interleave between its get and put.
- **P2 — `_reckonInFlight` guard is dead code — accepted (harmless).** The guarded region is fully synchronous, so a second caller can never observe `true`. Harmless; kept as future-proofing + documents intent (no change).

### L15/L16 — sync/restore completeness + L39 offline-first (opus)
- **P2 (latent) — migration-095 backfill assumes "any `subscriptions` row == ever-PRO".** Safe against current live data (`subscriptions.status` ∈ {active, expired, cancelled} — every row is a real subscription). Latent risk only if a future webhook writes a pending/failed `subscriptions` row at order-creation → would over-flag a never-PRO user and DENY their instant grant. Documented as a known assumption (this report + the diagnose); not a live defect.
- **Design note — the permanent-ledger always-union precludes a future "un-freeze a day" operation** (a stale cloud entry would resurrect an un-frozen day). No such op exists today; flagged so a future feature doesn't silently regress.
- Singular/plural round-trip, grant-flag cloud-true-wins restore, mig-096 RPC, offline-first (no UI-blocking cloud reads) — all VERIFIED CLEAN.

### L37 — observability / telemetry (sonnet)
- **P1 — grant + lapse op_types are LOW-priority → dropped during a cooldown window — FIXED.** `streak_freeze_first_pro_grant` + `streak_freeze_lapse_reset` are money-relevant and once-per-lifecycle (a dropped event is unrecoverable). Added both to `highPriorityOpTypes` (client `error_telemetry.dart`) AND `HIGH_PRIORITY_OP_TYPES` (server `log-client-error/index.ts`), kept in sync (twin test). **Requires a `log-client-error` redeploy to take live effect — batch-end deploy step.**
- **P2 — gated-off reckon emits no breadcrumb — FIXED.** Added a debug-only `debugPrint` on the gated-off branch (restore-not-settled / empty-schedule) so a founder debugging "streak didn't update after idle days" can see WHY decay was suppressed. (Kept as debugPrint, not a logEvent, to avoid release telemetry noise on the common pre-restore-rollover path.)
- catch-block swallow / consume-only-on-mutation / lapse-no-op silence — FALSE_ALARM (all correct).

### L1 / L33 — writer/reader drift + replaces-X (sonnet)
- **P1 — stale "`used_dates` is PER-WEEK (cleared on refill)" comment at `sync_restore_completeness.dart:157` — FIXED.** Contradicted the D1 permanent-ledger reality; rewritten to the always-union contract.
- **P0 (dev-scope) — `simulation_service.dart:457` calls `consumeMissedDayIfFreezeAvailable()` directly, bypassing the D2 reckon gates — DOCUMENTED.** Dev-only (kDebugMode, release-inert); the sim drives its own clock seam and intentionally must not wait for a real restore tick. Annotated as an intentional dev-seam exception (NOT a third production consume site). No prod impact.
- Spelling drift (Hive singular / cloud plural; the new flag plural on both sides), UI "this week" copy (the weekly BUDGET is still weekly — only `used_dates` changed) — VERIFIED CLEAN / FALSE_ALARM.

## Action items
- [x] Telemetry HIGH-priority (client + server) — fixed; **redeploy `log-client-error`** (batch-end, founder deploy-go).
- [x] Gated-off reckon breadcrumb — fixed.
- [x] Stale PER-WEEK comment — fixed.
- [x] Sim dev-bypass doc — fixed.
- [x] Concurrency P1 — verified FALSE_ALARM + pinned by regression test.
- [x] Migration-095 "subscriptions==ever-PRO" assumption + union/un-freeze note — documented (here + diagnose).

## Verdict
accepted — no unresolved P0/P1. The two concurrency P1s are verified FALSE_ALARMs
(pinned); the telemetry + drift P1s are fixed; the dev-scope P0 is intentional +
documented; the latent P2 is documented. Pending deploy step: `log-client-error`
redeploy so the new HIGH-priority op_types take live effect.
