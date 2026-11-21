---
branch: oi320-referrer-cap
plan: docs/plans/oi320-referrer-cap.md
date: 2026-10-11
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/7058fd0f49df-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-11-hermes-oi320-referrer-cap.md
---

# Plan review - OI-320, a per-referrer cap on referral credit (migration 158)

Founder decision (2026-10-11): "Seven referrals per 90 days. Final. Yeah, let's make it final." Plan: `docs/plans/oi320-referrer-cap.md`. One migration (`redeem_referral_atomic` replaced, both user columns of `referral_redemptions` made nullable with their foreign keys re-created `ON DELETE SET NULL`), four SQL test files, one Dart source-pin test, registry/ledger/doc updates. Catastrophic tier by CONTENT (a migration with SECURITY DEFINER), so this record carries `bpass: accepted` and `hermes: accepted`. Execution mode (CLAUDE.md 4.12.7): inline, one coordinator; every reviewer was a fresh read-only Sonnet reader (founder rule 2026-10-07), at most four at a time.

## Review rounds

- **R1** - a fresh context-blind reader with sandbox access, on the v1 plan and draft. Found a **P1 the converged-looking design had missed**: `delete-account` ends in `auth.admin.deleteUser`, which cascades through `public.users`, so a throwaway referee deleting its account took its credited audit row with it and reopened a slot (measured: 3 deletions turned 7 credits into 10); plus a deadlock in the OLD function body on mutual redemption (51 and 2 `40P01` in two runs of 3000 opposite pairs). Folded into v2.
- **R2** - a different fresh reader on v2 (83 tool calls): **no P0/P1, six P2 and five P3.** The same cascade on `referrer_id` (a deleted referrer lets the referee redeem a second code); a `lock_timeout`-less `DROP CONSTRAINT` that locks `public.users` too (the reviewer measured a 2.7 s convoy); two regressions the tests could not see (the referee's extend branch gated by the cap; deleted-referee rows dropped from the count); a live verify blind to a second foreign key; a replica-only guard that a user-count threshold could not make safe; and process text that mis-ordered the gates. Folded into v3.
- **B-pass** (`docs/reviews/7058fd0f49df-review.md`) - one fresh reader on the real diff: **no P0/P1, five P2, five P3**, every one resolved in the batch (the replica schema file's re-run hazard was reproduced and fixed; seven mutants that passed both SQL files drove three new verify cases and a Dart pin on the restated credit blocks).
- **Hermes pass** (`docs/audit/2026-10-11-hermes-oi320-referrer-cap.md`) - four Sonnet seats, twelve lenses, on the post-B-pass tree: **no P0/P1, two P2, seven P3, one false alarm**, every one resolved (RLS shape of the table pinned on the replica and in the live verify; stale counts and registry citations; the half-applied-runner wording; a live catalog inventory run; the race script's cleanup).
- **Convergence, stated plainly.** Round-1 findings were a P1 and a P1-class deadlock; round 2 had no P0/P1; the B-pass and the hermes seats, reading the real diff, found none and no finding touched the migration SQL after the round-2 fold (its sha256 `527999b451925d04bf8bafba10be5f3e8e44d7dc8922f59ba6cba5a8e92ecafa` is the file both later reviews read). That is a SELF-ATTESTATION of convergence, not a third plan-review round. Three design additions of mine came AFTER round 2 and were covered by the B-pass and the hermes pass only: the `referrer_id` foreign key change (round-2 finding 4), the post-condition `DO` block, and `lock_timeout`; the founder is told so.

## Ground truth

- Read at base `df2b1282` and the working tree by both plan reviewers, the B-pass, all four hermes seats and the coordinator: the migration, the function's old body (live definition, `md5` `1066f4cb5b1c36058fd5c0b635e3209d`, kept verbatim in the replica schema and in the inline rollback), `supabase/functions/redeem-referral/index.ts`, `delete-account/index.ts`, `restore-user-snapshot/index.ts`, `lib/core/services/sync/sync_restore_completeness.dart`, `ReferralRepository`, migrations 037/038/053/090/091/100/152/154/155/157, the blast-radius registry, the commit-time and merge-time gates (including the `origin/main` rewrite of the plan-review gate).
- Live, read-only, project `dedsavbjuwgarrhphgnl` (2026-10-11): the five constraints of the table (both FKs `ON DELETE CASCADE`, both columns NOT NULL), `created_at` `timestamptz` default `now()`, RLS enabled with exactly one SELECT policy and no triggers while anon/authenticated hold full grants, exactly one object mentioning the table (`public.redeem_referral_atomic`, still the old body), 3 rows and 0 in the last 90 days, 36 free fixture users. Nothing was written to the live project during the reviews. **Applied afterwards** (2026-10-11, 23:59 IST) on the founder's own go ("yeah approved"): `apply_migration` name `158_referral_referrer_cap`, cloud version `20261011182941`, the file byte-for-byte (the stored statement's sha256 equals the file's); post-apply catalog equals a local sandbox apply of the same file (function `md5` `e69618b8bdabe6ef495a0a463efd51e0`, `search_path=public`, ACL `{postgres,service_role}`, both foreign keys `ON DELETE SET NULL`, both columns nullable, `lock_timeout` 0); the live verify returned 28 of 28 `ok` and persisted nothing (3 rows, no NULL-party rows, no verify codes). The apply is recorded in commit `8fb4c727` (`closes-oi: OI-320`, ledger entry `158`, plan section 6).
- Run, not just read: the 28-case live verify (old body 18 fail / 10 ok; 158 28 ok), the 6-case deletion file, the race script (parts 1, 1b, 2a, 2b), the rollback (byte-exact), the duplicate-FK and refusal controls, a 58-mutant SQL matrix and a 80-mutant Dart-pin matrix (results in the plan section 3 and the hermes report), `flutter analyze lib/`, the full suite and the serial pre-commit gate loop.

## Section 4.6 / registry `requires: feature_flag` - position

No runtime kill switch, on purpose (plan section 2): a switch would live inside the SECURITY DEFINER function as a second code path, and its "off" state is the abuse this batch closes. The old path is preserved verbatim as the inline rollback block, measured byte-exact, which is the revert. Nothing enforces the registry entry mechanically (`scripts/safe_push.sh:132-135`, `scripts/reconcile_ci.dart:41`).

## What this record does NOT cover

- Push, PR and merge of `oi320-referrer-cap`: each is a separate founder go; the merge is only via `sh scripts/safe_pr_merge.sh <pr>`. `origin/main` is ahead of this branch and must be merged into it (and the gate loop re-run) before a push.
- Two product questions the founder answered YES to but that are not built: the invite copy stating the cap and a referrer's "n of 7 left" surface (OI-336, with the precondition that both restore selects carry `referrer_rewarded` / `referee_rewarded`; the Edge Function half needs its own deploy go).
- The review rounds above ran BEFORE the live apply; the apply added no code and changed no file the reviews read (the migration's sha256 is the one both later reviews read).
