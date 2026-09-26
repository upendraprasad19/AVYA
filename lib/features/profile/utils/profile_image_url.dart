// Source-of-truth for how the Profile avatar/banner image URLs are versioned
// (at UPLOAD time) and displayed (verbatim on READ).
//
// APK +34 / obs 4 (cache-buster-on-read): the Profile screen used to append a
// fresh `?t=${DateTime.now().millisecondsSinceEpoch}` to the avatar/banner URL
// on EVERY build (`_ProfileScreenState._addCacheBuster`). Because
// `CachedNetworkImage` keys its on-disk cache by URL, a new query string every
// render meant a guaranteed cache MISS → a network refetch every single time
// the user navigated to Profile. It "worked" only as a blunt way to show a
// freshly re-uploaded image (storage reuses a fixed object path —
// `<uid>/avatar.jpg` — so the public URL is identical after a re-upload, and
// `imageCache.evict` only clears the in-memory cache, not the disk cache).
//
// Correct contract: bust the cache key ONLY when the image actually changes.
// Stamp a version token at upload time; pass the stored URL through unchanged
// on read. Result: navigating to Profile is a cache HIT (no refetch), and a
// new upload changes the stored `?v=` → a one-time fresh fetch on every device
// (the version travels in the stored/synced URL).
class ProfileImageUrl {
  ProfileImageUrl._();

  /// READ path. Returns the stored URL verbatim — MUST NOT inject a per-build
  /// token (that is exactly the bug this replaces). Null/empty → null.
  static String? forDisplay(String? storedUrl) {
    if (storedUrl == null || storedUrl.isEmpty) return null;
    return storedUrl;
  }

  /// UPLOAD path. Stamps a cache-busting `v=<version>` onto the storage URL so
  /// the stored value changes only when a new image is uploaded. Idempotent:
  /// strips any prior `v` (and any legacy read-path `t`) before re-stamping.
  static String versioned(String publicUrl, {required int version}) {
    final uri = Uri.parse(publicUrl);
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('v')
      ..remove('t');
    params['v'] = version.toString();
    return uri.replace(queryParameters: params).toString();
  }
}
