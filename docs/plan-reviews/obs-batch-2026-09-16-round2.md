# Plan-review round 2 — obs-batch-2026-09-16

Scope: fresh, context-blind review of the CURRENT (post-B-pass, post-round-1)
staged state, per CLAUDE.md §4.12.1 — "the corrections themselves can
introduce new defects." This round does not re-litigate findings already
fixed by the B-pass (`docs/reviews/08821dc5a27b-review.md`) or round 1
(`docs/plan-reviews/obs-batch-2026-09-16-round1.md`); it scrutinizes the
remediation code those two rounds ADDED, and re-walks the full diff for
anything both rounds' narrower focus could have missed.

## Remediation review (B-pass fixes + round-1 fix)

**`disable_sync_auto_drain` kill-switch + `_draining` in-flight guard**
(`lib/shared/providers/sync_state_provider.dart`, `lib/core/services/sync_queue.dart`).
Read both in full.

- **Kill-switch reach is correctly scoped, not a gap.** `_autoDrainDisabled` is
  checked inline inside BOTH the connectivity listener and the periodic
  timer callback (not just once at `build()` time), so a flag flip takes
  effect on the very next fire of either trigger without needing the
  provider to rebuild. It deliberately does **not** gate `retryNow()`
  (manual tap) or the app-launch drain (`splash_screen.dart:256`) — correct
  by design, since the kill-switch's job (per its own doc comment and the
  B-pass Finding 3 that added it) is to disable the two NEW automatic
  triggers, not `drain()` itself. A user's manual "Retry" must keep working
  even with auto-drain disabled, and it does.
- **The `_draining` in-flight guard has a real, untested third-caller gap:
  `retryNow()` can silently no-op.** `retryNow()` is `await
  SyncQueue.instance.drain()` with nothing else. `drain()` now opens with
  `if (_draining) return;` — a bare, silent early return with no signal to
  the caller that no work happened. Before this batch, `retryNow()` always
  attempted `_loadAll()` + `_isDue` + `_runOne` on every tap (redundant only
  if a call was already in flight, but never a no-op). After this batch, the
  same guard that correctly protects the periodic timer and the connectivity
  listener from racing each other ALSO applies, unmodified, to a user's
  manual "Retry now" tap — a case the B-pass's Finding 4 (which added the
  guard) discusses only in terms of the two *new* triggers colliding with
  each other, not in terms of the pre-existing manual trigger. Concretely: if
  a user taps "Retry" on `SyncBanner` (`lib/shared/widgets/sync_banner.dart:46`,
  `onTap: () => ref.read(syncStateProvider.notifier).retryNow()` — fired
  and forgotten, not awaited, no loading/success/error state) while the
  periodic timer's or the connectivity listener's own `drain()` call is
  already mid-flight (a real possibility now that there are three
  independent triggers instead of one), the tap's `drain()` call returns
  immediately without touching a single op, and the UI shows no error, no
  "already retrying" state, nothing — the banner just sits there until
  whichever drain WAS already running finishes on its own and calls
  `_notifyPending()`. In the common case this self-heals (the in-flight
  drain processes the same due ops the user wanted retried), but the tap
  itself becomes a pure no-op with zero observability, exactly the failure
  shape CLAUDE.md's own recurring lesson `feedback_observability_silent_drop.md`
  warns about ("a rate-limited sink must return a distinguishable
  response"). `SyncState` has only `SyncIdle`/`SyncQueued(count)` — no
  "draining" state exists to make this visible even if a caller wanted to
  show one. **No test in `test/contracts/sync_queue_auto_drain_test.dart`
  exercises `retryNow()` at all, let alone its interaction with `_draining`**
  — confirmed by reading the file; it covers `shouldDrainOnConnectivityChange`,
  `isSyncAutoDrainDisabled`, the interval constant, and the wiring
  source-greps, and nothing else. This is a real gap in the remediation, not
  a pre-existing one — the guard is what turns a harmless double-execution
  into a silent, unindicated no-op for a case (`retryNow`) that predates this
  batch entirely. See Finding 1 below.

**Round-1's `else if (!isFutureUngeneratedPhase(selectedWeek))` WardCard
suppression** (`lib/features/train/screens/train/screen.dart:168-231`). Read
the full `if / else if` chain, not just the added line.

- The chain is: `if (selectedWeek == plan.currentWeek) <hero/expired card>
  else if (!isFutureUngeneratedPhase(selectedWeek)) <WardCard>`. There is no
  final bare `else`. So the combination `selectedWeek != plan.currentWeek`
  **and** `isFutureUngeneratedPhase(selectedWeek) == true` renders **neither**
  widget — not even a `SizedBox`. This is exactly the third, uncovered case
  the review brief asked me to hunt for. See Finding 2 below for whether it
  is reachable and what actually shows.
- The suppression comment (`screen.dart:195-206`) is accurate for what it
  claims (explains why the WardCard is suppressed for weeks 5-12) and does
  not contradict anything else in the file. It does not claim the resulting
  state is "nothing renders" or address the case where `weekDays` is
  non-empty despite `isFutureUngeneratedPhase` being true — an omission, not
  a false claim.
- I did not find any comment/doc-string elsewhere in `screen.dart` that the
  new guard makes stale. The one comment I checked closely — line 120-122,
  "hold rows sit at week 5+ and `plan.weeks` stops at the phase's 4" — is
  pre-existing, untouched by this diff, and turned out to be more precisely
  worded in its sibling file (`hold_chip_group.dart:19-25`: "`CurrentPlanData.weeks`
  only ever holds 4 entries for **phase 1**" — deliberately scoped, not a
  blanket claim). See Finding 2 for why that distinction matters here.

## Any new findings

### Finding 1 (P3) — `retryNow()` can silently no-op against the new `_draining` guard, untested

As described above: `SyncQueue.drain()`'s in-flight guard (added by the
B-pass for Finding 4) is a blanket guard over ALL callers, but was designed
and tested only against the two NEW auto-drain triggers colliding with each
other. The pre-existing manual "Retry" tap (`retryNow()` →
`SyncBanner.onTap`, unawaited, no loading/success/error UI) is a third caller
nobody analyzed against it. A user's tap during a concurrent auto-drain
silently does nothing, with no distinguishable response and no test
coverage of the interaction. Self-healing in the typical case (the
already-running drain calls `_notifyPending()` when it finishes and clears
the banner), but genuinely silent and unindicated if the in-flight drain is
slow (bad network) — during which a frustrated user could tap "Retry"
repeatedly and never see feedback that anything happened, or that nothing
did.

**Suggested fix (small, in scope for a follow-up, not blocking this batch):**
either (a) have `retryNow()` bypass or wait out `_draining` instead of
silently dropping (e.g. loop/await until the in-flight drain finishes, then
optionally run its own pass), or (b) return a `bool`/enum from `drain()`
indicating `ranOrSkipped` so `retryNow()` — and eventually the UI — can
distinguish "did nothing because already running" from "ran and found
nothing due." Given this is a UX/observability gap rather than a
correctness bug (no data is lost or corrupted; the queue drains eventually),
I am not scoring this as blocking, but it should not be silently left
unaddressed — it is a genuine residual the B-pass's own remediation
introduced and did not consider, of the same character as the two "not
blocking, but noted" residuals round 1 recorded for Fix 3 (Q2b, Q4).

### Finding 2 (P4, informational) — screen.dart's third case: gap when a future-phase week has non-empty data

Traced whether `isFutureUngeneratedPhase(selectedWeek) == true` can coincide
with `weekDays` (`plan.getWeek(selectedWeek)`) being **non-empty** — the
combination that would hit the suppressed-both-branches gap in the WardCard
chain while `_buildEmptyWeek`'s own `if (weekDays.isEmpty)` guard (further
down, unaffected by this batch) does NOT fire, so `_buildCompactWeekRows`
renders real content below a blank top status area instead of the new lock
card.

This is not purely hypothetical: `CurrentPlanData.build()`
(`lib/features/train/providers/train_provider.dart:776-789`, untouched by
this diff) computes `totalWeeks` as a fixed `4` only when `phase <= 1`; for
`phase > 1` it explicitly scans `repo.getWeek(5)` through `repo.getWeek(12)`
and extends `totalWeeks` (hence `weeks.length`, hence what `getWeek(week)`
can return) past 4 whenever the underlying schedule has non-empty data
there. `hold_chip_group.dart:19-22`'s own comment is careful to scope its
"only ever holds 4 entries" claim to **"phase 1"** specifically — implying
the same is not guaranteed once `phase > 1`. Hold rows are stamped
`week = 4 + ordinal` (same file, same comment) — precisely a week-5+-style
key. `HoldChipGroup` deliberately never drives `selectedWeekProvider` for
exactly this reason (its own comment: doing so would land on
`plan.getWeek(5) == []` and misrender "Week 5 hasn't started yet" — the
OI-125 trap, cross-referenced in `docs/sot_registry.yaml:6903` and multiple
prior diagnose-docs). But the REGULAR `WeekSelector` week chips (the ones
this batch's Fix 3 is about) are not part of that guard, and their
`onSelect` unconditionally calls `selectedWeekProvider.notifier.select(week)`
for any PRO user tapping a next-phase-group chip (`screen.dart:344-368`).

I was not able to fully confirm from static reading alone whether a live
account can simultaneously be (a) on phase 2+, (b) in an active hold, and
(c) have that hold's row actually picked up by the `totalWeeks` scan (vs.
`repo.getWeek`'s hold-row visibility being gated some other way I did not
trace to the bottom of) — so I am not asserting this reproduces today. What
I can assert from the code as staged: **if** that combination occurs, the
top-of-screen status area silently renders nothing (not even the
already-known-wrong "Week N hasn't started yet" OI-125 placeholder),
while the compact week rows below correctly show the real (hold) day. That
is a narrow regression in *kind* — "shows something, even if wrong" becoming
"shows nothing" — but arguably neutral-to-slightly-better in *substance*,
since the old placeholder was already a documented, known-wrong trap
message for this exact scenario, not a message this fix was asked to
preserve.

Neither the B-pass nor round 1 examined this specific three-way
combination; round 1's own Q2b/Q4 residual notes cover adjacent-but-distinct
edge cases (phase/`plan_start_date` drift, and subscription downgrade
mid-session). Recording this here for completeness, at the same
non-blocking disposition round 1 gave those two. Not required to fix in
this batch.

### Finding 3 (P4, documentation precision) — stale test-count in c4f9a1's mutation-proof claim

`docs/diagnoses/2026-09-16-train-phase-lock-empty-state-reads-as-bug-c4f9a1.md`'s
`touched_layers_checked` tier-1 evidence states the round-1 mutation-proof
as: *"reverted `'else if (!isFutureUngeneratedPhase(selectedWeek))'` to a
bare `'else'` in screen.dart, reran
`test/contracts/train_phase_lock_empty_state_test.dart` -> exactly 1 of 3
assertions in that file reddened ... restored and reran -> 3/3 green
again."* I independently ran the actual file (see below): it contains
**4** tests, not 3, and the mutation reddens exactly 1 of 4 — the correctly
named one ("the status-card branch is gated by
`!isFutureUngeneratedPhase(selectedWeek)`..."). The functional claim (which
assertion catches the regression) is accurate and the protection is real;
only the total count is stale, most likely because a 4th test
(`_buildEmptyWeek accepts isFutureUngeneratedPhase and currentPhase` or the
"when locked, uses `futurePhaseUnlockCopy`..." test) was added to the file
after this mutation-proof sentence was drafted and the sentence was never
re-derived — the same class of drift the B-pass already caught once in this
batch (Finding 6, stale line citations in the sync-queue diagnose-doc).
Purely cosmetic; does not affect this batch's correctness. Suggested fix:
change "1 of 3 ... 3/3" to "1 of 4 ... 4/4" in that doc.

## Mutation-proof independently re-verified

Re-ran the round-1 remediation's own mutation-proof claim (train
phase-lock, `docs/diagnoses/2026-09-16-train-phase-lock-empty-state-reads-as-bug-c4f9a1.md`
tier-1 evidence) rather than trusting its stated numbers, since that is
also where I found Finding 3 above.

1. Confirmed the pre-mutation baseline: `flutter test
   test/contracts/train_phase_lock_empty_state_test.dart` → **4 passed**,
   0 failed (the file has 4 `test(...)` blocks across 3 `group(...)`s, not
   3 tests as the diagnose-doc's mutation-proof sentence claims).
2. Edited `lib/features/train/screens/train/screen.dart`, replacing
   `else if (!isFutureUngeneratedPhase(selectedWeek))` with a bare `else`
   (the exact mutation the diagnose-doc describes).
3. Re-ran the same file: **3 passed, 1 failed** — the failure was exactly
   the test named in the diagnose-doc ("the status-card branch is gated by
   `!isFutureUngeneratedPhase(selectedWeek)`, not shown unconditionally
   whenever `selectedWeek != plan.currentWeek`"), failing with `Expected:
   not <-1> / Actual: <-1>` (the mutated source no longer contains the
   literal string the test greps for) — an exact match to the diagnose-doc's
   claimed failure mode, just with a denominator of 4 rather than 3.
4. Restored via `git checkout -- lib/features/train/screens/train/screen.dart`
   (the file was staged, so this reverts the working tree to the exact
   staged/batch content, not to `main`). Verified: `git status --porcelain
   -- lib/features/train/screens/train/screen.dart` → `M ` (staged-only,
   same as before the mutation); `git diff --cached --stat -- <same file>`
   → unchanged at "18 insertions(+), 2 deletions(-)", identical to the
   pre-mutation stat.
5. Final full-tree check: `git status --porcelain` across the whole repo
   matches the exact 26-path snapshot recorded at the start of this session
   (same files, same `M `/`A ` markers) — no residue from the mutation
   experiment anywhere.

Also re-ran, as a second (lighter) consistency check, the batch's own
blast-radius classification against the CURRENT staged file list:
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
→ `platform` (matches the batch's own documentation), and independently
re-classified each of the five fixes' own file groups in isolation — all
five matched their diagnose-docs' self-declared tiers exactly (quote-picker
→ `feature`; sync files → `account`; train phase-lock files → `account`,
i.e. the B-pass's Finding 2 correction has not drifted again; auth files →
`account`; `vercel.json` → `account`; `pubspec.yaml`+`pubspec.lock` alone →
`platform`, the actual driver of the batch-wide `platform` tier). No new
drift since the B-pass's own verification.

## Overall verdict: CONVERGED

Both new findings are P3/P4, non-blocking, and narrower in consequence than
round 1's own Fix-3 issue was (which was a P2 requiring remediation before
convergence): Finding 1 is a real but self-healing UX/observability gap with
no data-loss or correctness risk; Finding 2 is a traced-but-not-confirmed
edge case whose worst outcome (a blank status area) is arguably no worse
than the pre-existing, already-documented-as-wrong placeholder it would
otherwise show; Finding 3 is a one-digit documentation staleness with no
functional impact. None of the three rises to the bar that sent round 1 back
for another pass (a P2, definitely-reachable, user-visible contradiction).
Recommend logging Finding 1 as a small non-blocking follow-up (a `bool`/enum
return from `drain()` or a `retryNow()` that waits out an in-flight drain
instead of dropping) and Finding 3 as a one-line diagnose-doc correction,
neither of which need to hold up this batch.
