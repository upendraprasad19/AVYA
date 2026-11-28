// SOURCE PINS — OI-503 (plan docs/plans/2026-11-13-coach-chat-time-dup.md,
// section 4 C2; migration 178; diagnose d4a7c9).
//
// Writers: ai-proxy's chat reservation INSERT and ai-media-proxy's three
// ai_coach_interactions INSERTs (image paywall, video paywall, analysis) store
// the phone's turn key as `client_key`, sanitized by _shared/client_key.ts.
// Reader: SyncService._restoreCoachInteractions (and the push's key lookup).
//
// Presence pins only. The behaviour is covered by Deno
// (_shared/client_key_test.ts; ai-media-proxy/index_test.ts "the paywall row
// carries the phone's key") and by the restore/push tests in test/sync/.
// Deliberate exclusions are pinned too: food-analysis rows carry no key, and
// the chat dedup replay inserts nothing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// The `.insert({ ... })` object that follows [anchor] (the first `})` after it).
String _insertAfter(String src, String anchor) {
  final a = src.indexOf(anchor);
  expect(a, greaterThanOrEqualTo(0), reason: 'anchor not found: $anchor');
  final ins = src.indexOf('.insert({', a);
  expect(ins, greaterThan(a));
  return src.substring(ins, src.indexOf('})', ins));
}

void main() {
  test('the shared sanitizer keeps exactly coach_ + 10-16 digits, the CHECK pattern', () {
    final ts = _read('supabase/functions/_shared/client_key.ts');
    expect(ts, contains(r'/^coach_[0-9]{10,16}$/'));
    final sql = _read('supabase/migrations/178_coach_client_key.sql');
    expect(sql, contains(r"client_key ~ '^coach_[0-9]{10,16}$'"),
        reason: 'the CHECK and the sanitizer must agree, or a sanitized key fails the insert');
  });

  group('ai-proxy', () {
    final src = _read('supabase/functions/ai-proxy/index.ts');

    test('the chat reservation stores the sanitized key', () {
      final body = _insertAfter(src, 'const chatReservation = await supabaseClient');
      expect(body, contains('channel: "app"'));
      expect(body, contains('client_key: sanitizeClientKey(client_key),'));
    });

    test('the key is read from the body', () {
      final start = src.indexOf('const body = await req.json();');
      final destr = src.substring(start, src.indexOf('} = body;', start));
      expect(destr, contains('client_key,'));
    });

    test('food and vision rows carry no key (their bodies send none)', () {
      // Every ai_coach_interactions INSERT except the chat reservation.
      final inserts = RegExp(r'\.insert\(\{').allMatches(src).map((m) {
        return src.substring(m.start, src.indexOf('})', m.start));
      }).where((b) => b.contains('channel:')).toList();
      expect(inserts.length, greaterThanOrEqualTo(3), reason: 'food, vision, chat');
      final keyed = inserts.where((b) => b.contains('client_key')).toList();
      expect(keyed, hasLength(1), reason: 'only the chat reservation is keyed');
      expect(keyed.single, contains('channel: "app"'));
      expect('client_key: sanitizeClientKey('.allMatches(src).length, 1);
    });
  });

  group('ai-media-proxy', () {
    final src = _read('supabase/functions/ai-media-proxy/index.ts');

    test('the key is sanitized once', () {
      expect('sanitizeClientKey('.allMatches(src).length, 1);
      expect(src, contains('const clientKey = sanitizeClientKey(client_key);'));
    });

    test('all three interaction inserts carry it', () {
      for (final channel in const [
        'channel: "image_paywall"',
        'channel: "video_paywall"',
      ]) {
        final at = src.indexOf(channel);
        expect(at, greaterThan(0), reason: channel);
        final end = src.indexOf('});', at);
        expect(src.substring(at, end), contains('client_key: clientKey,'), reason: channel);
      }
      final analysis = _insertAfter(src, 'const { error: interactionLogError } = await supabaseClient');
      expect(analysis, contains('client_key: clientKey,'));
      expect('client_key: clientKey,'.allMatches(src).length, 3);
    });

    test('both paywall call sites pass it', () {
      expect(
        'checkFreeImageQuota(supabaseClient, userId, media_url, media_type, message, clientKey)'
            .allMatches(src)
            .length,
        2,
      );
      expect(src, contains('videoPaywallReply(supabaseClient, userId, message, media_url, clientKey)'));
    });
  });
}
