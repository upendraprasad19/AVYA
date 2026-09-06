---
branch: oi162-slice3-lifetime-meters
date: 2026-09-06
blast_radius: platform
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: pending
---

# Plan-review record — OI-162 slice 3a, the weekly-report lifetime meter (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart
supabase/functions/weekly-report/index.ts scripts/usage_counter_source_lib.dart
docs/sot_registry.yaml` → `platform`. ⚠ Getting that number took three wrong readings: piping a
path into that script WITHOUT a trailing `-` silently classifies the STAGED set instead, and
returns `feature` for everything — including `verify-payment`, which the registry pins
`catastrophic`. Use args mode, and sanity-check against a path whose tier you already know.

## Rounds

| Round | Findings |
|---|---|
| 1 | 1 BLOCKING, 3 major, 4 minor |
| 2 | 1 BLOCKING (new), 4 major, 2 minor → **SPLIT under §4.12.1** |
| 3 | 1 BLOCKING, 5 major, 3 minor |
| 4 | 0 blocking, 2 major, 3 minor |
| 5 | 0 blocking, 2 major, 1 moderate, 1 minor |
| 6 | 0 blocking, 1 major, 1 moderate |
| 7 | **0 blocking, 0 major** — 1 moderate, 2 minor, all fixed → **CONVERGED** |

Every finding carries a written disposition in `docs/audit/oi162-slice3-plan.md` §8/§10/§11/§12.

**The split is the reason this converged.** Round 2's repeated new-material signal is exactly
what §4.12.1 describes, and slice 2 had just cost six rounds by my not heeding it. Splitting
`ai-media-proxy` out as 3b left one Edge Function with one read and one write; rounds 4-7 then
found progressively smaller things in it. Rounds 1-3 were finding design defects in a unit
covering two functions with different shapes.

## What the review actually bought

Ranked by what would have shipped without it:

1. **A total free-tier lockout.** Round 6. The redesign turns a `count: "exact"` read (2 outcomes)
   into a value-select (3: row / error / **absent**). My round-3 remediation had hardened "an
   unreadable counter refuses" — written for the error branch, and it swallows the absent branch.
   `usage_counters` holds zero rows for this key, so **every** first-time free user would have
   been refused permanently. The file offers both `.single()` (throws on zero rows) and
   `.maybeSingle()` precedents, so picking wrong was plausible rather than hypothetical.
   ⚠ **My own fix created this.** Recorded as instance #24 of the guard-without-its-mirror class,
   which now carries the new lesson: a guard's mirror can be created by the guard's own
   remediation, so when a fix changes a read's SHAPE, re-enumerate the outcome states.
2. **Data loss.** Round 1. v1 said `consume_quota` "replaces the insert-as-quota-unit". Taken
   literally that deletes the insert — and `sync_coach.dart:178-181` restores with NO channel
   filter, while `reports_screen.dart:47` caches only ONE latest report, so that row is the sole
   persisted copy of every weekly report.
3. **The slice shipping while the bug stayed live.** Round 2. v2 specified only the WRITE; the
   READ at `:93-98` feeds `isFirstReport` and the 403 at `:118`. The ledger would have
   incremented with nothing reading it.
4. **A board disposition that was wrong about my own work.** Round 5, live-verified: `:2743` was
   marked "stays open" when slice 2's migration 129 had already made its premise impossible.
5. **An untested ordering invariant.** Round 7. Nine mutations pinned presence, gating and target;
   none pinned that the insert PRECEDES the consume — the reversed order being the worse failure.
6. **A whole live-apply step that was never needed.** Round 2: `quota_key` is unconstrained
   `text`, so no migration. 130 stays free.

## Ground truth verified

Live: the full channel census with `summarized = 0` repo-wide (proving never-used, not pruned);
`usage_counters` schema, RLS state, grants and zero rows for both proposed keys;
`consume_quota`'s `RETURNING uc.used` and `-1` semantics; `cleanup_usage_counters`'s two-sided
predicate; all three slice-2 trigger bodies reading `usage_counters` exclusively. Source: every
`weekly-report` citation, `sync_coach.dart`, `reports_screen.dart`, the SoT registry entry and
its 4-block contract test, `usage_counter_source_lib.dart`'s ceiling-not-ratchet, and that no
Edge Function calls `consume_quota` yet.

## Owed before merge

The B-pass runs at §6 step 3, **before** the deploy — reordered in v6 after round 5 caught that
v4 copied slice 1's deploy-then-review ordering without its justification (migration 128 was
inert; this gate is not). `bpass:` and `bpass_review:` are filled in then.
