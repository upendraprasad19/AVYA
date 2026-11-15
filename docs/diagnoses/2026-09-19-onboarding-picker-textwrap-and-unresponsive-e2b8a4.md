---
bug_id: e2b8a4
date: 2026-09-19
batch: web-onboarding-e2e-bug-batch
status: fixed
blast_radius: account
symptom: >
  THREE friend-reported live-web bugs from the same voice-message batch. Two
  are live-reproduced in-session (not just hypothesized): (1) on the
  onboarding DOB date picker, the YearPicker/CalendarDatePicker grid wrapped
  4-digit years and 2-digit days onto two lines inside their fixed-size cells
  (e.g. "2002" rendered as "200"/"2" stacked). (2) on the time picker
  (wake-time / workout-time), users could not confirm a time at all: at the
  default desktop-web viewport the dial + OK/Cancel row did not render (not
  scrolled off-screen — genuinely absent), confirmed live via direct
  canvas-pixel sampling. The THIRD report — Stats-screen activity pills
  "unresponsive" — was investigated (widget test + a live Browser-pane drive
  under MobileFrame) and found to be NOT an independent defect; see "Bug 3"
  below. A separate, lower-severity instance of the same architectural
  family as (1)/(2): the onboarding Plan screen's "FOUNDATION" phase title
  wrapped onto two lines ("FOUNDATI"/"ON") inside WardPhaseBlock's title row,
  and a second, previously-undiscovered defect in the SAME widget
  (weeksLabel had no maxLines/overflow and was not flex-wrapped, so it
  overflowed the Row independent of the title fix).
concept: responsive_picker_host
sot_registry_entry: not_applicable
contract_test_path: test/contracts/responsive_picker_host_test.dart, test/contracts/wake_workout_time_picker_dial_only_test.dart, test/contracts/dob_picker_calendar_only_and_builder_test.dart, test/contracts/mobile_frame_mediaquery_test.dart
writers: >
  lib/shared/widgets/responsive_picker_builder.dart (the shared `builder:`
  for showTimePicker/showDatePicker, used by identity_screen.dart's DOB
  picker) — sets explicit `datePickerTheme`/`timePickerTheme` text styles
  (no custom font family) so the picker's fixed-size grid cells and
  hour/minute display never inherit the app's Fraunces/DM-Sans theme, plus a
  genuinely bounded ConstrainedBox (90%/95% of viewport) instead of an
  unbounded SingleChildScrollView. lib/app.dart's `MobileFrame` (formerly
  private `_MobileFrame`, MaterialApp.router's `builder:` wrapper on web) —
  THE ACTUAL FIX for Bug 2 (see root_cause below): now wraps its `child` in a
  `MediaQuery` reporting the frame's real clipped content size, not the
  outer browser-window size. lib/features/profile/screens/
  edit_profile_screen.dart:714,767 (`_pickWakeUpTime`/
  `_pickPreferredWorkoutTime`) — both now pass `initialEntryMode:
  TimePickerEntryMode.dialOnly`, removing the keyboard-entry toggle icon that
  was a SEPARATE, live-reachable path into a genuinely broken layout (see
  root_cause below). lib/shared/widgets/wardroom/ward_phase_block.dart
  — title Text sets maxLines:1/overflow:ellipsis; weeksLabel Text is now
  wrapped in Flexible with its own maxLines:1/overflow:ellipsis.
  ROUND-1 REVIEW ADDITIONS (context-blind review of this batch's own diff,
  same day): lib/features/profile/screens/edit_profile_screen.dart's
  `_pickDateOfBirth()` (~:662) — had NO `builder:` at all on the original
  same-day fix; now passes `builder: responsivePickerBuilder` AND
  `initialEntryMode: DatePickerEntryMode.calendarOnly`. lib/features/
  onboarding/screens/identity_screen.dart's DOB `showDatePicker` (~:84) —
  already had the builder; now also passes `initialEntryMode:
  DatePickerEntryMode.calendarOnly`. lib/shared/widgets/
  responsive_picker_builder.dart — added `datePickerTheme.
  headerHeadlineStyle/headerHelpStyle` (reusing stockTextTheme's own values,
  same explicit-no-family pattern as dayStyle/yearStyle); a reviewer-proposed
  removal of the wholesale `textTheme: stockTextTheme` reset was TRIED and
  REVERTED (see impact_analysis — it reintroduced Bug 1). lib/app.dart's
  `MobileFrame` — introduced a shared `frameBorderWidth` constant (2.5)
  consumed by BOTH the border decoration and the MediaQuery content-size
  formula, so the reported content size matches what `Container`'s
  `BoxDecoration.border` actually leaves the child (a `Border.all(width:)`
  implies decoration-padding of that width on every edge).
readers: >
  The Material date-picker grid (YearPicker/CalendarDatePicker) and
  time-picker dialog (TimePickerDialog) rendered wherever `showDatePicker`/
  `showTimePicker` is called anywhere in the app — including Edit Profile's
  `_pickWakeUpTime`/`_pickPreferredWorkoutTime` (lib/features/profile/screens/
  edit_profile_screen.dart:714,767), which call `showTimePicker` with NO
  custom `builder:` and are the only live wake/workout-time picker surface in
  the shipped product (muster's own picker was retired earlier in this
  batch) — both ALSO now writers of their own fix (see below: both pass
  `initialEntryMode: TimePickerEntryMode.dialOnly`). WardPhaseBlock's title +
  weeksLabel Text on the onboarding Plan screen. ROUND-1 ADDITIONS: the
  CalendarDatePicker grid rendered from Edit Profile's `_pickDateOfBirth`
  (previously the ONLY DOB surface with no builder fix at all — a user
  editing DOB from Profile rather than onboarding still hit Bug 1's original
  wrap); MobileFrame's `child` MediaQuery consumers, which now receive a
  content size netted for the frame's actual border width.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "responsivePickerBuilder must not wrap its child in an unbounded SingleChildScrollView — pinned by test/contracts/responsive_picker_host_test.dart."
  - "responsivePickerBuilder must set explicit datePickerTheme/timePickerTheme text styles (no custom font family) rather than relying on a textTheme reset alone — a textTheme reset alone does not stop the app's DM-Sans/Fraunces FAMILY from still reaching the picker via the datePickerTheme/timePickerTheme fallback chain (`dayStyle ?? textTheme.bodyLarge`, `hourMinuteTextStyle ?? textTheme.displayMedium`). Pinned by responsive_picker_host_test.dart's 2nd/3rd-pass tests against the REAL AppTheme.dark."
  - "MobileFrame (lib/app.dart) must give its `child` a MediaQuery matching the frame's real clipped content size, not the outer window size — otherwise ANY root-navigator overlay content (dialogs, pickers) inside `child` makes layout/orientation decisions against the wrong, larger size while being painted into a smaller clipped box. Pinned by test/contracts/mobile_frame_mediaquery_test.dart, mutation-proven."
  - "Every real showTimePicker call site must pass initialEntryMode: TimePickerEntryMode.dialOnly — Material's default dial mode always shows a keyboard-toggle icon regardless of the initial mode requested, and switching to input mode at MobileFrame's narrow web content width clips the AM/PM toggle and OK button off-screen entirely (OK becomes unreachable; Cancel still works). Pinned by test/contracts/wake_workout_time_picker_dial_only_test.dart, mutation-proven."
  - "A Text widget rendering a variable-length phase/category title OR a fixed-looking-but-actually-variable label inside a Row alongside another Row child must set maxLines+overflow AND be wrapped in Flexible/Expanded (not left as a bare Row child) — a bare Text child claims its full intrinsic width before any flexible sibling sees remaining space, so maxLines/overflow on it alone does nothing. Pinned by test/wardroom/ward_phase_block_test.dart for both the title and weeksLabel."
  - "Every real showDatePicker call site must pass BOTH builder: responsivePickerBuilder AND initialEntryMode: DatePickerEntryMode.calendarOnly — a second real DOB call site (Edit Profile) had neither, reopening Bug 1's exact wrap on a surface nobody re-grepped for when Bug 1 was first fixed, and Material's default .calendar entry mode always shows a keyboard-toggle icon into an input-mode layout never verified safe at MobileFrame's narrow web content width (the same reachable-toggle shape as the time-picker finding above). Pinned by test/contracts/dob_picker_calendar_only_and_builder_test.dart, mutation-proven per file."
  - "responsivePickerBuilder's wholesale `textTheme: stockTextTheme` reset (job #1) must NOT be removed even after every at-risk field gets its own explicit datePickerTheme/timePickerTheme style — those explicit styles deliberately carry NO custom fontFamily, and an unset fontFamily MERGES onto whichever ambient DefaultTextStyle is in scope rather than falling back to a platform default; without job #1's reset that ambient style is the app's real DM-Sans theme, which reintroduces Bug 1's exact family-leak. Tried removing it (a review-suggested 'redundancy' cleanup) and reverted after test/contracts/responsive_picker_host_test.dart's 2nd-pass test caught the reintroduced DMSans_regular fontFamily on a real day cell."
  - "lib/app.dart's MobileFrame must compute the MediaQuery content size it hands to `child` using the SAME border-width constant the frame's own BoxDecoration.border uses, not the bare frame width/height — Container's decoration-padding equals the border width on every edge, so the child actually receives frameW/frameH minus 2x that width. Pinned by test/contracts/mobile_frame_mediaquery_test.dart's updated expected-value formula, mutation-proven (frameBorderWidth zeroed reddens the content-size assertion)."
proposed_fix: >
  See root_cause + fix sections below — this field is retained for schema
  compatibility; the full, corrected account superseding the original
  same-day proposal is in the doc body.
regression_test_planned: >
  test/contracts/responsive_picker_host_test.dart (6 tests: unbounded-scroll
  absence + bounded ConstrainedBox enforcement; textTheme reset; 2nd-pass
  real-showDatePicker family/wrap check against AppTheme.dark; 3rd-pass
  real-showTimePicker dial/OK-presence check against AppTheme.dark via
  responsivePickerBuilder; DOB-picker-still-uses-host source-grep; muster-
  no-longer-has-a-time-picker source-grep). test/contracts/
  mobile_frame_mediaquery_test.dart (NEW — 2 tests, mutation-proven): direct
  `MediaQuery.of(context)` capture inside MobileFrame's child at a wide
  (1280x720) viewport, asserting it equals the frame's real clipped content
  box (not the outer window) and is genuinely portrait-shaped; and a
  narrow-viewport passthrough test asserting NO override happens on a real
  phone width. test/wardroom/ward_phase_block_test.dart (1 test covering
  both the title-wrap and weeksLabel-overflow findings, mutation-proven
  against both). test/onboarding/stats_screen_activity_pills_test.dart (NEW
  — 6 tests; a closure/no-defect-found verification for Bug 3, not a fix
  pin, but retained as durable regression coverage for a screen that
  previously had zero tests). test/contracts/dob_picker_calendar_only_and_
  builder_test.dart (NEW, ROUND-1 REVIEW — 4 tests: 2 source-grep tests pin
  `builder: responsivePickerBuilder` + `initialEntryMode: DatePickerEntryMode.
  calendarOnly` at BOTH real DOB call sites — edit_profile_screen.dart AND
  identity_screen.dart — independently mutation-proven per file; 2 behavioral
  tests pin Flutter's own calendarOnly contract directly (toggle icon absent,
  OK still confirms and returns the seeded date), not just this app's
  parameter choice). test/contracts/mobile_frame_mediaquery_test.dart's
  wide-viewport test UPDATED (ROUND-1 REVIEW) for the border-width fix: the
  expected content-size formula now subtracts `frameBorderWidth * 2` from the
  frame dimensions on both axes, matching MobileFrame's corrected formula;
  mutation-proven by zeroing frameBorderWidth in the source and confirming
  the height assertion reddens at the correct line, then restoring.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "responsive_picker_builder.dart, app.dart (MobileFrame), and ward_phase_block.dart all rewritten; flutter analyze lib/ clean (45 pre-existing info-only issues, zero new); all listed tests green AND mutation-proven (fix temporarily reverted, confirmed each test reddens on the correct assertion, then restored)" }
  - { tier: 1, layer: client_code, status: verified, evidence: "LIVE-VERIFIED in the Browser pane against the actual dev server, not just widget tests — see impact_analysis for the full account. Both bugs were re-reproduced BEFORE the final fix (confirming the doc's original same-day 'fixed' status was premature) and then confirmed genuinely fixed AFTER it, via screenshots and a live debugPrint of the real MediaQuery values reaching the picker." }
  - { tier: 1, layer: client_code, status: verified, evidence: "Bug 3 (Stats-screen activity pills): test/onboarding/stats_screen_activity_pills_test.dart (6/6 green, no code change needed) PLUS a live Browser-pane drive of all four pills via a temporary dev-panel button (StatsScreen pushed directly, bypassing the auth-gated route, then removed) at the same MobileFrame desktop viewport that broke Bug 2 — all four selected/deselected correctly, zero console errors. No independent defect found; see Bug 3 section below." }
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "Edit Profile's two showTimePicker call sites now pass initialEntryMode: TimePickerEntryMode.dialOnly. LIVE-VERIFIED via a temporary dev-panel QA button (removed after): the keyboard-toggle icon is now absent from the dial dialog at the default web viewport (screenshot), and OK still dismisses correctly at both the default viewport AND a tall (900x1300) resized viewport re-testing the memory-documented clock-hand-rotation symptom (screenshots, both before this fix landed the icon was present and after it is gone). test/contracts/wake_workout_time_picker_dial_only_test.dart (3/3 green, mutation-proven — reverting dialOnly on either call site reddens the source-grep test on the correct assertion)." }
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "ROUND-1 REVIEW Finding 1+2: edit_profile_screen.dart's _pickDateOfBirth() had NO builder at all (reopening Bug 1's wrap on a 2nd real DOB surface) and neither real DOB call site set initialEntryMode (reachable keyboard-toggle, same class as the time-picker finding). Fixed: both call sites now pass builder: responsivePickerBuilder + initialEntryMode: DatePickerEntryMode.calendarOnly. test/contracts/dob_picker_calendar_only_and_builder_test.dart (4/4 green, mutation-proven per file — reverting either fix independently reddens only that file's source-grep test)." }
  - { tier: 1, layer: client_code, status: verified, evidence: "ROUND-1 REVIEW Finding 1+2 LIVE-VERIFIED: a temporary dev-panel QA button drove edit_profile_screen.dart's exact showDatePicker call shape at a genuine MobileFrame-active narrow viewport (600x950 outer, frame capped 390x844, confirmed via window.innerWidth/innerHeight JS query — NOT the earlier landscape-passthrough test at MobileFrame-inactive width). Screenshot confirms: the 1-31 day grid renders on single lines with no wrapping, the header ('Select date' / 'Mon, Jan 15') renders correctly with the new headerHeadlineStyle/headerHelpStyle overrides (first live test of that specific addition), and no keyboard-toggle icon appears next to Cancel/OK. QA button removed after (git diff --stat on dev_panel_screen.dart returns empty)." }
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "ROUND-1 REVIEW Finding 3: a reviewer-proposed removal of responsivePickerBuilder's wholesale textTheme: stockTextTheme reset (argued as redundant once every at-risk field has its own explicit style) was TRIED and caused an ACTUAL regression, caught by running the existing test/contracts/responsive_picker_host_test.dart suite (not by re-reasoning) — 2 of 6 tests failed, including the real day cell's rendered fontFamily reading DMSans_regular again. Root cause: an explicit TextStyle field with fontFamily:null does not mean Flutter's bundled default, it MERGES onto the ambient DefaultTextStyle, which without job #1's reset falls through to the app's real DM-Sans theme. Reverted to keep the reset; kept the reviewer's other two header-style additions (headerHeadlineStyle/headerHelpStyle) as legitimate extra hardening. All 6 tests green after revert." }
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "ROUND-1 REVIEW Finding 4: MobileFrame's MediaQuery content-size formula used the bare frame width/height, but Container's BoxDecoration.border(width: 2.5) implies decoration-padding of 2.5 on every edge (Container._paddingIncludingDecoration), so child actually receives frameW/H minus 5.0 on each axis, not the bare dimensions. Fixed with a shared frameBorderWidth constant consumed by both the border and the MediaQuery formula. test/contracts/mobile_frame_mediaquery_test.dart's wide-viewport test updated to the same formula; mutation-proven (frameBorderWidth zeroed in source reddens the content-height assertion at the correct line, restored, diff confirmed clean)." }
impact_analysis: >
  Account blast radius — both bugs sit on the mandatory onboarding path (DOB
  is required on Identity) and/or Edit Profile's wake/workout-time pickers.
  Bug 2 (unresponsive time picker) was a HARD completion blocker on desktop
  web for any user who could not confirm a time via dial — matching a
  friend's real report. LIVE VERIFICATION (this session, in the Browser
  pane against a real `flutter run -d web-server` dev server, not just
  widget tests):
  Bug 1 — first live pass showed the "fixed" DOB picker STILL wrapping
  2-digit days; root-caused to `datePickerTheme.dayStyle` falling back to
  `textTheme.bodyLarge`, whose DM Sans FAMILY (not just size) still leaked
  through a textTheme-reset-only fix. Fixed via explicit
  `datePickerTheme.dayStyle/yearStyle/weekdayStyle`; a clean fresh-boot
  re-test then showed all two-digit days rendering correctly on one line.
  Bug 2 — after the datePickerTheme fix, showTimePicker was STILL
  live-reproduced with the dial + OK/Cancel genuinely absent (confirmed via
  direct canvas-pixel sampling: flat background color, not a visibility/
  color issue), for BOTH the responsivePickerBuilder-wrapped call AND a bare
  `showTimePicker` with no builder at all — proving the picker's own theme/
  ConstrainedBox fix was not the actual cause. Root-caused by reading
  `lib/app.dart`'s `MobileFrame` widget: on any browser window wider than
  500px it draws a decorative phone-shaped frame around the whole app via
  pure LAYOUT (`Container(width:, height:)` + `ClipRect`), but never gave
  its wrapped content a matching `MediaQuery` — so `showTimePicker`'s
  dialog (default `useRootNavigator: true`, landing inside that same
  content) computed its portrait/landscape layout AND its on-screen
  position against the OUTER, full-window size (confirmed live via a
  `debugPrint` of `MediaQuery.sizeOf(context)` immediately before opening
  the picker: it printed the full 1280x720 desktop window, not the frame's
  actual ~322x652 visible box). At that landscape-shaped outer size,
  Flutter's own TimePickerDialog chooses its LANDSCAPE layout (524x342,
  wider than the ~322px-wide visible frame) and centers itself against the
  full window — so only whatever slice of that mis-sized, mis-positioned
  dialog happened to fall inside the narrow clipped frame was visible: the
  hour:minute header did, the dial and OK/Cancel (further along in the
  landscape arrangement) did not. Fixed by wrapping MobileFrame's `child` in
  a `MediaQuery` reporting the frame's real inner content size. Re-verified
  live after the fix: a `debugPrint` of the same MediaQuery value now reads
  `Size(321.6, 652.0)` (the frame's real content box, independently matching
  what the new regression test computes from the same formula), and
  screenshots show the dial, portrait-stacked AM/PM toggle, and Cancel/OK
  all rendering and interactive — tested for both the bare-showTimePicker
  shape (Edit Profile's real call shape) and the responsivePickerBuilder-
  wrapped dial-mode shape.
  CORRECTED FINDING, now fixed (not out of scope after all): an earlier pass
  of this investigation checked `grep -rn "TimePickerEntryMode.input" lib/`
  (zero matches) and concluded the input-mode layout clipping was
  unreachable in the shipped product. That check was too narrow — Material's
  default `TimePickerEntryMode.dial` ALWAYS shows a keyboard-toggle icon
  regardless of the initial mode requested, and tapping it switches to the
  identical input-mode layout live, from BOTH of Edit Profile's real
  showTimePicker calls, with no `initialEntryMode` override needed to reach
  it. Live-reproduced post-MobileFrame-fix: at the default web viewport,
  tapping the toggle icon shows "Enter time" mode with the AM/PM toggle and
  OK button clipped off the right edge entirely — Cancel remains tappable,
  OK does not, so the dialog becomes permanently unconfirmable once a user
  switches modes (screenshot). Root cause (Flutter SDK source,
  `time_picker.dart:2418-2421,2607-2629`): input mode's own requested size is
  independent of MobileFrame's clamp and the icon that reaches it is present
  by default — this was never actually gated by which `initialEntryMode` a
  call site passes. Fixed by adding `initialEntryMode: TimePickerEntryMode.
  dialOnly` to both `_pickWakeUpTime` and `_pickPreferredWorkoutTime`, which
  Flutter only omits the toggle icon for (`time_picker.dart`'s `actions` Row
  conditions the `IconButton` on `_entryMode.value == TimePickerEntryMode.
  dial || TimePickerEntryMode.input`, never `.dialOnly`/`.inputOnly`) —
  removing the only path into the broken layout rather than trying to patch
  Material's own input-mode width math. Live-verified: the toggle icon is
  now absent from the dial dialog at the default viewport, and OK still
  dismisses correctly there and at a resized tall (900x1300) viewport
  (re-testing the separately-reported clock-hand-rotation symptom, also
  confirmed gone).
  The original same-day version of this diagnose-doc claimed Bug 1 was fixed
  and Bug 2's fix was "structural... verified via widget tests" while
  explicitly flagging that live-browser verification had NOT completed —
  both claims were premature: Bug 1's originally-shipped fix was
  insufficient (see above) and Bug 2's actual root cause was not yet
  discovered. This section replaces that account with the one actually
  confirmed live.
---

# Onboarding picker text-wrap + unresponsive time picker (e2b8a4)

## What happened

Two friend-reported bugs. Both were live-reproduced in the Browser pane
during this session — including a SECOND live pass that caught the
first pass's own fix as insufficient for Bug 1, and a THIRD investigation
that found Bug 2's real root cause lived somewhere the picker's own code
could never fix.

**Bug 1 — DOB text wrap.** The onboarding DOB date picker's YearPicker and
CalendarDatePicker grids wrapped 4-digit years and 2-digit days onto two
lines inside their fixed-size cells.

*First-pass fix (insufficient, live-disproven):* resetting
`responsivePickerBuilder`'s `textTheme` to Flutter's stock Material
defaults. This passed a widget test built around a synthetic oversized
`TextTheme` fixture — but a live re-test in a real browser showed the wrap
was still happening. Root cause: `CalendarDatePicker`/`YearPicker` day and
year cells resolve `datePickerTheme.dayStyle/yearStyle ?? textTheme.
bodyLarge` (Flutter's own `_DatePickerDefaultsM3`). Resetting the whole
`textTheme` correctly fixed the *size* but did not stop the app's own
`bodyLarge` — built via `AppTypography.dmSansFamily()`, a deliberate
null-`fontSize` "seed" style — from still supplying its DM Sans *family*
through that same fallback chain. `flutter test` never fetches the real
web font and silently substitutes a fallback, which is exactly why the
synthetic-fixture widget test could not see this: it proved fontSIZE
resolves, not that the FAMILY is gone, and DM Sans's real (browser-only)
metrics are what actually wrap 2-digit days and 4-digit years inside
Material's fixed-size grid cells.

*Actual fix:* `datePickerTheme.dayStyle/weekdayStyle/yearStyle` are now set
EXPLICITLY (no custom font family at all) — these fields take absolute
precedence over the textTheme-derived fallback, sidestepping the app's font
pipeline entirely for these cells rather than depending on how the ambient
theme resolves. **Live-confirmed fixed**: a clean fresh-boot re-test showed
all two-digit days rendering correctly on one line.

**Bug 2 — time picker dial/OK/Cancel genuinely absent.** Live-reproduced:
at the default desktop-web viewport, opening the time picker showed the
hour:minute header but the dial and OK/Cancel action row did not render at
all — not scrolled off-screen, confirmed via direct canvas-pixel sampling
(flat background color).

*First hypothesis (real hardening, NOT the actual cause):* the same
font-family-leak class as Bug 1, one theme extension over —
`hourMinuteTextStyle` resolving via `textTheme.displayMedium` (Fraunces).
`responsivePickerBuilder`'s `timePickerTheme` was extended with explicit
text styles the same way `datePickerTheme` was. This is a legitimate,
mutation-tested hardening (a picker that inherited the app's real Fraunces
theme WOULD be a real risk) — but a live re-test with this fix compiled in
showed the dial/OK/Cancel STILL genuinely absent, identically. A further
isolation test — a bare `showTimePicker` call with NO custom `builder` at
all, removing every one of `responsivePickerBuilder`'s theme overrides AND
its `ConstrainedBox` — produced the IDENTICAL symptom, proving neither the
picker's theme nor its bounding box was the actual cause.

*Actual root cause:* `lib/app.dart`'s `MobileFrame` widget (the app's
`MaterialApp.router` `builder:`, previously named `_MobileFrame`). On any
browser window wider than 500px, it draws a decorative phone-shaped frame
around the whole app to make the web preview look like a mobile app —
purely via LAYOUT (`Container(width: frameW, height: frameH)` +
`ClipRect`), sizing the frame to roughly a 390:844 aspect ratio capped to
the viewport. Critically, it never gave the app content inside that frame
a matching `MediaQuery` — every descendant, including anything raised on
the app's root Navigator (which lives INSIDE the frame's `child`), still
read the OUTER, full-browser-window size via `MediaQuery.of(context)`.
`showTimePicker`/`showDatePicker` default to `useRootNavigator: true`,
landing their dialog in exactly that Navigator's Overlay. At a typical
desktop viewport (confirmed live: 1280x720), Flutter's own `TimePickerDialog`
reads that outer, LANDSCAPE-shaped size, concludes landscape orientation,
and lays out + centers its LANDSCAPE dialog (524x342 — wider than the
frame's ~322px-wide visible content box) against the full window — so only
whatever slice of that oversized, mis-positioned dialog happened to fall
inside the actual narrow clipped frame was visible on screen. The
hour:minute header (positioned early in the landscape layout) fell inside
that slice; the dial and OK/Cancel (further along) did not. This explains
every earlier observation at once: why the "genuinely absent" symptom
persisted with or without `responsivePickerBuilder` (both read the same
wrong `MediaQuery.sizeOf(context)`), and why fixing the picker's own theme
could never have fixed it — the picker was never the writer of the wrong
value.

**Bug 2 continued — Enter-time (keyboard) mode reachable and genuinely
broken, corrected from an earlier premature "out of scope" call.** An
earlier pass of this same investigation checked
`grep -rn "TimePickerEntryMode.input" lib/` (zero matches) and concluded
input-mode's own width-clipping was unreachable in the shipped product,
since no call site explicitly requests it. That check was too narrow:
Material's default `TimePickerEntryMode.dial` always renders a
keyboard-toggle icon next to Cancel/OK, and tapping it — a real, discoverable
gesture, not a hidden dev-only path — switches to the identical broken
layout live, from BOTH of Edit Profile's real `showTimePicker` calls, with
no special parameter needed. Live-reproduced post-MobileFrame-fix: at the
default web viewport, tapping the toggle shows "Enter time" mode with the
AM/PM toggle and OK button clipped off the right edge — Cancel remains
tappable, OK does not, permanently blocking confirmation once a user
switches modes. Root cause (`time_picker.dart:2418-2421,2607-2629`):
input-mode's own requested size is independent of MobileFrame's clamp, and
the icon that reaches it is present regardless of which `initialEntryMode`
a call site passes — this was never actually gated on that parameter, which
is exactly what the narrower grep missed. Fixed by adding
`initialEntryMode: TimePickerEntryMode.dialOnly` to both
`_pickWakeUpTime` and `_pickPreferredWorkoutTime` — Flutter only omits the
toggle icon for `.dialOnly`/`.inputOnly` (`time_picker.dart`'s `actions` Row
conditions the `IconButton` on `_entryMode.value == TimePickerEntryMode.dial
|| TimePickerEntryMode.input`), so this removes the only path into the
broken layout rather than patching Material's own input-mode width math.
Live-verified: the toggle icon is now absent at the default viewport, and OK
still dismisses correctly there and at a resized tall (900x1300) viewport —
also re-confirming the separately-reported clock-hand-rotation symptom
(memory `project_e2e_web_bug_batch_2026_09_19_inflight.md`'s "TALLER
viewports (900px-1400px)... clicking OK... instead ROTATES THE CLOCK HAND")
is gone, since it shared the same MobileFrame root cause.

**Related, lower severity — WardPhaseBlock.** The Plan screen's
"FOUNDATION" phase title (the longest of the three phase names) wrapped
onto two lines. A SECOND, previously-undiscovered defect was found the
first time this file's own regression test actually ran end-to-end:
`weeksLabel`'s `Text` had no `maxLines`/`overflow` and was a bare (non-
`Flexible`/`Expanded`) `Row` child — a `Row` gives non-flexible children
their full intrinsic width before any flexible sibling sees remaining
space, so at the exact narrow width this test squeezes, the `Row` genuinely
overflowed regardless of what the title's own fix did.

**Bug 3 — Stats-screen activity pills "unresponsive" (investigated, NOT an
independent defect).** The third friend report from the same voice-message
batch. `_activitySelector()` in `lib/features/onboarding/screens/
stats_screen.dart` (~:255-317) renders four chips (SEDENTARY/LIGHT/MODERATE/
HEAVY) via plain `GestureDetector.onTap → setState(() => _activity =
opt.$2)`, reading `_activity == opt.$2` to pick `AppColors.accent` vs
`AppColors.card`. Two independent checks found no defect:

1. `test/onboarding/stats_screen_activity_pills_test.dart` (new, 6 tests,
   all green): pumps `StatsScreen` directly and drives every tap
   combination, including re-tapping the already-selected pill and the
   pre-selected default ('moderate'). All pass.
2. A temporary dev-panel button pushed `StatsScreen` directly (bypassing
   `/onboarding/stats`'s auth gate the same way `/dev` itself is always
   reachable regardless of auth state) and drove all four pills live in the
   Browser pane, under `MobileFrame`, at the same desktop-shaped viewport
   that broke Bug 2. All four selected/deselected correctly on screen, with
   zero console errors. The button and its import were removed immediately
   after (same TEMP lifecycle as the Bug 1/2 QA scaffold below).

Unlike the time-picker dialog, `_activitySelector()` never reads
`MediaQuery` size/orientation and raises no root-navigator overlay — it is
an ordinary in-flow widget laid out via real `BoxConstraints` inside
`MobileFrame`'s already-correctly-clipped child tree, so it was never
structurally exposed to Bug 2's MediaQuery-propagation defect in the first
place. Conclusion: no independent StatsScreen defect exists. The most
likely explanation is that the founder's friend was describing the SAME
wake-time-picker lockup (Bug 2) — a blocker severe enough that the
founder's own account needed a Remote Control workaround to escape it
during muster — rather than a distinct third bug, consistent with reports
arriving informally via voice message rather than a precise per-screen
account.

## Round 1 review findings (context-blind review of this batch's own fix)

Per CLAUDE.md §4.3's self-initiated ≥account `/code-review` discipline, this
batch's own diff was put through a context-blind review round before commit.
It found four real issues in the fixes above — three material, one
negligible — plus a reviewer-suggested remedy that turned out to be wrong on
live testing. All four are fixed; the wrong remedy is documented rather than
silently discarded.

**Finding 1 — Edit Profile's DOB picker had no builder at all.** Bug 1's fix
was applied to `identity_screen.dart`'s onboarding DOB picker but nobody
re-grepped for every other `showDatePicker` call site. `lib/features/profile/
screens/edit_profile_screen.dart`'s `_pickDateOfBirth()` (~:662) called
`showDatePicker` with no `builder:` parameter — a user editing their DOB from
Profile (rather than during onboarding) would hit the exact same DM-Sans
family wrap Bug 1 was supposed to have fixed everywhere. Fixed by wiring the
same `builder: responsivePickerBuilder` used by `identity_screen.dart`.

**Finding 2 — neither real DOB call site set `initialEntryMode`.** Both
`identity_screen.dart` and `edit_profile_screen.dart`'s DOB pickers defaulted
to `DatePickerEntryMode.calendar`, which — like `showTimePicker`'s default
dial mode (Bug 2 continued, above) — always renders a keyboard-toggle icon
that switches to a differently-sized fixed layout never verified safe at
MobileFrame's narrow web content width. Fixed by adding `initialEntryMode:
DatePickerEntryMode.calendarOnly` to both real call sites, the same fix
shape already applied to the time pickers.

**Finding 3 — a suggested "redundancy" removal was tried, found to
reintroduce Bug 1, and reverted.** The reviewer additionally argued that
`responsivePickerBuilder`'s wholesale `textTheme: stockTextTheme` reset (job
#1 in that file's class doc) had become redundant collateral damage now that
every at-risk field (`dayStyle`, `yearStyle`, `hourMinuteTextStyle`, etc.)
has its own explicit override — and that removing it would restore DM
Sans/Fraunces to OK/Cancel button labels and other never-at-risk text with
"zero risk" to the day/hour cells, since explicit per-field styles "take
absolute precedence." **This remedy was applied, then disproven by actually
running the test suite, not by re-reasoning about the claim**: `flutter test
test/contracts/responsive_picker_host_test.dart` immediately showed 2 of 6
tests failing, including the real day cell's rendered `fontFamily` reading
`DMSans_regular` again — a genuine reintroduction of Bug 1. Root cause: a
`TextStyle` field with `fontFamily: null` does not mean "use Flutter's
bundled default" — it means the field MERGES onto whatever ambient
`DefaultTextStyle` is in scope at render time. Without job #1's reset, that
ambient style is `baseTheme.textTheme` — the app's real DM-Sans theme — so
every family-less explicit style below it (by design, since none of them set
a custom family) inherits DM Sans straight back through the merge chain. The
reviewer's "zero risk" claim was factually wrong for this specific mechanism.
**Fixed by reverting**: `textTheme: stockTextTheme` is back in place, with
both the class doc and the inline comment rewritten to document the
tried-and-reverted history and the underlying merge mechanism, rather than
silently discarding the failed attempt. The reviewer's other, independently
correct observation — that the calendar header (`headerHeadlineStyle`/
`headerHelpStyle`) resolves via `textTheme.headlineLarge`/`labelLarge`
(`_DatePickerDefaultsM3`) when unset, the same Fraunces-carrying chain
implicated in the hour/minute bug — was kept: both fields are now set
explicitly, reusing `stockTextTheme`'s own values (not inventing new sizes),
as additional hardening layered on top of the restored job-#1 reset rather
than a replacement for it. **Durable lesson**: a code-review finding's
suggested FIX is itself a hypothesis requiring the same live/test
verification as the finding itself — not something to trust and apply on
the reviewer's stated reasoning alone.

**Finding 4 — MobileFrame's MediaQuery formula didn't account for its own
border width (negligible in practice, fixed for correctness).**
`MobileFrame`'s `Container` draws `border: Border.all(width: 2.5)`, but the
`MediaQuery` content size handed to `child` was computed from the bare frame
width/height. `Container`'s `_paddingIncludingDecoration` adds the border
width as implicit padding on every edge (`decoration.padding` for a
`BoxDecoration` with a border returns `EdgeInsets.all(width)`), so `child`
actually receives `frameW/frameH` minus `2 × borderWidth`, never the bare
frame dimensions the old formula assumed. At the diagnose's own cited
viewport this is a ~1.5% discrepancy — far short of flipping a
portrait/landscape decision — but the `MediaQuery` this widget hands to
`child` should describe the box it actually gets. Fixed by introducing a
single `frameBorderWidth` constant consumed by both the border decoration
and the content-size formula, so they can never drift apart again.

## Fix

1. `responsivePickerBuilder`: `datePickerTheme.dayStyle/weekdayStyle/
   yearStyle` and `timePickerTheme.hourMinuteTextStyle/dayPeriodTextStyle/
   helpTextStyle/dialTextStyle/timeSelectorSeparatorTextStyle` all set
   EXPLICITLY (no custom font family), plus a genuinely bounded
   `ConstrainedBox` (90% viewport height / 95% viewport width) replacing an
   earlier unbounded `SingleChildScrollView`. Real, useful hardening for any
   call site that uses this builder — but NOT what fixed Bug 2's live
   symptom (see above).
2. **`lib/app.dart`'s `MobileFrame`** (the actual fix for Bug 2): wraps its
   `child` in a `MediaQuery` reporting the frame's real inner content size
   (`Size(frameW, frameHeight - notchHeight - homeIndicatorHeight)`) with
   `viewInsets`/`viewPadding`/`padding` reset to zero, instead of leaving
   the outer, full-window `MediaQuery` to leak through. Renamed from
   private `_MobileFrame` to public `MobileFrame` so `test/` can pump it in
   isolation.
3. `WardPhaseBlock`'s title `Text` keeps `maxLines: 1, overflow:
   TextOverflow.ellipsis` (unchanged from the original same-day fix);
   `weeksLabel`'s `Text` is now wrapped in `Flexible` with its own
   `maxLines: 1, overflow: TextOverflow.ellipsis`.
4. **`lib/features/profile/screens/edit_profile_screen.dart`'s
   `_pickWakeUpTime`/`_pickPreferredWorkoutTime`** (:714,767): both now pass
   `initialEntryMode: TimePickerEntryMode.dialOnly`, removing the
   keyboard-toggle icon that was a separate, live-reachable path into a
   genuinely broken (clipped, unconfirmable) layout — corrects an earlier
   premature "out of scope" call in this same doc (see the Bug 2 continued
   section above).
5. Deleted the temporary "Picker QA (temp)" / "Stats QA (temp)" / "Time
   picker QA (temp)" / "DOB picker QA (temp)" scaffolds added to
   `lib/features/dev/dev_panel_screen.dart` across this investigation
   (confirmed via `git diff --stat` showing zero residual diff on that file)
   along with their now-unused imports — all were explicitly marked TEMP and
   served their purpose.
6. **ROUND-1 REVIEW — `lib/features/profile/screens/edit_profile_screen.dart`'s
   `_pickDateOfBirth()`** (~:662): now passes `builder: responsivePickerBuilder`
   (was missing entirely) AND `initialEntryMode: DatePickerEntryMode.
   calendarOnly` (Findings 1+2).
7. **ROUND-1 REVIEW — `lib/features/onboarding/screens/identity_screen.dart`'s
   DOB `showDatePicker`** (~:84, already had the builder): now also passes
   `initialEntryMode: DatePickerEntryMode.calendarOnly` (Finding 2).
8. **ROUND-1 REVIEW — `responsivePickerBuilder`'s `datePickerTheme`**: added
   `headerHeadlineStyle`/`headerHelpStyle` (both reusing `stockTextTheme`'s own
   values, no custom family) as additional header hardening; the reviewer's
   separate suggestion to remove the wholesale `textTheme: stockTextTheme`
   reset was tried and reverted — see Finding 3 above (this is NOT in this
   list as a shipped change; it is documented because it was tried).
9. **ROUND-1 REVIEW — `lib/app.dart`'s `MobileFrame`** (Finding 4): introduced
   a shared `frameBorderWidth` constant (2.5) consumed by both the border
   decoration and the `MediaQuery` content-size formula, so the reported
   content size matches what the child actually receives net of the border's
   implicit decoration-padding.

## Why the original same-day "fixed" status was premature

The version of this doc written earlier the same day claimed both bugs
fixed on the strength of widget tests alone, while explicitly noting that
live-browser verification "did not reliably complete" and recommending a
follow-up spot-check. That live spot-check is exactly what this session did
— and it found BOTH bugs still reproducible, for two different reasons
(Bug 1's fix was incomplete; Bug 2's fix targeted the wrong file entirely).
This is the concrete version of this project's own repeated lesson that a
green widget-test suite is only as wide as what it actually exercises: none
of the original widget tests used the app's REAL theme or the app's REAL
`MobileFrame` wrapper, so neither could have caught either gap.

## Verification

**Widget tests** (all green, all mutation-proven — see `regression_test_
planned` above for the full list and `test/contracts/mobile_frame_
mediaquery_test.dart`'s own header comment for an honest account of what a
widget test can and cannot prove about this specific bug: it can pin the
`MediaQuery` propagation itself, but Flutter's widget-test harness resolves
dialog layout against real `BoxConstraints` regardless of what `MediaQuery.
size` claims, so it cannot reproduce the VISUAL "genuinely absent" symptom
the way a real paint pass does — that is what live verification is for).

**Live verification** (this session, Browser pane against a real
`flutter run -d web-server` dev server): both bugs re-reproduced before the
final fixes, then re-confirmed fixed after — screenshots of the DOB grid
(all two-digit days on one line) and the time picker (dial, portrait-
stacked AM/PM toggle, and Cancel/OK all rendering, OK dismissing the dialog
correctly), plus a `debugPrint` of the exact `MediaQuery` value reaching the
picker before and after the `MobileFrame` fix (`Size(1280.0, 720.0)` before
→ `Size(321.6, 652.0)` after, matching the regression test's independently
re-derived expected value). The `dialOnly` fix was separately live-verified:
screenshots showing the keyboard-toggle icon present (pre-fix) vs. absent
(post-fix) at the default viewport, and OK dismissing correctly both there
and at a resized tall (900x1300) viewport.

**Round-1-review fixes, live-verified** (same session, same dev server): a
temporary "DOB picker QA (temp)" dev-panel button drove
`edit_profile_screen.dart`'s exact `showDatePicker` call shape (builder +
`calendarOnly` + the corrected `responsivePickerBuilder` header styles) at a
genuinely MobileFrame-active narrow viewport — resized to 600x950 outer
(confirmed via a `window.innerWidth/innerHeight` JS query returning
900x1300 in an earlier attempt and 600x950 here; MobileFrame's own formula
caps the phone frame at 390x844 regardless, so a smaller outer viewport just
gives the frame more relative screen space for a clearer screenshot), which
is the genuine narrow-content-width case the fixes are about — distinct from
an earlier attempt at the tool's default viewport that rendered in landscape
with no phone-frame chrome, i.e. the `MobileFrame`-INACTIVE passthrough case
(`size.width <= 500`), which would not have exercised any of these fixes.
Screenshot confirms: the 1-31 day grid renders cleanly in a 7-column
Sun-Sat layout with every day on one line (no wrapping); the header block
("Select date" / "Mon, Jan 15") renders on two clean lines with no
overflow — the first live confirmation of the new `headerHeadlineStyle`/
`headerHelpStyle` overrides; and no keyboard-toggle icon appears in the
Cancel/OK action row. The `Icons.edit_outlined`-absent and OK-still-confirms
assertions are additionally pinned mechanically by
`test/contracts/dob_picker_calendar_only_and_builder_test.dart`'s two
behavioral tests, both green. The QA button and its now-unused import were
removed after (confirmed via `git diff --stat` on `dev_panel_screen.dart`
returning empty).

## Device verify

**Corrected**: an earlier version of this section claimed "Android uses
native pickers with a different viewport... this entire bug class does not
apply to native Android at all." That premise is wrong — `showTimePicker` is
Flutter's own cross-platform Material `TimePickerDialog`, not a bridged OS
picker; both real call sites (`edit_profile_screen.dart`) invoke it
unconditionally with no platform branching (confirmed: `grep -rn
"showTimePicker(" lib/` returns only these two call sites and the now-
removed dev-panel QA scaffold, none platform-gated). What IS true is
narrower: MobileFrame itself only activates on web viewports wider than
500px, so the SPECIFIC "dial/OK genuinely absent" symptom (Bug 2's root
cause — a root-navigator dialog reading the wrong outer MediaQuery) cannot
occur on a real Android device, since MobileFrame passes `child` through
unchanged there. The SEPARATE keyboard-toggle/input-mode clipping finding
(Bug 2 continued, above) was never actually MobileFrame-specific — it is a
width constraint on Material's own input-mode layout, and whether a real
narrow Android phone's width would independently trigger the same clipping
is genuinely UNVERIFIED (no device available this session; would need an
APK build, which requires explicit founder approval per this repo's
process). This is moot for what shipped: `initialEntryMode: TimePickerEntryMode.dialOnly`
removes the toggle icon UNCONDITIONALLY, on every platform, so the reachable
path into that layout is closed on Android regardless of the answer.

## See also

- `lib/shared/widgets/responsive_picker_builder.dart`
- `lib/app.dart` (`MobileFrame` — the actual fix location for Bug 2)
- `lib/shared/widgets/wardroom/ward_phase_block.dart`
- `lib/features/onboarding/screens/identity_screen.dart` (DOB)
- `lib/features/profile/screens/edit_profile_screen.dart` (the two real,
  live wake/workout-time picker call sites — bare `showTimePicker`, no
  builder, the exact shape Bug 2 blocked; also `_pickDateOfBirth()`, the
  second real DOB call site Round-1 review found missing the builder fix)
- `test/contracts/responsive_picker_host_test.dart`
- `test/contracts/mobile_frame_mediaquery_test.dart`
- `test/contracts/wake_workout_time_picker_dial_only_test.dart` (Bug 2 continued)
- `test/contracts/dob_picker_calendar_only_and_builder_test.dart` (Round-1 review Findings 1+2)
- `test/wardroom/ward_phase_block_test.dart`
- `test/onboarding/stats_screen_activity_pills_test.dart` (Bug 3 — no defect found)
- `lib/features/onboarding/screens/stats_screen.dart` (Bug 3 investigation target)
- `docs/diagnoses/2026-06-13-onboarding-picker-clipped-actions-e8a2c1.md`
  (the fix `responsivePickerBuilder`'s height-bounding mechanism supersedes)
- Companion diagnose (muster/induction restructure, same batch): see the
  batch retrospective memory file for the muster wake/workout-time question
  retirement that also removed `_pickTime` from `muster_screen.dart`.
