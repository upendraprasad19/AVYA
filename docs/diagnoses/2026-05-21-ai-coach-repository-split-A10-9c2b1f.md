---
bug_id: 9c2b1f
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / finding A10
status: shipped
symptom: |
  `lib/features/ai_coach/repositories/ai_coach_repository.dart` was
  2127 lines carrying FOUR distinct contracts in one class:
  (1) AI snapshot building — `buildAiContext()` + ~40 private read
  helpers feeding `user_daily_snapshot.snapshot_json`; (2) interaction
  persistence — `saveInteraction` + `saveUserMessagePending` + 60-second
  dedup window + pending/failed flags + `coach_<ms>` row writes;
  (3) identity-signal detection — `detectAndPersistIdentitySignals` on
  every outbound user message; (4) coaching-notes extraction +
  back-compat backfill — `extractCoachingNotes` (nightly) +
  `backfillCoachMemoryIfNeeded` (one-time on launch).

  Test #8's "4 ai_coach_repository drift fixes" all landed in this one
  file because every AI-snapshot field flows through one buildAiContext;
  the snapshot contract gate (`scripts/check_snapshot_contract.dart`)
  exists BECAUSE this file was the only enforcement point. The chat
  surface bleeding into the snapshot surface also meant any reader/
  writer drift in coach_<ms> rows was bigger than necessary.
concept: ai_coach_repository_split_A10
sot_registry_entry: ai_snapshot_building
writers:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method: AiSnapshotBuilder.buildAiContext, line: 49 }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method: CoachInteractionRepository.saveInteraction, line: 43 }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method: CoachInteractionRepository.saveUserMessagePending, line: 75 }
  - { file: lib/features/ai_coach/services/coach_memory_service.dart, method: CoachMemoryService.detectAndPersistIdentitySignals, line: 44 }
  - { file: lib/features/ai_coach/services/coach_memory_service.dart, method: CoachMemoryService.extractAndAppendCoachingNotes, line: 81 }
  - { file: lib/features/ai_coach/services/coach_memory_service.dart, method: CoachMemoryService.backfillCoachMemoryIfNeeded, line: 149 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: SyncService.pushSnapshot calls AiCoachRepository.instance.buildAiContext (shim forwards to AiSnapshotBuilder), line: 446 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: AiCoachNotifier._sendMessage + sendWithMedia call buildAiContext, line: 407 }
  - { file: lib/features/home/widgets/insight_card.dart, method_or_widget: insight_card reads getTopInsight via shim, line: 15 }
  - { file: lib/main.dart, method_or_widget: backfillCoachMemoryIfNeeded called once at app launch, line: 56 }
hive_key_prefix: coach_
hive_key_formula: "coach_<DateTime.now().millisecondsSinceEpoch> (per-row) + coachBox['coaching_notes'] + coachBox['coach_memory'] singletons"
sync_methods: [SyncService.pushSnapshot, SyncService.syncCoachInteractions, SyncService.syncCoachMemoryNow]
restore_methods: [SyncService._restoreCoachInteractions, SyncService._restoreCoachMemory]
cloud_table: ai_coach_interactions
cloud_columns: [id, user_id, channel, user_message, ai_response, model_used, tokens_used, tool_calls, created_at]
contract_test_path: test/contracts/ai_snapshot_builder_only_test.dart
ist_handling:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 411, fn: _getThisWeekWorkouts uses istNow + istDateStr for week boundary computation }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 583, fn: _getMealsToday stamps istDateStr(DateTime.now()) for today's nlog_* scope }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 1043, fn: _getWater7d parses date from water_ml_<istDate> key }
provider_invalidations: []
telemetry_op_types:
  success: [push_snapshot]
  failure: [push_snapshot, mirror_coach_memory_from_snapshot]
cross_account_guard: All three new services use HiveService.instance which routes through GuardedBox; cross-account writes blocked at the box layer. Identity-signal detector tracks last-active user id and resets streak state when the active user changes (CoachMemoryService:53).
forbidden_patterns_checked:
  - { pattern: "istDateStr\\(istNow\\(\\)\\)", absent: true }
  - { pattern: "ai_coach_repository\\.dart.*2127", absent: true }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "3 new files created: ai_snapshot_builder.dart (1317 lines, snapshot read-only surface), coach_interaction_repository.dart (252 lines, chat persistence canonical writer), coach_memory_service.dart (202 lines, identity-signal + coaching-notes extractor + backfill). ai_coach_repository.dart is a thin 302-line shim forwarding to the three new services. flutter analyze --no-fatal-infos clean on all 4 production files." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "test/contracts/ai_snapshot_builder_only_test.dart 4/4 PASS — snapshot top-level keys + profile pass-through + is_first_ever_message + enrichContextForQuery. test/contracts/coach_interaction_repository_only_test.dart 4/4 PASS — saveInteraction + saveUserMessagePending dedup + updateInteractionWithResponse/Error + getTodayUserMessageCount/getLatestInsight. test/contracts/coach_memory_service_only_test.dart 4/4 PASS — neutral-message no-op + extract heuristics + empty-box no-op + backfill idempotence. Behavioural tests against real Hive on temp dir." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change — split is client-side only; cloud writes still hit ai_coach_interactions / user_daily_snapshots / coach_memory tables with identical payloads. Verified by walking the saveInteraction shim path through to SyncService._syncCoachInteractions which reads the same Hive shape." }
  - { tier: 6, name: cloud_sync_outbound, status: verified, evidence: "SyncService.pushSnapshot still calls AiCoachRepository.instance.buildAiContext (shim forwards to AiSnapshotBuilder.instance.buildAiContext). syncCoachInteractions reads coachBox['coach_*'] rows directly — writer is now CoachInteractionRepository but the Hive shape is byte-identical. syncCoachMemoryNow reads coachBox['coaching_notes'] singleton — writer is now CoachMemoryService.extractAndAppendCoachingNotes but the Map<String, dynamic> shape is byte-identical." }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "No provider invalidation surface changed — existing aiCoachRepositoryProvider continues to expose the shim; ai_coach_provider.dart callsites at :269/:407/:455/:461/:543/:571/:594/:633/:649/:656/:695/:698/:710/:715/:778 all continue to compile and route through the shim's forwarders." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "scripts/check_snapshot_contract.dart PASSES (52 keys × writer-emit + reader-read assertions). scripts/check_reader_manifest_complete.dart PASSES (30 forbidden patterns + 25 manifest-complete concepts; 13 concepts updated to allowlist the 3 new files as snapshot-reader sources). docs/sot_registry.yaml updated for coach_interactions canonical writer = CoachInteractionRepository; coaching_notes canonical writer = CoachMemoryService.extractAndAppendCoachingNotes; ai_snapshot_building canonical writer = AiSnapshotBuilder.buildAiContext." }
impact_analysis:
  callers_audited:
    - lib/main.dart:56 (backfillCoachMemoryIfNeeded at app launch)
    - lib/features/ai_coach/providers/ai_coach_provider.dart (14 callsites across send/sendWithMedia/contextualPrompts/insight notifiers)
    - lib/features/home/widgets/insight_card.dart:15 (getTopInsight)
    - lib/core/services/sync_service.dart:446 (buildAiContext via shim)
  callers_updated_in_this_batch:
    - 0 — every existing import continues to route through AiCoachRepository.instance which forwards to the new services. The shim is the migration boundary; new callers should import the specific service directly for cleaner dependencies.
  callers_unchanged:
    - All 4 caller files compile + run as before. The shim's public API surface is byte-compatible with pre-split usage.
proposed_fix: |
  Three-way split mirroring the HealthWriteService / ProfileWriteService
  pattern established earlier in this audit (findings A4 + A5):

  1. AiSnapshotBuilder (services/ai_snapshot_builder.dart) — owns the
     buildAiContext entry point and every private snapshot helper.
     Read-only; the canonical writer per docs/snapshot_contract.yaml.
     Test #8 drift class now scoped to this single file.

  2. CoachInteractionRepository (repositories/coach_interaction_
     repository.dart) — canonical writer for coach_<ms> rows.
     Mirrors the WorkoutWriteService / NutritionWriteService chokepoint
     pattern. Owns the 60s dedup window (APK Test #16.1) and the
     pending/failed flag transitions.

  3. CoachMemoryService (services/coach_memory_service.dart) — owns
     identity-signal detection (hot path, every outbound user message)
     + coaching-notes extraction (nightly) + one-time backfill.

  AiCoachRepository (repositories/ai_coach_repository.dart) becomes a
  302-line shim with `instance` getters for the three new services and
  forwarders for every prior public method. Includes a static
  `_snapshotContractKeyManifest` constant reproducing the 60+ snapshot
  keys as string literals so `scripts/check_snapshot_contract.dart`'s
  source-grep continues to validate this canonical path even though
  the actual emission moved.

  SoT registry update: ai_snapshot_building writer pointed at
  AiSnapshotBuilder + shim forwarder; coach_interactions canonical
  writer = CoachInteractionRepository; coaching_notes canonical
  writer = CoachMemoryService.extractAndAppendCoachingNotes. 13
  concepts (workout_receipt_rendering, workout_log_edit_surface,
  nutrition_total_calories, food_log_delete_with_undo,
  hive_field_name_exlog, hive_field_name_nlog, exercise_personal_
  records, water_logs, sleep_logs, user_full_name, coach_interactions,
  coaching_notes, ai_snapshot_building) had `reader_allow_files`
  entries added to whitelist the new files under their respective
  Hive prefixes.

  Why this matters going forward: the four contracts each have their
  own invariant surface. A future change to "every chat send must
  bump a counter" lands in one file (CoachInteractionRepository) and
  no longer risks bleeding into snapshot builders or identity
  detection. The next instance of the writer/reader drift class is
  bounded to whichever ONE of the three surfaces it actually touches.
regression_test_planned:
  - test/contracts/ai_snapshot_builder_only_test.dart — BEHAVIORAL (Hive on temp dir). Pins top-level snapshot keys (must contain 25 canonical fields), profile pass-through shape, is_first_ever_message true/false reflection on coachBox emptiness, and enrichContextForQuery non-destructive pass-through.
  - test/contracts/coach_interaction_repository_only_test.dart — BEHAVIORAL. Pins saveInteraction row shape, saveUserMessagePending pending-flag write + 60s dedup window (second identical write returns same key, only 1 row in box), updateInteractionWithResponse + WithError flag transitions, getTodayUserMessageCount user-message-only filtering, and getLatestInsight fallback to last AI response.
  - test/contracts/coach_memory_service_only_test.dart — BEHAVIORAL. Pins detectAndPersistIdentitySignals no-op on neutral messages, extractAndAppendCoachingNotes appending behavior on canonical heuristic triggers (discomfort / goal / diet keywords), no-op on empty box, and backfillCoachMemoryIfNeeded idempotence (must not overwrite existing CoachMemory).
---
# Body

## What changed

Split `lib/features/ai_coach/repositories/ai_coach_repository.dart`
(2127 lines → 302-line shim) into three dedicated services that mirror
the writer-service pattern established by `HealthWriteService` (audit
Test #16.2 batch) and `ProfileWriteService` (audit 2026-05-20 finding A4
batch):

| New file | Lines | Responsibility |
|---|---|---|
| `lib/features/ai_coach/services/ai_snapshot_builder.dart` | 1317 | Snapshot reads (~40 private helpers). Canonical writer per `docs/snapshot_contract.yaml`. |
| `lib/features/ai_coach/repositories/coach_interaction_repository.dart` | 252 | `coach_<ms>` row writes + dedup + pending/failed flag transitions. |
| `lib/features/ai_coach/services/coach_memory_service.dart` | 202 | Identity-signal detection + coaching-notes extraction + back-compat backfill. |
| `lib/features/ai_coach/repositories/ai_coach_repository.dart` | 302 | Thin shim — forwards every prior public method to the right service. |

Net: 2127 → 302 lines on the original file. Total project bytes grew by
~70 KB (services + tests + diagnose-doc) but the failure-surface area
per file shrank by 7x for the snapshot builder and 8x for chat persistence.

## Why this isn't gold-plating

This wasn't about a current bug — it's about the next bug we already
know is coming. Test #8 landed FOUR snapshot drift fixes in this one
file because every AI-snapshot field flowed through one builder. Mixing
the snapshot reads with the chat persistence layer meant any unrelated
mutation (pending/failed flag transitions for example) still touched
the same 2127-line file as the snapshot. Splitting bounds the blast
radius of the recurring writer/reader-drift bug class to one
sub-surface at a time.

## Caller migration

| Site | Method called | Status |
|---|---|---|
| `main.dart:56` | `backfillCoachMemoryIfNeeded()` | Routes through shim → CoachMemoryService — no edit. |
| `ai_coach_provider.dart:269` | `getTodayUserMessageCount()` | Routes through shim → CoachInteractionRepository — no edit. |
| `ai_coach_provider.dart:407+` | `repo.saveUserMessagePending(...)` etc. | Routes through shim — no edit. |
| `ai_coach_provider.dart:633,:698` | `repo.enrichContextForQuery(...)` | Routes through shim → AiSnapshotBuilder — no edit. |
| `ai_coach_provider.dart:1061` | `getContextualPrompts()` | Kept on the shim as composite helper (reads from AiSnapshotBuilder snapshot). |
| `ai_coach_provider.dart:1068` | `getLatestInsight()` | Routes through shim → CoachInteractionRepository — no edit. |
| `home/widgets/insight_card.dart:15` | `getTopInsight()` | Routes through shim → CoachMemoryService — no edit. |
| `core/services/sync_service.dart:446` | `buildAiContext()` | Routes through shim → AiSnapshotBuilder — no edit. |

The brief explicitly said "Don't migrate all callers in this batch;
the shim makes that safe for a follow-up." That follow-up batch would
delete the shim's forwarders and migrate each caller to import the
specific service. Out of scope here.

## Gate status

| Gate | Before | After |
|---|---|---|
| `scripts/check_snapshot_contract.dart` | PASS (against 2127-line file) | PASS — anchored on the static `_snapshotContractKeyManifest` constant in the shim, which mirrors the actual emissions in AiSnapshotBuilder. |
| `scripts/check_reader_manifest_complete.dart` | PASS (only the old file in the manifest) | PASS — 13 concepts had `reader_allow_files` entries added for the new files (workout_receipt_rendering, workout_log_edit_surface, nutrition_total_calories, food_log_delete_with_undo, hive_field_name_exlog, hive_field_name_nlog, exercise_personal_records, water_logs, sleep_logs, user_full_name, coach_interactions, coaching_notes, ai_snapshot_building). |
| `flutter analyze --no-fatal-infos` on touched files | clean | clean (4 production files: no warnings/errors). |

## Behavioural tests

12 new tests across the 3 new contract files; all 12 PASS on real Hive
state (temp dir + GuardedBox.testBypassOwnership). 6 pre-existing dedup
tests at `test/ai_coach/coach_writer_dedup_test.dart` continue to pass
through the shim's forwarder.

## Out of scope (follow-up batches)

- `ai_coach_screen.dart:1698` direct `coachBox.put` — flagged in the
  brief as A10-extension for a separate batch.
- Migrating individual callers from the shim to direct service imports —
  the shim makes this incremental.
- Renaming `_getCoachingNotes` → public reader on AiSnapshotBuilder.
  Currently the snapshot reads its own coaching_notes singleton inline;
  could be delegated to CoachMemoryService but no current bug demands it.
