---
bug_id: b1f3a7
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: feature
symptom: >
  APK +34 obs 4 — the Profile avatar AND banner images re-download from the
  network every single time the user navigates to the Profile tab. They are not
  served from the local cache, so each visit shows a brief blank/reload and
  burns data, violating the Hive-first / offline-first expectation.
concept: profile_image_url_display
sot_registry_entry: profile_image_url_display
writers: >
  lib/features/profile/providers/profile_provider.dart uploadAvatar / uploadBanner
  now store ProfileImageUrl.versioned(publicUrl, version: now-millis) into
  userBox['profile']['avatar_url' | 'banner_url'] and the cloud user_profile row.
  The version token changes ONLY when a new image is uploaded (storage reuses a
  fixed object path `<uid>/avatar.jpg`, so the bare public URL is identical
  after a re-upload).
readers: >
  lib/features/profile/screens/profile/profile_content.dart (part of screen.dart)
  passes the stored URL to ProfileIdentity via ProfileImageUrl.forDisplay, which
  returns it VERBATIM. The previous reader, _ProfileScreenState._addCacheBuster,
  appended `?t=${DateTime.now().millisecondsSinceEpoch}` on every build — a new
  CachedNetworkImage disk-cache key per render → guaranteed cache miss → refetch.
hive_key_prefix: not_applicable (userBox['profile'] map fields avatar_url / banner_url)
hive_key_formula: not_applicable
sync_methods: lib/core/services/sync/sync_profile.dart _syncUserProfile (avatar_url / banner_url upsert)
restore_methods: lib/core/services/sync/sync_profile.dart _restoreUserProfile (avatar_url / banner_url pulled into Hive)
cloud_table: user_profile
cloud_columns: avatar_url, banner_url
contract_test_path: test/contracts/profile_image_url_stable_test.dart
ist_handling: >
  not_applicable — the version token is a real wall-clock millisecond stamp used
  purely as a cache-bust discriminator, not a date key, so it is intentionally
  NOT routed through istDateStr / nowWall (it must reflect the true upload moment
  and be monotonic across real uploads).
provider_invalidations:
  - userProfileProvider (invalidated after upload in screen.dart onReplaceAvatar / onReplaceBanner)
telemetry_op_types: not_applicable
cross_account_guard: >
  not_applicable for the fix itself — userBox is user-scoped and userProfileProvider
  already watches authUserIdTokenProvider; the URL carries no cross-account risk.
forbidden_patterns_checked:
  - "The profile image READ path must not inject a per-build cache-buster (DateTime.now() / millisecondsSinceEpoch / _addCacheBuster). Pinned by test/contracts/profile_image_url_stable_test.dart (comment-stripped source-grep) + the ProfileImageUrl.forDisplay stability spec."
proposed_fix: >
  Introduce lib/features/profile/utils/profile_image_url.dart with forDisplay
  (verbatim read) and versioned (upload-time `?v=<millis>` stamp, idempotent strip
  of any prior v/t). Read path (profile_content.dart) uses forDisplay; upload path
  (profile_provider.dart) stores the versioned URL in Hive + cloud; the obsolete
  _addCacheBuster method is removed from screen.dart.
regression_test_planned: >
  test/contracts/profile_image_url_stable_test.dart — (1) behavioral: forDisplay
  returns verbatim + identical across calls, null/empty → null; versioned is
  deterministic per version, differs across versions, and strips prior v / legacy
  t. (2) comment-stripped source-grep: profile_content uses ProfileImageUrl.forDisplay
  and no longer references _addCacheBuster; screen.dart no longer defines it;
  profile_provider versions both avatar + banner uploads.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "ProfileImageUrl helper + read pass-through + upload versioning + _addCacheBuster removed; flutter analyze clean on the profile library; profile_image_url_stable_test green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "userBox['profile'].avatar_url/banner_url now hold the versioned URL; read path returns it unchanged so navigating to Profile is a CachedNetworkImage disk-cache hit" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "versioned URL stored in cloud user_profile.avatar_url/banner_url too, so a 2nd device cache-misses the new version exactly once after restore" }
impact_analysis: >
  Feature blast radius — Profile image rendering + data usage. Root cause was a
  per-build cache-buster used as a blunt re-upload-refresh mechanism; it defeated
  ALL caching. The versioned-on-upload contract preserves the "show the new image
  immediately after re-upload" behaviour (the version travels in the stored +
  synced URL, so every device refetches exactly once) while restoring cache hits
  for normal navigation. No schema, sync-shape, or auth change. New SoT concept
  profile_image_url_display registered.
---

# Profile avatar/banner refetched on every navigation (cache-buster on read)

## What happened
APK +34 obs 4: the Profile avatar and banner reloaded from the network every
time the user opened the Profile tab.

## Root cause
`_ProfileScreenState._addCacheBuster` appended a fresh
`?t=${DateTime.now().millisecondsSinceEpoch}` to the avatar/banner URL on every
build (`profile_content.dart`). `CachedNetworkImage` keys its disk cache by URL,
so a new query string per render = a guaranteed cache miss = a refetch. It was a
blunt way to show a freshly re-uploaded image (storage reuses a fixed object
path → identical URL on re-upload; `imageCache.evict` only clears the in-memory
cache, not the disk cache).

## Fix
Bust the cache key only when the image actually changes: `ProfileImageUrl.versioned`
stamps `?v=<millis>` at upload time (stored in Hive + cloud); `ProfileImageUrl.forDisplay`
returns the stored URL verbatim on read. `_addCacheBuster` removed.

## Verification
`flutter analyze` clean on the profile library; `profile_image_url_stable_test.dart`
(forDisplay stability + versioned bust + comment-stripped source-grep). The
versioned URL persists in cloud so other devices refetch exactly once after a
re-upload.

## See also
- `lib/features/profile/utils/profile_image_url.dart`
- SoT concept `profile_image_url_display`
