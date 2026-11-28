---
bug_id: d3f7b2
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A2c)
status: fixed
blast_radius: platform
symptom: |
  Founder observation #2 (second half): after force-closing and reopening
  the app, the AI Coach chat showed 4 repeated `{"error":"Gemini returned no
  content"}` bubbles for "curd" — a food-logging attempt that never
  belonged in the chat thread at all.
concept: coach_chat_history_render_channel_filter
sot_registry_entry: coach_chat_history_render_channel_filter
writers:
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: _restoreCoachInteractions, line: 225 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "ChatHistoryNotifier.build (no guard, pre-fix)", line: 303 }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method_or_widget: "recentHistoryExchanges (already guarded)", line: 340 }
hive_key_prefix: coach_
hive_key_formula: "coach_<ms>"
sync_methods: []
restore_methods: [_restoreCoachInteractions]
cloud_table: ai_coach_interactions
cloud_columns: [channel]
contract_test_path: test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — no cross-user data path touched.
forbidden_patterns_checked:
  - "a re-typed literal {'app','chat','in_app_orphan'} set duplicated outside CoachInteractionRepository.coachChatChannels"
proposed_fix: |
  _restoreCoachInteractions pulls ALL ai_coach_interactions rows for the
  user with no channel filter — by design, since the repository-side reader
  (recentHistoryExchanges, feeding Gemini's own turn history) already
  filters correctly. ChatHistoryNotifier.build (the chat-BUBBLE renderer)
  had no equivalent guard at all. Applied the SAME coachChatChannels
  allowlist ({'app','chat','in_app_orphan'}, null=local-write=always-chat)
  inside build()'s row loop, skipping the entire row (both its user and AI
  bubble) for any other channel. Promoted the constant from private
  _coachChatChannels to public coachChatChannels on
  CoachInteractionRepository so both readers share one definition rather
  than duplicating the literal set.

  CORRECTED same day (A2d), by the self-triggered B-pass review on this very
  commit, BEFORE it merged: reusing the Gemini-history allowlist for the
  render path was itself a bug — it silently dropped every real proactive
  or paywall channel outside app/chat/in_app_orphan. A live grep of every
  channel value written server-side found 5 such channels: in_app
  (proactive-coach-promotion), promotion_ceremony
  (evaluate-rank-promotions), proactive_i_see_you (i-see-you-callout),
  image_paywall and video_paywall (ai-media-proxy) - plus one more,
  client-side app_event (AppEventsService, analytics-only), that the
  reviewer's own finding had not named. The corrected fix is a SEPARATE,
  purpose-built DENYLIST (CoachInteractionRepository.nonChatAnalysisChannels
  = food_text_analysis/scan_meal/cart_auditor/weekly_report/app_event) for
  the render path only - coachChatChannels reverts to Gemini-history-only,
  unchanged from before A2c. A denylist of the actual analysis-channel set
  (small, closed, IS what the original "curd" bug needs excluded) can't
  miss a future proactive channel the way enumerating "known good" channels
  demonstrably did twice within one review pass.
regression_test_planned:
  - test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart
impact_analysis: |
  Additive filter inserted before the existing row-to-bubble mapping in
  build() — a row that passes the filter is handled completely unchanged.
  No change to recentHistoryExchanges (Gemini-history path) or to the
  restore writer. Renaming the constant (drop leading underscore) has a
  single call site inside its own file, confirmed by grep before renaming;
  the pre-existing coach_chat_history_replay_writer_to_reader_test.dart
  (11 tests) still passes unmodified, confirming no behavior change to that
  concept.

  A2d addendum: the denylist swap touches ONLY ChatHistoryNotifier.build's
  filter condition and CoachInteractionRepository's constant declarations -
  recentHistoryExchanges (and its 11-test contract) is untouched, confirmed
  green after the correction too.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/ai_coach/ - 5 pre-existing infos, 0 new issues. flutter test - file now 16/16 (was 7/7 pre-A2d), coach_chat_history_replay_writer_to_reader_test.dart 11/11 (no regression), coach_media_consent_test.dart 22/22 combined run." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "behavioral test seeds coachBox rows across all 5 denylisted channels + null + in_app_orphan + the 6 previously-dropped proactive/paywall channels, reads the real chatHistoryProvider via a ProviderContainer, asserts render/no-render per row." }
mutation_proven:
  mutated: "A2c mutation (pre-correction): removed the entire channel-check block from ChatHistoryNotifier.build(). A2d mutation (post-correction): reverted the render-path filter from the denylist (nonChatAnalysisChannels) back to the ORIGINAL A2c allowlist shape (negated coachChatChannels.contains(channel)) - i.e. re-introduced the exact regression the review found - confirmed applied by reading the file both times."
  result: "A2c: RED 5 of 7 (scan_meal/cart_auditor/weekly_report rendered when they must not; source-grep pin failed). A2d: RED 6 of 16 - exactly the 5 new proactive/paywall regression tests (in_app, promotion_ceremony, proactive_i_see_you, image_paywall, video_paywall) plus the updated source-grep pin; the 6th proactive channel in that test group (app) correctly stayed GREEN since app was never excluded by either shape. Reverted both mutations; re-ran: GREEN, 16/16 passed."
  confirmed_applied: "Read the file (Edit tool's own before/after) to confirm the removed/reverted block matched the intended mutation both times."
---

## Summary

A restored, failed `food_text_analysis` interaction (a food-logging attempt
for "curd") rendered as an ordinary chat bubble after a cold app restart,
because the chat-bubble renderer had no channel filter at all — unlike the
sibling reader that feeds Gemini's own turn history, which already filtered
correctly.

## Root cause

`_restoreCoachInteractions` intentionally restores every `ai_coach_interactions`
row with no channel filter — that's correct, since filtering is a RENDER-time
decision made independently per consumer. `recentHistoryExchanges`
(feeds the model's own history) already applies a `coachChatChannels`
allowlist. `ChatHistoryNotifier.build` (renders the chat THREAD) had no
equivalent guard, so any restored non-chat-channel row — food-analysis,
scan-meal, cart-auditor, weekly-report — rendered as if it were a real
chat turn.

## Fix (A2c, first cut)

Applied the identical `coachChatChannels` allowlist inside `build()`'s row
loop, skipping the whole row for any channel outside `{'app', 'chat',
'in_app_orphan'}` (a null channel — an ordinary local write — always passes).
Promoted the constant from `CoachInteractionRepository`'s private
`_coachChatChannels` to public `coachChatChannels` so both readers share one
definition instead of duplicating the literal set.

## The regression this introduced, and the correction (A2d)

Found by the self-triggered B-pass review dispatched on this batch's staged
diff, BEFORE merge. `coachChatChannels` is an allowlist tuned narrowly for
"what feeds Gemini's own conversation history" — applying it to the render
path meant anything NOT in `{'app','chat','in_app_orphan'}` silently
vanished, including real, currently-shipping proactive and paywall messages.
A live grep of every `channel:` value written anywhere in
`supabase/functions/` found 5 such channels the reviewer's finding named
(`in_app`, `promotion_ceremony`, `proactive_i_see_you`, `image_paywall`,
`video_paywall`) plus one more the reviewer had not named
(`app_event`, client-side, `AppEventsService` — analytics-only, correctly
excludable either way).

The corrected fix replaces the allowlist with a **denylist** scoped to the
render path only: `CoachInteractionRepository.nonChatAnalysisChannels =
{'food_text_analysis','scan_meal','cart_auditor','weekly_report',
'app_event'}` — the small, closed set of channels that genuinely are raw
analysis output, i.e. exactly what the original "curd" bug needs excluded.
`coachChatChannels` reverts to being used by `recentHistoryExchanges` only,
unchanged from before A2c. A denylist of a closed, known-bad set can't
silently swallow a future proactive channel the way an allowlist of
"known good" channels demonstrably did — twice, within one review pass.

## Verification

- New behavioral tests seed rows across every denylisted channel (plus null,
  `in_app_orphan`, and — added in the A2d correction — all 6 previously
  affected proactive/paywall channels) and read the real
  `chatHistoryProvider`, asserting render/no-render per row.
- New source-grep tests pin that `build()` references
  `nonChatAnalysisChannels` (not `coachChatChannels`, not a re-typed copy)
  and that both constants are each defined exactly once and disjoint.
- Re-ran the pre-existing `coach_chat_history_replay_writer_to_reader_test.dart`
  (11/11 passed) to confirm neither the rename nor the A2d denylist swap
  changed the Gemini-history path.
- Mutation proof (A2c): removed the filter block entirely — 5 of 7
  assertions caught it; reverted, green again.
- Mutation proof (A2d): reverted the render-path filter back to the
  original A2c allowlist shape (i.e. reintroduced the exact regression the
  review found) — 6 of 16 assertions caught it (the 5 new proactive/paywall
  tests + the updated source-grep pin); reverted, 16/16 green again.

## Files changed

- Modified: `lib/features/ai_coach/providers/ai_coach_provider.dart`
- Modified: `lib/features/ai_coach/repositories/coach_interaction_repository.dart`
- Modified: `docs/sot_registry.yaml` (new `coach_chat_history_render_channel_filter` concept, corrected A2d)
- Modified: `test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart` (A2d — added 6 regression tests + app_event exclusion, updated source-pin group)
- Created: this diagnose-doc.
