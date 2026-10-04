---
branch: opt-a-rls-initplan-ship
date: 2026-07-07
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/opt-a-rls-initplan-bpass.md
hermes: accepted
hermes_report: docs/audit/opt-a-rls-initplan-hermes.md
---

# Plan-review record — opt-a-rls-initplan (OPT-A: RLS initplan wrap, catastrophic)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Catastrophic-tier
(migration touches every RLS policy — the last privacy fence), so it carries B-pass + Hermes.

## Scope
Migration `100_rls_initplan_select_wrap.sql`: wrap `auth.uid()` → `(select auth.uid())` in all 137
RLS policies that reference it (Postgres initplan perf — behavior-identical), + consolidate the
`saved_diet_plans` duplicate SELECT policy (5 `multiple_permissive` warnings). Diagnose-doc `e6b1a4`.

## Review arc (all context-blind; every claim verified against live pg_policies)
- **Plan-level ×4 (within the bundle):** the OPT-A design was reviewed across four independent plan
  rounds while it was part of the larger optimization plan. Each corrected it: 135→**129** simple
  policy count; the `saved_diet_plans` ALL+SELECT lockout trap; **blind-textual** substitution (not
  column-keyed — catches the `referral_redemptions` OR-shape); prefer `ALTER POLICY` (mig 055
  precedent) over DROP+CREATE; statement-ordering (exclude the dropped SELECT from the ALTER set);
  `ALTER POLICY` cannot change roles (dropped a needless re-verify). All folded.
- **Migration B-pass (completeness/correctness):** SQL clean (136+1=137, per-cmd clauses correct,
  byte-identical substitution, consolidation lockout-safe, transaction safe). Found the A/B
  verification SQL non-functional → **rewritten + validated live**. Record:
  `docs/reviews/opt-a-rls-initplan-bpass.md` (verdict: accepted).
- **Hermes (adversarial leak-hunt + cross-lens):** Opus leak-hunt **could not construct a leak or
  lockout** (auth.uid() STABLE → value-identical; EXISTS correlation intact; consolidation safe).
  Cross-lens found the rollback recipe non-functional (post-apply reads the wrapped form) → **replaced
  with literal reverse DDL**; and corrected the commit sequencing (apply-first, then commit file +
  manifest). Record: `docs/audit/opt-a-rls-initplan-hermes.md` (verdict: accepted).

## Ground-truth verification (live, 2026-07-07)
137 policies = 129 simple + 8 EXISTS; **0** already-wrapped, **0** `auth.jwt()`/`auth.role()`,
**0** RESTRICTIVE, **0** asymmetric USING/WITH-CHECK. Migration generated blind-textually from live
`pg_policies` (zero transcription); verified 171/171 `auth.uid()` occurrences wrapped, 0 bare.

## Convergence + live outcome
All review findings folded (no deferrals). **Applied live (founder go 2026-07-07):**
- `pg_policies`: still_bare_unwrapped=**0**, wrapped=**136**, saved_diet_plans=**1 policy**.
- Advisor: `auth_rls_initplan` **137→0**, `multiple_permissive` **5→0** (only `unused_index` remain).
- A/B leak check **PASS post-apply** (behavior-preserving; A sees only own, both OR arms, own diet
  plan readable, B blocked from A's read+write). Rollback path is literal + executable if needed.
