---
staged_against: opt-a-rls-initplan
verdict: accepted
---

# B-pass / migration-design review — opt-a-rls-initplan (migration 100)

- **Reviewer role:** fresh context-blind adversarial pass over the catastrophic-tier RLS migration
  `100_rls_initplan_select_wrap.sql` (completeness + correctness + syntax lens) — find defects, not
  validate. Verified against the actual file + LIVE `pg_policies` (project `dedsavbjuwgarrhphgnl`).

## Verdict: **accepted** (migration SQL clean; supporting-artifact fixes applied in-batch)

The migration itself passed every correctness point; the review's blockers were in the SUPPORTING
artifacts, all fixed in this batch before apply.

### Migration SQL — SOUND (all points)
- **Completeness:** 136 ALTER + 1 DROP = 137, exactly matching the 137 live `auth.uid()`-referencing
  policies. The only excluded policy is `saved_diet_plans "Users see own diet plan"` (the DROP target)
  — confirmed the sole intentional exclusion.
- **Per-cmd clause correctness:** INSERT → WITH CHECK only; SELECT/DELETE → USING only; UPDATE/ALL →
  both. No clause/cmd mismatch (no apply-time `USING not allowed for INSERT` error).
- **Substitution:** 8/8 spot-checked policies byte-identical to the original modulo the wrap —
  EXISTS correlation intact (nutrition_log_items / template_exercises), `referral_redemptions` OR
  both arms, `users =id`, plain `=user_id`, `community_reviews =reviewer_id`.
- **saved_diet_plans consolidation:** the ALL policy still gates all 4 verbs after the SELECT drop;
  no lockout, no cross-user opening.
- **Transaction/ordering:** BEGIN/COMMIT wraps atomically; no DROP-before-ALTER hazard (the dropped
  SELECT is excluded from the ALTER set); explicit BEGIN/COMMIT is a proven repo pattern (mig 052-055).

### Blockers found — ALL FIXED in-batch
1. **A/B verification SQL was non-functional** (missing NOT-NULL `item_index`; user_id FK to
   `public.users`; psql-only `\set` in a SQL-editor context; `referral_redemptions` OR-shape
   comment-only). → **Rewritten** to seed-as-owner + assert-under-RLS with two real uids, all
   NOT-NULL/FK satisfied, both OR arms + a positive own-read assertion. **Validated live: PASS on
   both the pre-apply baseline AND post-apply.**

### Non-blocking refinements — applied
- Header wording clarified to "136 ALTER + 1 DROP = 137 affected"; the 136 = 128 simple + 8 EXISTS.

**Post-apply confirmation:** the migration applied cleanly; live `pg_policies` shows
still_bare_unwrapped=0, wrapped=136; advisor `auth_rls_initplan` 137→0 and `multiple_permissive`
5→0; the A/B leak check PASSED post-apply (behavior-preserving, no leak, no lockout).
