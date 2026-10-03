---
reviewed_at: 2026-09-28T16:30:00+05:30
staged_against: origin/main...dfcd2bde (whole branch, 198 files; nothing staged — branch-named review per the merge-review precedent)
blast_radius: catastrophic
reviewer: 4 context-blind claude-sonnet subagents (isolated worktrees) + coordinator verification
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, self_attesting_artifact, restore_completeness, sync_atomicity, ef_auth_contract, capability_gating, io_flood]
findings_count: 12
false_alarm_count: 0
remediation_commit: 2675345b
verdict: accepted
---

# Code Review (B-pass) — `day-swapper-sync-load`

Task 33 of `docs/superpowers/plans/2026-09-26-day-swapper-sync-load.md`. The diff (`origin/main...dfcd2bde`)
was split across four reviewers so the mutation-heavy lenses each had a full budget (2026-09-08 split
rule): **R1** sync core + migration 148, **R2** day-swap engine + client UI, **R3** Edge Functions + AI coach
routing, **R4** gates, docs and self-attesting artifacts. Migration 148, its live-verify SQL and trigger test
(held outside the tree until the Task 34 live apply) were reviewed from the SDD handover copy.

Before dispatch: `flutter analyze lib/` 0 warnings, full `flutter test` 6814 passed / 0 failed, `deno check`
clean on the five touched EFs, and every commit on the branch had run the pre-commit gate loop (§4.12.5/.8).

Every finding below was re-verified by the coordinator against the code before it was accepted, and every
fix was mutation-proven (a restore of the pre-fix line, never a delete) with the red read for its reason.

## Finding 1 — P1 — sync_atomicity / io_flood (R1-F1)
- **file:line:** `lib/core/services/sync/sync_workout.dart` — `_syncScheduledWorkouts`'s `templatesResynced` recovery; `_syncWorkoutTemplates`'s `SyncSkipIndex` (domain `template`)
- **claim:** the FK self-heal re-runs `_syncWorkoutTemplates`, but that function's skip index still holds the lost template's confirmed fingerprint, so the re-run skips it. The cloud row is never recreated, the schedule row falls to the orphan fallback, and — unconfirmed by design (spec D4) — repeats 2 SELECTs + 2 upserts + a telemetry post every pass.
- **verification:** `test/sync/sched_template_fk_recovery_test.dart` (real SyncService against the stub; the cloud loses the template after pass 1). Pre-fix line restored → `Expected: ['Push A'] Actual: []`.
- **fix (2675345b):** `SyncSkipIndex.forcePushKeys` + `_syncWorkoutTemplates(forceKeys:)`; the recovery forces exactly `{rawTemplateId}`. Not `disabled`, which deletes the whole index at `commit` and would re-push every template next pass. Diagnose a9d3f6.
- **status:** fixed

## Finding 2 — P2 — guard_without_its_mirror (R1-F2)
- **file:line:** `lib/core/services/sync/sync_skip_index.dart` `pushIfChanged`, the `!confirmed` branch's `_forget(rowKey)`
- **claim:** deleting it left 18/18 green — the "unconfirmed" test never seeds a prior fingerprint. Without it, a row that later returns to its old content is skipped though the cloud never got the intermediate state.
- **verification:** new test "unconfirmed push DROPS the previously confirmed fingerprint"; mutation → `Expected: empty Actual: {'d': 'fp1'}`.
- **status:** fixed (2675345b)

## Finding 3 — P1 — guard_without_its_mirror / subscription gating (R2-F1)
- **file:line:** `lib/features/train/widgets/swap_confirm_sheet.dart` `build` (reached from `DaySwapDragWrapper`'s drop) vs `swap_picker_sheet.dart` `build`
- **claim:** the picker (Train ⇅, Home long-press) shows a spent free user the upsell; the drag confirm sheet showed a normal SWAP that could only answer "This week's swap is spent." with no way to PRO.
- **verification:** `test/widgets/swap_confirm_sheet_test.dart` spent test + mirror (free user with a swap left keeps SWAP). Gate disabled → 1 red, mirror green.
- **fix:** public `DaySwapSpentSheet` (one `forContext` factory → the one paywall), same condition in both sheets. Diagnose a7f2d9.
- **status:** fixed

## Finding 4 — P2 — sync_atomicity (R2-F2)
- **file:line:** `lib/core/services/swap_service.dart` `swapDays` — the allowance check in `build` vs `recordSwap` after the write
- **claim (as corrected):** the reviewer's mechanism — a lost read-modify-write increment in `DaySwapAllowance.recordSwap` — is wrong: `userBox` is a raw Hive box whose in-memory put is synchronous, and `recordSwap` has no await before it. The DEFECT is real by a different route: check-then-act across awaits, under a lock keyed only by the two dates, so two concurrent swaps on different pairs of one week both pass "not spent".
- **verification:** "free: two CONCURRENT swaps in one week — exactly one is done" (`day_swap_engine_test.dart`); week lock bypassed → both Done.
- **fix:** `_withWeekLock` per IST week (the `UsageCounterService._withLock` shape). Diagnose e2b9d4.
- **status:** fixed

## Finding 5 — P2 — writer_reader_drift / provider invalidation (R2-F3)
- **file:line:** `lib/features/ai_coach/services/tool_dispatcher.dart` `execute` — `if (!result.success) return result;` before the `swap_workout_days` invalidation block
- **claim:** a refused coach swap refreshed nothing; on a refusal that block is the only refresh path (no allowance revision bump), and a refusal is precisely when the cached week is stale.
- **verification:** "a REFUSED coach swap still refreshes daySwapWeekProvider"; gating the block on success → `Expected: completed Actual: null`.
- **status:** fixed (block moved above the early return). Diagnose a7f2d9.

## Finding 6 — P3 — consistency (R2-F4)
- **file:line:** `swap_service.dart` `preview` — locks before allowance; `swapDays`'s `build` — allowance before locks
- **claim:** preview and confirm could name different refusals for the same pair (dead today: `DaySwapPreview.refusal` has no lib reader).
- **verification:** "preview names the same refusal as swapDays when spent AND locked"; old order → `Expected: allowanceSpent Actual: completed`.
- **status:** fixed. Diagnose e2b9d4.

## Finding 7 — P3 — test coverage, informational (R3-F1)
- **file:line:** `supabase/functions/consume-day-swap/index.ts` `serve()` handler
- **claim:** no runtime test of the handler itself.
- **verification:** `logic.ts` holds every decision (15/15 Deno tests, 3 mutations each reddening its test); the handler is auth + dispatch in the same shape as `verify-payment` / `delete-account`, and R3 confirmed it matches the §4.4 rule-9 contract (service-role client, `getUser(token)`, user id from the token never the body). Live 401/200 check with a real user token is part of the Task 34 deploy verification (deploy-rollback skill 6.7).
- **status:** verified_clean

## Finding 8 — P1 — guard_without_its_mirror, gate G2 (R4-F1)
- **file:line:** `scripts/sync_no_now_fallback_lib.dart` `nowFallbackPattern`
- **claim:** `x ??= DateTime.now();` — the identical fallback — passed the hard-fail gate; the `=` broke `\?\?\s*DateTime`.
- **verification:** new lib test; `\?\?` restored → 1 red. No live `??=` now-fallback existed, so the hard-fail gate stayed green.
- **status:** fixed (`\?\?=?`; grep residue — a local or helper — documented in the lib). Diagnose f4c7a9.

## Finding 9 — P1 — guard_without_its_mirror, gate G1 (R4-F2)
- **file:line:** `scripts/sync_hash_skip_atomicity_lib.dart` — the catch-block check
- **claim:** `rethrow` / `return false;` anywhere in the block satisfied it, so `catch (e) { if (false) { rethrow; } }` — always swallowing — passed.
- **verification:** 3 new lib tests; anywhere-match restored → 2 red. Live sync layer still 0 violations (its catches end in `return false;`).
- **fix:** `endsInUnconditionalExit` — the LAST top-level statement must be the exit. Residue documented. Diagnose a9d3f6.
- **status:** fixed

## Finding 10 — P2 — self_attesting_artifact (R4-F3)
- **file:line:** `docs/audit/gate_test_ledger.yaml` — `check_sync_hash_skip_atomicity.dart` and `check_sync_no_now_fallback.dart` evidence
- **claim:** G1's "reddens 4 lib/e2e tests" was stale.
- **verification:** re-measured by the coordinator at 2675345b against both `test_path` files: G1 10 red (9 at dfcd2bde); G2's Mutation 1 8 red (7 at dfcd2bde, recorded as 8). Both entries corrected with the new R4-F1/F2 legs.
- **status:** fixed

## Finding 11 — P3 — diagnose bug_id uniqueness (R4-F4)
- **file:line:** three pre-existing collisions (`f7a2c9`, `e8a3b1`, `d3f7b2`), none touched by this branch; all 7 of this branch's bug_ids unique.
- **claim:** no gate detects a duplicate `bug_id`.
- **verification:** `docs/audit/open_issues.md` OI-140 (OPEN) — its 2026-09-26 re-verification already records these three.
- **status:** verified_clean (tracked as OI-140)

## Finding 12 — P2 — self_attesting_artifact (coordinator-found while verifying Finding 8)
- **file:line:** frontmatter `contract_test_path` / `regression_test_planned` of d5a1e7, e2b9d4, f4c7a9, a9d3f6
- **claim:** four docs named plan-time test files that were never created (`day_swap_engine_atomic_write_test.dart`, `completion_time_resolver_extended_test.dart`, `check_sync_no_now_fallback_test.dart`) under a `must add:` label; R4's path sweep covered the ledger and the registry, not diagnose frontmatter. `validate_diagnose_doc.dart` passes them — it checks the field's presence, not the file.
- **verification:** a regex sweep of every test path in the seven new docs, `Test-Path` each; every contract exists under another name.
- **status:** fixed (repointed; a9d3f6's live-verify SQL is stated as landing with the Task 34 apply)

## Lenses returned clean (from the four reports, spot-checked)
- **EF auth contract / cross-account (R3):** service-role client + `getUser(token)`; user id from the token; PRO read from `subscriptions`, not `users.subscription_status`; `consume_quota` is one atomic `INSERT ... ON CONFLICT ... RETURNING`.
- **Capability gating (R3):** offer-time filter in `registry.ts` AND execution-time re-check in `tool-loop.ts`; 3 mutations each reddened exactly its test.
- **Restore merge L1/L2/L3 + kill switches (R1):** L1 guard disabled → 3/13 red; L3 `>`→`>=` → 1/13 red.
- **Migration 148 (R1):** trigger no-op suppression NULL-safe, `search_path` pinned, live-verify runs inside `BEGIN … ROLLBACK`.
- **unawaited sinks (R1):** 49 new `unawaited(` sites, 0 without a telemetry sink.
- **IO/flood (R1, R3):** migrator runs once per user; `ai-proxy` adds no per-message read; `consume-day-swap` is called once per swap.
- **SoT registry + closure ledger (R4):** ~19 citations re-derived, 0 mismatches; `check_sot_registry_parity` PASS; `validate_audit_closure` PASS (32/32 terminal); all 7 diagnose docs validate.
- **Secrets (R3):** none in the diff.

## Founder triage notes
Triage by the coordinator under auto mode: every finding has a terminal status, 10 fixed in `2675345b`
(+ the ledger re-measure), 2 verified_clean with evidence. No finding was deferred. The founder can
override any status. Hermes (`/hermes-pass`) is required at this tier and runs next.
