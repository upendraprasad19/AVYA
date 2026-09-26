---
bug_id: e8a3b1
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A4)
status: fixed
blast_radius: platform
symptom: |
  Founder observation #4: reopening the app after a background restore
  (cold start, `_restoreCoachInteractions` pulling new/updated rows into
  coachBox) kept showing the AI Coach chat thread as it looked BEFORE the
  restore landed — stale messages, missing turns — for the rest of the
  session, until some unrelated rebuild happened to touch the provider.
related_bugs: [e8a3b1]
concept: ai_coach_chat_history
sot_registry_entry: "none — reactive UI-wiring fix, no new Hive key/field; see impact_analysis"
writers:
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: _restoreCoachInteractions, line: 225 }
  - { file: lib/features/auth/screens/restoring/heal_after_restore.dart, method_or_widget: "post-restore heal (fires the tick)", line: 74 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "ChatHistoryNotifier.build (no reactive link, pre-fix)", line: 165 }
  - { file: lib/features/ai_coach/screens/ai_coach/screen.dart, method_or_widget: "_AiCoachScreenState.initState/_onRestoreCompleted/dispose (new wiring)", line: 184 }
hive_key_prefix: coach_
hive_key_formula: "coach_<ms>"
sync_methods: []
restore_methods: [_restoreCoachInteractions]
cloud_table: ai_coach_interactions
cloud_columns: []
contract_test_path: test/features/ai_coach/coach_chat_restore_invalidation_test.dart
ist_handling: []
provider_invalidations: [chatHistoryProvider]
telemetry_op_types:
  success: []
  failure: [ai_coach_screen_restore_tick_listen]
cross_account_guard: Not applicable — no cross-user data path touched.
forbidden_patterns_checked:
  - "adopting HiveTabScaffoldMixin on AiCoachScreen (documented, gated architectural exclusion — check_tab_screen_uses_hive_scaffold.dart's allow-list)"
proposed_fix: |
  ChatHistoryNotifier.build() reads coachBox synchronously once, with no
  reactive link to a background restore completing. The other 4 tab screens
  get this link for free via HiveTabScaffoldMixin, which listens to
  SyncService.instance.restoreCompletedTick (a ValueNotifier<int> bumped by
  bumpRestoreCompleted() from heal_after_restore.dart:74) and invalidates
  their providers. AI Coach deliberately does NOT use that mixin (documented
  exclusion in the mixin's own header — fundamentally different mount shape),
  so it never got the invalidation half of that wiring either. Wired
  _AiCoachScreenState directly to the SAME underlying signal
  (SyncService.instance.restoreCompletedTick) without adopting the mixin:
  addListener(_onRestoreCompleted) in initState (screen.dart:184-185,
  try/catch-guarded so a test harness or pre-init screen mount can't crash on
  it), a new _onRestoreCompleted() (screen.dart:202-205) that guards on
  `mounted` and calls `ref.invalidate(chatHistoryProvider)`, and a symmetric
  removeListener in dispose (screen.dart:282-283). No separate scroll fix was
  needed: the screen's existing `ref.listen(chatHistoryProvider, ...)` already
  scrolls to bottom on any value change, so the invalidated rebuild falls
  through to that path for free.
regression_test_planned:
  - test/features/ai_coach/coach_chat_restore_invalidation_test.dart
impact_analysis: |
  Additive: a new listener registration + a new private method + a symmetric
  removal. No change to _restoreCoachInteractions, no change to
  ChatHistoryNotifier.build's row-mapping logic, no change to any Hive key or
  cloud column — this is a reactive-invalidation wiring fix, not a data
  contract change, which is why no docs/sot_registry.yaml entry was added
  (checked: no existing concept covers "when does the chat screen re-read
  coachBox", and Gate 9 only requires an entry for a non-empty
  hive_key_prefix tied to a NEW writer/reader pair — this fix adds neither).
  Same shape as A1 (swap-undo snackbar dismiss), which was also a pure
  UI-lifecycle fix with no registry entry. The try/catch around addListener
  mirrors HiveTabScaffoldMixin's own guard for the identical call, so a
  future widget test that pumps AiCoachScreen without SyncService initialised
  degrades the same way the mixin already does elsewhere, rather than
  crashing the mount.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/ai_coach/ — 5 pre-existing infos, 0 new issues. flutter test test/features/ai_coach/coach_chat_restore_invalidation_test.dart — 6/6 passed." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "Behavioral test seeds coachBox rows before and after a simulated restore tick (via tester.runAsync, real coachBox), reads the real chatHistoryProvider through a ProviderContainer, and asserts the post-restore row renders." }
mutation_proven:
  mutated: "Removed the addListener(_onRestoreCompleted) try/catch block from _AiCoachScreenState.initState() in screen.dart, confirmed applied by reading the file before running."
  result: "Ran flutter test test/features/ai_coach/coach_chat_restore_invalidation_test.dart: RED on exactly 1 of 6 — the source-grep pin 'initState registers the restore-tick listener' (Expected: true, Actual: false). The 2 behavioral tests stayed green (they exercise a fake ValueNotifier harness defined in the test file, not the real screen, so they can't see this mutation — documented in the test file's own header) and the other 3 source-grep pins stayed green (they check unrelated regions: _onRestoreCompleted's body, dispose's removeListener call, and the HiveTabScaffoldMixin-absence pin). Reverted the mutation by reading the current initState() body and restoring the exact removed block; re-ran: 6/6 green."
  confirmed_applied: "Read the file both before removing (to capture the exact block) and after reverting (via a targeted Read of the initState region) to confirm the restored text matched the original byte-for-byte."
---

## Summary

Reopening the app (or otherwise triggering a background restore) after AI
Coach had already mounted left the chat thread frozen at its pre-restore
state for the rest of the session — new or corrected rows landed in
`coachBox` but the chat screen never re-read them.

## Root cause

`ChatHistoryNotifier.build()` reads `coachBox` synchronously once, with no
reactive dependency on `_restoreCoachInteractions` completing. The other 4
tab screens (Home/Train/Nutrition/Profile) get exactly this invalidation for
free via `HiveTabScaffoldMixin`, which listens to
`SyncService.instance.restoreCompletedTick` and invalidates their providers
when it fires. AI Coach deliberately excludes itself from that mixin
(documented in the mixin's own header — its mount shape doesn't fit), and
that exclusion silently took the invalidation wiring with it — nobody ever
gave AI Coach an equivalent.

## Fix

Wired `_AiCoachScreenState` directly to the same underlying signal
(`SyncService.instance.restoreCompletedTick`) without adopting the mixin
itself, preserving the documented architectural exclusion:

- `initState()` registers a try/catch-guarded `addListener(_onRestoreCompleted)`.
- A new `_onRestoreCompleted()` guards on `mounted` and calls
  `ref.invalidate(chatHistoryProvider)`.
- `dispose()` symmetrically removes the listener.

The screen's existing `ref.listen(chatHistoryProvider, ...)` already scrolls
to bottom on any value change, so no separate scroll-specific fix was needed
— the invalidated rebuild falls through to that path for free.

## Verification

- New behavioral test seeds a pre-restore row, mounts the screen, seeds a
  post-restore row, fires a fake restore-tick (a `ValueNotifier<int>`
  standing in for the real singleton — touching `SyncService.instance`
  directly inside `testWidgets` hangs the runner outright, and even the fake
  notifier's real Hive I/O had to be wrapped in `tester.runAsync` for the
  same fake-async-zone reason), and asserts the post-restore row now renders.
- A second behavioral test confirms `dispose()` actually removes the
  listener (firing the tick post-dispose must not throw).
- 4 source-grep tests pin that the real `screen.dart` wires this exact
  mechanism to the real `SyncService.instance` singleton, and that the
  screen still does not adopt `HiveTabScaffoldMixin`.
- Mutation proof: removing the real `initState()` registration reddened
  exactly the one source-grep test built to catch it, and nothing else —
  confirming the other 5 tests don't accidentally depend on that wiring.
  Reverted; 6/6 green again.

## Files changed

- Modified: `lib/features/ai_coach/screens/ai_coach/screen.dart`
- Created: `test/features/ai_coach/coach_chat_restore_invalidation_test.dart`
- Created: this diagnose-doc.
