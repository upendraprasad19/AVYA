// APK Test #12.7 — pin that every fire-and-forget sync catch in
// `sync_service.dart` funnels through ErrorTelemetry.
//
// Pre-fix: `_reportSyncFailure` posted only to `log-client-error`. When
// that Edge Function itself was down, failures got enqueued in syncBox
// for retry but Crashlytics never saw them — the founder's 30+
// `client_errors` rows per cold start had no matching crash dashboard
// signal, making remote diagnosis blind. Wiring ErrorTelemetry into
// the single funnel means every catch in this file (and there are 50+)
// gets the Crashlytics non-fatal record automatically.
//
// Source-grep test — production singletons aren't DI'able.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  group('Test #12.7 — sync error telemetry sweep', () {
    test('SyncService imports ErrorTelemetry', () {
      final src = _src('lib/core/services/sync_service.dart');
      expect(
        src,
        contains(
            "import 'package:icanbefitter/core/services/error_telemetry.dart'"),
        reason: 'sync_service.dart must import ErrorTelemetry to wire '
            'Crashlytics into every sync failure.',
      );
    });

    test(
      '_reportSyncFailure invokes ErrorTelemetry.recordNonFatal — single funnel',
      () {
        final src = _src('lib/core/services/sync_service.dart');

        final fnIdx = src.indexOf('Future<void> _reportSyncFailure(');
        expect(fnIdx, greaterThan(0),
            reason: '_reportSyncFailure must exist.');

        // The body must call ErrorTelemetry.recordNonFatal. Slice to
        // the next sibling helper to avoid matching the inner `})` of
        // the function signature.
        final nextSibling = src.indexOf('\n  /// ', fnIdx + 1);
        final endIdx = nextSibling > 0 ? nextSibling : (fnIdx + 4000);
        final body = src.substring(
            fnIdx, endIdx > src.length ? src.length : endIdx);

        expect(
          body,
          contains('ErrorTelemetry.recordNonFatal('),
          reason: '_reportSyncFailure is the single funnel for every '
              'sync catch in this file. It must forward to '
              'ErrorTelemetry.recordNonFatal so Crashlytics sees every '
              'non-fatal sync failure (currently blind).',
        );
      },
    );

    test(
      '_ensureSessionOpen reports openForUser failures via ErrorTelemetry',
      () {
        final src = _src('lib/core/services/sync_service.dart');
        final fnIdx = src.indexOf('Future<String?> _ensureSessionOpen()');
        expect(fnIdx, greaterThan(0));
        // Slice generously — helper is short, ends before the next
        // `// ──` divider.
        final endIdx = src.indexOf('// ──', fnIdx);
        final body = src.substring(fnIdx,
            endIdx > fnIdx ? endIdx : (fnIdx + 1500).clamp(0, src.length));

        expect(
          body,
          contains('ErrorTelemetry.recordNonFatal'),
          reason: '_ensureSessionOpen failures must surface to '
              'ErrorTelemetry — the only signal we have if openForUser '
              'is itself broken.',
        );
      },
    );
  });
}
