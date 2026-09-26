-- 032: Audit trail for Privacy Policy + Terms of Service acceptance.
--
-- Flutter client stamps `userBox['terms_accepted_at']` + `terms_version`
-- in Hive the moment the user taps "I ACCEPT" in TermsModal. The stamp is
-- forwarded to Supabase on the next post-auth users-row upsert, so we have
-- a server-side audit trail of who agreed to which policy version and when.
--
-- Re-prompting on policy revision: `AppConstants.termsVersion` in the
-- Flutter app is compared against the stored `terms_version` on every
-- launch. Mismatch = modal re-appears. After the user re-accepts, the
-- new version + timestamp overwrites the old.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS terms_version TEXT;

COMMENT ON COLUMN users.terms_accepted_at IS
  'UTC timestamp when the user accepted the ToS/Privacy modal (TermsModal).';
COMMENT ON COLUMN users.terms_version IS
  'ToS version string accepted (matches AppConstants.termsVersion in Flutter).';
