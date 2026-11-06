---
bug_id: c1b9d4
date: 2026-09-22
batch: oi-batching-strategy-e5e359 (Batch A)
status: fixed
blast_radius: account
symptom: |
  OI-232 (founder observed live): switching the AI Coach screen's channel
  toggle to Telegram and then back to in-app chat leaves the message list
  scrolled to wherever it happened to land on remount, instead of jumping
  to the bottom (the most recent message) the way the screen's first paint
  correctly does.
concept: ai_coach_channel_scroll_position
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/ai_coach/screens/ai_coach/screen.dart, method_or_widget: "_ScreenState._jumpToBottom", line: 1 }
readers:
  - { file: lib/features/ai_coach/screens/ai_coach/screen.dart, method_or_widget: "build() ref.listen(channelProvider, ...)", line: 1 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/ai_coach/initial_scroll_to_bottom_test.dart
ist_handling: []
provider_invalidations:
  - "channelProvider (read, not invalidated — this fix only listens to its transitions)"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure UI scroll-position fix, no data access."
forbidden_patterns_checked:
  - "bare initState scroll-to-bottom without the existing one-shot _initialScrollDone gate (still enforced by the pre-existing forbidden-pattern test in the same file)"
proposed_fix: |
  screen.dart's ScrollController is created once per State and is NOT
  recreated across a channel switch, but Flutter does not preserve a
  freshly-built subtree's scroll offset across the Telegram WebView taking
  over the body and the chat ListView being unmounted/remounted — the
  existing `_initialScrollDone` gate in initState() is a ONE-SHOT guard
  for the screen's very first paint only, and correctly does not re-fire
  on this transition.

  Added a `ref.listen(channelProvider, ...)` inside build() that fires
  `_jumpToBottom()` (the same helper initState's first-paint path already
  calls) whenever channelProvider transitions INTO 'in_app' from any other
  value. Deliberately scoped to that one transition — switching in the
  other direction (into 'telegram') has no in-app list to scroll, and
  reads while already 'in_app' (e.g. a new message arriving) are
  unaffected, since `previous != 'in_app'` is false for those.
regression_test_planned:
  - test/ai_coach/initial_scroll_to_bottom_test.dart
impact_analysis: |
  Single-file, single-screen UI fix. No data model, no Hive, no Supabase
  surface touched. The pre-existing forbidden-pattern test in the same
  file (asserting NO bare unconditional initState scroll survives) was
  re-read to confirm the new ref.listen call does not reintroduce that
  anti-pattern — it is gated on a real state transition
  (`previous != 'in_app'`), not unconditional.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "flutter test test/ai_coach/initial_scroll_to_bottom_test.dart: 5/5 green (4 pre-existing + 1 new). flutter analyze on screen.dart: clean." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive read/write in this fix." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "n/a" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "n/a" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "n/a" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "n/a" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "n/a" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "n/a" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "n/a" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "n/a" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "n/a" }
  - { tier: 12, name: "Client → server contract", status: not_applicable, evidence: "Pure client-side scroll-position UI state, no server contract involved." }
mutation_proven:
  mutated: "git checkout -- lib/features/ai_coach/screens/ai_coach/screen.dart (full revert to pre-fix HEAD), keeping the new test."
  result: "flutter test test/ai_coach/initial_scroll_to_bottom_test.dart: exactly 1 of 5 tests reddened — the new channel-switch-back test (Expected: true, Actual: false, i.e. no ref.listen(channelProvider) call found in the source). The 4 pre-existing tests (first-paint gate + forbidden bare-initState-scroll pattern) stayed green, confirming the mutation did not collaterally break unrelated assertions."
  confirmed_applied: "Diffed the reverted file against the fixed backup before and after restore; re-ran the full file green (5/5) after restoring from the backup copy at $TEMP/screen_FIXED.dart.bak."
---

## Summary

Founder-observed (OI-232): switching the AI Coach screen from Telegram
back to in-app chat does not re-land the message list at the bottom the
way the screen's first paint does.

## Root cause

The screen's one-shot `_initialScrollDone` gate in `initState()` correctly
fires `_jumpToBottom()` on the very first build, but nothing re-fires it
when the chat subtree is unmounted (Telegram WebView takes over the body)
and later remounted (switching back to in-app). Flutter does not restore a
freshly-built `ScrollController`'s offset across that remount by itself.

## Fix

Added a `ref.listen(channelProvider, ...)` in `build()` that calls the
existing `_jumpToBottom()` helper exactly when `channelProvider`
transitions into `'in_app'` from any other value — i.e. only on the
switch-back, never on the switch-away and never on an unrelated rebuild
while already in-app.

## Verification

- `flutter test test/ai_coach/initial_scroll_to_bottom_test.dart`: 5/5
  green (4 pre-existing including the forbidden-bare-scroll negative test,
  1 new).
- Mutation proof: full revert of the source fix (test kept) reddens
  exactly the 1 new test; the 4 pre-existing tests, including the
  anti-pattern guard, stay green — confirming the fix is additive and does
  not touch the first-paint gate's existing behavior.

## Files changed

- Modified: `lib/features/ai_coach/screens/ai_coach/screen.dart`
- Modified: `test/ai_coach/initial_scroll_to_bottom_test.dart`
- Modified: `docs/audit/open_issues.md` / `docs/audit/closed_issues.md` /
  `docs/audit/OPEN_INDEX.md` (OI-232 closed)
- Created: this diagnose-doc.
