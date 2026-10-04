/**
 * USER_OWNED_BUCKETS — every Storage bucket the app writes user-owned objects
 * into, under a `<userId>/…` prefix. The ONE list delete-account purges.
 *
 * Single-owner audit 2026-09-26, P0 #6: delete-account purged 3 buckets
 * (progress-photos, chat-media, coach-media) while the client also writes
 * avatars (profile_provider.dart, via UserRepository.uploadImage) and banners
 * (same path). Both are PUBLIC buckets, so a deleted user's photo stayed
 * reachable by URL — 6 such avatars and 6 banners were live on 2026-09-26.
 *
 * Adding a bucket the client writes to without adding it here fails
 * test/contracts/delete_account_purges_all_user_buckets_test.dart.
 */
export const USER_OWNED_BUCKETS: readonly string[] = [
  "progress-photos",
  "chat-media",
  "coach-media",
  "avatars",
  "banners",
];
