---
branch: oi46-daily-cap-triggers
date: 2026-07-29
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/2dbdf134304e-review.md
---

# Plan review — oi46-daily-cap-triggers

OI-46's board text named a `channel='in_app'` gap that does not exist as a live value.
Re-verification against live code found the real gaps: chat's free-tier 10/day cap and the
combined scan_meal+cart_auditor 15/day vision cap were both check-then-insert (the vision one
worse — its enforcement point was a swallowed `catch (_) {}`, meaning even a hypothetical
trigger added there alone would never have actually fired); the 9 onboarding-critical
`user_profile` fields had no Postgres backstop at all. Building the fix surfaced an unplanned
fourth issue: the precedent trigger (migration 026) this batch was told to mirror has its own
live IST-boundary bug. Tier is `platform`: 3 new/modified Postgres migrations +
`supabase/functions/ai-proxy/index.ts` restructuring, both categorically `platform` per
`docs/blast_radius.yaml`.

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (general-purpose agent), on the first-draft diff | **PASS.** 2 real bugs found: the vision reservation was never resolved on Gemini-failure/invalid-JSON exit paths (reintroducing the exact "stuck pending row" class `food_text_analysis`'s own `resolvePlaceholder` exists to prevent — see that helper's own comment citing 8 stuck rows, 2026-05-11→15); a missing/empty `body.image` fell through to the reservation insert before either handler's truthy-image guard, orphaning a row on a malformed request. Both fixed: a shared `resolveVisionPlaceholder` helper now closes every exit path in both handlers; the image-empty check now runs before the reservation insert. 2 new regression tests added. 4 lower-severity/non-blocking notes (trigger-name-vs-comment mismatch, a stated-not-hidden non-serializable-transaction race matching the pre-existing migration 026 precedent, a stated-not-hidden chat-dedup gap matching pre-fix behavior, a diagnose-doc frontmatter field naming registry entries that didn't literally exist) — all either fixed alongside the two real bugs or explicitly accepted with reasoning in the diagnose-doc. |
| 2 — independent, context-blind (general-purpose agent), on the round-1-hardened diff | **PASS.** Verified both round-1 fixes complete and correct by tracing every `return` statement by hand (not by trusting round 1's summary) — confirmed. Found a NEW issue round 1's own fix introduced: `resolveVisionPlaceholder` (and two analogous chat-side inline UPDATEs) wrapped the resolution UPDATE in a bare `try/catch`, which never observes a PostgREST-level `{data, error}` failure (`feedback_postgrest_builder_no_catch.md`) — reintroducing the silent-failure shape one level down from what round 1 just fixed. Fixed by destructuring `.error` and logging on all three resolution sites. Also caught 2 migration comments citing `istDayStartIso()` as still-live evidence when this same diff deletes it, and 2 stale line-number citations in the diagnose-doc's own `writers:` field — both corrected. |
| B-pass — fresh context-blind (sonnet, `/code-review` skill, 5 lenses) | **PASS → accepted.** 1 P1, 1 P2 (detail in `docs/reviews/2dbdf134304e-review.md`). P1: a SECOND writer of the onboarding transition (`restoring_screen.dart`'s OBS-3 self-heal) was never enumerated by either plan-review round or the diagnose-doc's writer analysis — its own field-completeness check only covered 3 of migration 112's 9 gated fields, which would have put a narrow legacy cohort into a permanent doomed-retry loop. Fixed: widened to all 9 fields, gated the stamp *attempt* (not navigation) on completeness, added a regression test. P2: `platform` tier's registry `requires: [feature_flag]` isn't satisfied by any of the 3 new/modified triggers — checked against precedent (zero of ~113 prior trigger-adding migrations, including the literal one this batch mirrors, carry a runtime flag) and accepted as a documented exception rather than built as batch-specific infrastructure with no precedent elsewhere. |

## Why this is converged rather than merely green

Three consecutive rounds, three consecutive NEW findings, each one genuine and non-overlapping
with what the prior round caught: round 1 found the vision restructuring was functionally
incomplete; round 2 found round 1's own fix dropped an observability property (and, separately,
verified round 1's fixes rather than trusting them); the B-pass found a writer neither review
round's own writer/reader enumeration had surfaced at all, because both rounds inherited the
diagnose-doc's writer list rather than independently re-deriving it from a fresh grep. That last
point is the most load-bearing lesson of this record: the plan-review process caught bugs IN the
implementation across two rounds, but a structural bug in the ANALYSIS itself (an incomplete
writer enumeration) survived both rounds and was only caught by a differently-framed pass (the
B-pass's lens-based checklist, not a general "review this diff" prompt). Every fix at every round
was verified by re-running the actual contract tests and `flutter analyze` afterward, not assumed
correct from the finding's plausibility — 13 contract tests + 43 pre-existing routing tests green
after the final round, up from 11 tests before round 1 started.

## Ground truth

Verified directly against live code and files, not taken from any round's own prose: the exact
`RAISE EXCEPTION` string each trigger raises was read from the actual migration SQL and
cross-referenced character-for-character against every `.includes(...)` check in
`ai-proxy/index.ts` (confirmed exact, no truncation); the real trigger name
(`trg_chat_app_rate_limit`, not `trg_chat_app_daily_limit`) was confirmed by grepping the actual
`CREATE TRIGGER` statement, then the 5 wrong citations were independently re-grepped after the
fix to confirm zero remained anywhere in the repo, not just the 5 originally-cited files;
`hasCorePlanFields`'s pre-fix 3-field check and `_stampOnboardingCompletedAt`'s unconditional
fire-and-forget call were read directly from `restoring_screen.dart`, not inferred from its
surrounding comments; `sync_profile.dart`'s conditional-field-inclusion upsert
(`SyncService._hasValue` guards) was read in full to confirm the single-upsert-call claim before
finalizing the transition-gate design, not assumed from the SoT registry's prior description of
the concept; `docs/blast_radius.yaml`'s `platform`-tier `requires:` list was read directly, and
the "zero of ~113 prior migrations use a feature flag" claim was verified by grepping every
migration file in the repo, not sampled.

## Residuals, stated

- The new triggers' cap-check (`SELECT count(*)` then insert) runs under ordinary READ COMMITTED
  with no `FOR UPDATE`/advisory lock/unique-constraint-backed counter — two genuinely
  simultaneous inserts from the SAME user (e.g. a double-tap across two devices) can each pass
  the check before either commits, landing one row over cap. Self-inflicted only; mirrors the
  pre-existing `food_text_analysis` trigger's identical design (migration 024/026) verbatim.
  Closing it would mean redesigning the precedent this batch was explicitly told to mirror — not
  bundled into this fix.
- Chat's reservation does not get `food_text_analysis`'s pending-row dedup-reuse treatment — a
  rapid same-message double-tap while the first request is in-flight creates two reservations
  instead of reusing one. Unchanged from pre-fix behavior (the old completed-row-only dedup had
  the identical gap, just with the insert timing moved); porting the dedup-reuse pattern to chat
  is a separable enhancement, not required to close OI-46's named gaps.
- No Postgres-side kill-switch on any of the 3 new/modified triggers (B-pass Finding 2, accepted
  as a documented exception — see the round-3/B-pass row above and the diagnose-doc's own "B-pass"
  section for the full reasoning).

## Post-review: live apply + deploy (2026-07-29)

This record initially covered the branch as written, pre-apply. Per CLAUDE.md §4.3, plan approval
is not deploy approval — both actions below required and received their own separate, explicit
founder authorization via `AskUserQuestion` after this review converged:

- Migrations 111/112/113 applied to `dedsavbjuwgarrhphgnl` at 2026-07-29T16:03:47+05:30
  (`backups/applied_migrations.json` updated same batch). Verified live via `pg_trigger` + the
  full behavioral SQL test (`test/sql/oi46_daily_cap_triggers_live_verify.sql`, 7/7 passing).
- `ai-proxy` redeployed as version 79, closing the operational gap where the pre-batch deployed
  code would have thrown raw errors (chat) or silently swallowed the trigger's rejection entirely
  (vision) against the newly-live triggers. Boot-verified via smoke test.

Full detail in the diagnose-doc's "Live apply + deploy" section.
