---
branch: template-stable-identity
plan: docs/superpowers/plans/2026-09-26-template-stable-identity.md
review_rounds: 3
ground_truth_verified: true
verdict: converged
---

# Plan review — workout templates get one stable identity (unit 2a)

**Blast radius:** platform (schema migration + trigger, two Edge Function deploys, core sync
fan-out/restore logic touching every device). Classify the real drafted migration/EF files for
the final tier before the merge-to-main commit, per the `blast_radius_from_diff.dart` "do not
classify a not-yet-written path" pitfall (CLAUDE.md §4.9).

**Origin:** the reuse-audit batch's bug A (deleted workout templates resurrect on restore) and
B2 (saved meals never sync a delete) both trace to the same root: templates are matched by name,
not a stable id, so delete and rename cannot propagate correctly across devices. Two prior
design directions (an in-row "synced" marker; a second uid identity alongside name) each failed
review after finding the two-identity or client-decided-marker shape was structurally unfixable.
Founder decision 2026-09-26 (AskUserQuestion): **"Stable ID rework"** — give every template one
permanent id used everywhere, as its own multi-day, OI-tracked unit. Saved meals (2b) reuse
whatever this unit proves.

## Round 1 (context-blind) — plan rev 5 → not converged, 7 material findings

P0: dropping `UNIQUE(user_id,name)` (rev 5's original mechanism) makes an old app version's
template push fail (42P10) forever, and the every-launch restore sweep then deletes that
device's own unsynced templates locally — real data loss, not just "stops syncing up" as rev 5
claimed. P1×5: a drain-vs-in-flight-push race could let a deleted template survive; the plan's
"restore order is plan before schedules" premise was false on most restore paths (verified —
`sync_service.dart` runs templates and the plan snapshot in a parallel `Future.wait` on most
paths); the plan_json ghost-day rule contradicted itself as a result; a schedule push omitted
`template_id` entirely when null, so a stale (deleted) reference never cleared; migrator-vs-
restore ordering was unspecified; the claimed test-injection seam does not exist on `SyncService`.
Folded into rev 6: kept `UNIQUE(user_id,name)`, switched to a rename-on-delete trigger (frees the
name instead of dropping the constraint) with a second trigger branch that makes any further
write to a deleted row a full no-op; the drain does an UPSERT (not UPDATE) so it can create the
tombstone directly ahead of a racing creating push; a `deletedTemplateIds` set is computed once
and threaded through the restore pass instead of relying on execution order; schedule pushes now
always send the `template_id` key, including explicit null; the existing live-account test seam
(`test/supabase/supabase_test_helper.dart`) replaces the nonexistent mock.

## Round 2 (context-blind, on hardened rev 6) — not converged, 2 material + 2 minor

Verified findings 1/2/5/9-mechanism/10 from round 1 as genuinely fixed. New: rev 6's "gate
restore behind the migrator" would gate `_restoreIfNeeded`, the SOLE entry point for every
restore domain (templates, nutrition, weight, measurements, profile) — confirmed by reading it —
so an offline user would lose unrelated-domain restore, not just templates. Rev 6's
`deletedTemplateIds` threading never reached two standalone single-domain entry points
(`restoreWorkoutPlanForSyncDomain`, `restoreScheduledWorkoutsForSyncDomain`). Minor: a "3 of 4
restore paths run in parallel" claim was wrong (one path is sequential `await`s, not
`Future.wait` — doesn't change the fix); the `workout-window-closing` EF fix as described risked
an `!inner` embed join silently dropping schedule rows with a null `template_id`. Folded into
rev 7: the migrator now gates only `_restoreWorkoutTemplates`/`_syncWorkoutTemplates` themselves
(early-return offline), leaving `_restoreIfNeeded`'s other domains unaffected; a new
self-contained `_deletedTemplateCloudIds()` helper is called independently by all five sites that
need it, including both single-domain entry points; the EF filters deleted templates in
application code against its own existing second fetch, not via a join.

## Round 3 (focused, context-blind, verify-only on rev 7's four changes) — converged

Scoped to the four round-2 findings only (everything else already verified in rounds 1-2, out of
scope per §4.12.1's "don't re-review the whole thing a further time" once a unit is this deep).
All four verified sound against the actual code: the gating fix is structurally isolated per
`Future.wait`'s independent-future semantics (an early return in one Future cannot affect
siblings, confirmed no shared try/catch exists); both `*ForSyncDomain` entry points are real,
trivial, and have `userId` in scope for a one-line helper call; the "sequential, not parallel"
correction is a factual match to `_attemptSingleCallRestore`'s body; the EF's app-code filter is
strictly safer than the rejected join for the null-`template_id` case, since an unfiltered field
value is exempt by omission from the set rather than dropped by a join predicate.

**Verdict: converged.** No implementation exists yet — migration 145, both EF diffs, and every
client change in the plan's table are drafted next, each still subject to the existing per-fix
gates (mutation-proof regression tests, diagnose-doc, live-schema regen, `deno check`, B-pass
before merge). Live migration apply and both EF deploys each need their own explicit founder
go-ahead per §4.3, independent of this plan approval.
