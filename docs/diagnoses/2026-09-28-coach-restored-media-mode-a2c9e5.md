---
bug_id: a2c9e5
date: 2026-09-28
batch: oi-245-246-restore-fixes
status: fixed
blast_radius: platform
symptom: |
  OI-245. `SyncService._restoreCoachInteractions` (sync_coach.dart) hardcoded
  every restored `ai_coach_interactions` row's Hive `mode` field to
  `'quick'`. `CoachInteractionRepository.recentHistoryExchanges` (the reader
  that assembles Gemini chat history) excludes a row only when
  `mode == 'media'`. Verified live-code-read 2026-09-28: a successful PRO
  photo analysis is inserted by `ai-media-proxy/index.ts` with
  `channel: 'app'` (identical to a normal chat turn — `coachChatChannels`
  cannot discriminate it) and `user_message: '[Photo: ${media_type}] ...'`.
  Restoring that row on a new device / reinstall therefore produced a Hive
  row with `mode: 'quick'`, which passed the reader's `mode == 'media'`
  exclusion and was replayed into the model's next-turn context as if the
  user had typed the photo placeholder text as plain chat.
concept: coach_chat_history_replay
sot_registry_entry: coach_chat_history_replay
writers:
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "isRestoredMediaRow — pure recognizer for the server's [Photo/[Video placeholder-text prefix", line: 69 }
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_restoreCoachInteractions — derives mode from isRestoredMediaRow instead of hardcoding 'quick'", line: 284 }
readers:
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method_or_widget: "recentHistoryExchanges — excludes a row on mode == 'media'", line: 362 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods:
  - "SyncService._restoreCoachInteractions (sync_coach.dart)"
cloud_table: ai_coach_interactions
cloud_columns: [user_message, channel]
contract_test_path: test/contracts/coach_restored_media_mode_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types: []
cross_account_guard: Not applicable — restore is already scoped to the signed-in user's own cloud rows via the existing userId-filtered query; this fix changes only the Hive `mode` value derived per row, no account-scoping logic.
forbidden_patterns_checked:
  - "a cloud `mode` column for the server to write — rejected: the cloud table carries no mode column at all (same gap isRestoredHardFailureRow already documents for the hard-failure restore case), and adding one is a migration for a value fully re-derivable from existing text, the same reasoning that fix used."
  - "matching on channel alone — rejected: the successful PRO-photo insert uses channel 'app', identical to a normal chat turn; channel cannot discriminate this case, which is exactly why it slipped past coachChatChannels and needed the mode-derivation fix instead."
proposed_fix: |
  Add `isRestoredMediaRow(String? userMessage)` — pure, recognizes the
  `'[Photo'`/`'[Video'` prefix `ai-media-proxy/index.ts` writes for every
  media-turn insert (paywall-exhausted, video-paywall, AND the successful PRO
  analysis). `_restoreCoachInteractions` derives `mode` from it instead of
  hardcoding `'quick'`. Mirrors the established pattern
  `isRestoredHardFailureRow` already uses for the sibling gap (cloud table
  carries no flag column, so restore recognizes the row by text instead).
regression_test_planned:
  - test/contracts/coach_restored_media_mode_writer_to_reader_test.dart (new, 16 tests) — PARITY: the recognized prefixes still match ai-media-proxy/index.ts's literal insert text (2). BEHAVIOR: isRestoredMediaRow pure/mutation-tested for every server prefix, the local-only client placeholder, real chat text, null/empty, and a near-miss that merely mentions a photo mid-sentence (7). WIRING: _restoreCoachInteractions derives mode via isRestoredMediaRow, not a hardcode (source-grep, 1). DOWNSTREAM: a restored PRO-photo row (channel app) is excluded from recentHistoryExchanges while a restored real chat turn on the same channel survives (behavioral, real Hive, 1).
  - "Mutations run (rule 21): reverted 'mode' to the hardcoded 'quick' literal — the WIRING test (source-grep) reddened exactly as expected (1 of 11 assertions in that run); confirmed the mutation applied via `grep -c \"'mode': 'quick'\"` before/after. Restored the fix; full 11-test file green again."
impact_analysis: |
  - Every user with a restored PRO photo-coach turn (fresh install / new
    device / cleared Hive, after having used PRO photo analysis at least
    once): the restored turn is now correctly excluded from Gemini chat
    history replay, matching the live (non-restored) behavior.
  - No cloud/schema change. No deploy. Client-only.
  - No behavior change for a restored plain-text chat turn, a restored
    hard-failure apology row, or a restored non-chat-channel row (all
    already excluded by existing, untouched filters).
  - Tier: this fix touches lib/core/services/sync/** — platform tier per
    docs/blast_radius.yaml (first-match-wins; lib/features/ai_coach/** alone
    is account tier, but the writer lives under lib/core/services/sync/**).
related_bugs: [a1c6b9]
recurrence: >-
  Same class as diagnose a1c6b9 (isRestoredHardFailureRow): the cloud
  `ai_coach_interactions` table carries no flag column for a Hive-only
  concept (there, hadHardFailure; here, mode), so a restored row loses the
  signal and the reader's exclusion filter never fires. The fix pattern is
  identical — recognize the row from text the server already writes, rather
  than adding a column for a derivable value.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "isRestoredMediaRow added + wired in sync_coach.dart; flutter analyze lib/ — 45 pre-existing infos, 0 new issues." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/contracts/coach_restored_media_mode_writer_to_reader_test.dart's downstream group seeds real coachBox rows and asserts recentHistoryExchanges' output — 16/16 green." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — ai_coach_interactions is read-only in this fix." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "ai-media-proxy/index.ts is unchanged; the parity test only reads its existing source text to confirm the recognized prefixes still match." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "No request/response shape changed — restore's read of ai_coach_interactions and its Hive write shape are unchanged except the single 'mode' field's derivation." }
---

# Restored PRO photo-coach turns replayed to Gemini as plain text (OI-245)

## Root cause

`_restoreCoachInteractions` (sync_coach.dart) hardcoded every restored
`ai_coach_interactions` row's Hive `mode` field to `'quick'`, because the
cloud table carries no `mode` column at all — the exact same structural gap
diagnose `a1c6b9` already documents and fixed for the `hadHardFailure` flag.
`CoachInteractionRepository.recentHistoryExchanges` excludes a row from
Gemini history replay only when `map['mode'] == 'media'`, so a restored photo
turn always failed that check.

The live-path writer, `ai_coach_provider.dart`'s `sendWithMedia`, sets
`mode: 'media'` locally when the user sends a photo — but that local write
is never itself pushed to cloud; the AUTHORITATIVE cloud row is inserted
server-side by `ai-media-proxy/index.ts`, whose successful-analysis path uses
`channel: 'app'` — indistinguishable by channel from a normal chat turn — and
`user_message: '[Photo: ${media_type}] ${message}'`.

## Fix

`isRestoredMediaRow(String? userMessage)` recognizes the `'[Photo'`/`'[Video'`
prefix every ai-media-proxy insert uses (verified against the live source:
the successful-analysis path, the free-image-paywall path, and the
video-paywall path all share it). `_restoreCoachInteractions` now derives
`mode` from this recognizer instead of the hardcode.

## Verification

`test/contracts/coach_restored_media_mode_writer_to_reader_test.dart`
(16 tests, all four groups described above) plus a full re-run of
`test/sync/` + the pre-existing coach-history suite — no regressions.
