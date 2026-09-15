---
branch: deps-board-equipment
date: 2026-08-06
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
tier: full
diagnose: docs/diagnoses/2026-08-06-equipment-exclusions-collected-then-ignored-e2d6b8.md
closure: docs/audit/deps-board-equipment.closure.yaml
bpass_review: docs/reviews/deps-board-equipment-bpass.md
---

# Plan review — deps-board-equipment

Two commits: the `enable_equipment_exclusions` flip-on (diagnose `e2d6b8`) and the
supabase_flutter 2.12.4 → 2.17.1 bump (Dependabot #16 / OI-57).

**`review_rounds: 2` and `tier: full` are load-bearing.** §4.12.4's lighter
`ship_dark_build` tier explicitly does NOT apply here: this is the commit that flips a
flag's default, which is the moment real user risk starts. The full ×2 plus
`bpass: accepted` is required, and that is what ran.

## What was reviewed, and by whom

| Round | Reviewers | Findings |
|---|---|---|
| 1 | 2 independent context-blind (correctness/test-integrity; dependency/docs-truth) | 11 |
| 2 | 1 independent context-blind, on the **hardened** diff | 4 new |
| B-pass | 1 fresh 5-lens adversarial | 2, both already caught by round 2 |

All 15 carry a terminal state in the closure ledger. Every finding was re-verified by
the author against the actual files before being acted on — **two were REFUTED on that
re-check** (R9, R10) and are recorded as `verified_clean` with the evidence, because
acting on a wrong finding is the same defect class as missing a right one.

## The three findings that changed the code

**R3 — the round-1 warmup fix was circular.** The first attempt derived the wrist-tagged
move set from the same `WarmupCooldownSelector.moveInjuries` map the filter reads, making
both new assertions tautological while a comment claimed the opposite. Mutation-proven:
stripping `'wrist'` from `warmup_cooldown.dart:43` left all 7 tests passing. Replaced with
a hardcoded `{'Jump Rope'}` plus an independent pin on the map value; the same mutation
now fails. Round 2 re-ran the mutation and confirmed, and separately audited all six
`_kneeMoves` against `_moveInjuries` to confirm Jump Rope is the only wrist-tagged one.

**R4 — the batch's central claim was untested end-to-end.** The flip test passes
`exclusions:` as an explicit param, which short-circuits before the profile read
(`training_history_analyzer.dart:174-176`). "Profile read × DEFAULT config" — the only
combination a real device runs — had no coverage. Added, self-discriminating via a
kill-switch negative control.

**R12 — the kill-switch is reachable only in DEBUG builds, and R5 claimed otherwise.**
Round 1 found the kill-switch had no writer at all; the fix wired a dev-panel toggle.
Round 2 and the B-pass **independently** established that `app_router.dart:336` registers
`/dev` behind `if (kDebugMode)` (and the screen double-guards with a `kReleaseMode` early
return), so the control is compiled out of every shipped APK.

## Honest statement of what this ships with

- **Production revert of this flip still costs a code change plus an APK respin.** §4.6's
  "old path preserved verbatim, reachable when gate closed" is satisfied in the repo and
  **not on the device**. This is architectural — no RemoteConfig exists
  (`sync_service.dart:254`) — and applies to `enable_hold_weeks` and all twelve remaining
  OI-53 flags equally. Filed as **OI-95**; not fixed here because the right fix needs a
  product decision (an `/admin`-gated operator screen vs real remote config) and `/admin`'s
  own reachability is unconfirmed (OI-54). Exposing a plan-engine kill-switch on a
  user-facing screen would be worse than the gap.
- **Accepted risk, stated as a judgement not a fact:** the failure mode here is degraded
  plan *content*, not a crash or data loss, so respin latency is tolerable. That reasoning
  would NOT hold for a flag guarding auth, payment or sync.
- **The wider half of the blast radius is not the exclusion filter.** Flipping this one flag
  also activates ⑥ C2's WU-2 gym-cardio gate (`plan_generator.dart:298-308`), whose
  fallback predicate was always-false on the generated path per diagnose `b7a4e2`. Treadmill
  /Bike warmup and finisher pools now reach **every gym-tier user, including those who set
  no exclusions at all**. That is b7a4e2's fix finally landing after being inert since
  2026-07-17 — intended, but visible, and it is the reason this flip is not "inert for
  anyone who ignores the feature".
- **This does NOT clear the ship-dark ledger entry.** `flip_reviewed` stays `false` and
  `flip_commit` stays `null` until the flip is verified on a device. The ledger's own schema
  requires that (`ship_dark_pending_review.yaml:24-25`).
- **gotrue 2.26.0 is flagged BREAKING** ("handle already-consented OAuth authorization
  responses", #1536) and the first risk audit missed it by reading the changelog only to
  2.25.0. Re-checked: it is the only breaking release in the shipped range, it sits on the
  OAuth *server* surface, this app's only OAuth call is client `signInWithOAuth`
  (`auth_provider.dart:326`), and the tree compiles clean. Low risk, but **behavioural**,
  so live Google sign-in is a required device/web check.

## Ground truth verified

- Blast radius `platform` via `blast_radius_from_diff.dart` — matches `docs/blast_radius.yaml`
  for both `lib/shared/repositories/plan_engine/**` and `pubspec.*`.
- Every dependency version re-derived from `pubspec.lock`, not the PR changelog (the first
  commit message took them from the changelog and understated four of five).
- `flutter analyze`: 0 errors, 0 warnings, 240 infos — confirmed independently by the B-pass.
- Full suite green (4217 passed, 3 skipped) before the round-2 fixes; the three affected
  files re-run green after.
- Both regression tests proven by MUTATION, not assumed.

## Still owed before this is verified, not just reviewed

APK `1.0.0+38` — on-device *and* live-web. Specifically: live Google sign-in (gotrue
breaking change), both password-reset link shapes (`b7d4e2`'s standing instruction after any
SDK upgrade), and setting an equipment exclusion in Edit Profile then regenerating a plan to
confirm the excluded item is absent. Held at the founder's request; the flip is merged-ready
but not device-verified, and the ledger reflects that.
