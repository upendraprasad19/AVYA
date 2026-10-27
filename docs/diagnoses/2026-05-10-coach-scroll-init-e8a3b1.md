---
bug_id: e8a3b1
date: 2026-05-10
batch: APK Test #15
status: in_progress
symptom: Opening the AI coach screen lands the scroll position at 0 (oldest message at top). User has to manually scroll down through the entire transcript just to see the latest exchange and reach the input row.
concept: ai_coach_chat_history
sot_registry_entry: ai_coach_chat_history
writers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: chatHistoryProvider, line: 1 }
readers:
  - { file: lib/features/ai_coach/screens/ai_coach_screen.dart, method_or_widget: _AiCoachScreenState.build, line: 248 }
hive_key_prefix: null
hive_key_formula: "coachBox['ai_coach_interactions'] (cached) + ai_coach_interactions cloud table (live)"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns:
  - id
  - user_id
  - created_at
  - role
  - content
contract_test_path: test/ai_coach/initial_scroll_to_bottom_test.dart
ist_handling: []
provider_invalidations:
  - chatHistoryProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "_scrollToBottom\\(\\)\\s+inside\\s+initState", absent: true }
proposed_fix: |
  Add bool _initialScrollDone = false flag on _AiCoachScreenState. Add
  _jumpToBottom() method that uses ScrollController.jumpTo (no animation,
  no flash on first paint). In build(), after watching chatHistoryProvider,
  add gate: if (!_initialScrollDone && messages.isNotEmpty) {
  _initialScrollDone = true; _jumpToBottom(); }. ref.listen calls
  unchanged — they handle subsequent message arrivals with the existing
  300 ms _scrollToBottom animation.
regression_test_planned:
  - test/ai_coach/initial_scroll_to_bottom_test.dart
---

# Bug E — AI coach scrolls to bottom on first paint

## Symptom

Opening the AI coach screen lands the scroll position at 0 (oldest message at top of viewport). User has to manually scroll down through the entire transcript just to see the latest exchange and reach the input row at the bottom. Founder reported this as friction during APK Test #14 install: "AI coach, always gets scrolled to top. this is too much work for a user to scroll down and then strt chatting."

## Root cause

`_AiCoachScreenState.build()` (lib/features/ai_coach/screens/ai_coach_screen.dart:263-268) wires `_scrollToBottom()` via four `ref.listen` calls — `chatHistoryProvider`, `pendingLogActionsProvider`, `pendingToolIntentsProvider`, `workoutDraftProvider`. These fire when the provider value CHANGES, but never on the initial mount when the cached transcript is already populated. Result: the screen builds, the ListView lays out from index 0 down, and no scroll command ever fires until the next provider value change (which only happens when the user sends a message or a new tool intent appears).

`initState` was not a viable home for the scroll either — `ScrollController` has no clients before the ListView is built, and the messages provider may not be loaded synchronously on mount.

## Fix

Build-time one-shot gate in `build()`:

```dart
if (!_initialScrollDone && messages.isNotEmpty) {
  _initialScrollDone = true;
  _jumpToBottom();
}
```

`_jumpToBottom()` uses `ScrollController.jumpTo(maxScrollExtent)` — instant, no animation. `_scrollToBottom()` (300 ms `animateTo`) stays for subsequent message arrivals where the eased motion is the right UX. The gate flips `_initialScrollDone = true` so the jump fires exactly once per screen mount.

## Verification

- 4 source-grep contract tests pass:
  - `_initialScrollDone` flag declared
  - `_jumpToBottom()` method exists with `jumpTo(maxScrollExtent)`
  - Build-time gate `!_initialScrollDone && messages.isNotEmpty` calls `_jumpToBottom()` (NOT `_scrollToBottom()` — which would flash)
  - Forbidden: `_scrollToBottom()` / `_jumpToBottom()` directly inside `initState`
- On-device verification at install: opening AI coach with non-empty history lands at the latest reply + input row visible. No scroll-from-top flash.

## Related

- `ref.listen` lifecycle — only fires on value transitions, not mount. This is the same class of bug as Test #12.6's `subscriptionInfoProvider` cold-start issue (state-change provider needs explicit first-paint trigger).
- `_jumpToBottom` vs `_scrollToBottom` — preserve both; first-paint and incremental updates have different UX needs.
