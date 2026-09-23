---
branch: confirm-email-init-race
date: 2026-09-24
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/cac1e4ee9414-review.md
---

# Plan review — confirmEmail() missing ensureSupabaseReady() guard (`confirm-email-init-race`)

## Why this record exists

`lib/features/auth/providers/auth_provider.dart` is explicitly named in root
CLAUDE.md §4.12.6's **L** classification
("payment/auth/sync/schema/EF/plan-engine/CLAUDE.md") — the full, unabridged
×2 plan-review process applies before this branch can merge to `main`.

## Scope

Second of two root causes behind **OI-244** ("6 of 9 real external signups in
the prior 10 days never completed confirmation"). The first cause
(Vercel-redirect losing `token_hash`, diagnose `f92d17`) was fixed and merged
to `main` earlier the same day on branch `claude/oi-242-flaky-test-filing`
(PR #43; its own keystone record is
`docs/plan-reviews/claude-oi-242-flaky-test-filing.md`). Minutes after that
fix went live, the founder reproduced the identical user-facing symptom
TWICE more — once in an ordinary browser, once in a fresh incognito window
(ruling out caching) — which led to this second, independent root cause:
`AuthNotifier.confirmEmail()` was the only sign-in-family method never
gated behind `ensureSupabaseReady()`. Diagnose `42a98d`.

1. `ad595244` — the fix: `if (!await ensureSupabaseReady()) return;` added
   to `confirmEmail()`, mirroring the pattern already used by
   `signInWithEmail`/`checkEmailRegistered`/`signInWithGoogle`/etc. A
   self-triggered B-pass (`docs/reviews/cac1e4ee9414-review.md`, `verdict:
   accepted`) caught one real P1 in the first draft before this commit:
   placing the new guard AFTER the pre-existing OI-205
   `confirmEmailAuthGuardState` check let a device with a real persisted
   session slip past that guard, because `ensureSupabaseReady()`'s success
   path synchronously restores any persisted session as part of the same
   awaited call — so `isAuthenticated` reads unconditionally (and wrongly)
   `false` until it resolves. Fixed by reordering before this commit landed;
   two lower-severity findings (an unbounded-hang comment overclaiming
   coverage; a stale diagnose-doc citation) also resolved in the same
   commit.
2. `8feb47a0` — docs-only follow-up fixing a SECOND round of citation drift
   that plan-review round 1 caught (see below) — the B-pass's own Finding 3
   fix had been re-verified before Finding 2's fix landed, not after, so two
   `docs/diagnoses/2026-09-23-confirm-email-supabase-not-ready-race-42a98d.md`
   citations were still stale in the actual committed diff despite the
   review file claiming otherwise. No code change.

Both commits were rebased onto a newer `origin/main` (7 unrelated upstream
commits, PRs #42/#44) after round 2 completed, to make the branch
mergeable — see "Rebase" below.

## Review timeline (2 rounds + 1 B-pass, all independent/context-blind)

1. **B-pass** on the original (unreordered) draft: 3 findings (1 P1, 1 P2,
   1 P3), 0 false alarms, all fixed/resolved before commit. `docs/reviews/
   cac1e4ee9414-review.md`, `verdict: accepted`.
2. **Plan-review round 1** (dispatched fresh, context-blind, against commit
   `ff3e5434` as it stood — since superseded by rebase, see below):
   **NOT fully converged on first pass** — independently re-verified the
   ordering fix against the actual installed `supabase_flutter`/`gotrue`
   package source (not assumed), independently mutation-proved the
   regression test by editing the code, confirming red, reverting, and
   confirming clean/green again — but found the diagnose-doc's B-pass
   Finding 3 "fixed" claim had not actually held: two file:line citations
   (`symptom:` prose and the `readers:` YAML field) were still wrong in the
   final committed state, because Finding 2's own fix landed after Finding
   3's re-verification pass and shifted the same lines again. Fixed in
   `8feb47a0` (then `docs/reviews/cac1e4ee9414-review.md`'s Finding 3
   `status:` updated to document the full, honest history rather than
   silently rewriting it).
3. **Plan-review round 2** (dispatched fresh, context-blind, with no memory
   of round 1's conclusions, explicitly instructed to verify everything
   itself including round 1's own two fixes and to try a *different*
   mutation than round 1 used): **CONVERGED** on the code and documentation.
   Independently traced the root-cause mechanism three packages deep
   (`supabase_service.dart` → `supabase_auth.dart` → `gotrue_client.dart`),
   confirming `setInitialSession` sets `_currentSession` synchronously with
   no intervening `await`, and separately confirmed the one network call in
   `Supabase.initialize()` (`recoverSession()`) is fire-and-forget
   (`CancelableOperation.fromFuture`, not awaited) — strengthening the
   B-pass's Finding 2 "hang risk is narrow" resolution with a concrete
   mechanism neither the fix nor the B-pass had stated. Independently
   verified all 9 file:line citations in the diagnose-doc (including
   re-confirming round 1's two corrections) — all accurate, no third stale
   citation found. Ran an independent mutation (`return;` → `{}`, i.e.
   swallow-and-fall-through instead of short-circuit) distinct from round
   1's — reddened as expected, reverted clean. Confirmed the single
   production call site (`confirm_email_screen.dart:75`) has no
   loading-state assumption broken by the reorder. `flutter analyze
   lib/features/auth/` clean. Two non-code items flagged as needing
   resolution before merge (not before push): the branch was 7 commits
   behind `origin/main` (conflicts confined to 2 auto-generated index
   files, real fix files merge clean — confirmed via read-only
   `git merge-tree`), and this keystone record did not yet exist. Both
   addressed below/by this file.

## Rebase (post round-2, pre-merge)

`git rebase origin/main` — 2 conflicts, both in auto-generated index files
(`docs/audit/OPEN_INDEX.md`, `docs/diagnoses/INDEX.md`), resolved by
regenerating them from their own generators
(`scripts/build_oi_index.dart`, `scripts/build_bug_index.dart`) rather than
hand-resolving conflict markers, exactly as round 2's `git merge-tree`
dry-run predicted. Every other touched file (`auth_provider.dart`,
`docs/sot_registry.yaml`, the diagnose-doc, the review file, `lib/features/
auth/CLAUDE.md`) auto-merged with zero conflicts — confirmed neither file
was touched by any of the 7 upstream commits
(`git diff --stat 6bf13072..280bf52e -- <those paths>`: empty). Re-verified
post-rebase: `check_sot_registry_parity.dart` PASS, `validate_diagnose_doc.dart`
OK, all 17 confirmEmail-related tests green, `flutter analyze
lib/features/auth/` clean. Original pre-rebase SHAs `ff3e5434`/`085d407f`
became `ad595244`/`8feb47a0`; content identical, only parent history changed.

## Ground truth (independently re-verified across both rounds, not merely asserted)

- Root cause: live Supabase `auth_logs` (ClickHouse, `source = 'auth_logs'`)
  queried across two real founder reproductions, confirming `POST /resend`
  succeeded while `POST /verify` never reached the server — proving the
  failure is client-side, before any network attempt.
- The ordering mechanism verified against the actual installed package
  source in the pub cache (`supabase_flutter-2.17.1`, `gotrue-2.27.1`), not
  assumed from prose, by both round 1 and round 2 independently, with round
  2 tracing one layer deeper than round 1.
- `test/contracts/confirm_email_readiness_behavioral_test.dart` (3 cases)
  and the 2 sibling test files: 17/17 green, confirmed by the B-pass, round
  1, and round 2 independently, each also running and reverting their own
  mutation.
- `dart run scripts/check_sot_registry_parity.dart`: PASS, 0 errors — this
  batch itself fixed 2 stale line-range citations
  (`signOutInProgress`/`signOut`) that the reordering fix's line-shift
  broke, caught by the gate at commit time.
- `dart run scripts/validate_diagnose_doc.dart`: OK, checked after every
  edit to the diagnose-doc across both rounds and again post-rebase.
- `flutter analyze` clean on every touched `lib/` file, every round and
  post-rebase.
- `docs/audit/open_issues.md`'s OI-244 entry independently checked for
  internal consistency against the diagnose-doc's own claims by round 1.

## Residual, explicitly out of scope for this branch

1. **Not yet deployed to Vercel production.** Requires separate, explicit
   founder authorization per CLAUDE.md §4.3 before this fix takes live
   effect — this record covers mergeability to `main`, not the deploy step.
   Distinct from, and in addition to, the deploy authorization already
   given for `f92d17`.
2. **Android App Links not claiming `/confirm`** on real devices — separate
   root cause (likely Play App Signing certificate mismatch), tracked under
   OI-244, unaffected by either fix on this branch or `claude/
   oi-242-flaky-test-filing`, needs the founder's own Play Console check.
3. **Tier 11 (external services) not re-queried this round.** Round 2
   noted it did not re-run the live ClickHouse `auth_logs` query — the
   B-pass and the original diagnose already did, and nothing in this
   batch's docs-only/reordering-only diff could change what that query
   would show.

## Verdict

**Converged.** 1 B-pass + 2 independent context-blind plan-review rounds,
round 1's finding (stale diagnose-doc citations, a second-order drift from
Finding 2's own fix) independently fixed and then independently
re-confirmed accurate by round 2, which found no further material issue in
either the code or the documentation. Rebased cleanly onto current
`origin/main` with zero conflicts outside auto-generated index files. Safe
to merge to `main`.
