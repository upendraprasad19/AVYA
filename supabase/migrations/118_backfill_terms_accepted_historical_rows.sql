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
