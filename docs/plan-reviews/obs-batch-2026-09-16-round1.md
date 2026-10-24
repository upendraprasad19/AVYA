# Plan-review round 1 — obs-batch-2026-09-16

Scope: plan/diagnosis-level review only (root-cause correctness + fix scoping),
per CLAUDE.md §4.12. The B-pass (`docs/reviews/08821dc5a27b-review.md`, 7
findings, all remediated) already covered code-level bugs — not re-litigated
here except where a code-level fact is needed to evaluate a diagnosis claim.
All claims below were checked against the actual staged diffs, the real
`assets/data/exercise_library.json`, and the real production source files —
not against the diagnose-docs' own prose.

## Fix 1 (quote-picker): PASS

**Q1 — root cause.** Read `categoryForWorkout` pre- and post-fix directly.
The pre-fix order (pull → push → legs) meant any name containing a whole-word
PULL-category token (BACK, CURL, LAT, ROW, PULL, DEADLIFT, BICEP) short-
circuited before the LEGS branch ever ran. "Barbell Back Squat" and "Leg Curl
(Lying)" both hit this. The diagnosis (a genuine keyword-*priority* collision,
not a word-boundary bug) is correct — confirmed by hand: `\bBACK\b` and
`\bCURLS?\b` both legitimately match those names as whole words, so no amount
of word-boundary tightening changes the outcome; only re-ordering does.

**Q2 — scope, independently re-verified against the real library (not the
diagnose-doc's own audit).** Ran a standalone script recomputing OLD vs NEW
`categoryForWorkout` against all 292 real entries in
`assets/data/exercise_library.json`, cross-checked against each entry's own
`category` ground-truth field:

```
total changed by reorder + BACK word-boundary: 10
('Barbell Back Squat', gt=legs, old=pull, new=legs)          — correct
('Leg Press', gt=legs, old=push, new=legs)                    — correct
('Leg Curl (Lying)', gt=legs, old=pull, new=legs)             — correct
('Single Leg Romanian Deadlift', gt=legs, old=pull, new=legs) — correct
('Cable Tricep Kickback', gt=push, old=pull, new=push)        — correct
('Glute Kickback (Cable)', gt=legs, old=pull, new=legs)       — correct
('Standing Single Leg Curl', gt=legs, old=pull, new=legs)     — correct
('Dumbbell Kickback', gt=push, old=pull, new=general)         — improved, not fully correct (documented residual)
('Glute Kickback', gt=legs, old=pull, new=legs)               — correct
('Sliding Leg Curl', gt=legs, old=pull, new=legs)             — correct
```

This is an exact match to what the diagnose-doc + B-pass Finding 1 already
claim and disclose (including the "Dumbbell Kickback → general, not push"
residual gap). **No new, undocumented collision exists in the real library**
beyond the two already-accepted residuals (Nordic/Reverse Nordic Curl →
'pull' via CURL, ground truth 'legs'; Dumbbell Kickback → 'general', ground
truth 'push'). Independently confirmed both residuals against the live JSON
(`Nordic Curl | legs`, `Reverse Nordic Curl | legs`).

**Q3/Q4 — interaction / duplication.** Pure in-memory string classifier, no
other caller reorders or duplicates this logic (`week_selector.dart`'s
`_phaseRoman` is unrelated — different concept, checked as part of Fix 3).
Not applicable.

**Q5 — live check.** Not applicable — pure client-side string logic, fully
verifiable statically against the bundled JSON asset, which was done above.

## Fix 2 (sync auto-drain): PASS

**Q1 — root cause, checked for an alternate unaddressed cause.** Read the
full enqueue → persist → drain → executor chain directly
(`lib/core/services/sync_queue.dart`, `lib/core/services/sync/sync_profile.dart`,
`lib/core/services/sync_service.dart:669-679`):

- `enqueue()` persists to `syncBox['pending_sync_<id>']` **synchronously**
  before returning (`_persist` then `_notifyPending()`), which is what drives
  the `SyncBanner`'s "N waiting" count. The founder's observed banner is
  therefore proof the op **was** enqueued correctly — ruling out "a Hive
  write that never actually enqueued" as an alternate cause for this specific
  symptom.
- The founder's manual "Retry" tap resolved it **immediately**, which is only
  possible if `drain()` → `_runOne()` → the registered executor all already
  worked correctly. This rules out "a silently-failing executor" as an
  alternate cause — a broken executor would have made manual Retry fail too.
- The only remaining explanation consistent with both observations (banner
  shown + manual retry fixes it instantly) is exactly what the diagnose-doc
  claims: no automatic trigger ever called `drain()` except app-launch. Grep
  confirms this independently: `grep -rn "SyncQueue.instance.drain()" lib/`
  → exactly `splash_screen.dart:256` (launch) and 3 sites in
  `sync_state_provider.dart` (the 2 new ones + `retryNow()`), no others.

This is a well-supported diagnosis; the alternate-cause question the review
brief specifically raises ("a silently-failing executor" / "a write that
never enqueued") is not just theoretically ruled out but is ruled out **by
the founder's own two data points** (banner appeared, manual retry worked).

**Q2 — scope.** Additive only: two new *triggers* for the pre-existing
`drain()` path, no new payload/executor/backoff logic. Confirmed no other
`Timer.periodic` in the codebase was mis-attributed to this queue (the
diagnose-doc's own grep of other `Timer.periodic` sites — recording ticker,
video-render polling, workout timers, OTP resend, profile-prediction poll —
was spot-checked and none plausibly overlaps this concept). Scope is neither
too narrow (both documented-but-missing triggers are now wired) nor too
broad (`sync_queue.dart`'s core drain/backoff/executor logic is untouched
apart from the in-flight guard, which is itself a direct consequence of the
new triggers making overlap routine rather than rare — B-pass Finding 4,
already remediated).

**Q3 — interaction with untouched code.** Confirmed `syncStateProvider` is
never invalidated anywhere in the app (`grep -rn "syncStateProvider" lib/`
→ only `sync_banner.dart`'s `watch`/`read`, no `ref.invalidate` site exists),
which matches the diagnose-doc's "provider lives for the app's session"
claim and rules out a duplicate-timer/duplicate-listener leak from repeated
provider rebuilds.

**Q4 — half-shipped / duplicate mechanism.** No duplicate drain mechanism
exists elsewhere; this is the only trigger-registration site. The B-pass
already caught and fixed the two real gaps here (missing kill-switch for the
platform-tier blast radius, missing in-flight concurrency guard) — both
verified present in the current diff.

**Q5 — live check.** Live Postgres/Supabase state is not relevant to this
fix (no schema, no query, no executor logic changed). A live-device
connectivity toggle is explicitly and correctly flagged as OWED in the
diagnose-doc's own tier-11 evidence — appropriate, since `connectivity_plus`'s
platform channel cannot be exercised from `flutter test`. Not re-attempted
here (would require a real device); the diagnose-doc's own honesty about
this gap is correct and sufficient for a plan-review pass.

## Fix 3 (Train phase-lock): ISSUE FOUND (P2)

**Q1 — root cause.** Traced the "future phase" windowing mechanism
independently through `CurrentPlanData.getWeek` (`train_provider.dart:449`),
`WorkoutScheduleReadService.getWeek`/`completedWeekNumbers`
(`workout_schedule_read_service.dart:1131,1189`), and the doc comments there.
Confirmed: `plan_start_date` is re-anchored on every phase advance (per
`workout_schedule_read_service.dart:1148`, "the chip unlocks BEFORE any phase
advance **moves** `plan_start`"), and week numbers 1-12 exposed to the UI are
always *relative to the current phase's own `plan_start`* — i.e. weeks 1-4
are structurally always the current phase, 5-8 always the next, 9-12 always
the phase after, **regardless of the absolute phase number**. Given this,
`isFutureUngeneratedPhase(selectedWeek) = (selectedWeek-1)~/4 >= 1` is a
sound, phase-number-independent test — it does not need to know whether the
user is on phase 1 or phase 11, and I found no case where it misclassifies a
genuinely-current week as future. The root cause and the mechanism are
correctly diagnosed.

**Q2 — scope: THE FIX IS TOO NARROW WITHIN THE SAME SCREEN.** Reading
`screen.dart` end-to-end (not just the lines the diagnose-doc cites) surfaces
a second, pre-existing, **unaddressed** UI element that fires on exactly the
same trigger this fix targets:

```dart
// screen.dart:168-219 (unchanged by this diff)
if (selectedWeek == plan.currentWeek)
  ( ...hero card... )
else
  Padding(
    ...
    child: WardCard(
      child: Row(children: [
        Icon(Icons.calendar_today, ...),
        Text(
          selectedWeek > plan.currentWeek
              ? 'Week $selectedWeek hasn\'t started yet'
              : weekDays.isEmpty
                  ? 'No workouts scheduled for this week'
                  : 'Viewing Week $selectedWeek plan',
        ),
      ]),
    ),
  ),
```

`plan.currentWeek` comes from `getCurrentWeekNumber()`, which is **hard
clamped to `[1,4]`** (`workout_schedule_read_service.dart:1420`,
`clamp(1, 4)`). So for any `selectedWeek >= 5` (exactly the case this fix's
`isFutureUngeneratedPhase` targets), `selectedWeek > plan.currentWeek` is
**always true**, and this WardCard unconditionally renders "Week 5 hasn't
started yet" in the hero-card slot — in the *same* scroll view, a few
components above the newly-fixed empty-state card that now says "Complete
Phase III to unlock Phase IV."

This is the exact bug class the founder complained about ("reads like a
glitch"), sitting immediately adjacent to the fixed one, on the same tap,
untouched by this diff. Concretely, after this fix ships, tapping into a
future phase shows **two different messages about the same condition**: a
generic, unexplained "Week 5 hasn't started yet" near the top, and the new,
specific "Complete Phase III to unlock Phase IV" lock card further down. The
diagnose-doc's `impact_analysis` states *"Only the FALLBACK path... changes...
no navigation change"* without acknowledging this second widget exists or
fires on the identical condition — and the `writers`/`readers` YAML section
only cites the `_buildEmptyWeek` call site, not this WardCard block a few
dozen lines above it in the same file. This isn't a hypothetical: I traced
the exact clamp value and conditional to confirm it fires, not inferred it
from the diagnose-doc's prose.

Recommended remediation (small, in-scope): when
`isFutureUngeneratedPhase(selectedWeek)` is true, either suppress this
WardCard entirely (the new lock card below already explains the state) or
route its text through the same `futurePhaseUnlockCopy`-derived messaging so
the two don't read as contradictory/redundant. This does not require
touching the subscription-gate `/train/preview` mechanism the diagnose-doc
correctly declined to reuse — it's a same-screen, same-condition copy fix.

**Q2b — informational, not blocking (P4).** `_buildEmptyWeek`'s new copy
names `plan.phase` (from `progress['current_phase']`) as "the phase to
complete," while `isFutureUngeneratedPhase` derives "future" purely from
`plan_start_date`-relative week math. This codebase has at least one
documented precedent of `current_phase` and `plan_start_date` going out of
sync (`lib/features/train/CLAUDE.md`'s "PHASE I (DONE) missing" pitfall row,
2 known affected accounts, tracked via the `past_phase_blocks_strict_empty`
telemetry tripwire; OI-174 residuals on the related `phase_arc_display`
mechanism). In that drift scenario, a user who has *already* completed and
advanced past the phase named in the copy could see "Complete Phase III to
unlock Phase IV" for a phase they finished — which, unlike the old generic
"No workouts scheduled" message, actively asserts something false rather
than being vaguely uninformative. This is a pre-existing, rare (documented
as 2 accounts, ever) edge case this fix doesn't create, but the new copy is
more actively misleading than the old copy would be if that drift recurs.
Not blocking — noting it because Q2 of this review explicitly asks about
exactly this class of gap, and no existing test or telemetry would catch the
new copy's specific false-positive framing if the drift class recurs.

**Q3 — interaction with untouched code.** Verified the free-tier
subscription-lock branch (`!isProUser && week >= 5` at `screen.dart:349`)
still returns *before* `selectedWeekProvider.select(week)` runs, so a free
user cannot reach `isFutureUngeneratedPhase`'s branch via the week-chip tap
path (confirmed by direct read, unchanged by this diff).

**Q4 — half-shipped / interaction with the existing paywall-lock
mechanism.** Traced whether a user who is *simultaneously* non-PRO and
phase-locked can hit this new card: the tap-handler guard means a free user
can't set `selectedWeek >= 5` via the chip tap. However, `selectedWeekProvider`
is a plain `Notifier<int>` whose state is **not reset on a subscription
downgrade** (confirmed: no `ref.invalidate(selectedWeekProvider)` call site
is wired to any subscription-change listener — the only invalidation sites
are `screen.dart`'s own retry/regen callbacks and `hero_cards.dart:188`).
So a PRO user who selects week 5 and then loses PRO status **mid-session**
(e.g. expiry) without navigating away would continue to see the new
"Complete Phase X to unlock Phase Y" card — a message that doesn't mention
the now-relevant subscription requirement at all. This is a narrow,
low-probability timing window (requires a live downgrade while already
viewing a future week) and the pre-fix behavior in the same window was
similarly inaccurate (generic "no workouts"), so I'm not scoring this as a
blocking regression — flagging it alongside Q2b as a lower-priority residual
the diagnose-doc doesn't mention, for completeness only.

**Q5 — live check.** Not applicable — pure client-side derivation from
already-in-memory `plan.phase`/`selectedWeek`; no cloud state to query.

## Fix 4 (auth toast): PASS (with a documentation-precision note)

**Q1 — root cause.** Confirmed directly: `AuthState2` had exactly one
non-idle/loading/success bucket (`error`), and `signUpWithEmail`'s
confirmation-pending branch used it for lack of an alternative
(`auth_provider.dart:384` pre-fix). Diagnosis is correct.

**Q2 — scope.** Additive enum value, one call site changed
(`signUpWithEmail`'s confirmation branch), sibling "account already exists"
message correctly left on `.error` (confirmed unchanged at
`auth_provider.dart:369-371` — a real conflict requiring the user to change
course, not a happy-path next step). Scope is appropriately narrow.

**Q3 — audited every `AuthStatus` comparison site app-wide, not just
`sign_in_screen.dart`, per this review's explicit instruction.**
`grep -rn "AuthStatus" lib/` outside the two touched files returns exactly
two hits, both in `confirm_email_screen.dart`:

```dart
// :80  ref.listen — navigates away on success
if (next.status == AuthStatus.success) { context.go('/restoring'); }
// :88  build() — everything else falls through
if (authState.status == AuthStatus.error) { ...error UI... }
return _buildLoadingState(context);   // the implicit "else"
```

The diagnose-doc's own verification ("no switch statement anywhere
pattern-matches `AuthStatus` exhaustively — zero hits") is a **narrower
check than the risk it's meant to rule out**: an `if`-comparison with an
implicit "else" is exactly the shape that can silently mistreat a new enum
value, and a bare grep for `switch` wouldn't catch it. Doing the actual trace
myself: `authNotifierProvider` is a single app-wide `Notifier`, not scoped
per-screen, so `confirm_email_screen.dart` *can* observe a `.info` state left
over from an earlier `signUpWithEmail` call in the same session (the common
real-world flow: sign up, background the app, tap the email link on the same
device, App Link delivers back into the running Activity). In that case
`authState.status == AuthStatus.error` is false, and the screen falls through
to `_buildLoadingState()` — which is the **correct** UI for that moment
(verification via `confirmEmail` is about to run and will overwrite `state`
with the real outcome shortly after). No SnackBar/toast fires from this
screen for any status (its `ref.listen` only acts on `.success`), so there's
no double-toast risk either. **Net: the fallthrough is safe, but this was
confirmed by tracing the actual behavior, not by the diagnose-doc's own
justification method, which checked for the wrong risk shape (exhaustive
switch) rather than the one that mattered (safe-default fallthrough).**
Recommend tightening the diagnose-doc's `impact_analysis` wording for future
readers, but not a functional defect.

**Q4 — half-shipped/duplicate mechanism.** None — this is a genuinely new
severity bucket, no prior informational-toast mechanism existed to conflict
with.

**Q5 — live check.** Not applicable — pure client-side enum/state/UI change,
no cloud contract touched (confirmed: Supabase's response shape is
unaffected, only local classification of an already-existing branch).

## Fix 5 (vercel.json /confirm redirect): PASS

**Q1 — root cause.** Confirmed via direct read of `app_router.dart` (no
`setUrlStrategy` call exists anywhere in `lib/` — grep returns zero hits)
that Flutter web defaults to `HashUrlStrategy`, and confirmed the `/confirm`
GoRoute (`app_router.dart:142`, path `'/confirm'`) has no matching
`vercel.json` redirect pre-fix, identical to the already-fixed `/admin`
precedent. Diagnosis is correct and directly analogous to a working existing
pattern in the same file.

**Q2/Q3 — scope + conflicts with the rest of the routing table.** Read the
**entire** `vercel.json` (only 15 lines) rather than just the diff:

```json
{
  "redirects": [
    { "source": "/admin", "destination": "/#/admin", "permanent": false },
    { "source": "/admin/", "destination": "/#/admin", "permanent": false },
    { "source": "/confirm", "destination": "/#/confirm", "permanent": false },
    { "source": "/confirm/", "destination": "/#/confirm", "permanent": false }
  ],
  "rewrites": [
    { "source": "/((?!\\.well-known/).*)", "destination": "/index.html" }
  ]
}
```

No overlap or shadowing: `/admin` and `/confirm` are distinct literal
sources: neither is a prefix or regex that could match the other, and both
sit before the SPA catch-all `rewrites` rule, which itself still correctly
excludes `.well-known/` (confirmed unchanged). The `app_router.dart` route
registration (`path: '/confirm'`, exact match, no sub-path) matches the
redirect's destination fragment (`/#/confirm`) exactly. No other route in
this file could be shadowed by the new entries.

**Q4 — half-shipped/duplicate mechanism.** None — `/admin`'s redirect is the
only precedent and this fix is byte-for-byte the same shape, correctly
reused rather than reinvented.

**Q5 — live check: explicitly not performed, and that's the right call
here.** This fix is unmerged/undeployed — Vercel only builds this repo's
`main`/tracked branches, so a live `curl` against
`app.icanbefitter.com/confirm` right now would only test the **currently
deployed** (pre-fix) config, telling us nothing about the staged change. The
diagnose-doc already and correctly marks live verification as OWED
post-deploy (tier 11), which is the appropriate place for it — not this
pre-merge review. Static verification (the full-file read above, plus the
existing `test/contracts/confirm_web_redirect_test.dart` parsing the real
staged JSON) is the complete verification available at this stage.

## Summary

**1 issue found** (Fix 3), plus 2 lower-priority/informational notes (also
under Fix 3) and one documentation-precision note (Fix 4). No issues in
Fixes 1, 2, or 5.

- **P2 — Fix 3 scope gap (blocking, small fix):** `screen.dart`'s pre-existing
  "Week $selectedWeek hasn't started yet" `WardCard` (lines ~194-219) fires
  unconditionally whenever `selectedWeek > plan.currentWeek` — which is
  always true for the exact future-phase case this fix targets — and was not
  touched or even mentioned by this fix. Post-fix, tapping a future phase
  shows two different, un-reconciled messages about the same condition in
  one scroll view. This is the same "reads like a bug" complaint class the
  founder raised, left reachable a few components above the widget that was
  actually fixed. Recommend suppressing or re-wording that WardCard when
  `isFutureUngeneratedPhase(selectedWeek)` is true, in the same commit.
- **P4 — Fix 3 informational:** the new copy names `plan.phase` (from
  `current_phase`) while "future" is computed from `plan_start_date`; this
  codebase has a documented, rare precedent of those two drifting
  (`current_phase > 1` with stale `plan_start`/past-phase display gaps, 2
  known accounts). In that drift scenario the new copy could assert a false
  "complete phase X" to a user who already has. Not blocking; noted for
  awareness since no test/telemetry catches this specific framing.
- **P4 — Fix 3 informational:** `selectedWeekProvider`'s state isn't reset on
  a subscription downgrade, so a PRO user who selects a future week and then
  loses PRO mid-session could see the new lock copy without any mention of
  the (now relevant) subscription requirement. Narrow timing window,
  pre-existing gap in kind (not introduced by this fix), not blocking.
- **Documentation-only — Fix 4:** the diagnose-doc's "no switch pattern-
  matches AuthStatus exhaustively" justification checks a narrower risk
  shape than what actually matters (an `if`/implicit-else fallthrough in
  `confirm_email_screen.dart`). Independently traced that fallthrough and
  confirmed it's safe — no functional defect, just a weaker-than-it-reads
  verification method worth tightening in the doc.

**What was checked and passed cleanly for Fixes 1, 2, 4, 5:** root cause
traced against actual reader/writer code (not diagnose-doc prose) for all
five fixes; Fix 1's claimed keyword-collision set independently recomputed
against the full real 292-entry exercise library (exact match, no new gaps);
Fix 2's "could the symptom have a different unaddressed cause" question
answered definitively using the founder's own two observations (banner
appeared + manual retry worked) rather than assumption; Fix 4's AuthStatus
usage audited app-wide (not just the touched file) with the actual
fallthrough behavior traced by hand; Fix 5's entire (short) `vercel.json`
read for shadowing/conflicts rather than just the diff hunk.

**Verdict: NOT YET CONVERGED — one round of small, well-scoped remediation
needed (the Fix 3 WardCard reconciliation), then proceed to round 2 on the
hardened plan.** This does not rise to a full scope-split: the fix is
correctly architected and the gap is a same-file, same-screen copy/
conditional addition, not a redesign. No live-state verification via MCP/
Supabase tools was performed for this batch — correctly, since all 5 fixes
are client-side/static (pure Dart functions, enum/UI wiring, or a Vercel
config file with no deployed state yet to check against) and the diagnose-
docs already and correctly flag the two genuinely-unverifiable-until-deploy
claims (Fix 2's live connectivity toggle, Fix 5's live redirect) as OWED
post-deploy rather than claiming false certainty now.
