import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Bug 913261 (2026-05-16) — ai-media-proxy must classify thrown errors
/// into the right HTTP status code so the client retry layer + UI can
/// react appropriately:
///
///   - validation failures (bad URL, missing image, SSRF, image too
///     large) → 400 with descriptive body
///   - upstream Gemini issues (5xx from Google, timeout, JSON parse) →
///     502 (retry-eligible per `retryColdStart`)
///   - Storage fetch 404 (image upload incomplete / CDN propagation
///     race) → 400 with `error_type='storage'` hint
///   - Storage fetch 5xx → 502 (retry-eligible)
///   - genuine internal bugs → 500 (rare)
///
/// Pre-fix every throw inside the `serve()` try-block fell into a generic
/// catch that returned 500 with "Internal server error". The client's
/// `retryColdStart` layer treats 500 as a terminal server bug and does
/// NOT retry, even though many of those failures (Gemini timeout, Storage
/// 5xx) are exactly the class that 502/503/504 retries are designed to
/// absorb.
///
/// closes-diagnose: 2026-05-16-photo-analysis-500-913261
void main() {
  late String src;

  setUpAll(() {
    src = File('supabase/functions/ai-media-proxy/index.ts')
        .readAsStringSync();
  });

  group('Bug 913261 — ai-media-proxy HttpError class shape', () {
    test('HttpError class exists with status + errorType + message', () {
      expect(src.contains('class HttpError extends Error'), isTrue,
          reason:
              'A typed HttpError class is required so the bottom-of-handler '
              'catch can dispatch on errorType ∈ {validation, upstream, '
              'internal, storage} instead of returning 500 for every '
              'thrown error.');
      expect(src.contains('readonly status: number'), isTrue);
      expect(src.contains('readonly errorType:'), isTrue);
    });

    test('HttpError errorType union covers all 4 classes', () {
      // The union literal must enumerate validation | upstream | internal
      // | storage so future contributors don't quietly add a fifth class
      // without thinking through how the client surfaces it.
      expect(src.contains('"validation"'), isTrue);
      expect(src.contains('"upstream"'), isTrue);
      expect(src.contains('"internal"'), isTrue);
      expect(src.contains('"storage"'), isTrue);
    });
  });

  group('Bug 913261 — fetchImageAsBase64 typed error mapping', () {
    test('SSRF reject throws HttpError(400, "validation")', () {
      // The SSRF guard must throw the typed HttpError, not a raw Error
      // (which would fall through to 500). Pinned by source-grep on the
      // exact line.
      expect(
        src.contains(
            'throw new HttpError(400, "validation", "Only Supabase Storage URLs are allowed")'),
        isTrue,
        reason:
            'SSRF reject must produce 400 validation, not 500. Pre-fix the '
            'raw Error fell through the bottom catch as 500.',
      );
    });

    test('Storage 404 throws HttpError(400, "storage") with "upload incomplete"',
        () {
      // 404 is the most common production failure mode here — the photo
      // URL hasn't propagated to CDN yet OR the upload silently failed.
      // User-actionable; surface with a hint to retry the upload.
      expect(
        src.contains('error_type="storage"') ||
            src.contains('"storage",') &&
                src.contains('"Image upload incomplete'),
        isTrue,
        reason:
            'Storage 404 must produce 400 with errorType="storage" so the '
            'client maps to "Photo upload failed — please try picking the '
            'photo again." instead of the generic "couldn\'t analyse" '
            'message.',
      );
    });

    test('Storage 5xx throws HttpError(502, "upstream") for retry-eligibility',
        () {
      // Use a regex that's robust to both `\n` and `\r\n` line endings
      // (Windows checkout) and to varying indentation. We just need to
      // see `throw new HttpError(`, then `502`, then `"upstream"` in
      // proximity (within ~80 chars to scope to the same expression).
      final pattern = RegExp(
          r'throw\s+new\s+HttpError\s*\(\s*502\s*,\s*"upstream"',
          multiLine: true);
      expect(
        pattern.hasMatch(src),
        isTrue,
        reason:
            'Storage upstream 5xx must produce 502 so the client '
            'retryColdStart layer (which retries 502/503/504) can absorb '
            'transient Storage outages instead of surfacing them. '
            'Pattern looked for: `throw new HttpError(502, "upstream"`.',
      );
    });

    test('image-too-large throws HttpError(400, "validation")', () {
      expect(
        src.contains('"validation"') &&
            src.contains('Image too large'),
        isTrue,
        reason:
            'Oversized image must produce 400 validation. Pre-fix the raw '
            'Error fell through to 500 even though this is a deterministic '
            'caller bug that retry won\'t help.',
      );
    });
  });

  group('Bug 913261 — request body parse safety', () {
    test('req.json() wrapped in typed try/catch → 400 validation', () {
      // A malformed body would previously throw SyntaxError → 500.
      // Now caught explicitly and mapped to 400 validation.
      expect(
        src.contains('Request body is not valid JSON'),
        isTrue,
        reason:
            'req.json() must be wrapped in a try/catch that throws '
            'HttpError(400, "validation", "Request body is not valid JSON") '
            'so a malformed body produces 400, not 500.',
      );
    });
  });

  group('Bug 913261 — bottom-of-handler catch dispatches on HttpError', () {
    test('catch block checks `err instanceof HttpError`', () {
      expect(
        src.contains('err instanceof HttpError'),
        isTrue,
        reason:
            'Bottom-of-handler catch must dispatch on HttpError to return '
            'the typed status + error_type. Without this every thrown '
            'HttpError falls through to the generic 500 path and the '
            'classification refactor is pointless.',
      );
    });

    test('typed-error response includes error_type field', () {
      // Client recognises this field to decide between user-actionable
      // copy variants (storage / validation) and the generic upstream /
      // internal fallbacks.
      expect(
        src.contains('error_type: err.errorType'),
        isTrue,
        reason:
            'Typed error response must include error_type so the client '
            'can map to the right user-facing message and decide whether '
            'to flip mediaFailed=true on the user bubble.',
      );
    });

    test('genuine internal-bug fallback still returns 500 with request_id',
        () {
      // The "real bug" path stays at 500 (rare, alarm-worthy). request_id
      // logged server-side AND returned to the client for grep correlation.
      expect(
        src.contains('"Internal server error"'),
        isTrue,
        reason:
            'The non-HttpError fallback must still return 500 with '
            '"Internal server error" + request_id so genuine server bugs '
            'are alarm-worthy and greppable.',
      );
    });

    test('Gemini empty-content path returns 502 with error_type="upstream"',
        () {
      // The pre-existing 502 path (line ~411 in pre-fix) must now also
      // tag error_type so the client can distinguish.
      expect(
        src.contains('error_type: "upstream"') ||
            src.contains('"error_type":"upstream"'),
        isTrue,
        reason:
            'Empty-Gemini path must tag error_type="upstream" so the '
            'client surfaces "vision model temporarily unavailable" '
            'instead of the generic fallback.',
      );
    });
  });

  group('Bug 913261 — forbidden patterns (post-fix)', () {
    test('No raw `throw new Error(' '...' ')` inside fetchImageAsBase64', () {
      // Anchor the test to the helper boundaries to avoid spurious matches
      // elsewhere in the file. fetchImageAsBase64 must throw HttpError
      // exclusively — any raw Error would skip the typed-status dispatch.
      final start = src.indexOf('async function fetchImageAsBase64');
      final end = src.indexOf('serve(async (req: Request)');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = src.substring(start, end);
      // We expect zero `throw new Error(` calls — only `throw new HttpError(`.
      expect(
        RegExp(r'throw new Error\(').hasMatch(body),
        isFalse,
        reason:
            'fetchImageAsBase64 must throw HttpError exclusively. A raw '
            '`throw new Error(...)` here regresses Bug 913261 — the throw '
            'falls through to the generic 500 path and the user sees the '
            'broken-image placeholder again.',
      );
    });
  });
}
