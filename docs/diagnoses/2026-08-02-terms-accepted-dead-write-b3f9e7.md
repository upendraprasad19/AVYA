---
bug_id: b3f9e7
date: 2026-08-02
batch: terms-accepted-fix
status: fixed
symptom: |
  Founder spotted `users.terms_accepted_at` / `terms_version` NULL for
  every row in the live Supabase dashboard, including a row created the
  same day (2026-08-02 13:11:55, hours before this investigation). This
  is the EXACT symptom already diagnosed once in
  2026-05-16-terms-accepted-at-dpdp — that fix shipped 2026-05-16 and was
  believed closed. Live proof this session: the 10 most recent signups
  (spanning 2026-06-26 through 2026-08-02) are ALL still NULL on both
  columns — the original fix never once succeeded, for any user, in the
  2.5 months since it shipped.
concept: terms_acceptance
sot_registry_entry: terms_acceptance
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "_ensureLocalUser (email signup)", line: 695 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "ensureTermsConsentFallback (extracted; phone-OTP path calls it via hydrateFromCloud's else-branch)", line: 211 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_goHome fast-path call site (Google OAuth's REAL convergence point — see plan-review round 1)", line: 240 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_ensureOwnershipBeforeHome call site (second of the two OAuth call sites — covers the cold-start cohort _goHome's fast branch doesn't)", line: 503 }
readers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "hydrateFromCloud (Hive-to-cloud upward sync, email/OTP path only)", line: 287 }
hive_key_prefix: "terms_accepted_at | terms_version"
hive_key_formula: "literal keys on userBox (per-user scoped via HiveUserSession)"
sync_methods: [_ensureLocalUser, hydrateFromCloud]
restore_methods: [hydrateFromCloud]
cloud_table: users
cloud_columns: [terms_accepted_at, terms_version]
contract_test_path: test/contracts/terms_acceptance_behavioral_test.dart
ist_handling:
  - "Not applicable — terms_accepted_at is a timestamptz instant, stamped with DateTime.now().toUtc().toIso8601String(). The IST date-key contract (CLAUDE.md §15) applies to date columns / Hive date-key strings, not instants. Unchanged from the original 2026-05-16 fix's (correct) reasoning on this point."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [users_upsert_failed, users_unique_violation_23505, users_fk_violation_23503]
cross_account_guard: |
  Unchanged from the original diagnose doc's analysis: userBox is per-user
  scoped via HiveUserSession, so cross-account writes are impossible by
  construction. This fix does not touch that guard — it only moves WHEN
  the write happens (from before HiveUserSession.openForUser to after),
  not the ownership model itself. The new insertion point in
  _ensureLocalUser is deliberately placed AFTER the existing cross-account
  clear-guard (auth_provider.dart:552-588) completes, specifically so a
  device that previously held a different user's session (clearAllData()
  fires) can't wipe a terms write placed too early in the method.
forbidden_patterns_checked:
  - { pattern: "HiveService.instance.userBox.put(...) called synchronously inside sign_in_screen.dart's onPressed, before signUpWithEmail/HiveUserSession.openForUser has run", absent: true, after_fix: true }
  - { pattern: "AppConstants.termsVersion (not a hardcoded literal)", absent: false }
  - { pattern: "DateTime.now().toUtc().toIso8601String() (not naive local)", absent: false }
related_bugs: [2026-05-16-terms-accepted-at-dpdp]
recurrence: |
  This is the SAME symptom as 2026-05-16-terms-accepted-at-dpdp, but a
  NEW root cause — the original diagnosis correctly identified that the
  Q2 inline-checkbox UI never wrote to Hive, and its fix correctly added
  a Hive write. What that fix's author (and its source-grep regression
  test) missed: the write was placed at CREATE ACCOUNT tap time, BEFORE
  any Supabase session exists — so HiveUserSession.openForUser has never
  run, and HiveService.instance.userBox itself throws StateError before
  .put() can execute. The write was wrapped in try/catch (added
  specifically because Hive write failure was anticipated as POSSIBLE),
  which silently swallowed a throw that in fact happened on EVERY call,
  not occasionally. The regression test
  (test/contracts/terms_signup_writes_test.dart) is pure source-grep — it
  asserts the write CALL is present in the file text and lexically before
  signUpWithEmail(), which was true, and is structurally incapable of
  detecting that the call throws every time it executes. Per
  feedback_source_grep_false_confidence.md: source-grep tests are
  presence-only; this is the canonical example of why a
  behavioral_test_path (a real Hive round-trip) is required per SoT
  registry entry, not just presence pinning. Nobody ran the "manual: live
  SQL post-deploy must show non-NULL" verification step the original
  diagnose-doc called for — the gap sat undetected for 2.5 months until a
  founder manually browsing the Supabase dashboard noticed it today.
proposed_fix: |
  Three-part fix, per the founder-approved plan:
  1. Move the write out of sign_in_screen.dart's onPressed entirely.
     signUpWithEmail gains optional termsAcceptedAt/termsVersion params,
     threaded to both of its _ensureLocalUser call sites. _ensureLocalUser
     writes to userBox AFTER HiveUserSession.openForUser (line 526) has
     run AND after the cross-account clear-guard completes (line 588),
     BEFORE hydrateFromCloud (so the existing, unchanged upward-sync picks
     it up in the same pass) — auth_provider.dart:695-708.
  2. Google OAuth (live in prod as of today) and phone OTP (feature-flagged
     off, Twilio not yet wired) have NO Hive-side consent write at all —
     OAuth is a redirect flow with no synchronous response.user, so it
     never reaches a call site that could stamp Hive at tap time; OTP has
     no checkbox UI. Consent-fallback logic lives in
     AuthSessionBootstrapper.ensureTermsConsentFallback: if Hive has no
     value, check the cloud row; if that's also empty, stamp
     terms_accepted_at=created_at (not now() — converges with migration
     118's backfill value regardless of which runs first) +
     terms_version=AppConstants.termsVersion directly to cloud and mirror
     to Hive. Decision logic extracted into a pure
     shouldStampFallbackTermsConsent helper (same @visibleForTesting
     pattern as the existing classifyDestination) so it never clobbers a
     returning user's real historical timestamp.
     **CORRECTION (plan-review round 1, 2026-08-02):** the first
     implementation wired this fallback ONLY into
     AuthSessionBootstrapper.hydrateFromCloud's else-branch, believing (per
     hydrateFromCloud's own doc comment) that it was "the single place
     every post-auth path converges on." That premise was WRONG for Google
     OAuth: `signInWithGoogle()` only starts the OAuth redirect and
     returns — it never calls `_ensureLocalUser`, and `hydrateFromCloud`
     has exactly one call site in the whole repo (inside
     `_ensureLocalUser`). The actual post-redirect re-entry point is
     `RestoringScreen._kickoffRestore` (→ `resolveDestination` +
     `SyncService.restoreFromCloudForUser`), which never touched
     `hydrateFromCloud` either. Net effect of the first implementation:
     phone OTP was genuinely fixed (verifyOtp DOES reach
     `_ensureLocalUser`), but Google OAuth — the channel this plan named as
     the reason NOT to defer this work — was NOT, identical to the pre-fix
     defect. Caught by an independent context-blind plan-review (not the
     B-pass, which reviews line-level bugs, not design reachability) before
     merge. Fixed by extracting the fallback into a public
     `ensureTermsConsentFallback(userId)` method and calling it from BOTH
     `hydrateFromCloud`'s else-branch (phone OTP) AND `RestoringScreen`'s
     returning-user path (`_goHome`'s fast branch + the end of
     `_ensureOwnershipBeforeHome`) — the real point every OAuth session
     converges on, guarded by the same precondition (Hive session already
     open) that is the entire subject of this diagnose-doc. See
     `docs/plan-reviews/terms-accepted-fix.md` for the full review record.
  3. Backfill migration for the 19 pre-existing NULL rows:
     UPDATE users SET terms_accepted_at = created_at, terms_version = 'v1'
     WHERE terms_accepted_at IS NULL — a founder-approved best-effort
     proxy (the pre-checked checkbox gated the CREATE ACCOUNT button even
     though the Hive write silently failed, so consent was arguably given
     at created_at). This is a live prod data write and requires its own
     explicit go separate from this plan's approval, per CLAUDE.md §4.3.
     **Discovered at commit time:** the standalone .sql file is NOT
     committed in this batch — Gate 14 + Gate 39 (§6 tier 5) both require
     a real, non-null `applied_at` ledger entry paired with any committed
     migration file, so "prepared but not applied" cannot land as a file
     in `supabase/migrations/` today. The verbatim SQL is preserved in
     this doc's "Prepared backfill SQL" section and ships together with
     the actual apply + ledger entry in one future commit.
regression_test_planned:
  - test/contracts/terms_acceptance_behavioral_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "sign_in_screen.dart / auth_provider.dart / auth_session_bootstrapper.dart edited; flutter analyze run this batch." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "test/contracts/terms_acceptance_behavioral_test.dart proves a real userBox write now succeeds after HiveUserSession.openForUser, and throws before it (reproducing the exact pre-fix defect) — a genuine Hive round-trip, not source-grep." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "terms_accepted_at/terms_version columns already exist (migration 032, 2026-04-20). No schema change in this fix." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "Live SQL 2026-08-02: 10 most recent users all NULL on both columns pre-fix, confirming the defect was live and total, not partial. Live SQL 2026-08-03T10:04:53+05:30 (immediately post-migration-118 apply): a fresh `count(*) WHERE terms_accepted_at IS NULL` returned 0, down from the pre-apply count of 19." }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "Backfill migration 118 applied live 2026-08-03T10:04:53+05:30 (project dedsavbjuwgarrhphgnl), backfilling all 19 pre-existing NULL rows to created_at/'v1'. Ledger entry recorded in backups/applied_migrations.json (hash sha256:16c8afcb...28332). File committed to supabase/migrations/118_backfill_terms_accepted_historical_rows.sql in the same follow-up commit as this doc update, per the file+ledger+apply atomicity Gate 14/39 require — see 'Prepared backfill SQL' section below, now updated to reflect apply." }
  - { tier: 6, layer: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched by this fix." }
  - { tier: 7, layer: cron_jobs, status: not_applicable, evidence: "No cron job touched." }
  - { tier: 8, layer: rls_policies, status: not_applicable, evidence: "No RLS policy change — the fix is client-side write timing plus an existing authenticated-user upsert path." }
  - { tier: 9, layer: storage_buckets, status: not_applicable, evidence: "No storage interaction." }
  - { tier: 10, layer: secrets_api_keys, status: not_applicable, evidence: "No secret/key touched." }
  - { tier: 11, layer: external_services, status: not_applicable, evidence: "No external service (Razorpay/OneSignal/Firebase) touched." }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "Email-signup path + Google-OAuth returning-user path + phone-OTP path all now call ensureTermsConsentFallback/the direct write from a point after Hive session is confirmed open — verified by static tracing of the full call graph (grep -rn for every _ensureLocalUser/hydrateFromCloud/ensureTermsConsentFallback call site) + 47/47 targeted tests. Live browser E2E (real signup, confirm non-NULL cloud row) attempted but BLOCKED by an environment limitation (Browser pane could not composite frames this session, confirmed via a control test on a static site) — not claimed as verified; see Verification section." }
impact_analysis: |
  Blast-radius account — confirmed live via
  `dart run scripts/blast_radius_from_diff.dart` (no-arg form, reads
  `git diff --cached --name-only`) against the actual staged file set, NOT
  assumed. The auth/service files (lib/features/auth/**,
  lib/core/services/auth_session_bootstrapper.dart) are `account` tier.
  An earlier state of this batch also staged a NEW migration file under
  `supabase/migrations/**`, which docs/blast_radius.yaml declares
  `platform` unconditionally (line 62) regardless of apply-state — both
  plan-review rounds and the B-pass reviewed the batch at that `platform`
  tier. At actual commit time, `check_migrations_applied.dart` (Gate 14)
  and `check_applied_migrations_ledger.dart` (Gate 39) both hard-failed:
  neither recognizes a "prepared but not applied" migration file, and
  Gate 39 requires a real, non-null `applied_at` on every ledger entry.
  The migration file was removed from this batch as a result (verbatim
  SQL preserved below in "Prepared backfill SQL"; ships together with the
  real apply + ledger entry in a future commit), correctly dropping the
  tier to `account`. The change surface is narrowly scoped: the code-only
  portion purely relocates a WHEN-to-write for email signup (same values,
  same destination, different timing) plus a net-new, narrowly-scoped
  OAuth/OTP fallback that only ever fires when both Hive AND cloud are
  already empty (cannot regress an existing correct value). Per CLAUDE.md
  §4.3, an account-tier batch needs a self-initiated /code-review (B-pass)
  before merge to main — already run, at the higher `platform` tier this
  batch carried during review, and still valid (none of its findings
  depended on the migration file's presence). Per §4.12.3 a plan-review
  record (review_rounds >= 2) is required regardless of tier; both rounds
  ran, self-triggered in this same session, not deferred.
blast_radius: account
---

# `terms_accepted_at` / `terms_version` write is dead code — throws before Hive session opens, silently swallowed

## Symptom

Founder was browsing the live `users` table in the Supabase dashboard and
noticed `terms_accepted_at` and `terms_version` NULL for every visible row,
including one created the same day. This is the exact symptom
`2026-05-16-terms-accepted-at-dpdp` diagnosed and (believed) fixed two and a
half months earlier.

Live SQL this session:

```sql
select id, created_at, terms_accepted_at, terms_version, full_name
from public.users
order by created_at desc
limit 10;
```

All 10 most recent rows — spanning 2026-06-26 through **2026-08-02
13:11:55** (hours before this investigation) — show
`terms_accepted_at: null, terms_version: null`.

## Root cause

The 2026-05-16 fix added, at `sign_in_screen.dart`'s CREATE ACCOUNT
`onPressed` handler:

```dart
try {
  HiveService.instance.userBox.put('terms_accepted_at', ...);
  HiveService.instance.userBox.put('terms_version', ...);
} catch (_) {}
authNotifier.signUpWithEmail(email, password);
```

At the moment CREATE ACCOUNT is tapped, no Supabase session exists yet —
`signUpWithEmail`/`auth.signUp()` hasn't been called. `HiveService.instance
.userBox` is `userBoxGuarded.rawBox`, and `userBoxGuarded` resolves through
`wrapUserScopedBox` (`guarded_box.dart:229-343`). With no auth uid and no
`HiveUserSession.currentOwnerFullId` set, every fallback branch in that
function is unreachable, and it falls through to:

```dart
throw StateError(
    'HiveUserSession not opened — cannot wrap user-scoped box "$root". '
    'Call HiveUserSession.openForUser(userId) after sign-in.',   // guarded_box.dart:335-337
);
```

`HiveService.instance.userBox` throws while merely being *evaluated* —
`.put()` never runs. The `catch (_) {}` (added specifically because a Hive
write failure was anticipated as *possible*) silently swallowed a throw
that in fact happened on **every single call**, not occasionally.

`HiveUserSession.openForUser` only runs inside `_ensureLocalUser`
(`auth_provider.dart:526`), which itself only runs *after* `auth.signUp()`
resolves — i.e., strictly after the broken write already ran and failed.

## Why this is a recurrence, not a duplicate

The original diagnosis correctly identified the missing write (the Q2
inline-checkbox refactor dropped the old `TermsModal`'s Hive write) and
correctly added one back. What it missed: *where* to put it. Its own
regression test, `test/contracts/terms_signup_writes_test.dart`, is pure
source-grep — it asserts the write call's string is present and lexically
before `signUpWithEmail(`, which was true, and cannot detect that the call
throws every time it executes. The doc's own "Verification" section called
for a manual live-SQL check post-deploy; nothing on record shows it was
ever run, and no CLAUDE.md gate enforces that follow-up mechanically. The
gap sat live and undetected for 2.5 months.

## Fix

See `proposed_fix` in the frontmatter for the full three-part shape
(email-signup write relocation, OAuth/OTP fallback, historical backfill).
In short: the write moved out of the pre-auth UI handler entirely and into
`_ensureLocalUser`, executed only after `HiveUserSession.openForUser` has
actually opened the box — where it can succeed. Google OAuth (live in prod
as of today) and phone OTP (flagged off pending Twilio) had no consent
capture at all; `AuthSessionBootstrapper.ensureTermsConsentFallback` now
closes that gap for both, guarded by a pure, unit-tested predicate so it
can never overwrite a real historical value — called from
`hydrateFromCloud` for phone OTP and from `RestoringScreen`'s
returning-user path for Google OAuth (see the frontmatter's `proposed_fix`
CORRECTION note for why both call sites are needed).

## Note — redundant-but-safe double-fire for email/OTP logins

Plan-review round 2 (2026-08-02) traced that `/restoring` is reached by
**every** auth method, not just OAuth (`sign_in_screen.dart` routes there
unconditionally on `AuthStatus.success`). So a returning email/OTP user's
login now fires `ensureTermsConsentFallback` twice: once inside
`hydrateFromCloud` during `_ensureLocalUser` (fully awaited before
navigation), once more from whichever `RestoringScreen` branch runs after
`/restoring` mounts. Confirmed safe — the two calls are strictly sequential
(not concurrent) for a single login, and the method's own guard
(`if (localTermsAcceptedAt is String...) return;`) makes the second call a
same-tick no-op once the first has landed. No fix needed; noted here so a
future reader isn't surprised finding two call sites firing for the same
login.

## Known residual gap — NOT covered by this fix (investigate separately)

While tracing Google OAuth's actual post-auth call chain for the
correction above, found evidence (static-code tracing, NOT yet live-
confirmed) that a **brand-new** Google OAuth signup who has not yet
completed onboarding may hit a SEPARATE, more severe problem: onboarding
accumulates all answers in-memory (`OnboardingNotifier.state.answers`,
via `GoRouter` route extras) and only writes to Hive once, at
`completeOnboarding()` on the Plan screen's final tap
(`lib/features/onboarding/CLAUDE.md`, "State passing" section). Nothing
in `lib/features/onboarding/` calls `HiveUserSession.openForUser` — for
email/OTP users this is harmless because `_ensureLocalUser` already
opened the session before onboarding ever starts, but a fresh Google OAuth
signup reaches `/onboarding/mission-brief` (via `RestoringScreen`'s
`StartMissionBrief` branch, which does NOT open Hive) with **no Hive
session ever opened**. `GuardedBox.empty(...)` (`guarded_box.dart:39-41`)
throws `StateError` on WRITES for an authenticated-but-owner-null caller
(by design, so an in-flight sync can't leak into the wrong box) — so
`completeOnboarding()`'s `userBox['profile'] = ...` write may throw for
every brand-new Google OAuth signup today. This is a DIFFERENT bug
(onboarding-completion write ordering, not terms-consent specifically) in
the same bug CLASS this doc documents (a write placed somewhere the
required precondition was never satisfied) — filed separately (see
Follow-ups) rather than fixed here: confirming and fixing it correctly
needs its own investigation of the full onboarding bootstrap, which is a
materially larger, different-shaped unit of work than this diagnose-doc's
scope. This diagnose-doc's fix is honestly scoped to **returning** OAuth
users (`RestoringScreen`'s `GoHome` path) — not new signups still mid-
onboarding.

## Verification

```
$ flutter test test/contracts/terms_acceptance_behavioral_test.dart test/contracts/terms_acceptance_writer_to_reader_test.dart test/auth/terms_skip_test.dart test/contracts/auth_session_bootstrapper_test.dart
```

47/47 green, including new tests pinning: the ordering regression guard
(B-pass finding 1) and the `RestoringScreen` → `ensureTermsConsentFallback`
wiring (plan-review round 1 finding).

Live end-to-end verification (real signup through the web build, confirm
the resulting row is non-NULL) was attempted this session but blocked by
an environment limitation unrelated to this code (the Browser pane could
not composite frames in this session — confirmed via a control test
against a plain static site, which also failed identically). Not claimed
as verified; flagged explicitly per the instruction to say so rather than
claim success.

## Backfill SQL — applied live 2026-08-03, staged for commit

**UPDATE (2026-08-03T10:04:53+05:30):** applied live to production
(`dedsavbjuwgarrhphgnl`) via `mcp__supabase__apply_migration`, per explicit
founder authorization ("apply backfill") separate from this batch's original
commit/merge/push go-ahead. Pre-apply live count was 19 NULL rows (matching
this doc's earlier audit); post-apply count is 0. The file was authored at
`supabase/migrations/118_backfill_terms_accepted_historical_rows.sql`
(verbatim match to the SQL preserved below) and a real ledger entry recorded
in `backups/applied_migrations.json` (hash `sha256:16c8afcb...28332`,
`applier: claude-via-mcp`). Both are staged in this worktree, not yet
committed — commit/merge/push of this follow-up requires its own separate
explicit go per CLAUDE.md §4.3, same boundary as the original fix.

The paragraph below is preserved verbatim from before the apply, for the
audit trail of the reasoning that led here (the migration-file/ledger-gate
conflict that forced the original commit to ship without this file):

The Part-C backfill SQL below is fully designed, founder-approved (proxy =
`created_at`, version = `'v1'`), and its value semantics are already
load-bearing in shipped code (`AuthSessionBootstrapper`'s OAuth/OTP fallback
converges to the identical `created_at` value — B-pass Finding 2). The
**standalone migration file itself was deliberately not committed in the
original batch**, discovered live at commit time: `check_migrations_applied.dart`
(Gate 14) and `check_applied_migrations_ledger.dart` (Gate 39) both hard-fail
pre-commit, and Gate 39 explicitly requires every ledger entry's `applied_at`
to be non-null/non-empty — there is no "prepared but not applied" state this
repo's gate infrastructure recognizes. `supabase/migrations/CLAUDE.md` confirms
this is the established convention, not a gap: "Every `apply_migration` call
MUST be paired with a `backups/applied_migrations.json` update in the same git
commit." Filing a real ledger entry with a fabricated timestamp to satisfy the
gate was rejected as dishonest bookkeeping. The file below shipped together
with the actual live apply + a real ledger entry, in this follow-up commit,
once explicitly authorized (CLAUDE.md §4.3) — verbatim, not re-derived from
memory:

```sql
-- Intent: One-time backfill of the 19 pre-fix NULL terms_accepted_at/terms_version rows using created_at as a founder-approved best-effort consent-timestamp proxy.
-- Destructive?: no   -- additive-only (WHERE terms_accepted_at IS NULL), never overwrites an existing real value; idempotent on re-run
-- Rollback strategy: inline   -- see commented-out reverse block at end of file; targets rows by the exact signature this migration creates (terms_accepted_at = created_at AND terms_version = 'v1')
-- Linked diagnose-doc: b3f9e7

-- closes-diagnose: b3f9e7
--
-- users.terms_accepted_at / terms_version were 100% NULL for every
-- production row because the write that was supposed to populate them
-- (added by the 2026-05-16 fix for 2026-05-16-terms-accepted-at-dpdp)
-- threw StateError on every signup and was silently swallowed — see
-- docs/diagnoses/2026-08-02-terms-accepted-dead-write-b3f9e7.md. The
-- code-level fix (auth_provider.dart / auth_session_bootstrapper.dart)
-- makes the write actually succeed going forward. This migration only
-- addresses the 19 rows that predate the fix.
--
-- Founder-approved proxy: the pre-checked ToS/Privacy checkbox gated the
-- CREATE ACCOUNT button even though the Hive write silently failed, so
-- consent was arguably given at signup time — created_at is used as the
-- best-effort timestamp. 'v1' matches the current AppConstants.termsVersion
-- (lib/core/constants/app_constants.dart) at the time of this migration.

UPDATE public.users
SET terms_accepted_at = created_at,
    terms_version = 'v1'
WHERE terms_accepted_at IS NULL;

-- Rollback (inline, commented out — run manually if this backfill needs
-- reverting). Targets only rows matching the exact signature this
-- migration creates; a genuine future consent timestamp landing bit-for-
-- bit identical to created_at is not realistically possible.
--
-- UPDATE public.users
-- SET terms_accepted_at = NULL,
--     terms_version = NULL
-- WHERE terms_accepted_at = created_at
--   AND terms_version = 'v1';
```

Confirmed at apply-time: 118 was still next (no intervening migrations
landed between this doc's drafting and the live apply).

## Follow-ups (tracked, not deferred)

- ~~Author the backfill migration file, apply it, and record it in
  `backups/applied_migrations.json`~~ — **done 2026-08-03**, see the UPDATE
  note above. Still owed: commit/merge/push of this staged follow-up work,
  its own separate explicit go per CLAUDE.md §4.3.
- Investigate the onboarding-completion / Hive-session-timing gap for
  brand-new Google OAuth signups described above — potentially urgent
  (Google OAuth is live in prod today) but a distinct root cause and unit
  of work from this doc's terms-consent fix. Needs live confirmation
  before treating as a confirmed bug.
- Live end-to-end verification (real web signup, confirm non-NULL row) —
  blocked this session by a Browser-pane environment limitation; retry in
  a session where the pane composites, or verify manually.
