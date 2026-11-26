---
branch: oi348-landing3c
date: 2026-11-26
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi348-landing3c-bpass.md
hermes: pending
hermes_report: docs/audit/2026-11-26-hermes-oi348-landing3c.md
---

# Plan-review record — OI-348 Landing 3c (P2: free progress-photo upload, 1 per IST week)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Tier L (schema + Storage
trigger + subscription-adjacent gate + a root CLAUDE.md row). CATASTROPHIC: the migration this branch lands is a
`supabase/migrations/` file with `SECURITY DEFINER` content, which `blast_radius_content_rules_lib.dart` forces to
catastrophic at commit and at merge (the B-pass found the record said `account`; migration 154, the same shape,
was catastrophic too). So: a B-pass, a staged catastrophic review on the migration commit, and a Hermes pass.

Plan: `docs/plans/oi348-landing3c.md`. Founder calls 2026-11-26 (Q1-Q4: 1 free photo per IST week, server-counted;
2048 px; PRO uncapped; lapsed = free) and "Start both" (3c here, 3d in its own session).

## Rounds
- **Round 1** (context-blind Sonnet, on the prose plan + draft SQL): 15 findings, 7 P1, all folded: ADR-0022 copy in
  a no-purchase build (GO PRO only behind `showsUpgradeAffordance()`); the missing test and doc list; an UPDATE of
  `created_at` reopening the row door (BEFORE UPDATE guard); the Monday boundary at two clocks (the row takes its
  OBJECT's `created_at`); the sweep window and clock skew (60 min, own failures 2 min); the trigger running for
  other users' folders and a NULL folder (early return, fail closed); Storage platform behaviours named for the
  founder's live check.
- **Round 2** (fresh seat, on the post-round-1 plan, draft SQL and the repository diff): 12 findings, 2 P1 (the
  early return keyed on `auth.uid()` let anon reach the count and a forwarded-sub service_role skip the cap; no
  test of it), folded: the early return is keyed on `auth.role()` in (anon, authenticated) and IS DISTINCT FROM;
  live cases W9-W11 and a mutant. P2s folded: the owner-prefix mutant, the discarded-`created_at` and two-count
  header sentences, fail-open-if-dropped named on OI-316, the rollback restores 154's live ACL, `ownFailedCleanups`,
  the device-clock residual and the founder's two-tab check (OI-531).
- **Round 3** (fresh seat, narrow check of the round-2 folds against the BUILT code, draft and live verify): every
  fold present and correct, the rollback an exact inverse of 154's state in a valid order, nothing in the forward
  block that fails on apply. 0 P0, 0 P1, 3 P2: W9 / W10 now require the RLS wording (a missing INSERT privilege
  would also have passed `<> literal`), the `Destructive?` tag set to `yes` as 154 declared the same DROP TRIGGER
  shape, and pruning `ownFailedCleanups` declined (memory-only, user-prefixed paths, a path that can never be a
  candidate again). Converged.

## Ground truth
Live, read-only (2026-11-26): the bucket's policies and limits, `progress_photos` columns, the existing trigger and
`enforce_progress_photo_pro`'s security mode and ACL, TRIGGER privilege of `postgres` on `storage.objects`, the
existing triggers there, `auth.role()` / `auth.uid()` definitions. Every file:line in the plan was read on main
`8cd4556f`.

## B-pass
`docs/reviews/oi348-landing3c-bpass.md` (one fresh Sonnet seat, eight lenses, head 6766a101): 0 P0, 0 P1, 5 P2,
all accepted and fixed: the tier (catastrophic by content, so a Hermes pass is owed), the SoT cites of
`paywall_sheet.dart` / `subscription_service.dart` (stale-on-main ones re-derived too), the superseded
`subscription.md` paragraph marked, a failed insert without a server answer left to the 2-minute sweep plus
10 s bounds on the cleanup and the pre-check, the row door's bound as `168 hours`, live-verify W16.

## Hermes
(pending: owed before the merge; seats run as Sonnet per the founder's 2026-10-07 rule.)
