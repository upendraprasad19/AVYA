---
branch: single-owner-a2b
review_rounds: 10
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/307b548789a7-review.md
tier: platform
date: 2026-09-28
---

# Plan review — single-owner-a2b (units a2a, a2b-1, a2b-2, a2b-3)

**Scope:** the whole `single-owner-a2b` branch, which shipped FOUR units of
the `single-owner-batch-a` remediation (`docs/plans/2026-09-26-single-owner-batch-a.md`):
a2a (daily-snapshot test seam + `DISABLE_COACH_EXTRACTION` kill switch +
privacy-before-any-read gate, diagnose `c3f8e6`); a2b-1 (daily-snapshot
coaching-notes extraction rewritten to a watermark-bounded, metered read,
closing an OI-162-class unmetered-Gemini gap, diagnose
`a2b1c7`); a2b-2 (per-field `coach_extraction_locked_fields` lock so AI
extraction can no longer silently overwrite a user's explicit Edit Profile
edit, migration 148 LIVE-APPLIED, `daily-snapshot`/`protein-gap-alert`
redeployed, diagnose `a2b2f1`); and a2b-3 (DROPPED — `docs/plans/2026-09-27-single-owner-a2b-3-plan.md`,
`verified_clean` per §4.10, no code shipped: the snapshot-size-bound
rationale was checked against live readers and found to solve no real
problem, since the stored blob it would have bounded is never sent to any
model). A fifth, small fix (diagnose `e35936`) closes a test-infrastructure
regression a2a's own seam refactor silently introduced in a SHARED test
file, found only by this record's own final full-suite verification.

**Blast radius: platform** (`docs/blast_radius.yaml` pins
`supabase/functions/daily-snapshot/**` platform; `supabase/migrations/**`
is platform by default and migration 148 does not trip the
`SECURITY DEFINER`→catastrophic content rule, since
`lock_coach_extraction_fields` is `SECURITY INVOKER`). Confirmed live via
`git diff --name-only origin/main...HEAD | dart run
scripts/blast_radius_from_diff.dart -` → `platform`.

## Round summary (10 pre-implementation rounds across 3 units, each independently converged)

- **a2a — 2 rounds** (`docs/plan-reviews/single-owner-a2.md`, its own
  standalone record for the plumbing half of the original combined a2
  plan): round 3 found the seam/kill-switch/private-mode gaps that became
  this unit; round 4 (post-hardening) found only material issues in a2b's
  scope, confirming a2a's own plumbing had already converged. Ground truth
  independently re-verified against live code before the split.
- **a2b-1 — 3 rounds**: round 1 found 3 of 6 fixes underspecified in ways
  that risked shipping something WORSE than the bug (silent-skip-on-outage,
  an unbounded metering fix, a sibling-guard regression). Round 2
  (live-verified) found round 1's own fixes still had 3 material gaps in
  the SAME three mechanisms, plus 2 P2s and 2 P3s. Round 3 (live-verified)
  confirmed round 2's fixes held and found only one new P2 (a dead-literal
  + unstated scope-narrowing in the channel allowlist) — converged per the
  reviewer's own recommendation, a scoping/citation-class fix rather than a
  redesign.
- **a2b-2 — 5 rounds**: converged after the round-5 finding was itself
  mechanical (a citation/scope correction, not a design defect) —
  `review_rounds: 5` per its own plan frontmatter. Ground truth for the
  batch's OWN premise (not just a reviewer's claim) was independently
  re-verified DURING implementation, not just during review: Design §5's
  specified write target (`user_preferences.coaching_notes`) turned out to
  have ZERO live readers in the AI-facing path — a dead-end no review round
  caught, because all five read the write side's stated rationale without
  independently grepping for the read side. Fixed by redirecting to
  `coach_memory.locked_field_conflicts` (confirmed reachable via
  `ai_snapshot_builder.dart`'s wholesale `toJson()` pass-through). See
  `feedback_verify_plan_write_target_has_a_reader.md` for the durable
  process lesson this produced.
- **a2b-3 — 0 rounds needed**: dropped at the founder-decision stage before
  implementation, per §4.10's `verified_clean` terminal state — the
  live-data check that would have been round 1 of its plan review IS the
  reason it never needed one: `docs/plans/2026-09-27-single-owner-a2b-3-plan.md`'s
  own "Original rationale" section shows the size-management mechanism that
  actually matters for token cost (`_compactContext`) already exists and
  works on a completely different pipeline; the stored blob this unit would
  have bounded is selected by NOTHING that calls Gemini (`ai-proxy`,
  `ai-media-proxy`, `weekly-report` all select only `id` from
  `user_daily_snapshots`).

Total: **10 review rounds** across the three implemented units (2+3+5),
each independently converged before its own implementation began, all
ground-truth-verified against live code/data rather than assumed from
review prose.

## Self-triggered B-passes (3 rounds, one per implemented unit, per §4.3 — do not wait to be asked)

1. **a2a**: `docs/reviews/aa943309c727-review.md` — 2 findings, 0 false
   alarms, both fixed same commit. F1 caught the plan's own dependents list
   (3 test-header repoints + a new SoT concept + a guard note) that the
   first diff had simply skipped — invisible from the code alone, only
   visible by re-reading the plan. F2 flagged that 4 new source-grep tests
   never behaviorally invoke the seam they pin — accepted as a disclosed,
   codebase-wide limitation (module-scope `Deno.env.get(...)!` reads block
   dynamic import) rather than fixed.
2. **a2b-1**: `docs/reviews/aee7dfb3bf10-review.md` — 6 findings, 0 false
   alarms. **Finding 1 (P1) is the headline result of this whole branch**:
   the first draft advanced the extraction watermark the instant Gemini
   returned a parseable response, then let the caller run the merge writes
   afterward with NO guard — so a `mergeCoachingNotes` write failure lost
   the extracted facts PERMANENTLY (the watermark had already moved past
   the rows that produced them, and nothing re-reads a cleared window).
   Fixed same commit. Finding 6 (asserted_fixture_value) caught the
   reviewer's OWN suggested fix being wrong — adopting it would have
   silently defeated the microsecond-precision property the batch existed
   to get right, since `Date.parse()` truncates to millisecond resolution.
   See `feedback_verify_suggested_fix_independently.md`.
3. **a2b-2**: `docs/reviews/b56bd6f49571-review.md` — 2 findings, 0 false
   alarms, both fixed same commit (`8c158b65`), plus a founder-authorized
   follow-on redeploy (`977d0e2e`, `daily-snapshot` v28→v29) to make
   Finding 1's fix actually live. F1 (P2, blast_radius_mismatch) caught
   that the new locked-field guard had gone LIVE (migration applied, both
   Edge Functions deployed) with NO kill-switch, violating platform tier's
   §4.6 `feature_flag` requirement — fixed with a new, narrower
   `DISABLE_COACH_EXTRACTION_LOCK_GUARD` switch (deliberately separate from
   the pre-existing, coarser `DISABLE_COACH_EXTRACTION`). F2 (P3,
   guard_without_its_mirror/rule-21) caught that of TWO places sharing one
   deliberately-duplicated payload-naming-scheme bug fix
   (`.claude/emit_payload.js` and `.claude/deploy_via_api.js`'s `--rollback`
   path — found and fixed en route, affecting 9 Edge Functions with a
   same-directory-sibling import), only the first had a persisted
   automated regression test — added
   `.claude/deploy_via_api_rollback_payloadname_test.js` to close the gap.
4. **A fourth B-pass** (`docs/reviews/307b548789a7-review.md`) ran on the
   small `e35936` fix described below — 1 finding, 0 false alarms, filed
   as OI-260 (see that section).

**Every implemented unit self-triggered its own B-pass before its own
commit landed** — no unit merged un-reviewed, and CLAUDE.md §4.3's
"do not wait to be asked" instruction was followed literally throughout.

## The e35936 fix (found during THIS record's own final verification)

Writing this record required a genuine full-suite pass across the whole
branch — the first time `deno test supabase/functions/` had been run
across this branch's entire lifecycle (every prior verification was
per-function, per §4.11/§4.12.5's own repeated lesson that "a targeted run
is a different input set from the suite, not a subset"). That run
surfaced a real, silent regression: a2a's own test-seam refactor
(`geminiChatFn` injectable parameter) had broken
`_shared/gemini_backoff_retry_test.ts`'s literal-string retry-pinning check
for `daily-snapshot`, invisible to every targeted per-function test used
throughout a2a/a2b-1/a2b-2 and all 3 prior B-pass rounds, because the
failing test lives in `_shared/` and only a suite-wide run exercises it.
Fixed (`bf999034`, diagnose `e35936`), mutation-proven, with its own B-pass
finding (filed as OI-260 — a real but currently-non-live sibling gap in 4
OTHER functions' `reportGeminiExhaustion`-wiring tests). Full detail:
`docs/diagnoses/2026-09-28-gemini-backoff-retry-test-blind-to-injectable-seam-e35936.md`.

## Mutation evidence (full list across the branch)

- a2b-1: watermark-advance-before-merge-write fix — the B-pass's own
  Finding 1 mutation (reverting the guard reproduces permanent data loss on
  a merge failure).
- a2b-2: 12 new coach-extraction-lock Deno/Dart tests, mutation-proven per
  `docs/diagnoses/2026-09-27-coach-extraction-locked-fields-writer-drift-a2b2f1.md`
  (locked-field skip, value-equality for arrays, conflict-merge-over,
  `isVeg` vocabulary fix); the B-pass remediation's own kill-switch
  (4 new tests, reverting reddens exactly 2 of 4) and the
  `deploy_via_api.js` rollback-path fix (7 assertions, reverting reddens
  exactly 3 of 7, verified against REAL git history, not a synthetic
  fixture).
- e35936: `_shared/gemini_backoff_retry_test.ts`'s own widening — reverting
  the seam-recognition path reddens exactly 1 of 25 tests in that file
  (`daily-snapshot — retries: 2 passed`), independently re-run and
  confirmed by the B-pass subagent, not just self-reported.

Every mutation was restored via `cp` from a manual backup, never `git
checkout` (this repo's own documented EOL-mangling risk), and re-confirmed
green before the next step.

## Verification state at record time

- Full pre-commit gate loop (`sh scripts/pre-commit.sh`): green on every
  commit in this branch, including the final `bf999034`.
- `flutter analyze lib/` (whole-tree): 0 warnings/errors, 45 pre-existing
  `info`-level issues, none in any file this branch touched (verified via
  `grep -cE "^\s*(warning|error) -"` → 0, the exact fixed-width-severity-
  column check this repo's own common-pitfalls table warns is easy to get
  wrong).
- Full `flutter test` (`TZ=Asia/Kolkata`): **6573 passed, 9 skipped, 0
  failed.** Run once, after a2b-2's Dart implementation was complete and
  before its B-pass triage; not re-run for the e35936 fix (TS/JS-only, no
  Dart files touched, confirmed via `git diff --name-only`).
- Full `deno test supabase/functions/`: **649 passed, 2 failed** (both the
  pre-existing, VPS-only AddrInUse port-8000 conflict in
  `future-prediction`/`re-engagement` — confirmed unrelated to this
  branch's diff via `git diff --name-only origin/main...HEAD`, and already
  documented in this session's own harness memory as a known VPS-local
  environment quirk, not a CI-visible failure). Before the e35936 fix: 648
  passed / 3 failed — the third being the regression this fix closed.
- `deno check --node-modules-dir=none` on every touched function
  (`daily-snapshot`, `protein-gap-alert`, `_shared/coach_memory.ts`,
  `_shared/gemini_backoff_retry_test.ts`): all clean.
- Live migration 148 applied to `dedsavbjuwgarrhphgnl` (founder-authorized,
  separate from plan approval per §4.3): 27/27 existing rows
  backfill-locked, RPC ACLs and `SECURITY INVOKER` confirmed via
  `pg_get_functiondef`, `backups/live_schema_columns.json` regenerated from
  a FULL live `information_schema.columns` diff (which also caught and
  fixed an unrelated, pre-existing stale-column gap on
  `workout_templates.deleted_at` — see
  `docs/diagnoses/2026-09-27-coach-extraction-locked-fields-writer-drift-a2b2f1.md`).
- Live redeploys, all founder-authorized separately per §4.3: `daily-snapshot`
  v28 (initial a2b-2 ship) then v29 (B-pass Finding 1's kill-switch),
  `protein-gap-alert` v16 — all boot-verified via an anon-Bearer POST
  (confirms the module loaded, not just that the gateway responded).

## Out-of-scope discoveries, filed rather than fixed (per §4.2's own
distinction between a live bug in THIS diff vs. a real, non-live sibling
gap in unrelated files)

- **OI-257**: onboarding's `diet_preference: 'veg'` default doesn't match
  Edit Profile's own chip vocabulary (`vegetarian`/etc.) — found fixing the
  `protein-gap-alert` `isVeg` bug, a distinct architectural mismatch, not
  blocking a2b-2.
- **OI-258**: `backups/applied_migrations.json` missing an entry for
  migration 147 (a DIFFERENT unit's ledger gap) plus a live migration-
  145/146 numbering collision between diverged branch lineages, both
  already applied to the same prod database — discovered auditing the
  ledger ahead of migration 148's own apply, neither fixable from this
  branch (one file isn't even present in this branch's tree).
- **OI-260**: 4 sibling `reportGeminiExhaustion`-wiring tests share e35936's
  exact literal-string blind spot, but are not currently broken (none of
  those 4 functions uses an injectable seam) and fail loud, not silently,
  if the hazard ever fires.
