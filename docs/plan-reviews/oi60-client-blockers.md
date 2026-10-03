---
branch: oi60-client-blockers
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/2e9503eb-review.md
tier: platform
reviewed_at: 2026-08-25T01:15:00+05:30
---

# Plan review — OI-60 client-side flip blockers (FOB-7a, FOB-7b, OI-127)

> Status: **converged after two independent context-blind rounds.** Round 1
> returned 3 BLOCKING, round 2 returned 3 MAJOR + 1 MINOR, all accepted and
> fixed. `bpass:` is added only once the B-pass actually runs.
>
> ⚠ Sections above the "Round 1" heading are the ORIGINAL draft, corrected in
> place where round 1 refuted them. Every correction is marked; the round-1
> section below records what was found and why it was accepted.

## Scope

Three units, all pure client code. No Edge Function, no migration, no live prod
action. FOB-3 (ai-proxy redeploy) and FOB-4 (needs a migration) are separate.

## Ground truth established by direct read

### The hold row contract
- Hold rows are schedule rows stamped `is_hold: true` + `hold_ordinal: N`,
  written only by `WorkoutScheduleWriteService.holdWeek()` behind
  `enable_hold_weeks`. (`workout_schedule_read_service.dart:66-74, 829-830`)
- They also carry `week = 4 + ordinal`, but that index is unusable for display:
  `CurrentPlanData.weeks` only ever holds 4 entries for phase 1
  (`train_provider.dart` hardcodes `totalWeeks = 4`). (`:66-72`)
- Holds are Monday-backdated and start at `plan_start + 28`.
- The **gated** production seams are `activeHoldWeeks()` and
  `activeHoldOrdinalFor(date)` (`:891-896`); the ungated ones are `holdWeeks()`
  / `holdOrdinalForDate()`. Every production consumer goes through the gated
  pair so the flag empties the read surface from one point.
  ⚠ **CORRECTED after round 1:** the round-0 draft said *"any fix here MUST use
  the gated pair"*. That is true for FOB-7(b) (which reads hold DATES) and
  **false as an absolute** for FOB-7(a) — see "Design decisions" below. The
  established precedent at `:1032` excludes `is_hold` ungated.

### FOB-7(a) — `currentPhaseCompletionRate()` (`:1129-1153`)
```dart
final phase = (progress?['current_phase'] as int?) ?? 1;
final int totalWeeks;
if (phase <= 1) { totalWeeks = 4; }
else { var scanned = 4; for (int w = 5; w <= 12; w++) { if (getWeek(w).isEmpty) break; scanned = w; } totalWeeks = scanned; }
final days = <({bool isRest, bool isDone})>[];
for (int w = 1; w <= totalWeeks; w++) { for (final day in getWeek(w)) { ... days.add(...); } }
return phaseCompletionRate(days);
```
`getWeek(w)` (`:1063-1079`) resolves 7 dates from `plan_start + (w-1)*7` and
returns whatever `getScheduleForDate` yields — it is **purely date-driven** and
knows nothing about `is_hold`.

**Currently INERT** (so the fix is safe to land, but must land before the flag
flips). Both readers short-circuit on
`PlanEngineFlags.adherenceGateEnabled` (`enable_adherence_gate`, ship-dark,
default OFF):
- `graduation_screen.dart:376-380`
- `pro_phase_advance.dart:167-169`

### ✅ SETTLED — FOB-7(a) IS reachable (was the round-0 OPEN QUESTION)

**Resolved by execution, not analysis — see "Reachability" below. Outcome 1.**
The round-0 reasoning that follows is kept because round 1 showed WHY it failed,
and the two wrong citations in it are the ones the board still carries. Struck
through in substance, retained as the record:

- Holds start at `plan_start + 28`, i.e. week 5+ **by date**.
- For `phase <= 1`, `totalWeeks = 4`, so the accumulator covers
  `plan_start .. +27` only — **hold rows are outside it**. No folding.
- For `phase >= 2` the scan reaches `getWeek(5..12)`, which by date is exactly
  where hold rows live — so folding requires hold rows still inside the window
  **after** the phase advanced.
- But OI-127 R3 establishes that the PRO advance sets
  `plan_start = _normalizeToMonday(max(plan_end + 1, today))` — real location
  **`:1577`**, NOT the `:1446-1458` this draft inherited from the board (that
  range is `pastPhaseBlocks()` legacy bucketing). The strict `isBefore` filter is
  at **`:833`**, NOT `:803` (which is prose). **Both citations verified by me
  directly.** The substance is right and the PRO-advance path IS safe — but it
  is safe by date arithmetic, and `currentPhaseCompletionRate()` never consults
  the `:833` filter at all, so this argument never covered the case that matters.

**If that holds, the phase≥2 branch cannot see hold rows and FOB-7(a) as filed
is not reachable.** Reviewers: verify or refute this against the code. Three
candidate outcomes, and the fix differs for each:

1. ✅ **THIS ONE — a real path exists.** ⚠ but NOT via the mechanism this draft
   named: `generateAndScheduleFromDate` never writes `current_phase`, so it
   cannot reach the `phase >= 2` branch (round 1 BLOCKING #1). The real writers
   are `phase_progress_reconciler.dart:138` and the restore path
   `sync/sync_profile.dart:628`, neither of which moves `plan_start` in the same
   call — and diagnose `c9e4b7` records a REAL production account in exactly that
   state. Fix: exclude hold rows from `days` AND from the `scanned` denominator.
2. **Confirmed unreachable today, but only by an invariant nothing pins.**
   → The fix is a regression test that pins the invariant, plus the exclusion as
   defence in depth. Say so in the closure YAML rather than claiming a bug fix.
3. **Confirmed unreachable and already pinned.** → `verified_clean`, no code.

Do not let me merge outcome 1's fix on outcome 2's evidence.

### FOB-7(b) — the reconciler never heals a hold week
`plan_integrity_reconciler.dart`:
- `:130-133` builds the symptom set from `getWeek(1..4)` **only**.
- `:135-137` `needsHeal(local)` (`:94-105`) decides whether to fetch cloud at all.
- `:167-176` re-anchors `plan_start` / `plan_end` from `PlanWindowReanchor.resolve`.
- `:180-187` merges `bundle['schedules']` — **the whole bundle, not scoped to
  weeks 1-4**.

So the WRITE half already covers hold weeks; only the TRIGGER is narrow. A hold
week with stripped exercises never fires `needsHeal`, so nothing heals — on the
only week a free user is training.

**Widening the 1..4 scan is REFUTED** — `oi60-streak-identity.closure.yaml`,
P0-11 concern `d7f3a9`: that scan IS also the re-anchor trigger, so widening it
buys no healing and only makes the re-anchor fire more often. Do not re-propose.

**Proposed shape:** two predicates over one fetch. Let hold-week symptoms trigger
the **schedule heal** while leaving the **re-anchor** on its existing weeks-1-4
condition. Concretely: keep `needsHeal(weeks 1..4)` as the re-anchor gate, add a
separate hold-symptom check (built from `activeHoldWeeks()` dates) that can
trigger the fetch + merge without authorising the `plan_start`/`plan_end` write.

### OI-127 — unguarded re-anchor movers
`plan_integrity_reconciler.dart:175` writes `reStart` with no
`existingStart == null` guard; `sync/sync_workout.dart:1126` is the same shape.

⚠ `open_issues.md:3382-3400` records that this got **three different answers in
three rounds**; R1 was right by the wrong mechanism, R2 misattributed
`train_provider.dart:567` (it is inside `_autoGeneratePlan`, not the PRO
advance), R3 confirmed R1. Read that entry before re-analysing. The open part is
only the two unguarded movers. ⚠ The round-0 draft also cited
`_autoGeneratePlan`'s "first-generation branch (`:345-350`)" — round 1 found that
range is unrelated exercise-category code and `_autoGeneratePlan` starts at
`train_provider.dart:638`. Another citation inherited from the board unchecked;
dropped from this plan.

## Test obligations

- **FOB-7(a)**: the behavioral test MUST force `enable_adherence_gate` ON. With
  it OFF the readers short-circuit and the test proves nothing — the exact trap
  FOB-3's keep-set test fell into (`open_issues.md:1105-1109`: dropping `'hold'`
  from the keep set left every test green because two bloat fields absorbed the
  overage first). Mutation: restore hold rows to the accumulator; confirm red.
- **FOB-7(b)**: assert BOTH halves — the heal fires for a hold week, AND
  `plan_start`/`plan_end` did **not** move. The separation is the entire fix, so
  a test that only checks healing would pass on the refuted design too.
- ⚠ **OI-127**: ~~a re-anchor with `existingStart == null` must not write~~ —
  **REFUTED by round 1 (BLOCKING #3); this obligation is WITHDRAWN.** That is the
  documented fresh-install path (`plan_window_reanchor.dart:46-56`) and pinning
  it would break every new device's `plan_start` seed. See the re-scope below.
- Flag-OFF group: byte-identical behaviour with `enable_hold_weeks` OFF.

## Round 1 — 3 BLOCKING, 3 MAJOR, 3 MINOR. All BLOCKING accepted.

**BLOCKING #1 — my Outcome-1 evidence was a non-sequitur. ACCEPTED.**
`generateAndScheduleFromDate` never writes `current_phase` at all, so it leaves
`current_phase == 1` and routes to the `phase <= 1` branch — it cannot reach the
`phase >= 2` code the OPEN QUESTION was about. None of my three candidate
outcomes was supported by a chain reaching the right path.

**BLOCKING #2 — two load-bearing citations wrong, inherited from the board.
ACCEPTED, both re-verified by me directly:**
- `nextPhaseStartDate()` is at **`:1615` in this worktree** (`:1577` in `main` —
  this batch adds 38 lines above it), not `:1446-1458` (that range is
  `pastPhaseBlocks()` legacy bucketing — confirmed by reading it). Round 2
  caught the round-1 correction citing the pre-merge line; see MAJOR #1.
- The strict `isBefore(windowStart)` filter is at **`:833`**, not `:803`
  (`:801-805` is prose — confirmed).
Both errors trace verbatim to `open_issues.md:3404-3407`, R3's text, which is
labelled *"confirmed by direct read"*. **The board itself is wrong here**, and
the label is what made it look settled. Corrected on the board in this batch.

**BLOCKING #3 — my OI-127 fix was REFUTED, and would have been a P0. ACCEPTED.**
I proposed guarding the re-anchor with `existingStart == null`. Verified myself
at `plan_window_reanchor.dart:46-56`: `samePhase = localStart != null && …`, and
`if (!samePhase) return PlanWindowReanchor(cloudStart, cloudEnd)`. So
`localStart == null` is the **documented fresh-install path that seeds a new
device's `plan_start` at all**. My "guard" would have broken every fresh install
and first restore. Dropped entirely — see the re-scope below.

**MAJOR #4 — the function carries an explicit "deliberately does NOT touch"
note naming 11 downstream consumers. ACCEPTED as a real constraint**, and
handled by scope: the change is confined to `currentPhaseCompletionRate`'s own
two loops and does not alter `getWeek`, so the other consumers read exactly what
they read before. Recorded in the code comment as a deliberate revision.

**MAJOR #5 — `_autoGeneratePlan:345-350` citation points at unrelated code.
ACCEPTED** (also inherited from the OI-127 board entry). Dropped from this plan.

**MAJOR #6 — §4.1.5 bug-history miss. ACCEPTED, and it turned out to be the
key.** I never cited
`docs/diagnoses/2026-08-09-past-phase-display-and-expired-copy-c9e4b7.md`, which
records a REAL production account with `current_phase=2`, `plan_start` unmoved,
77 rows over ~13 weeks — and states the writer responsible is unconfirmed and
NOT FIXED. That is the precondition FOB-7(a) needs.

**MINORs #7–#9 — accepted; #8 and #9 confirmed my design for FOB-7(b).**

## Reachability: SETTLED BY EXECUTION

Round 1 recommended settling this with a seeded test rather than a fourth round
of analysis. Done, and it is decisive:

```
PROBE getWeek(5)=7 getWeek(6)=7 getWeek(7)=0
PROBE w5 first row is_hold=true
PROBE currentPhaseCompletionRate() = 0.6666666666666666
```

With **all 28 real days completed**, the rate read **0.667 instead of 1.0**. So
**Outcome 1: a real path exists.** `shouldOfferAdvanceChoice` would read a
perfect record as low adherence and offer the "detrained / repeat the phase"
path — to the free user who chose to stay rather than churn.

Four rounds of prose produced four answers; one seeded run produced the answer.

## Design decisions taken, for round 2 to challenge

1. **FOB-7(a)'s hold filter is UNGATED on `enable_hold_weeks`** — a deliberate
   departure from this plan's round-0 text, which insisted on the gated seam.
   Reason: `completedWeekNumbers` (`:1032`) already excludes
   `row['is_hold'] == true` with **no flag check**, and the two are the non-hold
   day-sources for closely-related ratios; drift between them is the exact
   writer/reader class. Gating would also leave the rate wrong for the one
   population that can hold rows while the flag reads OFF (held once, flag later
   turned off) — buying a byte-identical path with a known-wrong number. Rows
   only exist if `holdWeek()` ever ran, so for every user who never held the
   filter is a no-op and behaviour IS byte-identical. **Round 2: challenge this.**
2. **FOB-7(b) returns a RECORD, not a bool** — `computeTriggers` yields
   `(shouldFetch, mayReanchor)`. A bool would force the caller to re-derive the
   second decision, which is the guard-without-its-mirror class (#15: three
   passes fixed a guard and the caller kept discarding the binding).
3. **The card is NOT filtered.** `train_provider.dart:767-777` keeps counting
   hold weeks. What the Train screen renders during a hold is FOB-6 → **OI-125**,
   split out by founder as a feature that does not gate the flip. Filtering the
   card here would ship half of OI-125 by accident. The "mirrors the card
   exactly" comment is updated to say the mirror is now deliberately imperfect.

## OI-127 — RE-SCOPED after BLOCKING #3

The `existingStart == null` guard is refuted and abandoned. What this batch
actually does for OI-127:
- **Declines to widen the exposure** (corrected from "narrows" — round 2 MAJOR
  #2 proved the reachability condition is IDENTICAL, not smaller): the re-anchor
  at `:239` fires only on `triggers.mayReanchor`, which reduces to exactly the
  pre-batch `needsHeal(local)`. Adding a second trigger did not give the window
  write a new way to fire.
- **Corrects the board's wrong citations** (BLOCKING #2), so the next session
  does not re-derive from bad line numbers a fourth time.
- Leaves the open question — whether `plan_start` moving mid-hold breaks streak
  identity — OPEN, with the refutation recorded so the wrong fix is not
  re-attempted. It is NOT closed by this batch and is not claimed to be.

## Evidence

| unit | tests | mutation |
|---|---|---|
| FOB-7(a) | 6, all green | restore the two unfiltered `getWeek(w)` calls → **4 red**, 2 green (deliberate no-op controls) |
| FOB-7(b) | 8, all green | re-implement the REFUTED widened design → **1 red**, the one test built to catch it |

## Round 2

_(runs on THIS hardened plan — §4.12.1: corrections introduce defects)_

## Round 2 — 3 MAJOR, 1 MINOR, no BLOCKING. All accepted and fixed.

Round 2 reviewed the hardened plan AND the written implementation.

**MAJOR #1 — the corrected citation `:1577` was wrong. ACCEPTED, with a
correction to the correction.** Round 2 read `:1577` and found unrelated code.
Both of us were right about different trees: `nextPhaseStartDate` is at **`:1577`
in `main`** and at **`:1615` in this worktree**, because this batch's own edits
add 38 lines above it. My round-1 verification was honest but I cited the
pre-merge location in a document that will be read post-merge. Now cited as
`:1615` with the shift recorded, so the next reader is not sent to the wrong
line by either number.

**MAJOR #2 — "narrows OI-127's exposure" was FALSE. ACCEPTED, claim struck.**
Verified by reading both versions: OLD reachability for the two writes was
`needsHeal(local)`; NEW is `shouldFetch && mayReanchor`, and since
`shouldFetch = window || needsHeal(holdRows) ⊇ window` and `mayReanchor = window`,
that reduces to exactly `window == needsHeal(local)`. **Identical, not narrower.**
The honest claim is that this batch DECLINES TO WIDEN OI-127's exposure. Reworded
in the code comment and here. OI-127 stays fully OPEN and this batch does not
advance it beyond correcting the board's citations.

**MAJOR #3 — I reintroduced a pattern that was already rejected BY NAME. ACCEPTED
— a real bug.** `HoldWeekInfo.weekStart` is `byOrdinal[ordinal]!.first`
(`workout_schedule_read_service.dart:870`), the first SURVIVING hold date. A hold
week missing its Monday row yields a TUESDAY, so a 0..6 walk reads
`[Tue..Sun, next Monday]`. All three pieces of prior art predate this batch:
`train_provider.dart:577-579` ("Never `HoldWeekInfo.weekStart` either"),
`oi60-streak-identity.closure.yaml:51` (listed among REJECTED designs), and
`hold_week_streak_identity_behavioral_test.dart` (carries the reproduction).
**That is a second §4.1.5 bug-history miss in one batch** — a grep for
`HoldWeekInfo` or `weekStart` across `docs/` and `test/` would have found all
three. Fixed with `normalizeToMonday()`.

**Why it got past two rounds of tests:** the loop was INLINE in `reconcile()`,
which needs a live Supabase client, so no test could reach it. Extracted as
`gatherHoldRows()` (`@visibleForTesting`) — the extraction IS the durable fix;
the anchoring is just the bug. A loop no test can reach is a loop no test
protects.

**MINOR — the filtered `scanned` loop could UNDERCOUNT. ACCEPTED and FIXED, not
merely acknowledged.** Round 2 constructed it: weeks 5-6 fully hold, real phase-2
content at week 7+. `_withoutHoldRows(getWeek(5))` is empty → `break` at w=5 →
`totalWeeks=4` → weeks 7+ silently dropped from BOTH numerator and denominator.
The scan is reverted to the RAW week; only the accumulator filters. That loop
answers *"how far does the schedule extend"*, which hold rows legitimately
answer — holds must not COUNT, but they do EXTEND. Regression test added.

## ⚠ My first fix for MAJOR #3 shipped a VACUOUS test. Caught by mutation, not review.

The first missing-Monday test passed — and **still passed with the rejected
pattern restored.** It proved nothing.

Why: with ONE hold, the spill target (`hold1Monday + 7`) has no row at all, so
`getScheduleForDate` returns null for the correct walk and the rejected one
alike. Both read the identical six rows. The test's input set could not contain
the symptom, so it reported "no bug" in the same colour as "no bug found" —
[[feedback_green_check_input_set_width]] and [[feedback_bad_news_vs_no_news]],
inside the very test written to close a repeat offence.

Rebuilt with TWO holds plus a deleted hold-1 Monday, so hold 2 supplies a REAL
row at the spill target. Now the rejected pattern gathers hold 2's Monday twice
(14 rows, one duplicated) and the test reddens. **Only the mutation run revealed
this — no reviewer did.**

## Evidence — every claim re-measured after the round-2 fixes

| unit | tests | mutation performed | result |
|---|---|---|---|
| FOB-7(a) hold exclusion | 7 | restore the unfiltered `getWeek(w)` accumulator | **5 red**, 2 green (no-op controls) |
| FOB-7(a) undercount | (same file) | re-apply the filtered `scanned` loop | **1 red** — the round-2 regression test |
| FOB-7(b) trigger split | 8 | re-implement the REFUTED widened design | **1 red** — the test built for it |
| FOB-7(b) row gathering | 3 | restore `h.weekStart` (the rejected pattern) | **1 red** — after the rebuild; 0 red before it |

`flutter analyze` clean on all five changed files. The two
`depend_on_referenced_packages` infos are pre-existing repo pattern — the
already-merged `hold_week_identity_behavioral_test.dart` emits the same two.

## B-pass (§4.3) — 4 findings, 0 P0, all accepted and fixed

Run against commit `2e9503eb` before the merge, self-initiated. Every finding was
re-verified by me against the files before acting; all four held.

**P1 — my own records claimed, in the PAST TENSE, something I had not done.**
This record and the closure YAML both said the three wrong OI-127 citations were
"corrected on the board in this batch". They were corrected in THIS DOCUMENT and
nowhere else — `git log bdbeb1a2..HEAD -- docs/audit/open_issues.md` returned
**zero commits**, and `sed -n '3404,3410p'` still showed `:1446-1458`, `:803` and
`:345-350` verbatim. So the batch that exists partly to stop the board sending the
next session to wrong line numbers was about to merge leaving all three in place,
while asserting it had fixed them. Now actually fixed on the board, with the
correction stamped inline so a fifth round can see what changed and why.

**P2 — `docs/sot_registry.yaml` still described the OLD behaviour.** Two entries:
`hold_display_read_path` said `currentPhaseCompletionRate (still clamped)`, and
`phase_adherence_rate`'s writer notes said `totalWeeks MIRRORS the card EXACTLY`.
Both are false after this change, and `lib/CLAUDE.md` requires the registry be
updated in the SAME commit as the writer. The code comment already said the mirror
is deliberately imperfect; the registry contradicted it. Both corrected.

**P2 — the diagnose `bug_id` COLLIDED.** `d3b8f1` already named
`2026-08-15-cleanup-delete-boundary-keyed-on-uuid-d3b8f1.md` (landed `acffbd43`),
so `closes-diagnose: d3b8f1` was ambiguous between two unrelated bugs. Renamed to
`b9d4c2`. **Nothing detects this class**: `validate_diagnose_doc.dart` takes one
path and never scans the corpus, and there is no diagnose-id sibling to
`check_oi_numbering_unique.dart` — which exists because the OI-number version of
this exact bug shipped six times. Filed as **OI-140**.

**P2 — my mutation count was wrong: 5 red / 2 green, not 4 / 3.** The reviewer
re-ran it; so did I, confirming. The uncounted fifth is "a hold-only week extends
the scan but contributes NO days", which is not a no-op under that mutation. The
cause is mundane and worth naming: I measured 4-of-6 when the file had SIX tests,
then added the round-2 regression test and **never re-measured**, copying the stale
number into two documents. The protection is stronger than I claimed, not weaker —
but rule 24 treats mutation counts as load-bearing evidence, so a stale one
undermines every other count in the same table.

**The pattern across all four:** none is a defect in the CODE. All four are defects
in the EVIDENCE — a past-tense claim for work not done, two docs describing
superseded behaviour, an id collision, and a stale measurement. The ×2 plan review
read the design and found design defects; the B-pass read the artifacts and found
that the artifacts lied. Both were needed.

**Clean lenses:** the reviewer independently re-ran all four mutations (three
matched exactly), traced `computeTriggers`'s record to its call site and confirmed
both bindings are read distinctly rather than collapsed, and ran a 121-test
regression sweep across the new files plus every neighbouring hold/reanchor/restore
suite — all green.
