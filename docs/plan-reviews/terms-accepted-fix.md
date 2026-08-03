---
branch: terms-accepted-fix
date: 2026-08-02
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/69feb22879b4-review.md
---

# Plan-review record — terms-accepted-fix (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Account-tier — auth/service code only (confirmed live via
`dart run scripts/blast_radius_from_diff.dart`, no-arg form, against the actual staged file
set — not assumed).

**Tier corrected mid-batch (2026-08-02, after both review rounds, at actual commit time):**
the plan reviewed by both rounds below staged a NEW migration file under
`supabase/migrations/**`, which `docs/blast_radius.yaml` declares `platform` unconditionally
regardless of apply-state — `platform` was the right tier for that staged set, and both
rounds reviewed it as such. At commit time, `check_migrations_applied.dart` (Gate 14) and
`check_applied_migrations_ledger.dart` (Gate 39) both hard-failed: neither recognizes a
"prepared but not applied" migration file, and Gate 39 requires every ledger entry's
`applied_at` to be real and non-null — there is no way to stage the file honestly without
either applying it live (not authorized) or fabricating a timestamp (rejected). The migration
file was removed from this batch (verbatim SQL preserved in the diagnose-doc's "Prepared
backfill SQL" section; ships together with the real apply + ledger entry in a future commit),
dropping the tier to `account`. This does not reopen either review round: neither round's
findings depended on the migration file's mere presence in the commit — Finding 2 (B-pass)
concerned value-semantics convergence between the migration and the runtime fallback, which
the already-shipped code fix preserves regardless of when the file itself lands. `bpass:
accepted` was earned at the higher tier and remains accurate. Not catastrophic → no Hermes.

## Scope

Fixes diagnose [b3f9e7](../diagnoses/2026-08-02-terms-accepted-dead-write-b3f9e7.md):
`users.terms_accepted_at` / `terms_version` were 100% NULL for every production row because the
2026-05-16 fix's write executed before `HiveUserSession.openForUser` had run, so the Hive box
getter threw `StateError` on every single call, silently swallowed by `catch (_) {}`. Three-part
fix: (A) relocate the email-signup write into `_ensureLocalUser`, after the Hive session is
actually open; (B) add a Google-OAuth/phone-OTP consent fallback (neither auth path had any
consent capture at all); (C) design — but do not commit or apply — a backfill migration for 19
pre-existing NULL rows (SQL finalized and founder-approved; the standalone file ships together
with the actual apply in a future commit, per the tier-change note above). Plus (D) real
behavioral tests (the original bug shipped undetected for 2.5 months specifically because its
regression test was pure source-grep) and (E) documentation.

## Review arc (2 rounds; §4.12)

- **Round 1 — context-blind, ground-truth-verified (fresh Sonnet subagent).** Tasked with
  verifying the diagnose-doc's claims against live code independently, not trusting prose —
  including the plan's own. Verdict: **issues-found (1 blocking)**. Re-traced the root cause from
  scratch (confirmed accurate), checked completeness of the fix's reach (clean), and specifically
  traced whether Part B's fallback was reachable for EVERY auth method it claimed to cover.
  Finding: **`AuthSessionBootstrapper.hydrateFromCloud` — the method the fallback was wired
  into, and whose own doc comment calls it "the single place every post-auth path converges
  on" — has exactly one real call site in the repo, inside `_ensureLocalUser`, which
  `signInWithGoogle()` never reaches** (OAuth only starts the redirect and returns; the
  post-redirect re-entry is `RestoringScreen`, which calls `resolveDestination` +
  `restoreFromCloudForUser`, neither of which is `hydrateFromCloud`). Net effect: phone OTP was
  genuinely fixed, but Google OAuth — the plan's own named reason NOT to defer Part B ("went live
  in production today") — was left with the exact pre-fix defect. Independently re-verified by me
  (not taken on faith) before accepting: traced `signInWithGoogle()`, `hydrateFromCloud`'s one
  call site, `_ensureLocalUser`'s 4 callers, and `RestoringScreen._kickoffRestore`'s actual call
  chain myself, all confirming the finding.

  **Fix:** extracted `AuthSessionBootstrapper.ensureTermsConsentFallback(userId)` as a
  standalone public method. Called from BOTH `hydrateFromCloud`'s else-branch (phone OTP) AND
  two new call sites in `RestoringScreen` — `_goHome`'s fast branch and the end of
  `_ensureOwnershipBeforeHome` — both positioned after `HiveUserSession.openForUser` is
  confirmed open, covering the warm-resume and cold-start cohorts respectively. Also fixed 2
  non-blocking findings from round 1: corrected 4 stale file:line citations (diagnose-doc +
  SoT registry), and confirmed the OAuth/OTP fallback's `created_at`-based stamp (a same-day
  B-pass finding, see below) already made it race-free against migration 118. `lib/features/auth/CLAUDE.md`'s
  "Post-auth flow" section (which itself asserted the false `hydrateFromCloud()` convergence
  claim — the root confusion source) corrected in the same edit. New debugging-skill entry
  §2.48 codifies the class: "a 'single convergence point' comment is trusted instead of
  verified."

- **Round 2 — independent context-blind review of the round-1 correction (fresh Sonnet
  subagent).** Per §4.12: "the corrections themselves can introduce new defects." Tasked with
  re-verifying round 1's finding was real (not a false alarm) and specifically hunting for new
  defects the fix itself might have introduced — dispose races, double-fire, precondition
  violations, redundant work. Verdict: **converged — no blocking issues.** Independently
  re-traced the entire call graph from scratch (did not read round 1's writeup as ground truth
  without re-verifying), confirmed both new `RestoringScreen` call sites are positioned after
  Hive-open **by construction** (traced `HiveUserSession._openForUserLocked` itself to confirm
  the "owner already matches" fast-path genuinely implies boxes are open, not an optimistic
  early flag), confirmed no dispose-race (`AuthSessionBootstrapper` is a ref-free singleton),
  and confirmed no double-fire within a single `_goHome` invocation (the two branches are
  mutually exclusive). Found and I fixed 3 concrete, non-blocking issues in the same session:
  1. `ensureTermsConsentFallback`'s `userBox` access sat outside its own try/catch — moved
     inside so a (currently unreachable) precondition violation routes through
     `ErrorTelemetry.recordNonFatal` like every sibling method, instead of surfacing as an
     unhandled async exception.
  2. The new `RestoringScreen` wiring test was presence-only (`.contains()`) — would not have
     caught a future edit reordering either call before its `openForUser`, or deleting one of
     the two call sites. Strengthened to a method-bounded `indexOf` ordering check (mirroring
     the existing `auth_provider.dart` ordering-guard test's rigor), per the reviewer's exact
     recommendation.
  3. 4 more stale file:line citations (introduced BY round 1's own correction — the extraction
     shifted line numbers and the citations weren't re-derived) — corrected, including the SoT
     registry's `hydrateFromCloud` `line_range`, which had drifted far enough to point at the
     wrong method entirely.

  One informational (no-fix) finding: every returning email/OTP login now redundantly-but-safely
  fires `ensureTermsConsentFallback` twice (once via `hydrateFromCloud`, once via
  `RestoringScreen`) because `/restoring` is reached by every auth method, not just OAuth —
  traced as strictly sequential (not concurrent) and idempotent via the method's own guard.
  Documented in the diagnose-doc for future-reader clarity; not a defect.

## Ground truth verified, not assumed

Every claim in the diagnose-doc's `touched_layers_checked` and `impact_analysis` was checked
against live tooling by at least one of the two review rounds (not taken on the author's word):
`guarded_box.dart`'s actual throw condition, the live `blast_radius_from_diff.dart` classifier
output, `docs/blast_radius.yaml`'s literal glob rule, the full call graph for every auth method
(`signInWithEmail`/`signUpWithEmail`×2/`verifyOtp`/`signInWithGoogle`), `backups/applied_migrations.json`
(migration 118 confirmed NOT applied), and `flutter test`/`flutter analyze` run independently by
each reviewer rather than trusting a prior "green" claim.

## Known, honestly-scoped residual (not part of this batch)

While tracing the OAuth call graph, found (via static code tracing only, NOT yet live-confirmed)
that a brand-new Google OAuth signup who has not yet completed onboarding may hit a separate,
more severe `StateError` during `completeOnboarding()` — the Hive session is never opened before
then for that specific auth path, unlike email/OTP. This is a DIFFERENT root cause (onboarding
bootstrap ordering, not terms-consent) and a materially larger, different-shaped unit of work.
Both review rounds confirmed the diagnose-doc frames this honestly (explicitly titled "NOT
covered," hedged language, tracked as a Follow-up requiring live confirmation) rather than
silently folding it in or hiding it. Filed as a separate spawned investigation task, not bundled
into this branch.

## Verification

`flutter analyze` clean on all 6 touched Dart files. `flutter test` on
`terms_acceptance_behavioral_test.dart` + `terms_acceptance_writer_to_reader_test.dart` +
`terms_skip_test.dart` + `auth_session_bootstrapper_test.dart` → 48/48 green (re-run
independently by both review rounds, not just the author). Live browser E2E (real signup,
confirm non-NULL cloud row) attempted but blocked by a session-level environment limitation
(Browser pane could not composite frames — confirmed via a control test on a plain static
site failing identically) — not claimed as verified.

## Convergence

Round 1 found one blocking, design-level issue (a false "convergence point" premise) — fixed
by extracting and correctly re-wiring the fallback. Round 2, reviewing that fix specifically for
new defects, found none blocking — only 3 small, independently-fixed hardening items (defensive
catch placement, test rigor, citation drift) and 1 informational no-fix note. No new *material*
issue surfaced in round 2 (the §4.12 "keeps-finding-new-issues → split" signal did not fire) —
the unit is converged, not oversized.

**Verdict: converged.**
