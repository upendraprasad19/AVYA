---
reviewed_at: 2026-11-12T16:35:00+05:30
staged_against: 19b3c23bb59b8d951f3a7bec82f44b8b780ad10c
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: coordinator triage 2026-11-12; F2 and F4 fixed in the follow-on commit, F1 and F3 false alarms with reasons, F5 already tracked on OI-253.
---

# Code Review: OI-479 "Clear conversation" (branch `oi479-clear-conversation`)

One fresh, context-blind Sonnet reviewer read the three-dot diff `origin/main...19b3c23b`, which was CI-green: 27 files,
plus the inventory fix. It used the agent brief preamble, all 8 lenses, and an exhaustive read-only command list (the
four new test files, `dart analyze`, and read-only git). It ran no mutations, no scripts and no SQL. It ran the four test
files under `TZ=Etc/GMT+12`: 11, 15, 7 and 5 tests, all green. It found no P0, P1 or P2.

## Finding 1 — P3 — guard_without_its_mirror
- **file:line:** lib/core/services/coach_chat_clear.dart:78-87 (`raiseTo`), :99-108 (`clear`)
- **claim:** A device clock that runs fast at the clear and is later stepped back stores a future marker. New turns
  until the clock catches up are hidden. Suggested fix: cap the read at `min(stored, now)`.
- **verification:** `grep -n "NO read-time clamp" docs/plans/2026-11-12-oi479-clear-conversation.md`
- **status:** false_alarm. The suggested fix is the regression plan-review round 1 rejected (F2): a read-time cap of a
  future marker to `now` hides every row up to `now`, including every row written after the clear, and keeps doing so on
  each read while the stored value is in the future. The case itself is the documented clock-skew residue (plan 3.1):
  a clock fast by d hides new turns for d at most, because the device's own clock stamps both the marker and the rows.

## Finding 2 — P3 — unawaited_no_error_sink
- **file:line:** lib/features/ai_coach/screens/ai_coach/compact_header.dart:133-134
- **claim:** `unawaited(confirmClearCoachConversation(context, ref))` has no error sink. A throw from
  `CoachChatClear.clear()`, for example a closed user box mid sign-out, would be an uncaught zone error.
- **verification:** `git diff origin/main...19b3c23b -U0 | grep -n "unawaited("`
- **status:** accepted, fixed. The flow catches the throw, records `coach_chat_clear_failed` and shows "Couldn't clear
  this chat. Try again." Test: `test/ai_coach/clear_conversation_menu_test.dart` "a clear that throws is reported and
  told". Mutation: try/catch removed, 1 red, restored byte-identical.

## Finding 3 — P3 — writer_reader_drift
- **file:line:** lib/features/home/providers/home_provider.dart:725-748 (`_getLatestCoachTip`)
- **claim:** The Home coach tip ignores the marker, so after a clear it can still quote the last cleared reply.
- **verification:** `grep -n "Home tip" lib/features/ai_coach/CLAUDE.md`
- **status:** false_alarm. Out of scope by the founder's instruction "we should only clear the conversation in the chat"
  (2026-11-12). Coordinator call C1 in the plan keeps the Home tip unchanged, and the nested CLAUDE.md row lists it
  among the deliberate non-readers.

## Finding 4 — P3 — writer_reader_drift (registry bounds)
- **file:line:** docs/sot_registry.yaml, concept `coach_chat_cleared_at`, `_restoreUserPreferences` `line_range: 1085-1176`
- **claim:** The real span is 1088-1179. The parity gate checks bounds only, so it passes.
- **verification:** `grep -n "Future<void> _restoreUserPreferences" lib/core/services/sync/sync_profile.dart`
- **status:** accepted, fixed, and widened by the coordinator to every registry cite into a file the batch touched:
  - Five spans corrected: the two `_restoreUserPreferences` block cites, the inline cite at `971-1033`,
    `_syncUserPreferences` `588-673` (real `663-753`), and `ChatHistoryNotifier.build` `165-327` and `172-221` (real
    `172-361`). Three of these were already stale on `main`.
  - 13 bare single-line cites that the batch's shift had skipped were moved. All 15 bare cites into touched files now
    point at the same text they cited on `main`.
  - Class OI-262; this measurement is recorded there.

## Finding 5 — P3 — guard_without_its_mirror
- **file:line:** lib/features/auth/providers/auth_provider.dart:1010-1025
- **claim:** A clear made offline, followed by sign-out before the push lands, is lost with the wiped user box.
- **verification:** `grep -n "OI-253" docs/diagnoses/2026-11-12-coach-clear-conversation-noop-5970aa.md`
- **status:** accepted, no change. This is the documented OI-253-class residue, recorded on OI-253 as a second instance.

## Founder triage notes
Coordinator triage on the founder's standing direction to carry a unit through its pipeline. The merge itself stays the
founder's call.

## Tuning entry
- **2026-11-12** - blast-radius platform - 5 findings; 2 false_alarm (40%); tuning: both false alarms re-opened
  decisions the plan had already recorded (a rejected read-time clamp, a founder scope call), so SKILL.md section 3 step
  4 now has the brief carry the plan's rejected alternatives and the founder's scope decisions. The lens-1 inserted-lines
  sub-check now also covers bare single-number cites, which a range-only shift skips.
