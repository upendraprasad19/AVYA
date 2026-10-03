---
reviewed_at: 2026-08-20T14:30:00+05:30
staged_against: b7602ad3016b
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, test_can_actually_fail]
findings_count: 2
findings_accepted: 2
findings_false_alarm: 0
verdict: accepted
---

# Code Review — b7602ad3016b (FOB-1 week identity)

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** lib/features/profile/providers/profile_provider.dart:313 (root cause); lib/features/home/screens/home_screen.dart:765-770 and lib/features/train/screens/train/screen.dart:171-177 (missing invalidation at both hold-write call sites)
- **claim:** `UserStatsNotifier.build()` computes `weekId` via a plain call — `WorkoutScheduleService.instance.weekIdentity()` — instead of `ref.watch(weekIdentityProvider)` or `ref.watch(currentPlanProvider)`. This means `userStatsProvider` (the sole data source for `journey_timeline.dart` and `profile_content.dart` — 2 of the "six" surfaces this batch fixes) has NO dependency-graph link to the hold write at all. Riverpod invalidates `weekIdentityProvider`/`holdStatusProvider` because they each declare `ref.watch(currentPlanProvider)`; `userStatsProvider` declares no such watch, so it is never marked dirty by the same event.
  Concretely: both places that call `runFreeTierRepeatWrite`/`holdWeek()` from the UI — `PlanExpiredCard.onRedoComplete` wired in `home_screen.dart:766-769` and `lib/features/train/screens/train/screen.dart:172-176` — invalidate `currentPlanProvider` (+`todayWorkoutProvider`/`selectedWeekProvider`) but never `userStatsProvider`. The app's 5 tabs live under `StatefulShellRoute.indexedStack` (`lib/core/router/app_router.dart:359-361`), so a tab that was already mounted this session is NOT rebuilt on tab-switch — Riverpod state simply survives. `userStatsProvider` is otherwise invalidated only by: `edit_profile_screen.dart:1723`, `reports_screen.dart:175`, `tool_dispatcher.dart:1438` (an unrelated AI-coach tool), and `screen.dart:112`'s `invalidateOnRetry` (a manual pull-to-refresh/error-retry hook, not a tab-mount hook). None of these fire from the hold-taking action.
  **Trigger:** a user opens the app, visits Profile at any point (building `userStatsProvider` once), then goes to Train, taps "Keep Training Phase 1" while `enable_hold_weeks` is ON (the flag this batch exists to flip on). Home and Train immediately show "HOLDING · H1" (correctly reactive). Switching back to the already-mounted Profile tab still shows the pre-hold "WEEK 4 OF 4" / "0 weeks to complete Phase 1" — the exact cross-tab self-contradiction this diagnose-doc (`docs/diagnoses/2026-08-20-hold-week-identity-clamp-f4c8e1.md`) says the batch fixes — until an unrelated action (edit profile, view weekly report, an AI-coach tool call, or a manual retry) happens to invalidate `userStatsProvider`, or the next day-rollover (`day_rollover_service.dart:190-221`, which also does not list `userStatsProvider`). This is not merely "as stale as before" — pre-fix, `currentWeek` staleness was cosmetically minor (off by a few hours near a week boundary); post-fix, the SAME staleness now means the two-of-six surfaces this batch is supposed to have fixed keep showing the old, wrong, contradicted-by-Home/Train copy indefinitely.
- **verification:** `grep -n "ref.watch(currentPlanProvider)\|ref.watch(weekIdentityProvider)" lib/features/profile/providers/profile_provider.dart` returns nothing; `grep -n "invalidate(userStatsProvider" lib/features/home/screens/home_screen.dart lib/features/train/screens/train/screen.dart` returns nothing (compare `grep -n "invalidate(currentPlanProvider" ` on the same two files, which does).
- **suggested-fix:** Either have `UserStatsNotifier.build()` do `ref.watch(currentPlanProvider)` (or read `ref.watch(weekIdentityProvider)` directly for `weekInPhase`/`holdOrdinal`) so it re-derives whenever the plan/hold state changes, regardless of which call site wrote it — this is more robust than patching every current and future hold-write call site with an extra `ref.invalidate(userStatsProvider)`.
- **status:** accepted — FIXED in-batch. `UserStatsNotifier.build()` now does
  `final weekId = ref.watch(weekIdentityProvider);` (`profile_provider.dart`), taking the
  reviewer's preferred option: it links the notifier to the dependency graph once, for every
  current AND future hold-write call site, instead of patching two call sites with an
  `invalidate` a third would forget. `weekIdentityProvider` itself watches `currentPlanProvider`,
  so the chain is complete. Confirmed no import cycle: `train_provider.dart` does not import
  `profile_provider.dart` (`grep -n "profile_provider" lib/features/train/providers/train_provider.dart`
  → 0 hits). The wiring test's token for this file was tightened from `weekIdentity()` to
  `ref.watch(weekIdentityProvider)` so a revert to the singleton reddens rather than passing —
  and it DID redden during this fix, which is how the token drift was caught.

## Finding 2 — P2 — test_can_actually_fail
- **file:line:** test/contracts/hold_week_identity_behavioral_test.dart:291-327 (`surface wiring (PRESENCE-ONLY — cannot catch a behavioural revert)` group)
- **claim:** This group is the ONLY test coverage touching `journey_timeline.dart`, `profile_content.dart`, `home_screen.dart`, `phase_roadmap_screen.dart` and `reports_screen.dart` in this batch, and every assertion in it is `body.contains(entry.value)` against the raw source text — it cannot fail on a logic inversion, only on the literal token disappearing. The test file's own group name discloses this ("cannot catch a behavioural revert"), but the practical effect is that the one place this batch's actual UI-visible behavior lives (the ternaries computing "HOLDING · Hn" vs "WEEK n OF 4") has zero behavioral assertion, on any of the five UI files, and zero test would catch Finding 1 above or a far more trivial bug like an inverted `isHolding` check.
- **verification:** Live-mutated and re-ran to confirm rather than assert from reading. `lib/features/profile/screens/profile/profile_content.dart:32` was changed from `stats.isHolding ? 'Holding · H...' : 'Week ...'` to `!stats.isHolding ? 'Holding · H...' : 'Week ...'` (an inverted condition — a real defect that would show "Holding · Hnull" to every non-holding user and "Week 4" to every holder) and `PATH=/opt/flutter/bin:$PATH flutter test test/contracts/hold_week_identity_behavioral_test.dart` was re-run: **16/16 still passed**. The file was then restored from a pre-edit backup and verified byte-identical (`git diff -- lib/features/profile/screens/profile/profile_content.dart` empty, `git status` shows only the pre-existing staged `M`).
- **suggested-fix:** Extract the label-selection logic per surface into a small pure function (e.g. `String profileWeekSegment(UserStatsData stats)`, `String journeyWeekLabel(UserStatsData stats)`) and add a table-driven unit test asserting the exact rendered string for `{isHolding:false, currentWeek:4}` → `"WEEK 4 OF 4"` and `{isHolding:true, holdOrdinal:2}` → `"HOLDING · H2"` (and the equivalent pair for each of the other four surfaces / Remotion). This is cheap and would have caught both this mutation and Finding 1's staleness if extended to also assert `userStatsProvider`'s output after a real `holdWeek()` write without an intervening `ref.invalidate`.
- **status:** accepted — FIXED in-batch, exactly as suggested. All five label ternaries were
  extracted to pure functions in the new `lib/core/utils/hold_week_labels.dart`
  (`homeWeekSegment`, `profileWeekSegment`, `journeyWeekLabel`, `journeyPhaseOneMilestone`,
  `roadmapWeekLabel`), each taking `holdOrdinal` as the SINGLE discriminator so
  "holding but ordinal null" is not a representable state. New table-driven behavioral test
  `test/contracts/hold_week_labels_test.dart` (16 cases) asserts the exact rendered string on
  BOTH arms of all five, plus a cross-cutting group asserting no formatter can ever interpolate
  the literal "null" — which is precisely what the reviewer's inversion produced.
  **Re-proven by re-running the reviewer's exact mutation:** inverting `profileWeekSegment`'s
  ternary now reddens **4 tests** (it reddened 0 before this fix). Source restored
  byte-identically and re-verified green afterwards.
  Note the residual scope limit, stated rather than glossed: this closes the LABEL logic, not
  widget rendering. There is still no widget test mounting these five screens, so a surface that
  stopped calling its formatter altogether would be caught only by the presence-grep. Making that
  a real widget test is a larger piece of work than this batch, and it is not a flip-on blocker.

## Lens coverage — what was checked and why each clean lens returned clean

- **writer_reader_drift** — The only writer of the fields this batch reads (`is_hold`, `hold_ordinal`) is `WorkoutScheduleWriteService.holdWeek()` (`lib/core/services/workout_schedule_write_service.dart:287-288`), which is UNCHANGED in this diff (confirmed: `git diff --cached -- lib/core/services/workout_schedule_write_service.dart` returns nothing — the file isn't even in the staged file list). The new readers (`activeHoldOrdinalFor`/`holdOrdinalForDate` at `workout_schedule_read_service.dart:847-856`) read the identical field names the writer stamps. No drift introduced.
- **function_exception_swallow** — `git diff --cached | grep -n "functions.invoke"` → 0 matches. No `.functions.invoke(` call is added or touched by this diff (the pre-existing `video-render-trigger` invoke in `video_render_provider.dart` is untouched — that file is not in the staged file list; the diff only adds one new key, `holdOrdinal`, to an existing `inputProps` map built at `reports_screen.dart:1387`). N/A.
- **blast_radius_mismatch** — Ran the real classifier: `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -` → `Blast-radius: account`, matching the diff's own claim (`docs/plan-reviews/claude-oi-pending-hold-weeks-1od97o.md` frontmatter and `docs/audit/fob1-week-identity.closure.yaml`). Traced why: `lib/core/services/workout_schedule_read_service.dart` and `lib/core/services/workout_schedule_service.dart` both resolve to `account` (the latter has its own explicit rule at `docs/blast_radius.yaml:229`; the former falls through to the `lib/core/services/**` catch-all at `:302`) — the highest tier of any touched path. The `lib/features/{train,profile,home}/**` files are explicit `feature`-tier overrides (`:285-288`); `remotion/**`, `test/**`, `docs/**` are feature/default. `account` requires `[regression_test, behavioral_test_path, code_review_b_pass]` — `test/contracts/hold_week_identity_behavioral_test.dart` is staged (regression_test), `docs/sot_registry.yaml`'s new `hold_week_identity` entry declares `behavioral_test_path:` pointing at the same file, and this review is the `code_review_b_pass`. Requirement met structurally, findings above notwithstanding.
- **secrets_in_tree** — `git diff --cached | grep -nE "sk-[A-Za-z0-9]{10,}|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN|eyJhbGciOi|service_role"` → 0 matches.
- **unawaited_no_error_sink** — `git diff --cached | grep -n "^+.*unawaited("` → 0 matches. No `unawaited(` call is added by this diff. N/A.
- **guard_without_its_mirror** — Full trace of `WeekIdentity.weekInPhase`/`holdOrdinal` to every consumer:
  - `home_screen.dart:319-324` — `ref.watch(weekIdentityProvider)`, `weekInPhase` used only in the `!isHolding` branch where it's non-null by construction (XOR-typed constructors `WeekIdentity.week(int)`/`WeekIdentity.hold(int)` make a null read impossible without a null-assertion, and none is present). Clean.
  - `profile_provider.dart:348-350` — `weekId.weekInPhase ?? WorkoutScheduleService.instance.getCurrentWeekNumber()`: verified the fallback is value-identical to `weekId.weekInPhase` in every case (non-hold: `weekInPhase` already equals `getCurrentWeekNumber()`'s result by construction inside `weekIdentity()`; hold: `weekInPhase` is null so the fallback evaluates `getCurrentWeekNumber()` directly, which is *also* clamped to 4 during a hold) — not a value bug, though see Finding 1 for the reactivity gap around this same call.
  - `journey_timeline.dart:92-94,185-187` / `profile_content.dart:32-34` — both string interpolations of `stats.holdOrdinal` are guarded by `stats.isHolding` ternaries; confirmed by mutation-testing the guard (Finding 2) that the guard's *presence* is real but its *correctness* is untested.
  - `phase_roadmap_screen.dart:63,229-231` — `ref.watch(weekIdentityProvider).holdOrdinal`, guarded by `holdOrdinal == null ? ... : ...`. Clean; `currentWeek`/`completePct` deliberately NOT branched (recomputed fresh in the same `build()` since `ConsumerWidget.build()` reruns wholesale whenever any watched provider invalidates — verified this is NOT the same non-reactive-singleton shape as Finding 1, because this file's `build()` itself is gated by the `ref.watch(weekIdentityProvider)` call added by this diff).
  - `reports_screen.dart:1387` — `ref.read(weekIdentityProvider).holdOrdinal` inside an `onPressed` callback (not `build()`), so `ref.read` is correct here — no reactivity requirement for a one-shot button-press read, and `weekIdentityProvider`'s own cache is correctly invalidated via the provider graph (`ref.watch(currentPlanProvider)` inside its body) independent of whether anything is currently watching it.
  - Checked for bypasses of `activeHoldWeeks()`/`activeHoldOrdinalFor()`: `grep -rn "\.holdWeeks()\|\.holdOrdinalForDate(\|holdWeeksEnabled" lib test` — the one raw `holdOrdinalForDate()` call outside the read-service (`train_provider.dart:556`, pre-existing, not touched by this diff) is reached only when its caller's own `holdOrdinal` parameter (sourced from the already-gated `holdStatusProvider`) is non-null, so it cannot fire with the flag OFF. No new bypass introduced.
  - Remotion boundary (`WeeklyRecapVideo.tsx` vs `reports_screen.dart`): `holdOrdinal?: number` (TS optional) receives a Dart `int?` serialized through `functions.invoke`'s JSON body → `video-render-trigger/index.ts:28-51` (passthrough, no schema) → Remotion's `defaultProps` merge. TSX's `holdOrdinal == null` (loose equality) correctly catches both JSON `null` and an absent/`undefined` key, so the two are equivalent; no zod/schema validation exists to reject a `null` where `undefined` was expected. Clean.
  - Non-reactive-path check (the sharpest sub-question) surfaced Finding 1.
  - OI-125 trap (`selectedWeekProvider`/`getWeek()` fed a hold ordinal): grepped every new/changed line for `selectedWeekProvider`/`getWeek(` — none of the six surfaces or the new providers touch either; `SelectedWeekNotifier` is untouched by this diff. Clean.
- **test_can_actually_fail** — Reported as Finding 2, with a live mutation-and-restore proving the claim rather than asserting it.

## Founder triage notes

Triaged in-batch by the implementing session, 2026-08-20. **2 findings, 2 accepted, 0 false
alarms** — no lens tuning indicated (false-alarm rate 0/2). Both were fixed in this batch per
§4.2 rather than filed; neither was a judgement call.

Worth recording for the skill's tuning history: lens 6 found the P1 by asking the sharpest form
of its own question — not "is this guard correct?" (it was) but "is the value it produces
REACTIVE at the call site?". The seam, the provider and four of six surfaces were all correct;
the defect was that two surfaces reached the correct value through a notifier with no
dependency-graph edge to the write. That is the `guard_without_its_mirror` shape one level out:
the fix covered the thing being looked at and not the thing one step away.

The P2 is the second consecutive batch where `test_can_actually_fail` beat a mutation-proven
change. This batch shipped TWO mutation proofs on the service seam and cited both — and the
label layer, which is what the user actually reads, still had zero behavioral coverage.
Mutation-proving the seam does not mutation-prove the surfaces that consume it.
</content>
