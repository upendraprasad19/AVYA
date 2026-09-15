// Regression guard — diagnose 2026-05-30-weight-logs-realtime-publication-empty
// (e3f1a7).
//
// The PRO realtime sync (lib/core/services/sync/sync_realtime.dart) opens a
// `.from('weight_logs').stream()`. Supabase Realtime requires weight_logs to be
// a member of the supabase_realtime publication; it was empty, so the stream
// channelError'd on every subscribe. Migration 079 adds it.
//
// flutter test cannot reach the live publication; the authoritative behavioral
// proof is the live check recorded in the diagnose-doc (pg_publication_tables
// now lists weight_logs; the recurring realtime_stream_weight_logs error
// stopped after the migration). This is a source-grep guard pinning the
// migration that grants membership.
//
// Run: flutter test test/contracts/weight_logs_realtime_publication_test.dart

import 'dart:io';
import 'package:test/test.dart';

const _migration = 'supabase/migrations/079_enable_weight_logs_realtime.sql';

String _stripSqlComments(String src) =>
    src.replaceAll(RegExp(r'--[^\n]*'), '');

void main() {
  group('weight_logs realtime publication (e3f1a7)', () {
    late String code;

    setUpAll(() {
      final f = File(_migration);
      expect(f.existsSync(), isTrue, reason: 'migration 079 must exist');
      code = _stripSqlComments(f.readAsStringSync());
    });

    test('adds weight_logs to the supabase_realtime publication', () {
      final re = RegExp(
          r'ALTER\s+PUBLICATION\s+supabase_realtime\s+ADD\s+TABLE\s+(public\.)?weight_logs',
          caseSensitive: false);
      expect(re.hasMatch(code), isTrue,
          reason: 'migration 079 must ALTER PUBLICATION supabase_realtime ADD '
              'TABLE public.weight_logs — the membership the client stream needs.');
    });

    test('the client still subscribes to weight_logs (reader unchanged)', () {
      final reader = File('lib/core/services/sync/sync_realtime.dart');
      expect(reader.existsSync(), isTrue);
      final src = reader.readAsStringSync();
      expect(src.contains("from('weight_logs')"), isTrue,
          reason: 'if the realtime reader stops subscribing to weight_logs, '
              'this publication membership is dead config — revisit.');
    });
  });
}
