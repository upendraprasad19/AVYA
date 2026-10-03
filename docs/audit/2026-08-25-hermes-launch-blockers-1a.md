---
batch: launch-blockers-1a
reviewed_at: 2026-08-25T10:05:00+05:30
reviewed_target: d45d7182 (the SUPERSET — see scope note)
blast_radius: catastrophic
lens_set: [L1, L11, L15, L37, L39]
agents_dispatched: 5
model: opus
findings_count: 17
verdict: accepted
---

# Hermes pass — launch-blockers-1a (catastrophic)

Five parallel Opus lens agents, context-blind, per `.claude/skills/hermes-pass/SKILL.md`.
Lens set is the registry's **sync/restore** recommendation (L1, L11, L15, L16/L37, L39), chosen
because the batch's real risk surface was sync/restore; the payment-path change that sets the
catastrophic tier is comment-only.

## ⚠ SCOPE — read this before trusting the verdict

**The pass ran against `d45d7182`, the SUPERSET, not against the diff that shipped.** That is the
whole point of it: it found **two P0s that broke both of that batch's headline fixes**, and per
§4.12.1 the unit was SPLIT. What shipped as `launch-blockers-1a` is the converged remainder; the
plan-engine (OI-89) and sync/restore (OI-98) work was removed to `launch-blockers-1` and is NOT in
the shipped diff.

So `verdict: accepted` means precisely: **every finding this pass raised against content that
remains in `launch-blockers-1a` is fixed, and every finding against removed content went with the
removed content.** No Hermes finding against the shipped code is outstanding. It does NOT mean the
pass re-ran against the final diff — it did not. The shipped diff got its own B-pass
(`docs/reviews/a51a2ba9de14-review.md`, 6 findings, all accepted).

## The two P0s — both against removed content

**P0-1 (L1, L37) — the OI-89 hard floor keys on a field the SoT registry declares unsafe for it.**
`docs/sot_registry.yaml` (`exercise_equipment_tier`): *"Invariant: derive ⊆ equipment_tier (no
under-tag); **over-tags tolerated**"*, and it names `queryV4` the *"sole production reader"*. Four
bundled rows are tiered `bodyweight` while `equipment_needed` names real kit — `Standing Calf
Raise` (barbell), `Chin Up` (pull-up bar), `Reverse Crunch`/`Decline Push Up` (bench). Driving the
real `pickV4` produced **6 leaks across 3 patterns**. `Chin Up` is one of the three exercises OI-89
literally reported, and it reached `elbow_flexion` via `universalPoolV4`, passing the batch's brand
new attempt-5 skip.

**P0-2 (L11, L39) — the OI-98 restore leg reads the row its own device overwrites first.**
`splash_screen.dart:189` fires `pushSnapshot()` **14 lines before** `checkAndSync()`, through a
leading-edge coalescer, so it runs immediately. With an empty local blob `emissionMap()` emits all
10 keys enabled; `daily-snapshot` upserts `snapshot_json` wholesale on `(user_id, snapshot_date)`;
the leg then selects the newest row — the poisoned one. Once adopted, local is full and the leg
no-ops forever. Confirmed against live prod: **126 snapshot rows, 14 carry prefs, every one 10 keys
with `off_count = 0`.**

## Findings by lens (17 total)

| Lens | P0 | P1 | P2 | P3 | Disposition |
|---|---|---|---|---|---|
| L1 writer/reader drift | 1 | 3 | 2 | 1 | 1 shipped-content finding fixed (telemetry collapse); rest removed with OI-89/98 |
| L11 restore-completeness | 1 | 2 | 2 | 2 | all against removed content |
| L15 cross-account ownership | 0 | 3 | 3 | 2 | all against removed content |
| L37 null-shape readers | 1 | 1 | 4 | 2 | 3 shipped-content findings fixed (render site, consent asymmetry, drain docstring); rest removed |
| L39 restore round-trip | 1 | 2 | 3 | 2 | all against removed content |

Counts overlap across lenses — several findings were reached independently by two or three agents,
which is itself signal: the P0s were not marginal.

### Findings against SHIPPED content — all fixed

1. **Paywall telemetry collapse (L1, P2).** Routing all three surfaces through one `'PRO'` sentinel
   merged the Profile chip's funnel segment into the generic bucket — the exact preservation the
   batch's own diagnose-doc promised. Fixed with a distinct `genericUpgradeProfile` sentinel, with
   the predicate derived from the constants rather than a re-typed literal.
2. **Render site unpinned (L37, P2).** Reverting `title: _featureTitle` restored the tautology on
   every payment surface with all tests green. Pinned and mutation-proven.
3. **Google-OAuth consent asymmetry (L37, P2 → escalated P1 by the split B-pass).** Recorded as a
   founder decision row rather than patched — see below.
4. **Drain-guard docstring overclaimed (L37, P3).** Said it "closes the mechanism"; it closes the
   setUp-contamination window while the unawaited write remains. Corrected.

### Accepted open risks — recorded, not silently carried

- **Bodyweight-plan defect** — `GO_LIVE_CHECKLIST.md` §6, plus the full rebuild spec at
  `docs/plans/oi89-oi98-rebuild-spec.md` on the held branch.
- **Google OAuth has no consent gate** — `GO_LIVE_CHECKLIST.md` founder row 3.5, and a pitfalls row
  in `lib/features/auth/CLAUDE.md`. Fixing it means deciding where consent sits in a redirect flow,
  which is a UX decision.

## Methodology note worth keeping

The B-pass had already run lens 6 on the bodyweight guard, mutated **both** guard sites, watched 5
tests redden, and passed it. All of that was true and all of it was beside the point: the test's
oracle read the same `equipment_tier` field as the code under test. **Mutating a guard cannot
detect an oracle derived from the same expression as the guard.** That sub-shape is now recorded in
the code-review skill's tuning history and in `feedback_mistake_guard_without_its_mirror.md`
(instance #16).

## Founder triage

`verdict: accepted` under the scope stated above. The pass's most valuable output is not a fix —
it is the split decision and the rebuild spec it justified.
