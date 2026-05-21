// Bug t1m5b0 regression test (APK Test #16.2) — Failure B.
//
// Pins the contract that the AI-coach chat-media upload path produces
// a SIGNED URL (createSignedUrl) rather than a getPublicUrl shape.
//
// Storage rejects `${SUPABASE_URL}/storage/v1/object/public/<bucket>/...`
// with HTTP 400 when the bucket is private. The `chat-media` bucket is
// private (storage.buckets.public = false, confirmed live 2026-05-18).
//
// Pre-fix the upload path called `.getPublicUrl(storagePath)` which
// happily returned a `/public/chat-media/...` URL — but Storage's HTTP
// API returned 400 on every fetch attempt, including all 3 retries in
// the ai-media-proxy storage-race backoff schedule. The user saw
// "PHOTO FAILED · Tap to retry" with no recovery path.
//
// createSignedUrl(path, ttlSeconds) returns a `/sign/<bucket>/<path>?token=...`
// URL which Storage accepts for private buckets. ai-media-proxy's
// parseStorageUrl already handles the sign-URL shape.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  test(
      't1m5b0 — chat-media upload uses createSignedUrl (private bucket cannot use getPublicUrl)',
      () {
    final src =
        readScreenSource('ai_coach');

    // Strip block + line comments so the explanatory comment naming the
    // anti-pattern does not match (it has to mention getPublicUrl in
    // prose).
    final stripped = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    // Find ALL `from('chat-media')` callsites and require that AT LEAST
    // ONE of them creates a signed URL, and NONE of them call
    // getPublicUrl. The codebase currently has two callsites: one for
    // uploadBinary and one for createSignedUrl; both use `from('chat-media')`.
    final chatMediaIndices = <int>[];
    int searchFrom = 0;
    while (true) {
      final idx = stripped.indexOf("from('chat-media')", searchFrom);
      if (idx < 0) break;
      chatMediaIndices.add(idx);
      searchFrom = idx + 1;
    }
    expect(chatMediaIndices, isNotEmpty,
        reason:
            'chat-media upload site moved or renamed — re-baseline this test.');

    // Build a window covering every chat-media block (each anchor +
    // 600 chars). Concatenate so a single .createSignedUrl( anywhere
    // satisfies the assertion.
    final buf = StringBuffer();
    for (final i in chatMediaIndices) {
      final end = (i + 600 <= stripped.length) ? i + 600 : stripped.length;
      buf.write(stripped.substring(i, end));
      buf.write('\n---\n');
    }
    final window = buf.toString();

    expect(
      window.contains('.createSignedUrl('),
      isTrue,
      reason:
          'chat-media upload must call .createSignedUrl(path, ttlSeconds) — '
          'a signed URL is required because chat-media is a PRIVATE bucket. '
          'getPublicUrl returns /public/<bucket>/... which Storage rejects '
          'with 400 for private buckets, breaking the AI coach photo flow.',
    );
    expect(
      window.contains('.getPublicUrl('),
      isFalse,
      reason:
          't1m5b0 regression — chat-media upload reverted to getPublicUrl. '
          'Storage returns 400 for /public/<private-bucket>/... URLs, '
          'producing "PHOTO FAILED" on every attempt.',
    );
  });
}
