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
        // C-7 (audit-2026-05-11) — the helper now delegates to the
        // shared `HiveUserSession.ensureOpenedForCurrentSession` static
        // (so RankService / SubscriptionService / migrators / splash
        // all share one entry). Either form is acceptable as long as
        // openForUser failures still funnel through ErrorTelemetry
        // somewhere downstream.
        final syncSrc = _src('lib/core/services/sync_service.dart');
        final fnIdx =
            syncSrc.indexOf('Future<String?> _ensureSessionOpen()');
        expect(fnIdx, greaterThan(0));
        final endIdx = syncSrc.indexOf('// ──', fnIdx);
        final body = syncSrc.substring(
            fnIdx,
            endIdx > fnIdx
                ? endIdx
                : (fnIdx + 1500).clamp(0, syncSrc.length));

        final reportsInline =
            body.contains('ErrorTelemetry.recordNonFatal');
        final delegatesToShared =
            body.contains('HiveUserSession.ensureOpenedForCurrentSession');
        expect(
          reportsInline || delegatesToShared,
          isTrue,
          reason: '_ensureSessionOpen must either call '
              'ErrorTelemetry.recordNonFatal inline OR delegate to '
              'HiveUserSession.ensureOpenedForCurrentSession (which '
              'does). Both forms preserve the Crashlytics signal.',
        );

        if (delegatesToShared) {
          // Verify the downstream helper still funnels through
          // ErrorTelemetry — otherwise the delegation drops the signal.
          final hsSrc =
              _src('lib/core/services/hive_user_session.dart');
          final ensureIdx = hsSrc.indexOf(
              'static Future<String?> ensureOpenedForCurrentSession()');
          expect(ensureIdx, greaterThan(0),
              reason:
                  'shared helper must exist if SyncService delegates to it');
          final ensureEnd = hsSrc.indexOf('\n  }', ensureIdx);
          final ensureBody = hsSrc.substring(
              ensureIdx,
              ensureEnd > ensureIdx
                  ? ensureEnd
                  : (ensureIdx + 2000).clamp(0, hsSrc.length));
          expect(
            ensureBody,
            contains('ErrorTelemetry.recordNonFatal'),
            reason:
                'HiveUserSession.ensureOpenedForCurrentSession must '
                'forward openForUser failures to ErrorTelemetry — '
                'else the delegation drops the only signal we have if '
                'openForUser is itself broken.',
          );
        }
      },
    );
  });
}
