# FOB-1 — hold-week identity (OI-60 blocker 1 of 5) · 2026-08-20

Branch `claude/oi-pending-hold-weeks-1od97o` · commit `4f5e510` · diagnose `f4c8e1`
Closure `docs/audit/fob1-week-identity.closure.yaml` (11/11 terminal) · B-pass accepted.

## How this batch started

The founder asked two things: what is pending on them, and why the hold-week
display fix they remembered making was invisible in the webapp. The second
answer set the work: the fix IS on main; `enable_hold_weeks` is default OFF, and
`/dev` — the only in-app writer of that flag — is `kDebugMode`-gated, so
`vercel_build.sh`'s `--release` build compiles it out of app.icanbefitter.com
(that gap is OI-95). Not a bug. They then chose to start clearing OI-60's flip
blockers, and FOB-1 was picked because it is the ONLY remaining blocker
completable end to end without a live-prod action.

## What was actually wrong

`getCurrentWeekNumber()` ends in `.clamp(1, 4)`; a hold starts at
`plan_start + 28`. So it returns **4 for every hold at every ordinal, forever**.
The Train tab had already adopted the opposite rule (`c8b3f2` D1: drop the
counter, the `HOLDING · Hn` pill carries the identity). Nothing else had — so
the app contradicted itself depending on which tab you were on.

## Three things worth carrying forward

**1. The filing understated the work, in a direction greps cannot find.**
Two of the six surfaces were not what the FOB list said. `phase_roadmap_screen`
does not call the clamp — it calls `getProgramWeek`, which is
`programWeekFor(phase, getCurrentWeekNumber())`, so the clamp is one level down
and a grep for it misses the file. Its own comment claimed it had been "moved
off `getCurrentWeekNumber`"; it had been moved off the *direct call* only.
`profile_content.dart` was named only through its provider. **Enumerate a
helper's CONSUMERS, not just the literal's call sites.**

**2. Mutation-proving a SEAM does not mutation-prove its SURFACES.**
This batch shipped two mutation proofs on the service seam and cited both in the
commit message. The B-pass then inverted a ternary in `profile_content.dart` — a
real defect printing "Holding · Hnull" to every non-holding user — and **all 16
tests still passed**, because the only surface coverage was
`body.contains('stats.isHolding')` against raw source. A source grep over a
widget is presence, not behaviour. Fix: extract the label ternaries to pure
functions (`lib/core/utils/hold_week_labels.dart`) and assert the exact string
on both arms. The same inversion now reddens 4.

**3. A correct value is worthless if its consumer cannot see it change.**
The B-pass P1: `UserStatsNotifier.build()` read the identity via a plain
singleton call, so `userStatsProvider` had no dependency-graph edge to the hold
write. Tabs live under `StatefulShellRoute.indexedStack` and do not remount on
switch, so Profile would have kept showing `WEEK 4 OF 4` while Home showed
`HOLDING · H1` — the batch would have *reintroduced* the contradiction it
existed to close, on two of its own six surfaces. **In a `build()`, `ref.watch`
the provider; never call the singleton.**

## Process notes

- **`--no-verify` was used ONCE, with explicit founder approval in chat**, for a
  single documented gap: `pre-push.sh` runs a bare `flutter test` — no `TZ`, no
  `--exclude-tags golden` — while CI sets both. Two Windows-only golden tests
  cannot pass on a Linux runner (`dart_test.yaml` documents this). Everything
  else pre-push would run was run and was green.
- **A misreport worth remembering:** the first full-suite run showed 5 failures
  and was reported as though `main` were red. Four were the harness, not the
  repo — proven by re-running them at clean `HEAD` in a throwaway worktree.
  Exactly one was mine. **Reproduce against a clean baseline before calling a
  suite red.**
- The 7 `sot_registry` line citations this batch broke were all ACCURATE at HEAD
  (verified, not assumed) — the insertions shifted them. Gate 34 caught it.

## Still open on OI-60

FOB-3, FOB-4 (coach snapshot + Sunday push/weekly report — **3 EF redeploys**),
FOB-5 (hold telemetry + the `channel = 'app'` metric fix — **migration apply**),
FOB-7(a)/(b) + OI-127 (completion-rate + reconciler; read the closure YAML first
— widening the 1..4 scan is already REFUTED, the shape is *split the trigger
from the write*). OI-125 is a feature, explicitly not a flip blocker.
The flip-on commit needs its own full ×2 and must clear all three
`enable_hold_weeks` ledger rows at once.
