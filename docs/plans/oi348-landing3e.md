# OI-348 Landing 3e: dictated words readable in full (V1)

Status: CONVERGED. Round 3 (narrow) closed every R2 item; 4 small plan-text fixes (N1-N4) folded, no code-shape change.
Branch / worktree: `oi348-landing3e`, off main `02f70bf8`. Tier M (an `ai_coach` UI file), blast radius `account`
(`docs/blast_radius.yaml:438`: `lib/features/ai_coach/**`). Execution: inline, one author.

## 1. Observation and decision
Founder, 2026-11-25, A19 on AAB +50: a long dictated sentence cannot be read in full before it is sent. After Stop,
all the spoken text should be visible, so it can be checked, edited and sent (like the Claude app's voice input).
Founder go, 2026-11-26: "Start 3e", after this proposal: a multi-line field that grows to about 6 lines and then
scrolls, in BOTH dictation hosts; the live words wrap while listening; A19 step 8 is amended.

This reverses one display choice of `docs/plans/voice-input-unified.md` D4 (line 87, review row R2B-10): "the live
words in a reversed single-child horizontal scroll so the NEWEST words stay visible". The newest words stay visible
(section 3), but the older ones are no longer pushed off a single line.

Not a data loss: Send already sends the whole string (`SpeechInputController._finish(userSend, _liveText)` ->
`CoachComposer._onSpeechEnd` -> `_writeField(combined); widget.onSend(combined)`). Only the display is one line.

## 2. Writer and readers (file:line on main 02f70bf8)
- Writer of the words: `SpeechInputController._liveText` (`lib/core/services/speech_input_controller.dart:117`,
  written by `engineResult` `:404-427`), sent whole by `_finish(SpeechEndReason.userSend, _liveText)` (`:203`) as
  `SpeechSessionEnd.transcript` (built at `:548`). Unchanged.
- Coach, while listening: `_LiveWords` (`lib/features/ai_coach/screens/ai_coach/input_bar.dart:555-589`):
  `maxLines: 1`, `softWrap: false`, horizontal `SingleChildScrollView(reverse: true)` with
  `NeverScrollableScrollPhysics`, inside the fixed `height: 48` bubble (`:240-253`).
- Coach, after Stop: `_onSpeechEnd` (`:151-195`) -> `_writeField` (`:144-149`) -> `composerField` `TextField`
  (`:309-329`), no `maxLines` (one line), cursor at the end, so only the tail shows.
- Nutrition, while listening and after: `FoodLoggerSection` `TextField` (`lib/features/nutrition/widgets/
  food_logger_section.dart:294-312`), no `maxLines`, `readOnly: speechBusy`; live words through `_setFieldText`
  (`:90-96`) from `_onSpeechChanged` (`:100-104`); the field is UNFOCUSED while listening (`_onMicTap` `:178`).
- The chat list above the coach composer: `Expanded` `ListView` (`screen.dart`), followed to its bottom only by
  `_scrollToBottom` (`:213`) and `keepBottomAfterChip` (`measurement_chip_slot.dart:177`, wired at `screen.dart:376`).

## 3. Change
Shared, in `lib/core/services/speech_input_lifecycle.dart` (both hosts import it; not a platform-tier path):
`kDictationFieldMaxLines = 6`, `kDictationLineHeight = 1.4` and `kDictationStrut = StrutStyle(fontSize: 14, height:
1.4, forceStrutHeight: true)` (R1-3). A forced strut makes every line exactly `scale(14) * 1.4` tall, whatever the
font's metrics and whether DM Sans has loaded (google_fonts loads it asynchronously), so the live box's cap and the
fields' own 6-line height are the same number. The cap is `MediaQuery.textScalerOf(context).scale(14) * 1.4 * 6`.
No `TextPainter`.

C1. Coach bubble (`input_bar.dart:240-253`): `height: 48` becomes `constraints: BoxConstraints(minHeight: 48)`, and
the padding gains 5 dp top and bottom (R1-1: the 1 dp border is added to the padding by `Container`, so a one-line
bubble is 36 + 10 + 2 = 48). Radius 24 stays.

C2. Coach idle field (`composerField`): keep `controller:` and `focusNode:` as the first two arguments (pinned by
`measurement_flag_off_identity_test.dart:576`), add `minLines: 1`, `maxLines: kDictationFieldMaxLines`,
`keyboardType: TextInputType.text`, `strutStyle: kDictationStrut`, and `hintMaxLines: 1` in its decoration (R1-9:
the limit hint must not wrap and grow an untouched bubble). `TextInputType.text` keeps the `done` action
(`EditableText` picks `newline` only for `TextInputType.multiline`), so the keyboard's action key still calls
`onSubmitted` (send) and never inserts a newline; on the web the engine uses an `<input>` for a text type, so a
hardware Enter also sends (read from the SDK, checked live on the web after the merge). Pasted newlines are not
blocked, as today. The idle `Row` uses `CrossAxisAlignment.end`, so compass, attach, mic and send sit on the last
line as the field grows; the field sits in `ConstrainedBox(minHeight: 36)` + `Align(Alignment.centerLeft)` so ONE
line stays centred against the 36 dp buttons (R1-2; `AlignmentDirectional.centerStart`, R2-9). At the daily limit the `GestureDetector` wraps that whole 36 dp box (R2-8: the paywall tap area grows from the text line to the 36 dp row, a deliberate small change).

C3. Coach listening bar (`_buildListeningBar` + `_LiveWords`): the words wrap (no `maxLines`, `softWrap: true`,
`strutStyle: kDictationStrut`) in a VERTICAL `SingleChildScrollView(reverse: true)` (still
`NeverScrollableScrollPhysics`) under `ConstrainedBox(maxHeight: cap)`, itself in `ConstrainedBox(minHeight: 36)`
+ `Align(AlignmentDirectional.centerStart)` (R1-2, R2-9). The red dot, its 8 dp gap and the clock go in ONE `SizedBox(height: 36)` holding a centred `Row(mainAxisSize: MainAxisSize.min)` (N1: today's 9 dp dot, 8 dp gap and clock; the 10 dp gap
after the clock and the `Expanded` live words stay in the outer Row) (R2-1: under `end` they would otherwise sit on the bottom edge, about 13 dp and 10 dp below the buttons). Up to 6 lines every word shows; past 6 the box stays at 6 lines and shows the NEWEST
(a reversed scroll holds offset 0 at the end). The bar's `Row` uses `CrossAxisAlignment.end`.

C4. The chat follows a taller composer (R1-4). `CoachComposer` gains `onHeightGrew(double delta)`: a private
`_HeightReporter` (a `SingleChildRenderObjectWidget` whose `RenderProxyBox` compares its height after each layout
and, when it grew, schedules ONE post-frame call with the difference) wraps the composer's `Container` (bubble AND counter row). Rules (R2-2): `_lastHeight` starts null and the FIRST layout only records; it is updated on EVERY layout, a shrink
included, so only a step that grows reports, by exactly that step (N2) (a composer mounted with prefilled text reports nothing); `_lastHeight` is set inside `performLayout` before scheduling, so a second layout in the same frame does not schedule twice; `updateRenderObject` replaces the callback (no stale closure); the post-frame call runs only while the render object is `attached`. `onHeightGrew` is an OPTIONAL nullable parameter, passed LAST at the call site, after `onListeningChanged` (R2-4: the identity pin reads `CoachComposer(controller:_messageController,focusNode:_inputFocusNode,`, and the composer tests construct it without the callback). The screen
passes `(delta) => keepBottomAfterChip(_scrollController, delta)`: the chip's existing rule, so a chat at (or within
16 dp of) its bottom stays at its bottom and a chat scrolled up is left alone. A shrink calls nothing (the list
gains room). Edges, stated (R2-3): two growths less than 200 ms apart (a paste followed at once by a typed line) can end the follow short by the second delta, because the first animation still runs and the second call sees more than delta + 16 below; accepted, since dictation adds a line at most about once a second and the next reply runs `_scrollToBottom`. `_scrollToBottom` (300 ms) and this follow share the controller; the later `animateTo` replaces the earlier and both aim at `maxScrollExtent`.

C5. Nutrition field: `minLines: 1`, `maxLines: kDictationFieldMaxLines`, `keyboardType: TextInputType.text` (same
reason as C2: `onSubmitted` runs `_analyse`), `strutStyle: kDictationStrut`, `hintMaxLines: 1`, and a
`ScrollController` owned by the state (`_fieldScroll`, disposed in `dispose`). The field is unfocused while
listening, and an unfocused `EditableText` does not scroll to its caret on a value change (`editable_text.dart`
`_didChangeTextEditingValue` only calls `setState`), so after every live write `_onSpeechChanged` jumps the field to
its end in a post-frame callback, guarded by `mounted`, `_speech.isBusy` and `hasClients` (R1-8: a stale callback
must not fight the Stop-time caret scroll), with a `_jumpScheduled` flag so a burst of partial results schedules one jump per frame (R2-7). The row's alignment stays `center` (R1-10, a stated choice: the 32 dp
mic tile stays in reach in the middle of a 6-line field, and the spark icon and the tile do not split top and
bottom).

After Stop, both fields keep the text and the caret at the end. When Stop asks for focus (`speechEndWantsFocus`),
`EditableText` scrolls to the caret, so a text past 6 lines shows its END; when it does not (a hidden tab, a
preemption), the field shows its first 6 lines and scrolls by hand (R1-7, stated).

Looks, stated (R2-6): the strut makes one line 19.6 dp instead of DM Sans's natural ~18 dp; the coach row stays 36 (bubble 48) and the nutrition row stays at the 32 dp mic tile, so nothing visible moves. The hint has no strut and `hintMaxLines: 1` keeps it under 19.6 dp. `forceStrutHeight` at 1.4 does not clip Latin (DM Sans needs ~1.3), but a Devanagari word from the speech engine drawn in a fallback font may be clipped at the first and last line: accepted, checked once on the device (A19). A 6-line composer on a small phone with the keyboard open takes a large share of the chat: also an on-device check (A19, R2-12).

No kill switch: a layout change outside the CLAUDE.md 4.6 classes (payment, sync, auth, AI prompt, plan generator);
the rollback is a revert.

## 4. Tests (behavioural, real widgets, the fake speech engine)
Setup (R1-5): the surface is 360 x 800 dp; the live-words viewport rect is the render box of the vertical
`SingleChildScrollView`, which shrink-wraps its text under 6 lines and is capped at 6 (N4); the expected line height is MEASURED from a one-word render (a forced
strut makes it exact), never taken from the production formula; text length is grown until the rendered height
passes a target (no "about N lines" by eye). The fonts fall back to the test font; the strut makes heights font-free.

Coach, in `test/ai_coach/coach_composer_speech_test.dart`. The old test "the words show live and the newest stay
visible" (`:167-191`, it asserts a horizontal overflow) is REWRITTEN as T1/T2 (R1-12):
- T1 listening, 3 lines: the live `Text`'s whole rect lies inside the live-words viewport (one `Text`, so no per-word
  rect, R2-10); the bubble is taller than 48.
- T2 listening, 10+ lines: the viewport height equals 6 x the measured line height (within 1 px),
  `text.bottom == viewport.bottom` (within 1 px), `text.top < viewport.top` and `text.height > viewport.height`. Run again with
  `MediaQuery(textScaler: TextScaler.linear(1.5))`: the cap scales with it.
- T3 after Stop, 3 lines: the field has `minLines` 1 / `maxLines` 6, the bubble is taller than 48, the whole text
  is in the controller; once the field has focus, the `TextInput.setClient` arguments in `tester.testTextInput.log`
  carry `inputType.name == 'TextInputType.text'` and `inputAction == 'TextInputAction.done'` (R1-6: THIS is the
  `keyboardType` guard).
- T3b after Stop, 10+ lines (R1-7): the field is 6 lines tall, the text intact, and the caret at the end is in view:
  `EditableTextState.renderEditable.getLocalRectForCaret(TextPosition(offset: len))` (paint offset included) lies
  within the `RenderEditable` size, after pumping past the 100 ms caret animation (R2-7, R2-10).
- T3c cross-check (R2-5): with the same long text, the bubble while listening and the bubble after Stop have the same
  height (within 1 px), so the live cap and the field's own 6 lines are one number.
- T4 mirror: idle empty, idle one line, the one-word listening bar and the limit-reached bubble (hint) each
  measure 48 (`closeTo(48, 0.01)`) (R1-1, R1-9).
- T4b alignment (R1-2, R2-1): with one line, the field's vertical centre equals the compass icon's centre (idle), and
  the live words', the red dot's and the clock's centres equal the X button's centre (listening), each within 1 px.
- T5 the done action sends the whole text once (`receiveAction(TextInputAction.done)` -> `sent == [text]`); it does
  NOT guard the keyboard type (R1-6).
- T9 (R1-4, R2-4) `onHeightGrew`, run for `isPro` true and false: growing the text from one line to three calls it
  with positive deltas whose sum equals the change of the WHOLE composer's `tester.getSize` height; clearing the text
  calls nothing; then grow, shrink, regrow: each reported delta equals the height gained by THAT step and the shrink
reports nothing (N2).
- T9c (R2-2): mounting with 3 lines of text already in the controller calls nothing. The screen wiring is a source pin
  (the screen cannot be pumped): `onHeightGrew: (delta) => keepBottomAfterChip(_scrollController, delta)`.
  `keepBottomAfterChip` itself is already covered by `test/ai_coach/measurement_chip_slot_test.dart`.

Nutrition, in `test/widgets/food_logger_speech_test.dart`:
- T6 listening, 10+ lines: the field's scroll offset equals its max extent after a live write (newest in view).
- T7 mirror: listening, 2 lines: offset 0, the field taller than one line, shorter than 6.
- T8 after Stop, 3 lines: `maxLines` 6, the text intact, the `setClient` arguments as T3, the done action analyses
  once.
- T8b after Stop, 10+ lines: 6 lines tall, caret line in view (as T3b).
- T8c (R2-5, N3): the one-line nutrition field's `RenderEditable` height equals the height of
  `Text('x', style: AppTypography.body, strutStyle: kDictationStrut)` drawn in the test
  (the strut, not the font, sets it), so dropping the strut from the field reddens a test.

Mutations (each applied once, match count checked, restored by copy and compared): coach field `maxLines` back to
1 (T3, T3b); live words `maxLines: 1` (T1); `reverse` removed (T2); the cap removed (T2); the strut dropped from the
live words (T2's scaled run or the cap match); the nutrition jump-to-end removed (T6); `keyboardType` removed on
each field (T3, T8); padding 6 instead of 5 (T4); `CrossAxisAlignment.end` without the min-height centring (T4b);
the dot and clock left outside their 36 dp box (T4b); `_HeightReporter` never calling (T9); the first layout
reported as growth (T9c); `_lastHeight` updated only on growth (T9); the strut dropped from the coach idle field (T3c) and from the nutrition field (T8c).

## 5. Docs
`lib/features/ai_coach/CLAUDE.md` (mic piece: words wrap to 6 lines, newest in view; the composer grows and the chat
follows), `lib/features/nutrition/CLAUDE.md` (mic line), `docs/plans/voice-input-unified.md` (an amendment line
under D4 pointing here), the A19 step 8 text on the OI-348 board entry ("the field shows up to six lines, the newest
in view while speaking; after Stop the whole text, scrolling past six lines; a Hindi phrase shows uncut; on a small
phone with the keyboard open the chat above stays usable"), diagnose doc `c7e3a2` (full
template; tier M; not a recurrence: 6d9f3b lost words, this one never did), `docs/sot_registry.yaml` cites into the
two hosts re-mapped from the post-edit files and re-read (R1-11: `input_bar.dart:136-195` and
`food_logger_section.dart:83-145` are already off on main; `_onSpeechEnd` is `:151-195` / `:106-140`).

## 6. Order
Plan review round 1 (done) -> round 2 on this plan -> build -> local gate loop (whole-project analyze, gates, the
two test files, `measurement_chip_slot_test.dart`, `retry_loop_guard_test.dart` (it reads the whole `ai_coach/`
folder, R2-11), the speech suites) -> commit on the branch -> PR -> CI green ->
B-pass -> plan-review record -> founder go to merge. No migration, no Edge Function.

## Round 1 log (context-blind Sonnet, 2026-11-26)
R1-1 P1 bubble 50 not 48 (border) -> pad 5 (C1). R1-2 P1 `end` lowers one line -> min-height + centre (C2, C3, T4b).
R1-3 P1 TextPainter on a late-loading font, no scaler -> forced strut (section 3). R1-4 P2 chat does not follow ->
C4, T9. R1-5 P2 font-free test setup -> section 4 setup. R1-6 P2 T5 does not guard the keyboard -> T3/T8 setClient.
R1-7 P2 no 10-line after-Stop case -> T3b, T8b, focus note. R1-8 P2 jump guards -> C5. R1-9 P3 hint wraps ->
hintMaxLines. R1-10 P3 nutrition alignment -> stated choice. R1-11 P3 registry cites -> section 5. R1-12 P3 name
the rewritten test -> section 4.

## Round 2 log (fresh context-blind Sonnet seat on the post-round-1 plan, 2026-11-26)
R2-1 P1 dot and clock drop to the bottom under `end` (introduced by R1-2) -> 36 dp centred box, T4b. R2-2 P1 the
reporter's first layout, stale closure, detached call -> four rules in C4, T9c. R2-3 P2 follow edges -> stated and
accepted. R2-4 P2 T9 delta vs counter row, optional param after the pinned pair -> T9 both tiers, call order. R2-5
P2 no cross-check of the shared cap -> T3c, T8c. R2-6 P2 strut look change and Devanagari clipping -> stated, A19.
R2-7 P2 jump burst, caret animation -> `_jumpScheduled`, pump past 100 ms. R2-8 P3 paywall tap area -> stated.
R2-9 P3 RTL -> `AlignmentDirectional.centerStart`. R2-10 P3 rect wording -> T1/T2/T3b. R2-11 P3 header note and
`retry_loop_guard_test` -> section 6. R2-12 P3 small phone + keyboard -> A19 check.

## Build notes (deviations found by the tests, 2026-11-26)
B1 (T4, replaces C1's 5 dp padding and the 36 dp boxes). An M3 `IconButton` pads its tap target to 48 dp under loose
constraints; the old fixed 48 dp bubble squeezed it to 46 (tight 46 inside the 1 dp border). With 5 dp padding the
one-line bubble measured 60. Built instead: the bubble keeps today's zero vertical padding and `minHeight: 48`; every
button (compass, attach, small mic, morph, X, Stop, Send) sits in a `_slot`, a `_kRowHeight` (46) tall box with the
child centred, so the IconButtons keep today's 46 dp tap target and the 36 dp circles stay centred; the field box, the
live words and the dot+clock box are 46 tall instead of 36. One line = 46 + 2 = 48. Mutation M9 (`_kRowHeight` 48)
replaces "padding 6".
B2 (T3c, the cross-check doing its job). The engine rounds a line's height: the field's six lines measured 120 dp while
`scale(14) * 1.4 * 6` is 117.6. `dictationMaxHeight` now lays out one line with `TextPainter(strutStyle:
kDictationStrut, textScaler).preferredLineHeight` (the number `RenderEditable` multiplies by `maxLines`) times six. The
strut is forced, so the late-loading font does not change it (the reason section 3 avoided a TextPainter).
B3 (T3b/T8b, test only). `getLocalRectForCaret` is in text coordinates; the tests subtract the field's scroll offset,
and pump the frame that starts the 100 ms caret reveal before advancing the clock.

## Round 3 log (fresh seat, narrow check of the round-2 folds, 2026-11-26)
Every R2 item closed. N1 P3 inner Row min size and spacing -> C3. N2 P2 `_lastHeight` on every layout -> C4, T9
grow-shrink-regrow, mutation. N3 P3 T8c names the RenderEditable and the fixture. N4 P3 the viewport rect is the
scroll view's render box. Converged.
