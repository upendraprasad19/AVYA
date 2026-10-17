# B-pass review: age floor 13 and the "by tapping" sign-up consent (`age-floor-signup-consent`)

Date: 2026-10-16. Blast radius `account` (L tier: auth). Plan: `docs/plans/age-floor-signup-consent.md`. Record: `docs/plan-reviews/age-floor-signup-consent.md`.

**Method.** Two fresh context-blind Sonnet reviewers on the working tree (the whole batch is `git diff 3c86960d`: the code commit plus the staged round-2 edits), under `docs/agent_brief_preamble.md` and an exhaustive read-only command list (`git diff`, `git show`, `git log`, `git status`, `ls`, `wc`, `grep`, the Read / Grep / Glob tools; no `dart`, `flutter`, script, database or network tool, no writes). A: production code and tests, with proposed mutants. B: documents and claims. Both ran after two plan-review rounds (round 2 was itself two lenses).

**Result.** 0 P0, 0 P1. Reviewer A: 3 P2, 9 P3 (15 proposed mutants). Reviewer B: 4 P2, 7 P3. 0 false alarms; every finding was verified against the code before it was adopted. Every one is fixed or recorded with a reason below.

## Reviewer A: code and tests

| # | Sev | Finding | Disposition |
|---|---|---|---|
| A-P2-1 | P2 | `scroll_date_picker_clamp_test` read only what `onDateChanged` reported, never where the wheels ended up: deleting the two `jumpToItem` calls left it green | FIXED: the month and day cases read `FixedExtentScrollController.selectedItem` (Oct = 9, day 16 = 15). Mutant R1 (the two jumps deleted) is RED |
| A-P2-2 | P2 | `age_floor_pickers_test` asked only for `latestAllowedDob(`: `.add(Duration(days: 4000))` on the chat or Edit Profile ceiling stayed green | FIXED: each picker's ceiling expression is pinned verbatim (`_ceilings`). Mutants R2 (chat) and R3 (Edit Profile) are RED |
| A-P2-3 | P2 | nothing opened the identity picker with a carried-in date younger than 13, so deleting the `initialDate` clamp (a Flutter assertion in debug) stayed green | FIXED: a widget test carries `latest + 1 day`, taps the date tile and expects `initialDate == lastDate` and no exception. Mutant R4 is RED |
| A-P3-1 | P3 | the resume path (`classifyDestination` treats a non-null date of birth as "identity done") skips the identity floor for a profile that stored 10 to 12 under the old floor; `completeOnboarding` has no floor check | RECORDED with a reason (plan section 4 "Client-only enforcement"): no such profile exists (youngest 24 on 2026-10-04), the policy deletes an account found under 13 |
| A-P3-2 | P3 | `ScrollDatePicker` did not clamp a seeded `initialDate` later than `lastDate`: the year wheel opened past its last item and Next kept a date the picker never offers | FIXED: `initState` clamps the seed to `lastDate`; a test opens on `lastDate` and reads all three wheels. Mutant R5 is RED |
| A-P3-3 | P3 | `jumpToItem` runs inside `onSelectedItemChanged` while a finger may still be dragging; behaviour on a device is unverified | RECORDED: `DEVICE-CHECK-AGE-CONSENT` (drag the month wheel past the ceiling and release) |
| A-P3-4 | P3 | the consent links were untested: swapping the two URLs or dropping a recognizer survived | FIXED: both spans are asserted to carry distinct `TapGestureRecognizer`s, and source pins fix each recognizer to its URL and its span (whole-line comment stripping, because a `//` inside a URL must survive). Mutants R7 (URLs swapped) and R8 (recognizers swapped) are RED |
| A-P3-5 | P3 | the notice was a `RichText` (no text scaling) although it is the consent mechanism | FIXED: `Text.rich`; a test asserts the scaler is not `noScaling`; the colour assertion moved to the notice's own span. Mutant R6 (RichText again) is RED |
| A-P3-6 | P3 | the picker scan compared raw paths (a Windows clone lists backslashes) and knew only two opener names | FIXED: paths are normalised; seven opener names are scanned |
| A-P3-7 | P3 | `auth_flow_test` T3 (`find.byType(Checkbox)` is empty) passes on any screen; T5 is gone | RECORDED: a device test that runs by hand with credentials; the notice itself is asserted by `sign_up_consent_notice_test`, which is the enforced coverage |
| A-P3-8 | P3 | `identity_dob_floor_test` computes `latestAllowedDob(DateTime.now())` twice; a run straddling local midnight can flip it | RECORDED: negligible (a sub-second window once a day), documented in the test file |
| A-P3-9 | P3 | the floor is enforced only in the client (Edit Profile `_save`, a cloud restore and a wrong device clock bypass it) | RECORDED in plan section 4 with the A-P3-1 reason |

Reviewer A's other proposed mutants (the day never pulled back, no clamp, clamp to 1 December, `carried = _dob!`, a boundary off by one day, the 29 February branch, the `isBefore` boundary, the fallback Hive line, a local-time stamp) were already RED by the round-1 and round-2 runs, or are covered by the same tests; the CONTINUE date-only mutant (`carried = _dob!`) needed the time-of-day fixture added in round 2.

## Reviewer B: documents and claims

| # | Sev | Finding | Disposition |
|---|---|---|---|
| B-P2-1 | P2 | GO_LIVE 3.5 said "RESOLVED" and the auth CLAUDE.md row said "every path", but the founder decision and the plan cover the email path only; the Google button has no notice and the Google / phone stamp is automatic | FIXED: 3.5 is "NARROWED, founder to confirm" with the facts; the CLAUDE.md row and the auth-detail heading say email only |
| B-P2-2 | P2 | the paragraph under GO_LIVE 3.1 still said "currently unverified" and cited `sign_in_screen.dart:1396,1400` | FIXED: published and read 2026-10-16; lines 1459 and 1463 |
| B-P2-3 | P2 | `naming_conventions.md` called `termsV2EffectiveFromUtc` the instant the policy took effect; the constant is a date boundary (IST midnight of 16 October) | FIXED |
| B-P2-4 | P2 | the ledger's REVIEWS row cited a `bpass: accepted` the plan-review record did not carry yet | FIXED: this file exists and the record carries `bpass: accepted` and `bpass_review` |
| B-P3-1 | P3 | stale line numbers in the plan; registry `terms_acceptance` ranges (`auth_provider.dart` 1159-1168, `sign_in_screen` ~939, `hydrateFromCloud` 758-1088) | FIXED to 1290-1295, ~1096, 774-1109 |
| B-P3-2 | P3 | `functionality-flow.md` ONB-04 still "needs test"; AUTH-06 omitted the notice, v2 and the RestoringScreen call site | FIXED (ONB-04 also leaves the uncovered list) |
| B-P3-3 | P3 | `database.md:57` said "TermsModal no longer exists" and then "skip the standalone TermsModal" | FIXED: the tail is labelled history |
| B-P3-4 | P3 | the auth-detail consent heading disagreed with the nested CLAUDE.md | FIXED |
| B-P3-5 | P3 | OI-305: the "Blocked on" line still said "keep the current age rules"; the Decision line said "beside" the button (it is above); "written and reviewed" before this review | FIXED (the first line says SUPERSEDED; "above"; the Progress sentence names the reviews) |
| B-P3-6 | P3 | OI-310 still says the pages are "Last updated: June 2026" | RECORDED: the OI-310 text is edited on PR #118's branch (the board is only consistent once that merges, which the merge order guarantees comes after this PR); it is not duplicated here to avoid a three-way conflict |
| B-P3-7 | P3 | migration 032's header and live column comment still describe a `TermsModal` | RECORDED in `database.md:57`: the migration is applied and is not edited |

## Verified true by the reviewers

`2026-10-15T18:30:00Z` is IST midnight of 16 October and `termsVersionForAccountCreatedAt` uses `isBefore`; no reader compares `terms_version` (grep over `lib`, `supabase`, `scripts`, `test`, `integration_test`); exactly three picker call sites plus the widget; `latestAllowedDob` clamps 29 February correctly (13 is never a leap offset); the plan's consent and bootstrapper cites; OPEN_INDEX has 208 headings and 208 rows; no banned deferral phrase in the diff.

## Mutation appendix (round 2 and B-pass, on the final tree)

Each mutation: anchor count asserted before writing, file restored in a `finally`, `git diff --stat` checked after.

| Mutant | File | Result |
|---|---|---|
| C1 clamp always to `lastDate` | `scroll_date_picker.dart` | RED |
| C2 month not pulled back | same | RED |
| C3 day never pulled back | same | RED |
| C4 no clamp at all | same | RED |
| CONTINUE compare keeps the time of day (`carried = _dob!`) | `identity_screen.dart` | RED (needs the 15:30 fixture) |
| fallback cloud update writes `AppConstants.termsVersion` | `auth_session_bootstrapper.dart` | RED |
| fallback Hive put writes `AppConstants.termsVersion` | same | RED |
| R1 the two wheel `jumpToItem` calls deleted | `scroll_date_picker.dart` | RED |
| R2 chat ceiling `.add(Duration(days: 4000))` | `onboarding_chat_screen.dart` | RED |
| R3 Edit Profile ceiling loosened by 3650 days | `edit_profile_screen.dart` | RED |
| R4 identity `initialDate` clamp removed | `identity_screen.dart` | RED |
| R5 `initState` clamp removed | `scroll_date_picker.dart` | RED |
| R6 notice back to `RichText` | `sign_in_screen.dart` | RED |
| R7 privacy and terms URLs swapped | same | RED |
| R8 privacy span given the terms recognizer | same | RED |

## What the pass proved about method

The code was right on every boundary the reviewers checked; what was thin was what the tests could SEE. Three of the four test findings were the same shape: an assertion on a reported value (the callback, the source text) standing in for the state the user sees (the wheel position, the expression, the dialog's seed). The document reviewer found one claim that overreached a decision (3.5 "resolved" for a founder decision that covered email only). Round 2's lens A had already found the fallback call-site wiring observed by no test; the three together say the same thing: a pure-function test next to a wiring change protects the function, not the wiring.
