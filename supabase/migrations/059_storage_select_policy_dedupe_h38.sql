-- H-38 Path 1 — dedupe duplicate SELECT policies on storage.objects for
-- avatars + banners buckets. Cosmetic cleanup; advisor
-- `public_bucket_allows_listing` still flags because buckets remain
-- public=true (intentional UX — avatar <img src> rendering).
--
-- Pre-state: 3 identical SELECT policies per bucket (created
-- accidentally over multiple manual dashboard tweaks). Each has the
-- same qual `bucket_id = 'avatars' | 'banners'` and the same `public`
-- role. The 3-way dupes are: "Allow public read X", "Anyone can view
-- X", "X are publicly accessible". We keep "Allow public read X" as
-- the canonical name (matches the naming used by the INSERT/UPDATE
-- policies on the same buckets).
--
-- Post-state: 1 SELECT policy per bucket. INSERT/UPDATE dupes (3 each)
-- intentionally left alone — out of scope for Path 1 / future cleanup.
--
-- Disposition: H-38 marked ACCEPTED. Public-bucket flag is intentional
-- for avatar/banner rendering; advisor warning is known + acknowledged.

DROP POLICY IF EXISTS "Anyone can view avatars" ON storage.objects;
DROP POLICY IF EXISTS "Avatars are publicly accessible" ON storage.objects;

DROP POLICY IF EXISTS "Anyone can view banners" ON storage.objects;
DROP POLICY IF EXISTS "Banners are publicly accessible" ON storage.objects;
